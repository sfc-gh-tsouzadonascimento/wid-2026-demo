-- =============================================================================
-- Step 6: Semantic View for Cortex Analyst
-- WiD 2026 Demo — "The Future You"
-- =============================================================================
-- Creates a semantic view over TRANSACTIONS, CUSTOMERS, TRANSACTION_ANOMALIES,
-- and PIPELINE_RUNS. Powers Scene 2 (ad-hoc executive questions → SQL + charts)
-- and is used by the Cortex Agent's BankAnalyst tool.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;
USE WAREHOUSE WID_DEMO_WH;

CREATE OR REPLACE SEMANTIC VIEW RETAILBANK_2028.PUBLIC.BANK_ANALYTICS
AS YAML $$
name: bank_analytics
description: >
  RetailBank 2028 analytics covering daily transactions by region, customer
  segments with churn risk, ML-detected anomalies, and pipeline execution logs
  including fraud alert monitoring.

tables:
  - name: customers
    base_table:
      database: RETAILBANK_2028
      schema: PUBLIC
      table: CUSTOMERS
    description: >
      Customer accounts with churn risk scores and segmentation.
      One customer (CUSTOMER_ID) can have multiple accounts (ACCOUNT_ID).
    dimensions:
      - name: customer_name
        expr: CUSTOMER_NAME
        description: "Customer full name"
        data_type: VARCHAR
      - name: segment
        expr: SEGMENT
        description: "Customer segment: RETAIL, SMB, CORPORATE, HIGH_NET_WORTH, PRIVATE_BANKING"
        data_type: VARCHAR
      - name: region
        expr: REGION
        description: "Customer region: EU_WEST, NA_EAST, APAC, LATAM, EU_NORTH"
        data_type: VARCHAR
      - name: account_open_date
        expr: ACCOUNT_OPEN_DATE
        description: "Date the account was opened"
        data_type: DATE
      - name: last_activity_date
        expr: LAST_ACTIVITY_DATE
        description: "Date of last account activity"
        data_type: DATE
      - name: transaction_volume_rank
        expr: TRANSACTION_VOLUME_RANK
        description: "Rank by monthly transaction volume (1 = highest). Filter top N with WHERE transaction_volume_rank <= N."
        data_type: NUMBER
    measures:
      - name: churn_risk_score
        expr: CHURN_RISK_SCORE
        description: "Churn risk 0.00-1.00. Above 0.6 is high risk."
        data_type: DECIMAL
        default_aggregation: avg
      - name: monthly_transaction_volume
        expr: MONTHLY_TRANSACTION_VOLUME
        description: "Monthly transaction volume count"
        data_type: NUMBER
        default_aggregation: sum
      - name: customer_count
        expr: CUSTOMER_ID
        description: "Count of unique customers"
        data_type: NUMBER
        default_aggregation: count_distinct
      - name: account_count
        expr: ACCOUNT_ID
        description: "Count of accounts (one customer can have multiple)"
        data_type: NUMBER
        default_aggregation: count_distinct

  - name: transactions
    base_table:
      database: RETAILBANK_2028
      schema: PUBLIC
      table: TRANSACTIONS
    description: "Daily transaction aggregates by region over 90 days"
    dimensions:
      - name: transaction_date
        expr: TRANSACTION_DATE
        description: "Date of transactions"
        data_type: DATE
      - name: txn_region
        expr: REGION
        description: "Region: EU_WEST, NA_EAST, APAC, LATAM, EU_NORTH"
        data_type: VARCHAR
    measures:
      - name: transaction_count
        expr: TRANSACTION_COUNT
        description: "Number of transactions on this date in this region"
        data_type: NUMBER
        default_aggregation: sum
      - name: transaction_value
        expr: TRANSACTION_VALUE
        description: "Total monetary value of transactions"
        data_type: DECIMAL
        default_aggregation: sum
      - name: avg_transaction_value
        expr: AVG_TRANSACTION_VALUE
        description: "Average transaction value for the date/region"
        data_type: DECIMAL
        default_aggregation: avg
      - name: pct_change
        expr: PCT_CHANGE_VS_7DAY_AVG
        description: "Percentage change vs 7-day rolling average"
        data_type: DECIMAL
        default_aggregation: avg

  - name: anomalies
    base_table:
      database: RETAILBANK_2028
      schema: PUBLIC
      table: TRANSACTION_ANOMALIES
    description: "ML-detected anomalies from Snowflake ANOMALY_DETECTION model"
    dimensions:
      - name: anomaly_date
        expr: TS
        description: "Timestamp of the observation"
        data_type: TIMESTAMP
      - name: anomaly_region
        expr: SERIES
        description: "Region where anomaly was evaluated"
        data_type: VARCHAR
      - name: is_anomaly
        expr: IS_ANOMALY
        description: "TRUE if the ML model flagged this as anomalous"
        data_type: BOOLEAN
    measures:
      - name: actual_value
        expr: "Y"
        description: "Actual transaction count"
        data_type: NUMBER
        default_aggregation: sum
      - name: forecast_value
        expr: FORECAST
        description: "ML model forecast value"
        data_type: FLOAT
        default_aggregation: avg
      - name: upper_bound
        expr: UPPER_BOUND
        description: "Upper prediction interval bound"
        data_type: FLOAT
        default_aggregation: avg
      - name: lower_bound
        expr: LOWER_BOUND
        description: "Lower prediction interval bound"
        data_type: FLOAT
        default_aggregation: avg
      - name: anomaly_count
        expr: "CASE WHEN IS_ANOMALY THEN 1 ELSE 0 END"
        description: "Count of anomalies"
        data_type: NUMBER
        default_aggregation: sum

  - name: pipeline_runs
    base_table:
      database: RETAILBANK_2028
      schema: PUBLIC
      table: PIPELINE_RUNS
    description: "Log of automated pipeline executions including fraud alert results"
    dimensions:
      - name: pipeline_name
        expr: PIPELINE_NAME
        description: "Name of the pipeline"
        data_type: VARCHAR
      - name: run_timestamp
        expr: RUN_TIMESTAMP
        description: "When the pipeline ran"
        data_type: TIMESTAMP
      - name: status
        expr: STATUS
        description: "Pipeline status: SUCCESS, FAILED, RESTARTED"
        data_type: VARCHAR
      - name: is_ai_generated
        expr: AI_GENERATED
        description: "Whether the pipeline was AI-generated"
        data_type: BOOLEAN
    measures:
      - name: duration_seconds
        expr: DURATION_SECONDS
        description: "Pipeline run duration in seconds"
        data_type: NUMBER
        default_aggregation: avg
      - name: records_processed
        expr: RECORDS_PROCESSED
        description: "Number of records processed"
        data_type: NUMBER
        default_aggregation: sum
      - name: auto_resolved_count
        expr: AUTO_RESOLVED_COUNT
        description: "Fraud alerts auto-resolved by the system (NOT human-escalated)"
        data_type: NUMBER
        default_aggregation: sum
      - name: human_escalated_count
        expr: HUMAN_ESCALATED_COUNT
        description: "Fraud alerts escalated to human review (NOT auto-resolved)"
        data_type: NUMBER
        default_aggregation: sum

relationships:
  - left_table: customers
    right_table: transactions
    join_type: inner
    relationship_columns:
      - left_column: region
        right_column: txn_region

verified_queries:
  - name: churn_risk_by_segment_top50
    question: "Which customer segments have the highest churn risk among top 50 accounts?"
    sql: >
      SELECT SEGMENT, AVG(CHURN_RISK_SCORE) AS avg_churn_risk,
             COUNT(DISTINCT CUSTOMER_ID) AS customer_count
      FROM RETAILBANK_2028.PUBLIC.CUSTOMERS
      WHERE TRANSACTION_VOLUME_RANK <= 50
      GROUP BY SEGMENT
      ORDER BY avg_churn_risk DESC

  - name: overnight_anomalies
    question: "Show me overnight anomalies detected by the ML model"
    sql: >
      SELECT TS, SERIES AS region, Y AS actual, FORECAST,
             UPPER_BOUND, LOWER_BOUND, IS_ANOMALY
      FROM RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES
      WHERE IS_ANOMALY = TRUE
      ORDER BY TS DESC

  - name: fraud_alert_counts
    question: "Show me the raw fraud alert counts from last night"
    sql: >
      SELECT PIPELINE_NAME, RUN_TIMESTAMP, AUTO_RESOLVED_COUNT, HUMAN_ESCALATED_COUNT
      FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS
      WHERE PIPELINE_NAME = 'FRAUD_ALERT_MONITOR'
      ORDER BY RUN_TIMESTAMP DESC
      LIMIT 1

  - name: transaction_value_by_region_7d
    question: "Total transaction value by region for the last 7 days"
    sql: >
      SELECT REGION, SUM(TRANSACTION_VALUE) AS total_value
      FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS
      WHERE TRANSACTION_DATE >= CURRENT_DATE() - 7
      GROUP BY REGION
      ORDER BY total_value DESC

custom_instructions: |
  When asked about "top N" accounts or customers, filter using TRANSACTION_VOLUME_RANK <= N.
  When asked about "overnight" data, use the most recent date available.
  Always prefer charts for comparisons and trends.
  Use bar charts for segment comparisons and line charts for time series.
  When asked about fraud alerts, clearly distinguish AUTO_RESOLVED_COUNT from HUMAN_ESCALATED_COUNT.
$$;

-- Verify
DESCRIBE SEMANTIC VIEW RETAILBANK_2028.PUBLIC.BANK_ANALYTICS;

SELECT 'Step 6 complete — semantic view created.' AS status;
