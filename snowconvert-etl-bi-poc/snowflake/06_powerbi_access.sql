-- =====================================================================
-- 06 POWER BI ACCESS
-- Option A (recommended for users / DirectQuery): Microsoft Entra ID SSO via
--   External OAuth security integration - each report viewer queries as themselves.
-- Option B (import-mode refresh): dedicated service user with BI_READER role.
-- Check current Snowflake guidance on password-based service users before
-- choosing B for production; prefer SSO/OAuth where the Power BI connector supports it.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- Option A: Entra ID (Azure AD) External OAuth for Power BI SSO
CREATE SECURITY INTEGRATION IF NOT EXISTS POWERBI_ENTRA_SSO
  TYPE = EXTERNAL_OAUTH
  ENABLED = TRUE
  EXTERNAL_OAUTH_TYPE = AZURE
  EXTERNAL_OAUTH_ISSUER = 'https://sts.windows.net/<entra_tenant_id>/'
  EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://login.windows.net/common/discovery/keys'
  EXTERNAL_OAUTH_AUDIENCE_LIST = ('https://analysis.windows.net/powerbi/connector/Snowflake')
  EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'upn'
  EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'LOGIN_NAME'
  EXTERNAL_OAUTH_ANY_ROLE_MODE = 'DISABLE';

-- Option B: service user for scheduled import refresh
CREATE USER IF NOT EXISTS SVC_POWERBI
  TYPE = SERVICE                   -- authenticates with a programmatic access token (PAT)
  DEFAULT_ROLE = BI_READER
  DEFAULT_WAREHOUSE = WH_BI
  DEFAULT_NAMESPACE = 'SALES_DW_PROD.DBO'
  COMMENT = 'Power BI semantic model refresh';
GRANT ROLE BI_READER TO USER SVC_POWERBI;

-- Restrict where Power BI can connect from (Power BI service tag IP ranges / gateway IPs)
CREATE NETWORK RULE IF NOT EXISTS PLATFORM.INTEGRATIONS.NR_POWERBI_INGRESS
  MODE = INGRESS TYPE = IPV4
  VALUE_LIST = ('<powerbi_service_tag_range_1>', '<onprem_gateway_ip>');
CREATE NETWORK POLICY IF NOT EXISTS NP_POWERBI
  ALLOWED_NETWORK_RULE_LIST = ('PLATFORM.INTEGRATIONS.NR_POWERBI_INGRESS');
-- ALTER USER SVC_POWERBI SET NETWORK_POLICY = NP_POWERBI;

-- Query tagging -> lets us attribute BI cost per report in observability views
ALTER USER SVC_POWERBI SET QUERY_TAG = 'app=powerbi;layer=dbo';

-- Report users (SSO) get BI_READER through SCIM-provisioned group roles, e.g.
-- GRANT ROLE BI_READER TO ROLE "AAD_SALES_ANALYSTS";
