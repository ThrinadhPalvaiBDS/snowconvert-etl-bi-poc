-- =====================================================================
-- 09 POWER BI ACCESS (POC_ADMIN mode)
-- SVC_POC_POWERBI (TYPE = SERVICE) signs in with a programmatic access token (PAT)
-- used as the password in the Power BI Snowflake connector.
-- Prereq (ADMIN): authentication policy POC_PBI_AUTH_POLICY on the user - see README.
-- =====================================================================
USE ROLE USERADMIN;
ALTER USER SVC_POC_POWERBI ADD PROGRAMMATIC ACCESS TOKEN PBI_POC_TOKEN
  ROLE_RESTRICTION = 'BI_READER'
  DAYS_TO_EXPIRY = 90
  COMMENT = 'Power BI semantic models - SnowConvert POC';
-- Copy token_secret NOW (shown only once).
-- Power BI: Snowflake connector, Database auth -> user SVC_POC_POWERBI, password = token
--   Server: <account>.snowflakecomputing.com  Warehouse: WH_BI  Database: SALES_DW_PROD  (schema DBO unchanged)
-- Rotate: ALTER USER SVC_POC_POWERBI ROTATE PROGRAMMATIC ACCESS TOKEN PBI_POC_TOKEN;

-- Optional SSO for report viewers (POC_ADMIN has CREATE INTEGRATION):
-- USE ROLE POC_ADMIN;
-- CREATE SECURITY INTEGRATION POWERBI_ENTRA_SSO TYPE = EXTERNAL_OAUTH ENABLED = TRUE
--   EXTERNAL_OAUTH_TYPE = AZURE
--   EXTERNAL_OAUTH_ISSUER = 'https://sts.windows.net/<entra_tenant_id>/'
--   EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://login.windows.net/common/discovery/keys'
--   EXTERNAL_OAUTH_AUDIENCE_LIST = ('https://analysis.windows.net/powerbi/connector/Snowflake')
--   EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'upn'
--   EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'LOGIN_NAME';
