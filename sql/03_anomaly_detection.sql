-- =============================================================================
-- Step 3: Anomaly Detection with Snowflake ML
-- WiD 2026 Demo — "The Future You"
-- =============================================================================
-- Trains a SNOWFLAKE.ML.ANOMALY_DETECTION model on the first 80 days of
-- TRANSACTIONS data, then runs detection on the most recent 10 days.
-- The 3 EU_WEST spikes seeded in Step 2 should be detected as anomalies.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;
USE WAREHOUSE WID_DEMO_WH;

-- ─── Training view: first 80 days (clean data) ──────────────────────────────
CREATE OR REPLACE VIEW RETAILBANK_2028.PUBLIC.TRANSACTIONS_TRAINING AS
SELECT
    TRANSACTION_DATE::TIMESTAMP_NTZ AS ts,
    REGION                          AS series,
    TRANSACTION_COUNT               AS target_value
FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS
WHERE TRANSACTION_DATE < CURRENT_DATE() - 10;

-- ─── Detection view: last 10 days (contains the spikes) ─────────────────────
CREATE OR REPLACE VIEW RETAILBANK_2028.PUBLIC.TRANSACTIONS_DETECTION AS
SELECT
    TRANSACTION_DATE::TIMESTAMP_NTZ AS ts,
    REGION                          AS series,
    TRANSACTION_COUNT               AS target_value
FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS
WHERE TRANSACTION_DATE >= CURRENT_DATE() - 10;

-- ─── Train the anomaly detection model ───────────────────────────────────────
-- Multi-series model: one sub-model per REGION.
-- Uses gradient boosting under the hood.
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION txn_anomaly_model(
    INPUT_DATA        => SYSTEM$REFERENCE('VIEW', 'RETAILBANK_2028.PUBLIC.TRANSACTIONS_TRAINING'),
    SERIES_COLNAME    => 'SERIES',
    TIMESTAMP_COLNAME => 'TS',
    TARGET_COLNAME    => 'TARGET_VALUE',
    LABEL_COLNAME     => ''
);

-- ─── Run anomaly detection on the last 10 days ──────────────────────────────
-- Results include: IS_ANOMALY, PERCENTILE, DISTANCE, FORECAST, bounds
CALL txn_anomaly_model!DETECT_ANOMALIES(
    INPUT_DATA        => SYSTEM$REFERENCE('VIEW', 'RETAILBANK_2028.PUBLIC.TRANSACTIONS_DETECTION'),
    SERIES_COLNAME    => 'SERIES',
    TIMESTAMP_COLNAME => 'TS',
    TARGET_COLNAME    => 'TARGET_VALUE',
    CONFIG_OBJECT     => {'prediction_interval': 0.99}
);

-- ─── Persist anomaly results ─────────────────────────────────────────────────
-- Store the results of the last DETECT_ANOMALIES call into a table.
CREATE OR REPLACE TABLE RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES AS
SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ─── Verify: show detected anomalies ────────────────────────────────────────
SELECT
    TS,
    SERIES AS region,
    TARGET_VALUE AS actual_count,
    ROUND(FORECAST, 0) AS forecast_count,
    ROUND(UPPER_BOUND, 0) AS upper_bound,
    ROUND(LOWER_BOUND, 0) AS lower_bound,
    IS_ANOMALY,
    ROUND(PERCENTILE, 4) AS percentile
FROM RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES
WHERE IS_ANOMALY = TRUE
ORDER BY TS;

-- Expected: 3 EU_WEST anomalies at days -3, -6, -8

SELECT 'Step 3 complete — anomaly model trained and anomalies detected.' AS status;
