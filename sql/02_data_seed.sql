-- =============================================================================
-- Step 2: Seed Data
-- WiD 2026 Demo — "The Future You"
-- =============================================================================
-- Creates and populates three tables:
--   TRANSACTIONS  — 90 days × 5 regions (~450 rows), 3 EU_WEST anomaly spikes
--   CUSTOMERS     — 2,000 rows (~800 unique customers, 1:many to accounts)
--   PIPELINE_RUNS — 30 rows, seeded errors for Scenes 1 & 4
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;
USE WAREHOUSE WID_DEMO_WH;

-- ─── TRANSACTIONS ────────────────────────────────────────────────────────────
-- Daily transaction aggregates per region over the last 90 days.
-- Three EU_WEST spikes are seeded so the anomaly detection model can find them.

CREATE OR REPLACE TABLE RETAILBANK_2028.PUBLIC.TRANSACTIONS (
    TRANSACTION_DATE       DATE,
    REGION                 VARCHAR(20),
    TRANSACTION_COUNT      NUMBER,
    TRANSACTION_VALUE      DECIMAL(18,2),
    AVG_TRANSACTION_VALUE  DECIMAL(18,2),
    PCT_CHANGE_VS_7DAY_AVG DECIMAL(8,4)
);

INSERT INTO RETAILBANK_2028.PUBLIC.TRANSACTIONS
WITH date_spine AS (
    SELECT DATEADD(DAY, SEQ4(), CURRENT_DATE() - 90) AS dt
    FROM TABLE(GENERATOR(ROWCOUNT => 90))
),
regions AS (
    SELECT column1 AS region, column2 AS base_count, column3 AS base_value
    FROM VALUES
        ('EU_WEST',   1200, 2400000),
        ('NA_EAST',   1500, 3200000),
        ('APAC',       900, 1800000),
        ('LATAM',      600, 1100000),
        ('EU_NORTH',   800, 1700000)
),
raw_data AS (
    SELECT
        d.dt AS transaction_date,
        r.region,
        -- Base count + daily noise ±15%
        GREATEST(100, ROUND(r.base_count * (1 + (RANDOM() % 15) / 100.0))) AS transaction_count,
        r.base_value AS base_val
    FROM date_spine d
    CROSS JOIN regions r
),
with_spikes AS (
    SELECT
        transaction_date,
        region,
        -- Inject 3 EU_WEST spikes in last 10 days
        CASE
            WHEN region = 'EU_WEST' AND transaction_date = CURRENT_DATE() - 3
                THEN transaction_count * 2.8
            WHEN region = 'EU_WEST' AND transaction_date = CURRENT_DATE() - 6
                THEN transaction_count * 3.1
            WHEN region = 'EU_WEST' AND transaction_date = CURRENT_DATE() - 8
                THEN transaction_count * 2.5
            ELSE transaction_count
        END::NUMBER AS transaction_count,
        base_val
    FROM raw_data
),
with_values AS (
    SELECT
        transaction_date,
        region,
        transaction_count,
        ROUND(transaction_count * (base_val / 1200.0) * (1 + (RANDOM() % 10) / 100.0), 2) AS transaction_value,
        ROUND(transaction_count * (base_val / 1200.0) * (1 + (RANDOM() % 10) / 100.0) / NULLIFZERO(transaction_count), 2) AS avg_transaction_value
    FROM with_spikes
)
SELECT
    transaction_date,
    region,
    transaction_count,
    transaction_value,
    avg_transaction_value,
    ROUND(
        (transaction_count - AVG(transaction_count) OVER (
            PARTITION BY region ORDER BY transaction_date
            ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        )) / NULLIFZERO(AVG(transaction_count) OVER (
            PARTITION BY region ORDER BY transaction_date
            ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        )) * 100, 4
    ) AS pct_change_vs_7day_avg
FROM with_values
ORDER BY transaction_date, region;

-- ─── CUSTOMERS ───────────────────────────────────────────────────────────────
-- ~800 unique customers, each with 1-4 accounts → ~2,000 rows total.
-- Includes churn risk scores and segments for Scene 2 analytics.

CREATE OR REPLACE TABLE RETAILBANK_2028.PUBLIC.CUSTOMERS (
    CUSTOMER_ID               NUMBER,
    ACCOUNT_ID                NUMBER,
    CUSTOMER_NAME             VARCHAR(100),
    SEGMENT                   VARCHAR(30),
    CHURN_RISK_SCORE          DECIMAL(4,2),
    MONTHLY_TRANSACTION_VOLUME NUMBER,
    TRANSACTION_VOLUME_RANK   NUMBER,
    ACCOUNT_OPEN_DATE         DATE,
    REGION                    VARCHAR(20),
    LAST_ACTIVITY_DATE        DATE
);

INSERT INTO RETAILBANK_2028.PUBLIC.CUSTOMERS
WITH segments AS (
    SELECT column1 AS segment, column2 AS weight
    FROM VALUES
        ('RETAIL', 40), ('SMB', 25), ('CORPORATE', 15),
        ('HIGH_NET_WORTH', 12), ('PRIVATE_BANKING', 8)
),
regions AS (
    SELECT column1 AS region
    FROM VALUES ('EU_WEST'), ('NA_EAST'), ('APAC'), ('LATAM'), ('EU_NORTH')
),
-- Generate 800 unique customers
base_customers AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS customer_id,
        'Customer_' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 4, '0') AS customer_name
    FROM TABLE(GENERATOR(ROWCOUNT => 800))
),
-- Assign segments and regions
customer_details AS (
    SELECT
        c.customer_id,
        c.customer_name,
        s.segment,
        r.region,
        ROUND(UNIFORM(0.05::FLOAT, 0.95::FLOAT, RANDOM()), 2) AS churn_risk_score,
        DATEADD(DAY, -UNIFORM(180, 2000, RANDOM()), CURRENT_DATE()) AS account_open_date,
        DATEADD(DAY, -UNIFORM(0, 30, RANDOM()), CURRENT_DATE()) AS last_activity_date
    FROM base_customers c
    CROSS JOIN (SELECT segment FROM segments SAMPLE (100 ROWS)) s
    CROSS JOIN (SELECT region FROM regions SAMPLE (100 ROWS)) r
    QUALIFY ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY RANDOM()) = 1
),
-- Generate 1-4 accounts per customer → ~2000 rows
accounts AS (
    SELECT
        cd.customer_id,
        cd.customer_id * 10 + a.acct_offset AS account_id,
        cd.customer_name,
        cd.segment,
        cd.churn_risk_score,
        UNIFORM(50, 5000, RANDOM()) AS monthly_transaction_volume,
        cd.account_open_date,
        cd.region,
        cd.last_activity_date
    FROM customer_details cd,
    LATERAL (
        SELECT SEQ4() AS acct_offset
        FROM TABLE(GENERATOR(ROWCOUNT => 4))
    ) a
    WHERE a.acct_offset < UNIFORM(1, 4, RANDOM() + cd.customer_id)
)
SELECT
    customer_id,
    account_id,
    customer_name,
    segment,
    churn_risk_score,
    monthly_transaction_volume,
    RANK() OVER (ORDER BY monthly_transaction_volume DESC) AS transaction_volume_rank,
    account_open_date,
    region,
    last_activity_date
FROM accounts;

-- ─── PIPELINE_RUNS ───────────────────────────────────────────────────────────
-- 30 pipeline execution logs. Key rows:
--   • FRAUD_ALERT_MONITOR: AUTO_RESOLVED_COUNT=11, HUMAN_ESCALATED_COUNT=3
--     (Scene 1: LLM often misreports these numbers — the "seeded error")
--   • CHURN_PREDICTION_REFRESH: AI_GENERATED=TRUE, status='SUCCESS'
--     (Scene 4: the AI-generated pipeline with the join-key bug)

CREATE OR REPLACE TABLE RETAILBANK_2028.PUBLIC.PIPELINE_RUNS (
    RUN_ID                 NUMBER,
    PIPELINE_NAME          VARCHAR(100),
    RUN_TIMESTAMP          TIMESTAMP_NTZ,
    STATUS                 VARCHAR(20),
    DURATION_SECONDS       NUMBER,
    RECORDS_PROCESSED      NUMBER,
    AI_GENERATED           BOOLEAN,
    PIPELINE_CODE          VARCHAR(5000),
    ERROR_MESSAGE          VARCHAR(1000),
    AUTO_RESOLVED_COUNT    NUMBER,
    HUMAN_ESCALATED_COUNT  NUMBER
);

INSERT INTO RETAILBANK_2028.PUBLIC.PIPELINE_RUNS VALUES
-- Last night's runs (most recent first)
(1,  'FRAUD_ALERT_MONITOR',       DATEADD(HOUR, -2, CURRENT_TIMESTAMP()), 'SUCCESS',    45,   14,    FALSE, NULL, NULL, 11, 3),
(2,  'CHURN_PREDICTION_REFRESH',  DATEADD(HOUR, -3, CURRENT_TIMESTAMP()), 'SUCCESS',   180, 2000,    TRUE,
     'SELECT c.CUSTOMER_NAME, c.SEGMENT, c.CHURN_RISK_SCORE, COUNT(DISTINCT a.ACCOUNT_ID) AS account_count, SUM(a.MONTHLY_TRANSACTION_VOLUME) AS total_volume FROM RETAILBANK_2028.PUBLIC.CUSTOMERS c JOIN RETAILBANK_2028.PUBLIC.CUSTOMERS a ON c.CUSTOMER_ID = a.ACCOUNT_ID WHERE c.CHURN_RISK_SCORE > 0.6 GROUP BY 1, 2, 3 ORDER BY c.CHURN_RISK_SCORE DESC',
     NULL, NULL, NULL),
(3,  'TRANSACTION_ETL',           DATEADD(HOUR, -4, CURRENT_TIMESTAMP()), 'SUCCESS',   120, 45000,   FALSE, NULL, NULL, NULL, NULL),
(4,  'CUSTOMER_SEGMENTATION',     DATEADD(HOUR, -5, CURRENT_TIMESTAMP()), 'SUCCESS',    90,  800,    TRUE,  NULL, NULL, NULL, NULL),
(5,  'ANOMALY_DETECTION_NIGHTLY', DATEADD(HOUR, -6, CURRENT_TIMESTAMP()), 'SUCCESS',    60,  450,    FALSE, NULL, NULL, NULL, NULL),
(6,  'COMPLIANCE_REPORT_INGEST',  DATEADD(HOUR, -7, CURRENT_TIMESTAMP()), 'SUCCESS',   200,   30,    FALSE, NULL, NULL, NULL, NULL),
(7,  'RISK_SCORE_RECALC',         DATEADD(HOUR, -8, CURRENT_TIMESTAMP()), 'SUCCESS',   150, 2000,    TRUE,  NULL, NULL, NULL, NULL),
(8,  'BALANCE_SNAPSHOT',          DATEADD(HOUR, -9, CURRENT_TIMESTAMP()), 'SUCCESS',    30, 12000,   FALSE, NULL, NULL, NULL, NULL),
-- Two days ago
(9,  'FRAUD_ALERT_MONITOR',       DATEADD(HOUR, -26, CURRENT_TIMESTAMP()), 'SUCCESS',   42,   10,   FALSE, NULL, NULL,  8, 2),
(10, 'CHURN_PREDICTION_REFRESH',  DATEADD(HOUR, -27, CURRENT_TIMESTAMP()), 'SUCCESS',  175, 2000,    TRUE,  NULL, NULL, NULL, NULL),
(11, 'TRANSACTION_ETL',           DATEADD(HOUR, -28, CURRENT_TIMESTAMP()), 'SUCCESS',  118, 43000,   FALSE, NULL, NULL, NULL, NULL),
(12, 'ANOMALY_DETECTION_NIGHTLY', DATEADD(HOUR, -30, CURRENT_TIMESTAMP()), 'SUCCESS',   58,  450,    FALSE, NULL, NULL, NULL, NULL),
-- Three days ago — a failure + restart
(13, 'FRAUD_ALERT_MONITOR',       DATEADD(HOUR, -50, CURRENT_TIMESTAMP()), 'SUCCESS',   44,   12,   FALSE, NULL, NULL,  9, 3),
(14, 'TRANSACTION_ETL',           DATEADD(HOUR, -52, CURRENT_TIMESTAMP()), 'FAILED',     5,    0,   FALSE, NULL, 'Connection timeout to source system', NULL, NULL),
(15, 'TRANSACTION_ETL',           DATEADD(HOUR, -51, CURRENT_TIMESTAMP()), 'RESTARTED', 125, 44000,  FALSE, NULL, NULL, NULL, NULL),
(16, 'CHURN_PREDICTION_REFRESH',  DATEADD(HOUR, -53, CURRENT_TIMESTAMP()), 'SUCCESS',  182, 2000,    TRUE,  NULL, NULL, NULL, NULL),
(17, 'COMPLIANCE_REPORT_INGEST',  DATEADD(HOUR, -54, CURRENT_TIMESTAMP()), 'SUCCESS',  198,   28,    FALSE, NULL, NULL, NULL, NULL),
(18, 'BALANCE_SNAPSHOT',          DATEADD(HOUR, -55, CURRENT_TIMESTAMP()), 'SUCCESS',   32, 12000,   FALSE, NULL, NULL, NULL, NULL),
-- Four days ago
(19, 'FRAUD_ALERT_MONITOR',       DATEADD(HOUR, -74, CURRENT_TIMESTAMP()), 'SUCCESS',   40,    8,   FALSE, NULL, NULL,  7, 1),
(20, 'ANOMALY_DETECTION_NIGHTLY', DATEADD(HOUR, -78, CURRENT_TIMESTAMP()), 'SUCCESS',   62,  450,    FALSE, NULL, NULL, NULL, NULL),
-- Five days ago
(21, 'FRAUD_ALERT_MONITOR',       DATEADD(HOUR, -98, CURRENT_TIMESTAMP()), 'SUCCESS',   38,   11,   FALSE, NULL, NULL, 10, 1),
(22, 'TRANSACTION_ETL',           DATEADD(HOUR, -100, CURRENT_TIMESTAMP()), 'SUCCESS', 115, 42000,   FALSE, NULL, NULL, NULL, NULL),
(23, 'CUSTOMER_SEGMENTATION',     DATEADD(HOUR, -102, CURRENT_TIMESTAMP()), 'SUCCESS',  88,  800,    TRUE,  NULL, NULL, NULL, NULL),
(24, 'RISK_SCORE_RECALC',         DATEADD(HOUR, -104, CURRENT_TIMESTAMP()), 'SUCCESS', 148, 2000,    TRUE,  NULL, NULL, NULL, NULL),
-- Six days ago
(25, 'FRAUD_ALERT_MONITOR',       DATEADD(HOUR, -122, CURRENT_TIMESTAMP()), 'SUCCESS',  41,    9,   FALSE, NULL, NULL,  8, 1),
(26, 'COMPLIANCE_REPORT_INGEST',  DATEADD(HOUR, -126, CURRENT_TIMESTAMP()), 'SUCCESS', 195,   30,    FALSE, NULL, NULL, NULL, NULL),
-- Seven days ago
(27, 'FRAUD_ALERT_MONITOR',       DATEADD(HOUR, -146, CURRENT_TIMESTAMP()), 'SUCCESS',  43,   13,   FALSE, NULL, NULL, 11, 2),
(28, 'TRANSACTION_ETL',           DATEADD(HOUR, -148, CURRENT_TIMESTAMP()), 'SUCCESS', 122, 44500,   FALSE, NULL, NULL, NULL, NULL),
(29, 'ANOMALY_DETECTION_NIGHTLY', DATEADD(HOUR, -150, CURRENT_TIMESTAMP()), 'SUCCESS',  59,  450,    FALSE, NULL, NULL, NULL, NULL),
(30, 'BALANCE_SNAPSHOT',          DATEADD(HOUR, -152, CURRENT_TIMESTAMP()), 'SUCCESS',  31, 12000,   FALSE, NULL, NULL, NULL, NULL);

-- ─── Verify ──────────────────────────────────────────────────────────────────
SELECT 'TRANSACTIONS' AS tbl, COUNT(*) AS row_count FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS
UNION ALL
SELECT 'CUSTOMERS', COUNT(*) FROM RETAILBANK_2028.PUBLIC.CUSTOMERS
UNION ALL
SELECT 'PIPELINE_RUNS', COUNT(*) FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS;

-- Check EU_WEST spikes exist
SELECT TRANSACTION_DATE, REGION, TRANSACTION_COUNT
FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS
WHERE REGION = 'EU_WEST'
  AND TRANSACTION_DATE >= CURRENT_DATE() - 10
ORDER BY TRANSACTION_DATE;

SELECT 'Step 2 complete — data seeded.' AS status;
