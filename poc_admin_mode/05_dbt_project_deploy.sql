-- =====================================================================
-- 05 DEPLOY dbt PROJECT (POC_ADMIN mode)
-- Git repo + dbt project owned by TRANSFORMER, so the CI user (SVC_POC_PIPELINE)
-- can add new versions on every merge without POC_ADMIN.
-- =====================================================================
USE ROLE POC_ADMIN;
USE SECONDARY ROLES ALL;

-- GitHub PAT secret + git repository (POC_ADMIN owns the schema, creates then hands over)
CREATE OR REPLACE SECRET PLATFORM.INTEGRATIONS.GH_PAT
  TYPE = PASSWORD USERNAME = 'ThrinadhPalvaiBDS' PASSWORD = '<github_fine_grained_pat_read_only>';

CREATE OR REPLACE GIT REPOSITORY PLATFORM.INTEGRATIONS.SNOWCONVERT_POC_REPO
  API_INTEGRATION = POC_ADMIN_GIT_API
  GIT_CREDENTIALS = PLATFORM.INTEGRATIONS.GH_PAT
  ORIGIN = 'https://github.com/ThrinadhPalvaiBDS/snowconvert-etl-bi-poc.git';
ALTER GIT REPOSITORY PLATFORM.INTEGRATIONS.SNOWCONVERT_POC_REPO FETCH;

-- TRANSFORMER needs to read the repo and fetch it in CI
GRANT READ, WRITE ON GIT REPOSITORY PLATFORM.INTEGRATIONS.SNOWCONVERT_POC_REPO TO ROLE TRANSFORMER;

-- Create the dbt project AS TRANSFORMER (owner = TRANSFORMER)
USE ROLE TRANSFORMER;
USE SECONDARY ROLES NONE;
CREATE OR REPLACE DBT PROJECT PLATFORM.DBT.SALES_DW
  FROM '@PLATFORM.INTEGRATIONS.SNOWCONVERT_POC_REPO/branches/main/dbt'
  EXTERNAL_ACCESS_INTEGRATIONS = (DBT_DEPS_EAI)
  COMMENT = 'Replatformed Load_SalesDW (SSIS) - SnowConvert AI POC';

-- Smoke run
USE WAREHOUSE WH_TRANSFORM;
EXECUTE DBT PROJECT PLATFORM.DBT.SALES_DW ARGS = 'build --target prod';
