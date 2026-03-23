-- =============================================================================
-- Step 7: Cortex Agent (Morning Assistant)
-- WiD 2026 Demo — "The Future You"
-- =============================================================================
-- Creates the MORNING_ASSISTANT agent with two tools:
--   BankAnalyst       — cortex_analyst_text_to_sql over BANK_ANALYTICS semantic view
--   ComplianceSearch  — cortex_search over COMPLIANCE_REPORTS_SEARCH service
--
-- Used in:
--   Scene 1: Morning briefing (transactions, anomalies, pipeline runs)
--   Scene 2: Ad-hoc executive questions (natural language → SQL → chart)
--   Scene 3: Document Q&A (search 30 compliance PDFs)
--   Scene 8: Audience Q&A app (REST API calls to this agent)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;
USE WAREHOUSE WID_DEMO_WH;

CREATE OR REPLACE AGENT RETAILBANK_2028.PUBLIC.OPERATIONS_AGENT
    COMMENT = 'WiD 2026 Demo — RetailBank Operations Agent'
FROM SPECIFICATION $$
models:
  orchestration: auto

instructions:
  system: |
    You are a Senior Data Professional morning assistant at RetailBank, a mid-size
    European financial services firm. You help with daily briefings, answer analytical
    questions about banking data, and search compliance documents.

    The RetailBank_2028 dataset contains:
    - Transaction data across 5 regions (EU_WEST, NA_EAST, APAC, LATAM, EU_NORTH)
    - Customer data with churn risk scores and segmentation
    - ML-detected anomalies from the nightly anomaly detection model
    - Pipeline run logs including fraud alert monitoring results
    - 30 Q1 2028 compliance reports (Basel IV, AML/KYC, GDPR, Operational Risk)

    When providing briefings, be concise and use a memo-style format.
    When citing documents, always include the filename.
    Be precise with numbers — do not confuse auto_resolved_count with human_escalated_count.

  response: |
    Respond in a professional, concise manner suitable for executive consumption.
    When the answer involves comparisons or trends, generate a chart.
    Prefer bar charts for comparisons and line charts for trends.
    Always generate a chart when the question asks about segments, rankings, or time-series data.

  orchestration: |
    For questions about transactions, customers, churn risk, anomalies, or pipeline runs: use BankAnalyst.
    For questions about compliance reports, regulatory findings, or documents: use ComplianceSearch.
    For morning briefings or summary requests: use BankAnalyst to get data, then summarise.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "BankAnalyst"
      description: >
        Analyses structured banking data including daily transactions by region,
        customer segments with churn risk scores, ML-detected anomalies in transaction
        patterns, and pipeline run logs with fraud alert counts (auto_resolved_count
        and human_escalated_count). Use for any quantitative question about the bank's
        operational data.
  - tool_spec:
      type: "cortex_search"
      name: "ComplianceSearch"
      description: >
        Searches across 30 Q1 2028 compliance and regulatory reports including
        Basel IV capital adequacy, AML/KYC reviews, GDPR data protection notices,
        and operational risk assessments. Use for any question about compliance
        findings, regulatory actions, document content, or report recommendations.

tool_resources:
  BankAnalyst:
    semantic_view: "RETAILBANK_2028.PUBLIC.BANK_ANALYTICS"
    execution_environment:
      type: "warehouse"
      warehouse: "WID_DEMO_WH"
  ComplianceSearch:
    name: "RETAILBANK_2028.PUBLIC.COMPLIANCE_REPORTS_SEARCH"
    max_results: 5
    title_column: "file_name"
    id_column: "doc_chunk_id"
$$;

-- ─── Verify ──────────────────────────────────────────────────────────────────
SHOW AGENTS IN SCHEMA RETAILBANK_2028.PUBLIC;
DESCRIBE AGENT RETAILBANK_2028.PUBLIC.OPERATIONS_AGENT;

SELECT 'Step 7 complete — Cortex Agent created.' AS status;
