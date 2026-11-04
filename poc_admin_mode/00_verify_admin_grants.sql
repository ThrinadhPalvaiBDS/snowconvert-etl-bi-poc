-- =====================================================================
-- 00 VERIFY what the admin applied (run as THRINADHP)
-- =====================================================================
SHOW GRANTS TO ROLE POC_ADMIN;                 -- expect CREATE DATABASE, CREATE WAREHOUSE, CREATE INTEGRATION,
                                               -- EXECUTE TASK, EXECUTE ALERT, IMPORTED PRIVILEGES on SNOWFLAKE
SELECT CURRENT_AVAILABLE_ROLES();              -- POC_ADMIN must be in the list

SHOW USERS LIKE 'SVC_POC%';                    -- check the "type" column for both users
DESC USER SVC_POC_POWERBI;                     -- TYPE must be SERVICE (LEGACY_SERVICE no longer exists)
SHOW GRANTS TO USER SVC_POC_POWERBI;
SHOW GRANTS TO USER SVC_POC_PIPELINE;          -- expect CORTEX_AI_FULL_ACCESS_ROLE
SHOW GRANTS TO ROLE POC_BI_READER;             -- expect USAGE on CORTEX_AI, CORTEX_AI.DATA, CORTEX_AI_WH
SHOW INTEGRATIONS LIKE 'POC%';                 -- POC_GIT_API, POC_DBT_DEPS_EAI, POC_EMAIL (owned by ACCOUNTADMIN)
SHOW AUTHENTICATION POLICIES IN ACCOUNT;       -- POC_PBI_AUTH_POLICY should exist (needed for the Power BI PAT)
