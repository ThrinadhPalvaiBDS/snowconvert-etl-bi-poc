-- =====================================================================
-- Request to the Snowflake account admin for the SnowConvert AI POC.
-- Requested by THRINADHP. Ordered by priority; each tier is independent.
-- Everything is scoped to the existing CORTEX_AI database and CORTEX_AI_WH.
-- =====================================================================
-- TIER 0: create the POC role and users if they do not exist yet.
-- Created under USERADMIN (not ACCOUNTADMIN) so THRINADHP, who holds USERADMIN,
-- can manage them afterwards. Safe to re-run.
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS POC_BI_READER COMMENT = 'SnowConvert POC - Power BI read access to compat views';
CREATE USER IF NOT EXISTS SVC_POC_POWERBI TYPE = SERVICE DEFAULT_ROLE = POC_BI_READER
  DEFAULT_WAREHOUSE = CORTEX_AI_WH DEFAULT_NAMESPACE = 'CORTEX_AI.DATA'
  COMMENT = 'SnowConvert POC - Power BI semantic model refresh';
CREATE USER IF NOT EXISTS SVC_POC_PIPELINE TYPE = SERVICE DEFAULT_ROLE = CORTEX_AI_FULL_ACCESS_ROLE
  DEFAULT_WAREHOUSE = CORTEX_AI_WH DEFAULT_NAMESPACE = 'CORTEX_AI.DATA'
  COMMENT = 'SnowConvert POC - ingestion + dbt runs';
GRANT ROLE POC_BI_READER TO USER SVC_POC_POWERBI;
SHOW ROLES LIKE 'POC_BI_READER';           -- must return 1 row before continuing

USE ROLE ACCOUNTADMIN;

-- TIER 1 (unblocks Power BI Service + clean CI) ---------------------------
-- Power BI service user (created by THRINADHP via USERADMIN) needs to reach the views
GRANT USAGE ON DATABASE  CORTEX_AI      TO ROLE POC_BI_READER;
GRANT USAGE ON SCHEMA    CORTEX_AI.DATA TO ROLE POC_BI_READER;
GRANT USAGE ON WAREHOUSE CORTEX_AI_WH   TO ROLE POC_BI_READER;
-- Non-personal identity for scheduled dbt / ingestion runs (user created via USERADMIN)
GRANT ROLE CORTEX_AI_FULL_ACCESS_ROLE TO USER SVC_POC_PIPELINE;

-- Power BI authenticates with a programmatic access token (PAT) used as the password.
-- SERVICE users can only create/use PATs when covered by a network policy, unless an
-- authentication policy waives that. The account has no network policies, so for the POC:
CREATE AUTHENTICATION POLICY IF NOT EXISTS CORTEX_AI.DATA.POC_PBI_AUTH_POLICY
  AUTHENTICATION_METHODS = ('PROGRAMMATIC_ACCESS_TOKEN')
  PAT_POLICY = (NETWORK_POLICY_EVALUATION = ENFORCED_NOT_REQUIRED, MAX_EXPIRY_IN_DAYS = 90, DEFAULT_EXPIRY_IN_DAYS = 90)
  COMMENT = 'SnowConvert POC - Power BI service user: PAT only, no network policy required';
ALTER USER SVC_POC_POWERBI SET AUTHENTICATION POLICY CORTEX_AI.DATA.POC_PBI_AUTH_POLICY;
-- Production alternative: a network policy with the Power BI service tag / gateway IP ranges instead.

-- TIER 2 (enterprise layout: separate layers + legacy 'DBO' schema name) --
-- With this, POC_RAW / POC_STAGING / POC_MARTS / DBO schemas can be created, and repointed
-- Power BI queries keep their original DBO schema reference.
GRANT CREATE SCHEMA ON DATABASE CORTEX_AI TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;

-- TIER 3 (Snowflake-native orchestration with dbt Projects on Snowflake) --
GRANT CREATE DBT PROJECT    ON SCHEMA CORTEX_AI.DATA TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;
GRANT CREATE GIT REPOSITORY ON SCHEMA CORTEX_AI.DATA TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;
GRANT CREATE SECRET         ON SCHEMA CORTEX_AI.DATA TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;
CREATE API INTEGRATION POC_GIT_API
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/<your-org>/')
  ALLOWED_AUTHENTICATION_SECRETS = ALL
  ENABLED = TRUE;
GRANT USAGE ON INTEGRATION POC_GIT_API TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;
-- dbt deps inside Snowflake (or commit dbt_packages/ to the repo instead):
CREATE NETWORK RULE CORTEX_AI.DATA.POC_DBT_DEPS_EGRESS MODE = EGRESS TYPE = HOST_PORT
  VALUE_LIST = ('hub.getdbt.com', 'codeload.github.com');
CREATE EXTERNAL ACCESS INTEGRATION POC_DBT_DEPS_EAI
  ALLOWED_NETWORK_RULES = (CORTEX_AI.DATA.POC_DBT_DEPS_EGRESS) ENABLED = TRUE;
GRANT USAGE ON INTEGRATION POC_DBT_DEPS_EAI TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;

-- TIER 4 (alerting from Snowflake) ---------------------------------------
CREATE NOTIFICATION INTEGRATION POC_EMAIL TYPE = EMAIL ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('<team-email@company.com>');
GRANT USAGE ON INTEGRATION POC_EMAIL TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE CORTEX_AI_FULL_ACCESS_ROLE;
