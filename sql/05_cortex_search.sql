-- =============================================================================
-- Step 5: Cortex Search Service
-- WiD 2026 Demo — "The Future You"
-- =============================================================================
-- Parses 30 compliance PDFs from @REPORTS_STAGE using AI_PARSE_DOCUMENT,
-- chunks them into ~2000-character segments, and creates a Cortex Search
-- service for semantic search in Scene 3.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;
USE WAREHOUSE WID_DEMO_WH;

-- ─── Step 5a: Parse all PDFs ─────────────────────────────────────────────────
-- Uses AI_PARSE_DOCUMENT in LAYOUT mode for structured text extraction.
-- Requires the stage directory to be refreshed (done in 04_generate_pdfs.py).

CREATE OR REPLACE TABLE RETAILBANK_2028.PUBLIC.REPORT_PARSED AS
SELECT
    RELATIVE_PATH                        AS file_name,
    AI_PARSE_DOCUMENT(
        @RETAILBANK_2028.PUBLIC.REPORTS_STAGE,
        RELATIVE_PATH,
        {'mode': 'LAYOUT'}
    ):content::VARCHAR                   AS content
FROM DIRECTORY(@RETAILBANK_2028.PUBLIC.REPORTS_STAGE)
WHERE RELATIVE_PATH LIKE '%.pdf';

-- Verify parsed documents
SELECT file_name, LENGTH(content) AS content_length
FROM RETAILBANK_2028.PUBLIC.REPORT_PARSED
ORDER BY file_name;

-- ─── Step 5b: Chunk parsed content ──────────────────────────────────────────
-- ~2000-character chunks with 200-character overlap for context continuity.

CREATE OR REPLACE TABLE RETAILBANK_2028.PUBLIC.REPORT_CHUNKS AS
WITH RECURSIVE chunker AS (
    -- First chunk from each document
    SELECT
        file_name,
        SUBSTRING(content, 1, 2000)  AS chunk_text,
        1                            AS chunk_index,
        content                      AS remaining_content
    FROM RETAILBANK_2028.PUBLIC.REPORT_PARSED

    UNION ALL

    -- Subsequent chunks with 200-char overlap
    SELECT
        file_name,
        SUBSTRING(remaining_content, 1801, 2000) AS chunk_text,
        chunk_index + 1,
        SUBSTRING(remaining_content, 1801)       AS remaining_content
    FROM chunker
    WHERE LENGTH(remaining_content) > 2000
)
SELECT
    file_name || '_chunk_' || chunk_index AS doc_chunk_id,
    file_name,
    chunk_text                            AS content,
    chunk_index
FROM chunker
WHERE LENGTH(chunk_text) > 50;

-- Verify chunks
SELECT
    COUNT(*)                AS total_chunks,
    COUNT(DISTINCT file_name) AS total_docs,
    ROUND(AVG(LENGTH(content)), 0) AS avg_chunk_length
FROM RETAILBANK_2028.PUBLIC.REPORT_CHUNKS;

-- ─── Step 5c: Create Cortex Search Service ──────────────────────────────────
-- This service powers the ComplianceSearch tool in the Cortex Agent (Scene 3)
-- and can also be used directly in Snowflake Intelligence.

CREATE OR REPLACE CORTEX SEARCH SERVICE RETAILBANK_2028.PUBLIC.COMPLIANCE_REPORTS_SEARCH
    ON content
    ATTRIBUTES file_name
    WAREHOUSE = WID_DEMO_WH
    TARGET_LAG = '1 hour'
AS
    SELECT
        doc_chunk_id,
        file_name,
        content
    FROM RETAILBANK_2028.PUBLIC.REPORT_CHUNKS;

-- Verify search service
SHOW CORTEX SEARCH SERVICES IN SCHEMA RETAILBANK_2028.PUBLIC;

SELECT 'Step 5 complete — Cortex Search service created.' AS status;
