-- =====================================================================
-- R04 POWER BI ACCESS
-- PART A runs with your own privileges. PART B needs the account admin
-- (it is also in ADMIN_REQUEST.sql). Until PART B is done, connect Power BI
-- Desktop as your own user for the repointing demo.
-- =====================================================================

-- ---------- PART A1: USERADMIN (you have CREATE ROLE / CREATE USER) ----------
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS POC_BI_READER COMMENT = 'SnowConvert POC - Power BI read access to compat views';
CREATE USER IF NOT EXISTS SVC_POC_POWERBI
  TYPE = SERVICE                       -- LEGACY_SERVICE no longer exists; Power BI uses a PAT as the password
  DEFAULT_ROLE = POC_BI_READER
  DEFAULT_WAREHOUSE = CORTEX_AI_WH
  DEFAULT_NAMESPACE = 'CORTEX_AI.DATA'
  COMMENT = 'SnowConvert POC - Power BI semantic model refresh';
-- Password login is not possible for SERVICE users; generate a PAT after ADMIN_REQUEST tier 1 (see below).
ALTER USER SVC_POC_POWERBI SET QUERY_TAG = 'app=powerbi;poc=snowconvert';
GRANT ROLE POC_BI_READER TO USER SVC_POC_POWERBI;

-- ---------- PART A2: object grants you CAN make (you own the views dbt creates) ----------
USE ROLE CORTEX_AI_FULL_ACCESS_ROLE;
GRANT SELECT ON VIEW CORTEX_AI.DATA.DIMCUSTOMER     TO ROLE POC_BI_READER;
GRANT SELECT ON VIEW CORTEX_AI.DATA.DIMPRODUCT      TO ROLE POC_BI_READER;
GRANT SELECT ON VIEW CORTEX_AI.DATA.DIMDATE         TO ROLE POC_BI_READER;
GRANT SELECT ON VIEW CORTEX_AI.DATA.FACTSALES       TO ROLE POC_BI_READER;
GRANT SELECT ON VIEW CORTEX_AI.DATA.FACTSALES_ERROR TO ROLE POC_BI_READER;
GRANT SELECT ON VIEW CORTEX_AI.DATA.VW_SALESBYMONTH TO ROLE POC_BI_READER;

-- ---------- PART B: ADMIN ONLY (you lack grant option on these) ----------
-- GRANT USAGE ON DATABASE  CORTEX_AI      TO ROLE POC_BI_READER;
-- GRANT USAGE ON SCHEMA    CORTEX_AI.DATA TO ROLE POC_BI_READER;
-- GRANT USAGE ON WAREHOUSE CORTEX_AI_WH   TO ROLE POC_BI_READER;

-- Verify once PART B is done:
-- SHOW GRANTS TO ROLE POC_BI_READER;

-- ---------- PART C: generate the Power BI token (after ADMIN_REQUEST tier 1) ----------
-- USERADMIN owns SVC_POC_POWERBI, so you can do this yourself. The secret is shown ONCE.
USE ROLE USERADMIN;
ALTER USER SVC_POC_POWERBI ADD PROGRAMMATIC ACCESS TOKEN PBI_POC_TOKEN
  ROLE_RESTRICTION = 'POC_BI_READER'
  DAYS_TO_EXPIRY = 90
  COMMENT = 'Power BI semantic models - SnowConvert POC';
-- In Power BI: Snowflake connector -> Database (Basic) auth
--   User name: SVC_POC_POWERBI     Password: <token_secret from the output above>
-- Rotate:  ALTER USER SVC_POC_POWERBI ROTATE PROGRAMMATIC ACCESS TOKEN PBI_POC_TOKEN;
-- Check:   SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER SVC_POC_POWERBI;
