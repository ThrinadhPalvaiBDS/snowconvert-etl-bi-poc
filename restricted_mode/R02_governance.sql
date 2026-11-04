-- =====================================================================
-- R02 GOVERNANCE with existing privileges
--  CREATE TAG only in CORTEX_AI.GOVERNANCE; masking/row access policies in DATA or GOVERNANCE;
--  APPLY MASKING / ROW ACCESS / TAG granted at account level to CORTEX_AI_FULL_ACCESS_ROLE.
--  Names are POC_-prefixed: DATA already has a policy called RAP_REGION.
-- =====================================================================
USE ROLE CORTEX_AI_FULL_ACCESS_ROLE;
USE WAREHOUSE CORTEX_AI_WH;
USE SCHEMA CORTEX_AI.GOVERNANCE;

CREATE TAG IF NOT EXISTS POC_PII_CLASS ALLOWED_VALUES 'EMAIL', 'PHONE', 'NAME'
  COMMENT = 'SnowConvert POC PII classification';

CREATE MASKING POLICY IF NOT EXISTS POC_MP_EMAIL AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('CORTEX_AI_FULL_ACCESS_ROLE') THEN val     -- POC engineers see clear text
    WHEN val IS NULL THEN NULL
    ELSE REGEXP_REPLACE(val, '^[^@]+', '*****')
  END;

ALTER TAG POC_PII_CLASS SET MASKING POLICY POC_MP_EMAIL;

-- Row access by region, driven by a mapping table you own
CREATE TABLE IF NOT EXISTS POC_REGION_ENTITLEMENT (ROLE_NAME VARCHAR, REGION VARCHAR);
CREATE ROW ACCESS POLICY IF NOT EXISTS POC_RAP_REGION AS (region VARCHAR) RETURNS BOOLEAN ->
  IS_ROLE_IN_SESSION('CORTEX_AI_FULL_ACCESS_ROLE')
  OR EXISTS (SELECT 1 FROM CORTEX_AI.GOVERNANCE.POC_REGION_ENTITLEMENT e
             WHERE IS_ROLE_IN_SESSION(e.ROLE_NAME) AND e.REGION = region);

-- After the first dbt build (dbt post-hook re-applies the tag on every run):
-- ALTER TABLE CORTEX_AI.DATA.DIM_CUSTOMER ADD ROW ACCESS POLICY CORTEX_AI.GOVERNANCE.POC_RAP_REGION ON (REGION);
-- Demo: test masking as a role that is NOT exempt
-- USE ROLE INVOICE_AP_ANALYST_ROLE;  SELECT EMAIL FROM CORTEX_AI.DATA.DIMCUSTOMER LIMIT 5;
-- (works only after you grant SELECT on the view to that role - see R04)
