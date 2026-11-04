-- =====================================================================
-- R00 SERVICE USERS (you hold USERADMIN: CREATE USER / CREATE ROLE)
-- Key-pair auth for pipeline runs. The admin must still grant
-- CORTEX_AI_FULL_ACCESS_ROLE to SVC_POC_PIPELINE (ADMIN_REQUEST.sql, tier 1),
-- because you cannot grant a role you do not own.
-- Until then, run the pipeline as yourself with a key pair on THRINADHP.
-- =====================================================================
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS SVC_POC_PIPELINE
  TYPE = SERVICE
  DEFAULT_ROLE = CORTEX_AI_FULL_ACCESS_ROLE
  DEFAULT_WAREHOUSE = CORTEX_AI_WH
  DEFAULT_NAMESPACE = 'CORTEX_AI.DATA'
  COMMENT = 'SnowConvert POC - ingestion + dbt runs';
-- ALTER USER SVC_POC_PIPELINE SET RSA_PUBLIC_KEY = '<svc_poc_pipeline.pub contents>';

-- Interim option: key pair on your own user (USERADMIN owns THRINADHP)
-- ALTER USER THRINADHP SET RSA_PUBLIC_KEY = '<thrinadhp.pub contents>';
-- DESC USER THRINADHP;   -- check RSA_PUBLIC_KEY_FP is populated
