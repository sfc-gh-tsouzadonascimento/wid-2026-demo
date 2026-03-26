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
--  5b. Flips any FAILED/RESTARTED pipeline runs to SUCCESS (dashboard all-green)
--  5c. Sets latest-day PCT_CHANGE_VS_7DAY_AVG positive (dashboard all-green)
--   6. Ensures CUSTOMERS_RAW table exists and creates buggy CUSTOMERS VIEW
--      (pipeline confused account_id with customer_id — the bug the notebook
--      discovers and fixes)
--  6b. Recreates semantic view BANK_ANALYTICS with high_risk_customer_count
--      measure, churn-specific custom instructions, and verified queries so
--      Snowflake Intelligence reliably returns the buggy inflated churn count
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

-- ─── 5b. Ensure all pipeline runs are SUCCESS ───────────────────────────────
-- The dashboard shows pipeline_success_rate with a green arrow only when >= 95%.
-- Flip any FAILED or RESTARTED runs to SUCCESS so the dashboard is all-green.

UPDATE RETAILBANK_2028.PUBLIC.PIPELINE_RUNS
SET STATUS = 'SUCCESS'
WHERE STATUS IN ('FAILED', 'RESTARTED');

-- ─── 5c. Ensure latest-day pct_change is positive ──────────────────────────
-- The dashboard shows daily_pct_change with a green arrow only when > 0.
-- Set all latest-day PCT_CHANGE_VS_7DAY_AVG to a small positive value so the
-- average is positive and the dashboard is all-green.

UPDATE RETAILBANK_2028.PUBLIC.TRANSACTIONS
SET PCT_CHANGE_VS_7DAY_AVG = ROUND(UNIFORM(1.5::FLOAT, 8.0::FLOAT, RANDOM()), 2)
WHERE TRANSACTION_DATE = (SELECT MAX(TRANSACTION_DATE) FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS);

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

-- ─── 6b. Recreate semantic view BANK_ANALYTICS ──────────────────────────────
-- The semantic view must have:
--   - high_risk_customer_count measure (CASE WHEN > 0.6 THEN 1 ELSE 0 END)
--   - custom_instruction telling Cortex Analyst NOT to join tables for churn count
--   - verified queries anchoring churn count to the CUSTOMERS view
-- This ensures Snowflake Intelligence returns the buggy-view-inflated churn
-- number (~815) rather than the real count (~325).
--
-- NOTE: Uses native DDL format (not YAML $$) so it works via snowflake_sql_execute.
-- When running via Snowsight worksheet, you can run this statement as-is.

CREATE OR REPLACE SEMANTIC VIEW RETAILBANK_2028.PUBLIC.BANK_ANALYTICS
	tables (
		RETAILBANK_2028.PUBLIC.CUSTOMERS comment='Customer accounts with churn risk scores and segmentation. One customer (CUSTOMER_ID) can have multiple accounts (ACCOUNT_ID).',
		RETAILBANK_2028.PUBLIC.TRANSACTIONS comment='Daily transaction aggregates by region over 90 days',
		ANOMALIES as RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES comment='ML-detected anomalies from Snowflake ANOMALY_DETECTION model',
		RETAILBANK_2028.PUBLIC.PIPELINE_RUNS comment='Log of automated pipeline executions including fraud alert results'
	)
	dimensions (
		CUSTOMERS.CUSTOMER_NAME as CUSTOMER_NAME comment='Customer full name',
		CUSTOMERS.SEGMENT as SEGMENT comment='Customer segment: RETAIL, SMB, CORPORATE, HIGH_NET_WORTH, PRIVATE_BANKING',
		CUSTOMERS.REGION as REGION comment='Customer region: EU_WEST, NA_EAST, APAC, LATAM, EU_NORTH',
		CUSTOMERS.ACCOUNT_OPEN_DATE as ACCOUNT_OPEN_DATE comment='Date the account was opened',
		CUSTOMERS.LAST_ACTIVITY_DATE as LAST_ACTIVITY_DATE comment='Date of last account activity',
		CUSTOMERS.TRANSACTION_VOLUME_RANK as TRANSACTION_VOLUME_RANK comment='Rank by monthly transaction volume (1 = highest). Filter top N with WHERE transaction_volume_rank <= N.',
		TRANSACTIONS.TRANSACTION_DATE as TRANSACTION_DATE comment='Date of transactions',
		TRANSACTIONS.TXN_REGION as REGION comment='Region: EU_WEST, NA_EAST, APAC, LATAM, EU_NORTH',
		ANOMALIES.ANOMALY_DATE as TS comment='Timestamp of the observation',
		ANOMALIES.ANOMALY_REGION as SERIES comment='Region where anomaly was evaluated',
		ANOMALIES.IS_ANOMALY as IS_ANOMALY comment='TRUE if the ML model flagged this as anomalous',
		PIPELINE_RUNS.PIPELINE_NAME as PIPELINE_NAME comment='Name of the pipeline',
		PIPELINE_RUNS.RUN_TIMESTAMP as RUN_TIMESTAMP comment='When the pipeline ran',
		PIPELINE_RUNS.STATUS as STATUS comment='Pipeline status: SUCCESS, FAILED, RESTARTED',
		PIPELINE_RUNS.IS_AI_GENERATED as AI_GENERATED comment='Whether the pipeline was AI-generated'
	)
	comment='RetailBank 2028 analytics covering daily transactions by region, customer segments with churn risk, ML-detected anomalies, and pipeline execution logs including fraud alert monitoring.'
	ai_sql_generation 'When asked about "top N" accounts or customers, filter using TRANSACTION_VOLUME_RANK <= N.
When asked about "overnight" data, use the most recent date available.
Always prefer charts for comparisons and trends.
Use bar charts for segment comparisons and line charts for time series.
When asked about fraud alerts, clearly distinguish AUTO_RESOLVED_COUNT from HUMAN_ESCALATED_COUNT.
When asked about customers at risk of churn, always use: SELECT COUNT(DISTINCT CUSTOMER_ID) AS customers_at_risk FROM RETAILBANK_2028.PUBLIC.CUSTOMERS WHERE CHURN_RISK_SCORE > 0.6. Do NOT join with other tables for this query.'
	with extension (CA='{"tables":[{"name":"customers","dimensions":[{"name":"customer_name"},{"name":"segment"},{"name":"region"},{"name":"account_open_date"},{"name":"last_activity_date"},{"name":"transaction_volume_rank"}],"measures":[{"name":"churn_risk_score","expr":"CHURN_RISK_SCORE","description":"Churn risk 0.00-1.00. Above 0.6 is high risk.","data_type":"DECIMAL","default_aggregation":"avg"},{"name":"monthly_transaction_volume","expr":"MONTHLY_TRANSACTION_VOLUME","description":"Monthly transaction volume count","data_type":"NUMBER","default_aggregation":"sum"},{"name":"customer_count","expr":"CUSTOMER_ID","description":"Count of unique customers. Use COUNT(DISTINCT CUSTOMER_ID) from CUSTOMERS table only — do not join with other tables when counting customers.","data_type":"NUMBER","default_aggregation":"count_distinct"},{"name":"high_risk_customer_count","expr":"CASE WHEN CHURN_RISK_SCORE > 0.6 THEN 1 ELSE 0 END","description":"Count of customers at risk of churn (score above 0.6). Use SUM of this measure for total at-risk count.","data_type":"NUMBER","default_aggregation":"sum"},{"name":"account_count","expr":"ACCOUNT_ID","description":"Count of accounts (one customer can have multiple)","data_type":"NUMBER","default_aggregation":"count_distinct"}]},{"name":"transactions","dimensions":[{"name":"transaction_date"},{"name":"txn_region"}],"measures":[{"name":"transaction_count","expr":"TRANSACTION_COUNT","description":"Number of transactions on this date in this region","data_type":"NUMBER","default_aggregation":"sum"},{"name":"transaction_value","expr":"TRANSACTION_VALUE","description":"Total monetary value of transactions","data_type":"DECIMAL","default_aggregation":"sum"},{"name":"avg_transaction_value","expr":"AVG_TRANSACTION_VALUE","description":"Average transaction value for the date/region","data_type":"DECIMAL","default_aggregation":"avg"},{"name":"pct_change","expr":"PCT_CHANGE_VS_7DAY_AVG","description":"Percentage change vs 7-day rolling average","data_type":"DECIMAL","default_aggregation":"avg"}]},{"name":"anomalies","dimensions":[{"name":"anomaly_date"},{"name":"anomaly_region"},{"name":"is_anomaly"}],"measures":[{"name":"actual_value","expr":"Y","description":"Actual transaction count","data_type":"NUMBER","default_aggregation":"sum"},{"name":"forecast_value","expr":"FORECAST","description":"ML model forecast value","data_type":"FLOAT","default_aggregation":"avg"},{"name":"upper_bound","expr":"UPPER_BOUND","description":"Upper prediction interval bound","data_type":"FLOAT","default_aggregation":"avg"},{"name":"lower_bound","expr":"LOWER_BOUND","description":"Lower prediction interval bound","data_type":"FLOAT","default_aggregation":"avg"},{"name":"anomaly_count","expr":"CASE WHEN IS_ANOMALY THEN 1 ELSE 0 END","description":"Count of anomalies","data_type":"NUMBER","default_aggregation":"sum"}]},{"name":"pipeline_runs","dimensions":[{"name":"pipeline_name"},{"name":"run_timestamp"},{"name":"status"},{"name":"is_ai_generated"}],"measures":[{"name":"duration_seconds","expr":"DURATION_SECONDS","description":"Pipeline run duration in seconds","data_type":"NUMBER","default_aggregation":"avg"},{"name":"records_processed","expr":"RECORDS_PROCESSED","description":"Number of records processed","data_type":"NUMBER","default_aggregation":"sum"},{"name":"auto_resolved_count","expr":"AUTO_RESOLVED_COUNT","description":"Fraud alerts auto-resolved by the system (NOT human-escalated)","data_type":"NUMBER","default_aggregation":"sum"},{"name":"human_escalated_count","expr":"HUMAN_ESCALATED_COUNT","description":"Fraud alerts escalated to human review (NOT auto-resolved)","data_type":"NUMBER","default_aggregation":"sum"}]}],"verified_queries":[{"name":"churn_risk_by_segment_top50","question":"Which customer segments have the highest churn risk among top 50 accounts?","sql":"SELECT SEGMENT, AVG(CHURN_RISK_SCORE) AS avg_churn_risk, COUNT(DISTINCT CUSTOMER_ID) AS customer_count FROM RETAILBANK_2028.PUBLIC.CUSTOMERS WHERE TRANSACTION_VOLUME_RANK <= 50 GROUP BY SEGMENT ORDER BY avg_churn_risk DESC"},{"name":"overnight_anomalies","question":"Show me overnight anomalies detected by the ML model","sql":"SELECT TS, SERIES AS region, Y AS actual, FORECAST, UPPER_BOUND, LOWER_BOUND, IS_ANOMALY FROM RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES WHERE IS_ANOMALY = TRUE ORDER BY TS DESC"},{"name":"fraud_alert_counts","question":"Show me the raw fraud alert counts from last night","sql":"SELECT PIPELINE_NAME, RUN_TIMESTAMP, AUTO_RESOLVED_COUNT, HUMAN_ESCALATED_COUNT FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS WHERE PIPELINE_NAME = ''FRAUD_ALERT_MONITOR'' ORDER BY RUN_TIMESTAMP DESC LIMIT 1"},{"name":"transaction_value_by_region_7d","question":"Total transaction value by region for the last 7 days","sql":"SELECT REGION, SUM(TRANSACTION_VALUE) AS total_value FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS WHERE TRANSACTION_DATE >= CURRENT_DATE() - 7 GROUP BY REGION ORDER BY total_value DESC"},{"name":"customers_at_risk_of_churn","question":"How many customers are at risk of churn?","sql":"SELECT COUNT(DISTINCT CUSTOMER_ID) AS customers_at_risk FROM RETAILBANK_2028.PUBLIC.CUSTOMERS WHERE CHURN_RISK_SCORE > 0.6"},{"name":"morning_briefing_churn","question":"What is the number of customers at risk of churn based on current risk scores?","sql":"SELECT COUNT(DISTINCT CUSTOMER_ID) AS customers_at_risk FROM RETAILBANK_2028.PUBLIC.CUSTOMERS WHERE CHURN_RISK_SCORE > 0.6"}]}');

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
