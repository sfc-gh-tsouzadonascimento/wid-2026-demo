-- =============================================================================
-- Reset Demo — Run before each live presentation
-- WiD 2026 Demo — "The Future You"
-- =============================================================================
-- This script re-anchors all timestamps to "right now", resets churn risk
-- scores, creates the buggy pipeline VIEW, recreates the agent without
-- ComplianceSearch, and drops the search service.
-- Idempotent — safe to run multiple times.
--
-- What it does:
--   1. Re-anchors TRANSACTION dates to end on yesterday
--   2. Re-anchors PIPELINE_RUNS timestamps to the last few hours
--   3. Re-anchors TRANSACTION_ANOMALIES to the last 10 days
--   4. Re-anchors CUSTOMER last_activity_date
--   5. Redistributes CHURN_RISK_SCORE so ~325 distinct customers are above 0.6
--      (producing ~815 via buggy view — the demo's target numbers)
--   6. Ensures CUSTOMERS_RAW table exists and creates buggy CUSTOMERS VIEW
--      (pipeline confused account_id with customer_id — the bug the notebook
--      discovers and fixes)
--   7. Recreates OPERATIONS_AGENT with BankAnalyst only (no ComplianceSearch —
--      that gets added live in Scene 2)
--   8. Drops COMPLIANCE_REPORTS_SEARCH service (gets created live in Scene 2)
--
-- Note: The semantic view BANK_ANALYTICS references "CUSTOMERS" which is now
-- a VIEW on top of CUSTOMERS_RAW. No semantic view change is needed.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;
USE WAREHOUSE WID_DEMO_WH;

-- ─── 1. Re-anchor TRANSACTIONS ─────────────────────────────────────────────
-- Shift all dates forward so the latest transaction date = yesterday
-- (today's data hasn't "arrived" yet — realistic for a morning briefing).

SET tx_offset = (SELECT DATEDIFF(DAY, MAX(TRANSACTION_DATE), CURRENT_DATE() - 1)
                 FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS);

UPDATE RETAILBANK_2028.PUBLIC.TRANSACTIONS
SET TRANSACTION_DATE = DATEADD(DAY, $tx_offset, TRANSACTION_DATE)
WHERE $tx_offset != 0;

-- ─── 2. Re-anchor PIPELINE_RUNS ────────────────────────────────────────────
-- Shift all run timestamps so the most recent run was ~2 hours ago.

SET pr_offset = (SELECT DATEDIFF(SECOND,
                    MAX(RUN_TIMESTAMP),
                    DATEADD(HOUR, -2, CURRENT_TIMESTAMP()))
                 FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS);

UPDATE RETAILBANK_2028.PUBLIC.PIPELINE_RUNS
SET RUN_TIMESTAMP = DATEADD(SECOND, $pr_offset, RUN_TIMESTAMP)
WHERE $pr_offset NOT BETWEEN -300 AND 300;  -- skip if already within 5 min

-- ─── 3. Re-anchor TRANSACTION_ANOMALIES ────────────────────────────────────
-- Shift so the latest anomaly observation = yesterday (matches transactions).

SET ta_offset = (SELECT DATEDIFF(DAY, MAX(TS)::DATE, CURRENT_DATE() - 1)
                 FROM RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES);

UPDATE RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES
SET TS = DATEADD(DAY, $ta_offset, TS)
WHERE $ta_offset != 0;

-- ─── 3b. Ensure CUSTOMERS_RAW table exists ─────────────────────────────────
-- On first reset after deployment, CUSTOMERS is a TABLE that needs renaming
-- to CUSTOMERS_RAW.  On subsequent resets, CUSTOMERS_RAW already exists and
-- CUSTOMERS is a VIEW — so we just drop the VIEW (step 6 recreates it).

BEGIN
    LET raw_exists INTEGER := (SELECT COUNT(*) FROM RETAILBANK_2028.INFORMATION_SCHEMA.TABLES
                                WHERE TABLE_SCHEMA = 'PUBLIC' AND TABLE_NAME = 'CUSTOMERS_RAW'
                                AND TABLE_TYPE = 'BASE TABLE');
    IF (:raw_exists = 0) THEN
        ALTER TABLE RETAILBANK_2028.PUBLIC.CUSTOMERS RENAME TO RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW;
    ELSE
        DROP VIEW IF EXISTS RETAILBANK_2028.PUBLIC.CUSTOMERS;
    END IF;
END;

-- ─── 4. Re-anchor CUSTOMER last_activity_date ──────────────────────────────
-- Shift so the most recent activity = today.

SET ca_offset = (SELECT DATEDIFF(DAY, MAX(LAST_ACTIVITY_DATE), CURRENT_DATE())
                 FROM RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW);

UPDATE RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW
SET LAST_ACTIVITY_DATE = DATEADD(DAY, $ca_offset, LAST_ACTIVITY_DATE)
WHERE $ca_offset != 0;

-- ─── 5. Redistribute churn risk scores ─────────────────────────────────────
-- Uses UNIFORM(0.05, 0.98) capped at 0.95 so that ~40.9% of customers
-- have scores above 0.6.  With 800 customers this gives ~325 at-risk,
-- and with ~2.49 accounts per customer the buggy view inflates to ~815.
--
-- Each customer gets ONE score shared across all their account rows.

MERGE INTO RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW tgt
USING (
    WITH customer_scores AS (
        SELECT
            CUSTOMER_ID,
            ROUND(LEAST(0.95, UNIFORM(0.05::FLOAT, 0.98::FLOAT, RANDOM())), 2) AS new_score
        FROM (SELECT DISTINCT CUSTOMER_ID FROM RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW)
    )
    SELECT CUSTOMER_ID, new_score
    FROM customer_scores
) src
ON tgt.CUSTOMER_ID = src.CUSTOMER_ID
WHEN MATCHED THEN UPDATE SET tgt.CHURN_RISK_SCORE = src.new_score;

-- ─── 6. Create buggy CUSTOMERS view ────────────────────────────────────────
-- The "overnight AI pipeline" rebuilt the CUSTOMERS view but mapped
-- ACCOUNT_ID into the CUSTOMER_ID position.  This inflates
-- COUNT(DISTINCT CUSTOMER_ID) from ~325 (real) to ~815 (account IDs).
--
-- The pipeline_review notebook discovers and fixes this during Scene 1C.
-- The semantic view BANK_ANALYTICS references "CUSTOMERS" — so once the
-- notebook fixes this VIEW, the agent automatically returns the correct count.

CREATE OR REPLACE VIEW RETAILBANK_2028.PUBLIC.CUSTOMERS AS
SELECT
    ACCOUNT_ID AS CUSTOMER_ID,      -- BUG: should be CUSTOMER_ID, not ACCOUNT_ID
    CUSTOMER_NAME,
    SEGMENT,
    REGION,
    CHURN_RISK_SCORE,
    ACCOUNT_ID,
    MONTHLY_TRANSACTION_VOLUME,
    LAST_ACTIVITY_DATE,
    ACCOUNT_OPEN_DATE,
    TRANSACTION_VOLUME_RANK
FROM RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW;

-- ─── 7. Recreate agent WITHOUT ComplianceSearch ─────────────────────────────
-- Scene 2 adds ComplianceSearch live during the demo.  The reset state
-- should only have BankAnalyst.

CREATE OR REPLACE AGENT RETAILBANK_2028.PUBLIC.OPERATIONS_AGENT
    COMMENT = 'WiD 2026 Demo — RetailBank Operations Agent'
FROM SPECIFICATION $$
models:
  orchestration: auto

instructions:
  system: |
    You are a Senior Data Professional morning assistant at RetailBank, a mid-size
    European financial services firm. You help with daily briefings and answer
    analytical questions about banking data.

    The RetailBank_2028 dataset contains:
    - Transaction data across 5 regions (EU_WEST, NA_EAST, APAC, LATAM, EU_NORTH)
    - Customer data with churn risk scores and segmentation
    - ML-detected anomalies from the nightly anomaly detection model
    - Pipeline run logs including fraud alert monitoring results

    When providing briefings, be concise and use a memo-style format.
    Be precise with numbers — do not confuse auto_resolved_count with human_escalated_count.

  response: |
    Respond in a professional, concise manner suitable for executive consumption.
    When the answer involves comparisons or trends, generate a chart.
    Prefer bar charts for comparisons and line charts for trends.
    Always generate a chart when the question asks about segments, rankings, or time-series data.

  orchestration: |
    For questions about transactions, customers, churn risk, anomalies, or pipeline runs: use BankAnalyst.
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

tool_resources:
  BankAnalyst:
    semantic_view: "RETAILBANK_2028.PUBLIC.BANK_ANALYTICS"
    execution_environment:
      type: "warehouse"
      warehouse: "WID_DEMO_WH"
      query_timeout: 299
$$;

-- ─── 8. Drop Cortex Search service ─────────────────────────────────────────
-- The search service gets created live in Scene 2 via the Snowsight UI.
-- Drop it here so the presenter can demonstrate the full creation flow.

DROP CORTEX SEARCH SERVICE IF EXISTS RETAILBANK_2028.PUBLIC.COMPLIANCE_REPORTS_SEARCH;

-- ─── Verification ──────────────────────────────────────────────────────────

-- Timestamp checks
SELECT '1. TRANSACTIONS' AS check_name,
    'latest=' || MAX(TRANSACTION_DATE)::VARCHAR || '  oldest=' || MIN(TRANSACTION_DATE)::VARCHAR AS result
FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS
UNION ALL
SELECT '2. PIPELINE_RUNS',
    'latest=' || MAX(RUN_TIMESTAMP)::VARCHAR(30) ||
    '  hours_ago=' || DATEDIFF(HOUR, MAX(RUN_TIMESTAMP), CURRENT_TIMESTAMP())::VARCHAR
FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS
UNION ALL
SELECT '3. ANOMALIES',
    'latest=' || MAX(TS)::DATE::VARCHAR || '  rows=' || COUNT(*)::VARCHAR ||
    '  anomalies=' || SUM(CASE WHEN IS_ANOMALY THEN 1 ELSE 0 END)::VARCHAR
FROM RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES
UNION ALL
SELECT '4. CUSTOMER ACTIVITY',
    'latest=' || MAX(LAST_ACTIVITY_DATE)::VARCHAR
FROM RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW;

-- Demo-critical numbers: agent sees buggy VIEW, notebook fixes it
SELECT 'BUGGY VIEW (agent sees this)' AS check_name,
    'count_distinct_customer_id=' ||
        (SELECT COUNT(DISTINCT CUSTOMER_ID) FROM RETAILBANK_2028.PUBLIC.CUSTOMERS
         WHERE CHURN_RISK_SCORE > 0.6)::VARCHAR ||
    '  (target: ~815)' AS result
UNION ALL
SELECT 'RAW TABLE (after notebook fix)',
    'distinct_customers_above_06=' ||
        (SELECT COUNT(DISTINCT CUSTOMER_ID) FROM RETAILBANK_2028.PUBLIC.CUSTOMERS_RAW
         WHERE CHURN_RISK_SCORE > 0.6)::VARCHAR ||
    '  (target: ~325)';

-- Agent tool check
DESCRIBE AGENT RETAILBANK_2028.PUBLIC.OPERATIONS_AGENT;

SELECT 'Reset complete.' AS status;
