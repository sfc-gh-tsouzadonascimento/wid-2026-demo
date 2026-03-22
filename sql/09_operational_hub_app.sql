-- =============================================================================
-- Step 9: Audience Q&A App (SPCS Deployment)
-- WiD 2026 Demo — "The Future You"
-- =============================================================================
-- Deploys the React audience Q&A app as a Snowpark Container Service.
-- Prerequisites:
--   1. Docker image built and pushed to the image repository
--   2. Steps 1-7 completed (database, data, agent all exist)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE RETAILBANK_2028;
USE SCHEMA PUBLIC;

-- ─── Image Repository ───────────────────────────────────────────────────────
CREATE IMAGE REPOSITORY IF NOT EXISTS RETAILBANK_2028.PUBLIC.APP_REPO;

-- Show the registry URL (needed for docker tag/push commands)
SHOW IMAGE REPOSITORIES LIKE 'APP_REPO' IN SCHEMA RETAILBANK_2028.PUBLIC;
-- Copy the repository_url from the output above for docker tag/push

-- ─── Compute Pool ───────────────────────────────────────────────────────────
-- CPU_X64_S with up to 3 nodes supports 200+ concurrent connections
CREATE COMPUTE POOL IF NOT EXISTS AUDIENCE_APP_POOL
    MIN_NODES = 1
    MAX_NODES = 3
    INSTANCE_FAMILY = CPU_X64_S
    COMMENT = 'WiD 2026 Demo — Audience Q&A App';

-- ─── Wait for compute pool ─────────────────────────────────────────────────
-- Run this and wait until state = ACTIVE/IDLE before creating the service
DESCRIBE COMPUTE POOL AUDIENCE_APP_POOL;

-- ─── Service ────────────────────────────────────────────────────────────────
-- IMPORTANT: Before running this, push the Docker image:
--   1. snow spcs image-registry login --connection demo_us
--   2. docker tag audience-app:latest <REPO_URL>/audience-app:latest
--   3. docker push <REPO_URL>/audience-app:latest
-- where <REPO_URL> is the repository_url from SHOW IMAGE REPOSITORIES above.

CREATE SERVICE IF NOT EXISTS RETAILBANK_2028.PUBLIC.AUDIENCE_APP
    IN COMPUTE POOL AUDIENCE_APP_POOL
    QUERY_WAREHOUSE = WID_DEMO_WH
    MIN_INSTANCES = 1
    MAX_INSTANCES = 3
    COMMENT = 'WiD 2026 Demo — Audience Q&A React App'
    FROM SPECIFICATION $$
spec:
  containers:
  - name: audience-app
    image: /retailbank_2028/public/app_repo/audience-app:latest
    env:
      PORT: "8080"
    resources:
      requests:
        memory: 512Mi
        cpu: 500m
      limits:
        memory: 1Gi
        cpu: 1000m
    readinessProbe:
      port: 8080
      path: /health
  endpoints:
  - name: app
    port: 8080
    public: true
$$;

-- ─── Verify ─────────────────────────────────────────────────────────────────
SELECT SYSTEM$GET_SERVICE_STATUS('RETAILBANK_2028.PUBLIC.AUDIENCE_APP');
SHOW ENDPOINTS IN SERVICE RETAILBANK_2028.PUBLIC.AUDIENCE_APP;

-- ─── Grant access ───────────────────────────────────────────────────────────
GRANT SERVICE ROLE RETAILBANK_2028.PUBLIC.AUDIENCE_APP!ALL_ENDPOINTS_USAGE
    TO ROLE ACCOUNTADMIN;

-- ─── Troubleshooting ────────────────────────────────────────────────────────
-- If service won't start, check logs:
-- SELECT SYSTEM$GET_SERVICE_LOGS('RETAILBANK_2028.PUBLIC.AUDIENCE_APP', 0, 'audience-app');

SELECT 'Step 9 complete — Audience Q&A App deployed to SPCS.' AS status;
