-- =====================================================================
-- 05 GOVERNANCE: tags, masking, row access (Enterprise edition+)
-- Policies are attached to MARTS objects; DBO compat views inherit them
-- because they select from MARTS.
-- =====================================================================
USE ROLE POC_ADMIN;
-- ALTER TAG ... SET MASKING POLICY needs APPLY MASKING POLICY on the account, which
-- CORTEX_AI_FULL_ACCESS_ROLE holds; secondary roles make it available in this session.
USE SECONDARY ROLES ALL;
USE SCHEMA PLATFORM.GOVERNANCE;

CREATE TAG IF NOT EXISTS PII_CLASS ALLOWED_VALUES 'EMAIL', 'PHONE', 'NAME' COMMENT = 'PII classification';
CREATE TAG IF NOT EXISTS DATA_DOMAIN ALLOWED_VALUES 'SALES', 'CUSTOMER', 'PRODUCT';

CREATE MASKING POLICY IF NOT EXISTS MP_EMAIL AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('PII_READER') THEN val
    WHEN val IS NULL THEN NULL
    ELSE REGEXP_REPLACE(val, '^[^@]+', '*****')
  END;

-- Tag-based masking: any column tagged PII_CLASS='EMAIL' gets masked automatically
ALTER TAG PII_CLASS SET MASKING POLICY MP_EMAIL;

-- PII_READER is created by USERADMIN in 01_bootstrap_poc_admin.sql

-- Region-based row access (mirrors Power BI RLS so DirectQuery users get the same rows)
CREATE TABLE IF NOT EXISTS REGION_ENTITLEMENT (ROLE_NAME VARCHAR, REGION VARCHAR);
CREATE ROW ACCESS POLICY IF NOT EXISTS RAP_REGION AS (region VARCHAR) RETURNS BOOLEAN ->
  IS_ROLE_IN_SESSION('POC_ADMIN')
  OR IS_ROLE_IN_SESSION('TRANSFORMER')
  OR IS_ROLE_IN_SESSION('BI_READER')        -- import-mode service account sees all; RLS stays in Power BI
  OR EXISTS (SELECT 1 FROM PLATFORM.GOVERNANCE.REGION_ENTITLEMENT e
             WHERE IS_ROLE_IN_SESSION(e.ROLE_NAME) AND e.REGION = region);

-- Applied after first dbt build (dbt post-hooks also re-apply - see dbt_project.yml)
-- ALTER TABLE SALES_DW_PROD.MARTS.DIM_CUSTOMER MODIFY COLUMN EMAIL SET TAG PLATFORM.GOVERNANCE.PII_CLASS = 'EMAIL';
-- ALTER TABLE SALES_DW_PROD.MARTS.DIM_CUSTOMER ADD ROW ACCESS POLICY PLATFORM.GOVERNANCE.RAP_REGION ON (REGION);

GRANT USAGE ON DATABASE PLATFORM TO ROLE TRANSFORMER;
GRANT USAGE ON SCHEMA PLATFORM.GOVERNANCE TO ROLE TRANSFORMER;
GRANT APPLY ON TAG PII_CLASS TO ROLE TRANSFORMER;
