-- =====================================================================
-- Remaining items for the account admin (after the grants already applied)
-- =====================================================================

-- 1. Power BI service user: must be TYPE = SERVICE and use a PAT.
--    SERVICE users can create/use PATs only under a network policy, unless an
--    authentication policy waives it. No network policies exist in this account.
USE ROLE ACCOUNTADMIN;
ALTER USER SVC_POC_POWERBI SET TYPE = SERVICE;     -- harmless if already SERVICE
ALTER USER SVC_POC_POWERBI UNSET PASSWORD;
CREATE AUTHENTICATION POLICY IF NOT EXISTS CORTEX_AI.DATA.POC_PBI_AUTH_POLICY
  AUTHENTICATION_METHODS = ('PROGRAMMATIC_ACCESS_TOKEN')
  PAT_POLICY = (NETWORK_POLICY_EVALUATION = ENFORCED_NOT_REQUIRED,
                MAX_EXPIRY_IN_DAYS = 90, DEFAULT_EXPIRY_IN_DAYS = 90)
  COMMENT = 'SnowConvert POC - Power BI service user: PAT only';
ALTER USER SVC_POC_POWERBI SET AUTHENTICATION POLICY CORTEX_AI.DATA.POC_PBI_AUTH_POLICY;
-- Production: replace the waiver with a network policy for Power BI / gateway IP ranges.

-- 2. Cost guardrail on the POC warehouses (only ACCOUNTADMIN can create resource monitors)
CREATE RESOURCE MONITOR IF NOT EXISTS RM_SALES_POC WITH CREDIT_QUOTA = 100 FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY ON 90 PERCENT DO SUSPEND ON 100 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE WH_LOAD      SET RESOURCE_MONITOR = RM_SALES_POC;   -- run after THRINADHP creates the warehouses
ALTER WAREHOUSE WH_TRANSFORM SET RESOURCE_MONITOR = RM_SALES_POC;
ALTER WAREHOUSE WH_BI        SET RESOURCE_MONITOR = RM_SALES_POC;

-- 3. Optional clean-up: the ACCOUNTADMIN-owned POC_GIT_API, POC_DBT_DEPS_EAI, POC_EMAIL and
--    CORTEX_AI.DATA.POC_DBT_DEPS_EGRESS are not used in POC_ADMIN mode (POC_ADMIN creates its
--    own so it can grant USAGE onward). Keep them only if restricted mode is still in use.
