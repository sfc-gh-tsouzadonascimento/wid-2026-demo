-- =============================================================================
-- Step 1: Environment Setup
-- WiD 2026 Demo — "The Future You: A Day in the Life of a Data Professional"
-- =============================================================================
-- Creates database, warehouse, stages, and enables required features.
-- Run this first in Snowsight as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- ─── Database & Schema ───────────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS RETAILBANK_2028
    COMMENT = 'WiD 2026 Demo — RetailBank 2028 fictional dataset';

USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;

-- ─── Warehouse ───────────────────────────────────────────────────────────────
CREATE WAREHOUSE IF NOT EXISTS WID_DEMO_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    COMMENT = 'WiD 2026 Demo warehouse';

USE WAREHOUSE WID_DEMO_WH;

-- ─── Stage for compliance PDFs ───────────────────────────────────────────────
CREATE STAGE IF NOT EXISTS RETAILBANK_2028.PUBLIC.REPORTS_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for compliance/regulatory PDF reports';

-- ─── Enable cross-region inference for Cortex AI ─────────────────────────────
-- Required so Cortex functions can route to available model regions
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- ─── Verify setup ────────────────────────────────────────────────────────────
SHOW DATABASES LIKE 'RETAILBANK_2028';
SHOW WAREHOUSES LIKE 'WID_DEMO_WH';
SHOW STAGES IN SCHEMA RETAILBANK_2028.PUBLIC;

SELECT 'Step 1 complete — environment ready.' AS status;
