"""
Step 4: Generate 30 Synthetic Compliance PDFs
WiD 2026 Demo — "The Future You"

Generates 30 fictional compliance/regulatory reports as PDFs using
Cortex Complete for content and fpdf2 for rendering. Uploads them
to @RETAILBANK_2028.PUBLIC.REPORTS_STAGE.

Categories:
  - 10 Basel IV Capital Adequacy
  -  8 AML/KYC Reviews (3 flagging increased Q1 AML risk)
  -  7 GDPR Data Protection
  -  5 Operational Risk Assessments

Usage:
  pip install -r requirements.txt
  python 04_generate_pdfs.py

Requires a Snowflake connection named 'demo_us' configured via:
  cortex connection add demo_us
  — OR —
  Set env vars: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, etc.
"""

import os
import sys
import tempfile
import textwrap
from pathlib import Path

try:
    from fpdf import FPDF
except ImportError:
    sys.exit("fpdf2 not installed. Run: pip install fpdf2")

try:
    import snowflake.connector
except ImportError:
    sys.exit("snowflake-connector-python not installed. Run: pip install snowflake-connector-python")


# ─── Report Definitions ──────────────────────────────────────────────────────

REPORTS = [
    # Basel IV (10 reports)
    {"filename": "Basel_IV_Capital_Adequacy_Q1_2028_Overview.pdf",
     "title": "Basel IV Capital Adequacy — Q1 2028 Overview",
     "category": "Basel IV",
     "prompt": "Write a 2-page executive summary of a fictional European bank's Basel IV capital adequacy position for Q1 2028. Include CET1 ratio (13.2%), leverage ratio, risk-weighted assets breakdown by credit/market/operational risk, and a recommendation to maintain buffers above the 10.5% minimum. Mention that the countercyclical buffer for EU operations was raised to 1.0%."},

    {"filename": "Basel_IV_Credit_Risk_SA_Implementation.pdf",
     "title": "Basel IV Credit Risk SA Implementation Status",
     "category": "Basel IV",
     "prompt": "Write a 2-page status report on implementing the Basel IV Standardized Approach for credit risk at a mid-size bank. Cover progress on risk-weight recalibration for residential mortgages, SME lending exposure classification, and the timeline for output floor phase-in. Note that 78% of portfolios have been migrated."},

    {"filename": "Basel_IV_Market_Risk_FRTB_Review.pdf",
     "title": "Basel IV FRTB Market Risk Review",
     "category": "Basel IV",
     "prompt": "Write a 2-page review of a bank's Fundamental Review of the Trading Book implementation. Include the desk-level P&L attribution test results, the decision to use the Standardized Approach for 3 desks, and the impact on market risk capital charges (estimated +15% increase)."},

    {"filename": "Basel_IV_Operational_Risk_SMA.pdf",
     "title": "Basel IV Operational Risk — SMA Calculation",
     "category": "Basel IV",
     "prompt": "Write a 2-page report on the bank's transition to the Standardized Measurement Approach for operational risk under Basel IV. Include the Business Indicator Component calculation, historical loss multiplier, and the projected impact on operational risk capital."},

    {"filename": "Basel_IV_Leverage_Ratio_Assessment.pdf",
     "title": "Basel IV Leverage Ratio Assessment",
     "category": "Basel IV",
     "prompt": "Write a 2-page leverage ratio assessment for a European bank. Current ratio: 5.1% vs 3.5% minimum. Discuss exposure measure composition, G-SIB buffer applicability, and the impact of off-balance sheet items."},

    {"filename": "Basel_IV_Output_Floor_Impact.pdf",
     "title": "Basel IV Output Floor Impact Analysis",
     "category": "Basel IV",
     "prompt": "Write a 2-page analysis of the Basel IV output floor's impact on the bank's capital requirements. The 72.5% floor becomes binding for the mortgage portfolio, increasing RWA by EUR 1.2B. Discuss mitigation strategies."},

    {"filename": "Basel_IV_Liquidity_Coverage_Q1.pdf",
     "title": "Basel IV Liquidity Coverage Ratio — Q1 2028",
     "category": "Basel IV",
     "prompt": "Write a 2-page liquidity coverage ratio report. LCR: 142% (above 100% requirement). Include HQLA composition, net cash outflow projections, and stress scenario results."},

    {"filename": "Basel_IV_NSFR_Compliance.pdf",
     "title": "Basel IV Net Stable Funding Ratio Compliance",
     "category": "Basel IV",
     "prompt": "Write a 2-page Net Stable Funding Ratio compliance report. NSFR: 118%. Cover available stable funding sources, required stable funding for different asset categories, and the wholesale funding dependency reduction plan."},

    {"filename": "Basel_IV_CVA_Risk_Framework.pdf",
     "title": "Basel IV CVA Risk Framework Update",
     "category": "Basel IV",
     "prompt": "Write a 2-page update on the bank's Credit Valuation Adjustment risk framework under Basel IV. Include the transition to the Standardized CVA approach, hedge recognition criteria, and the projected capital charge impact."},

    {"filename": "Basel_IV_Large_Exposure_Review.pdf",
     "title": "Basel IV Large Exposure Limits Review",
     "category": "Basel IV",
     "prompt": "Write a 2-page review of the bank's large exposure framework. All counterparty exposures within the 25% Tier 1 limit. Flag one concentration in sovereign bonds (18% of Tier 1) and recommend diversification."},

    # AML/KYC (8 reports — 3 flag increased Q1 AML risk)
    {"filename": "AML_KYC_Q1_2028_Quarterly_Review.pdf",
     "title": "AML/KYC Q1 2028 Quarterly Review",
     "category": "AML/KYC",
     "prompt": "Write a 2-page AML/KYC quarterly review for Q1 2028. FLAG INCREASED RISK: Report a 34% increase in suspicious activity reports in the EU_WEST region linked to cross-border payment patterns. Recommend enhanced monitoring and additional staff. Include SAR filing statistics and KYC refresh completion rates."},

    {"filename": "AML_Transaction_Monitoring_Effectiveness.pdf",
     "title": "AML Transaction Monitoring Effectiveness Report",
     "category": "AML/KYC",
     "prompt": "Write a 2-page report on the effectiveness of the bank's AML transaction monitoring system. FLAG INCREASED RISK: Alert volumes up 28% in Q1 2028, with the EU_WEST corridor showing unusual patterns in mid-value transfers (EUR 5,000-15,000). Current false positive rate: 92%. Recommend ML-based model upgrade."},

    {"filename": "AML_Risk_Assessment_EU_WEST_Region.pdf",
     "title": "AML Risk Assessment — EU WEST Region",
     "category": "AML/KYC",
     "prompt": "Write a 2-page focused AML risk assessment for the EU_WEST region. FLAG INCREASED RISK: Three new typologies identified in Q1 involving layering through fintech intermediaries. Recommend immediate enhanced due diligence for 47 accounts. Include risk heat map description and escalation matrix."},

    {"filename": "KYC_Refresh_Program_Status.pdf",
     "title": "KYC Refresh Program Status Report",
     "category": "AML/KYC",
     "prompt": "Write a 2-page status report on the bank's KYC refresh program. 85% of high-risk customers refreshed. 12 customers re-classified from medium to high risk. Include remediation timelines and pending reviews by segment."},

    {"filename": "AML_Sanctions_Screening_Update.pdf",
     "title": "AML Sanctions Screening System Update",
     "category": "AML/KYC",
     "prompt": "Write a 2-page update on the sanctions screening system. Cover list updates processed, screening hit rates, and the integration of the new consolidated sanctions feed. No material findings."},

    {"filename": "AML_Correspondent_Banking_Review.pdf",
     "title": "AML Correspondent Banking Due Diligence Review",
     "category": "AML/KYC",
     "prompt": "Write a 2-page due diligence review of the bank's correspondent banking relationships. All 23 relationships reviewed. Two flagged for enhanced monitoring due to jurisdiction risk. Include risk ratings."},

    {"filename": "KYC_Beneficial_Ownership_Audit.pdf",
     "title": "KYC Beneficial Ownership Registry Audit",
     "category": "AML/KYC",
     "prompt": "Write a 2-page audit report on beneficial ownership data quality. 94% of corporate accounts have verified UBO records. 6% pending due to complex multi-jurisdictional structures. Recommend automated verification pilot."},

    {"filename": "AML_Training_Compliance_Report.pdf",
     "title": "AML Training Compliance Report — Q1 2028",
     "category": "AML/KYC",
     "prompt": "Write a 2-page AML training compliance report. 97% completion rate. Include module breakdown, assessment pass rates, and planned advanced training for the compliance team on crypto-asset AML requirements."},

    # GDPR (7 reports)
    {"filename": "GDPR_Data_Protection_Impact_Assessment.pdf",
     "title": "GDPR Data Protection Impact Assessment — AI Systems",
     "category": "GDPR",
     "prompt": "Write a 2-page DPIA for the bank's use of AI in credit scoring and customer segmentation. Cover lawful basis (legitimate interest), data minimisation measures, automated decision-making safeguards under Article 22, and the DPO's recommendation."},

    {"filename": "GDPR_Subject_Access_Request_Report.pdf",
     "title": "GDPR Subject Access Request Statistics — Q1 2028",
     "category": "GDPR",
     "prompt": "Write a 2-page report on DSAR handling for Q1 2028. 234 requests received (up 15% from Q4). Average response time: 18 days. Include breakdown by request type, channel, and the two requests that required deadline extensions."},

    {"filename": "GDPR_Data_Breach_Response_Drill.pdf",
     "title": "GDPR Data Breach Response Drill Results",
     "category": "GDPR",
     "prompt": "Write a 2-page report on the Q1 2028 data breach simulation drill. Scenario: credential stuffing attack on the mobile banking API. Include detection time (4 minutes), containment actions, notification timeline, and 3 improvement recommendations."},

    {"filename": "GDPR_Third_Party_Processing_Audit.pdf",
     "title": "GDPR Third-Party Data Processing Audit",
     "category": "GDPR",
     "prompt": "Write a 2-page audit of the bank's third-party data processors. 18 processors reviewed. All have updated DPAs. Two processors flagged for inadequate data deletion procedures. Include remediation actions."},

    {"filename": "GDPR_Consent_Management_Review.pdf",
     "title": "GDPR Consent Management Platform Review",
     "category": "GDPR",
     "prompt": "Write a 2-page review of the bank's consent management system. Cover opt-in/opt-out rates for marketing, analytics, and profiling purposes. Include the recent CMP upgrade and improved granular consent options."},

    {"filename": "GDPR_Cross_Border_Transfer_Assessment.pdf",
     "title": "GDPR Cross-Border Data Transfer Assessment",
     "category": "GDPR",
     "prompt": "Write a 2-page assessment of the bank's international data transfers post-EU-US Data Privacy Framework. Cover Standard Contractual Clauses usage, Transfer Impact Assessments for APAC operations, and the new binding corporate rules application."},

    {"filename": "GDPR_Records_of_Processing_Update.pdf",
     "title": "GDPR Records of Processing Activities Update",
     "category": "GDPR",
     "prompt": "Write a 2-page update on the bank's Article 30 records. 156 processing activities documented. 12 new activities added in Q1 (mainly AI-related). Include data flow mapping completeness by department."},

    # Operational Risk (5 reports)
    {"filename": "OpRisk_Incident_Report_Q1_2028.pdf",
     "title": "Operational Risk Incident Report — Q1 2028",
     "category": "Operational Risk",
     "prompt": "Write a 2-page operational risk incident summary for Q1 2028. 23 incidents logged. Top categories: IT system failures (8), process errors (7), external fraud (5), vendor issues (3). Total loss: EUR 1.2M. Include severity distribution and trend analysis."},

    {"filename": "OpRisk_Business_Continuity_Test.pdf",
     "title": "Operational Risk — Business Continuity Plan Test Results",
     "category": "Operational Risk",
     "prompt": "Write a 2-page BCP test results report. Scenario: primary data centre outage. RTO achieved: 2.5 hours (target: 4 hours). RPO: 15 minutes. Include failover success rates by system and three gaps identified."},

    {"filename": "OpRisk_Third_Party_Risk_Dashboard.pdf",
     "title": "Operational Risk — Third-Party Risk Dashboard Q1 2028",
     "category": "Operational Risk",
     "prompt": "Write a 2-page third-party risk dashboard. 45 critical vendors monitored. 3 vendors in amber status due to SLA breaches. Include concentration risk analysis and the cloud provider dependency assessment."},

    {"filename": "OpRisk_IT_Security_Assessment.pdf",
     "title": "Operational Risk — IT Security Posture Assessment",
     "category": "Operational Risk",
     "prompt": "Write a 2-page IT security assessment. Cover vulnerability management stats, penetration testing results, phishing simulation outcomes (12% click rate, down from 18%), and the zero-trust architecture migration progress."},

    {"filename": "OpRisk_Model_Risk_Governance.pdf",
     "title": "Operational Risk — Model Risk Governance Report",
     "category": "Operational Risk",
     "prompt": "Write a 2-page model risk governance report. 34 models in production. 8 models due for annual validation. Include the new AI model governance framework, model inventory by risk tier, and the validation pipeline status."},
]


# ─── PDF Generation ──────────────────────────────────────────────────────────

def get_snowflake_connection():
    """Connect to Snowflake using env vars or connection config."""
    # Try environment variables first
    account = os.environ.get("SNOWFLAKE_ACCOUNT", "SFSEEUROPE-DEMO_TNASCIMENTO_US")
    user = os.environ.get("SNOWFLAKE_USER", "TNASCIMENTO")
    password = os.environ.get("SNOWFLAKE_PASSWORD")
    role = os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN")
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE", "WID_DEMO_WH")

    if not password:
        # Try using snowflake-connector-python's connection config
        try:
            conn = snowflake.connector.connect(
                connection_name="demo_us",
                database="RETAILBANK_2028",
                schema="PUBLIC",
            )
            return conn
        except Exception:
            sys.exit(
                "No Snowflake credentials found.\n"
                "Set SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD env vars\n"
                "or configure a 'demo_us' connection."
            )

    return snowflake.connector.connect(
        account=account,
        user=user,
        password=password,
        role=role,
        warehouse=warehouse,
        database="RETAILBANK_2028",
        schema="PUBLIC",
    )


def generate_content(cursor, prompt: str) -> str:
    """Use Cortex Complete to generate report content."""
    full_prompt = (
        f"You are a compliance officer at a European bank called RetailBank. "
        f"Write a professional regulatory/compliance report section. "
        f"Use formal language, include specific numbers and dates (Q1 2028). "
        f"Do not use markdown headers — use plain text with section titles in ALL CAPS. "
        f"\n\n{prompt}"
    )
    cursor.execute(
        "SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', %s) AS content",
        (full_prompt,)
    )
    result = cursor.fetchone()
    return result[0] if result else "Content generation failed."


def sanitize_text(text: str) -> str:
    replacements = {
        "\u2014": "-", "\u2013": "-", "\u2012": "-",
        "\u2018": "'", "\u2019": "'",
        "\u201C": '"', "\u201D": '"',
        "\u2026": "...", "\u2022": "*",
        "\u00A0": " ", "\u200B": "",
        "\u02BC": "'", "\u2010": "-", "\u2011": "-",
        "\u2032": "'", "\u2033": '"',
        "\u00AD": "-", "\u2060": "",
        "\uFEFF": "",
    }
    for orig, repl in replacements.items():
        text = text.replace(orig, repl)
    return text.encode("ascii", errors="replace").decode("ascii")


def create_pdf(title: str, category: str, content: str, filepath: str):
    """Render content as a simple PDF."""
    title = sanitize_text(title)
    category = sanitize_text(category)
    content = sanitize_text(content)
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=25)
    pdf.add_page()

    # Header
    pdf.set_font("Helvetica", "B", 18)
    pdf.set_text_color(0, 51, 102)
    pdf.multi_cell(0, 10, title)
    pdf.ln(3)

    # Category badge
    pdf.set_font("Helvetica", "I", 11)
    pdf.set_text_color(100, 100, 100)
    pdf.cell(0, 8, f"Category: {category}  |  RetailBank - Q1 2028  |  CONFIDENTIAL")
    pdf.ln(10)

    # Divider
    pdf.set_draw_color(0, 51, 102)
    pdf.set_line_width(0.5)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(8)

    # Body
    pdf.set_font("Helvetica", "", 10)
    pdf.set_text_color(30, 30, 30)
    for line in content.split("\n"):
        stripped = line.strip()
        if not stripped:
            pdf.ln(3)
            continue
        try:
            pdf.set_x(10)
            if stripped == stripped.upper() and len(stripped) > 5 and not stripped.startswith("*"):
                pdf.ln(4)
                pdf.set_font("Helvetica", "B", 11)
                pdf.set_text_color(0, 51, 102)
                pdf.multi_cell(0, 6, stripped)
                pdf.set_font("Helvetica", "", 10)
                pdf.set_text_color(30, 30, 30)
            else:
                pdf.multi_cell(0, 5, stripped)
        except Exception:
            pdf.set_x(10)
            pdf.ln(5)
    
    # Footer
    pdf.ln(10)
    pdf.set_font("Helvetica", "I", 8)
    pdf.set_text_color(150, 150, 150)
    pdf.cell(0, 5, "This document is for demonstration purposes only. RetailBank is a fictional entity.", align="C")

    pdf.output(filepath)


def upload_to_stage(cursor, local_path: str, filename: str):
    """Upload a PDF to the Snowflake stage."""
    cursor.execute(
        f"PUT 'file://{local_path}' @RETAILBANK_2028.PUBLIC.REPORTS_STAGE "
        f"AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
    )


def main():
    print("=" * 60)
    print("WiD 2026 Demo — Generating 30 Compliance PDFs")
    print("=" * 60)

    conn = get_snowflake_connection()
    cursor = conn.cursor()
    cursor.execute("USE DATABASE RETAILBANK_2028")
    cursor.execute("USE SCHEMA PUBLIC")
    cursor.execute("USE WAREHOUSE WID_DEMO_WH")

    with tempfile.TemporaryDirectory() as tmpdir:
        for i, report in enumerate(REPORTS, 1):
            print(f"\n[{i:2d}/30] {report['filename']}")
            print(f"        Generating content...", end=" ", flush=True)

            content = generate_content(cursor, report["prompt"])
            print("done.", end=" ", flush=True)

            filepath = os.path.join(tmpdir, report["filename"])
            create_pdf(report["title"], report["category"], content, filepath)
            print("PDF created.", end=" ", flush=True)

            upload_to_stage(cursor, filepath, report["filename"])
            print("Uploaded.")

    # Refresh the directory table
    cursor.execute("ALTER STAGE RETAILBANK_2028.PUBLIC.REPORTS_STAGE REFRESH")

    # Verify
    cursor.execute("SELECT COUNT(*) FROM DIRECTORY(@RETAILBANK_2028.PUBLIC.REPORTS_STAGE)")
    count = cursor.fetchone()[0]
    print(f"\n{'=' * 60}")
    print(f"Done! {count} files in @REPORTS_STAGE")
    print(f"{'=' * 60}")

    cursor.close()
    conn.close()


if __name__ == "__main__":
    main()
