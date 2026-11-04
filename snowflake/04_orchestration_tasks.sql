-- =====================================================================
-- 04 ORCHESTRATION: Snowflake Task DAG replacing SSIS control flow
--
--  SSIS                              Snowflake
--  SQL - Get Watermark            -> handled by dbt incremental logic (is_incremental())
--  SEQ - Dimensions (2 DFTs)      -> T_DBT_DIMENSIONS  (snapshot + dims)
--  DFT - FactSales                -> T_DBT_FACTS       (incremental merge + rejects)
--  SQL - Update Watermark         -> T_POST_LOAD       (audit + watermark)
--  Send Mail / OnError handler    -> T_FINALIZER       (FINALIZE task, always runs)
-- =====================================================================
USE ROLE PLATFORM_ADMIN;
USE DATABASE SALES_DW_PROD;
USE SCHEMA AUDIT;

-- Prereqs (created in 00_account_bootstrap.sql): NI_DATA_OPS_EMAIL, EXECUTE TASK grant.

-- Root: schedule + refresh RAW from the landing stage
CREATE OR REPLACE TASK T_ROOT_SALES_DW
  WAREHOUSE = WH_LOAD
  SCHEDULE = 'USING CRON 0 2 * * * Asia/Kolkata'
  USER_TASK_TIMEOUT_MS = 3600000
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3
  TASK_AUTO_RETRY_ATTEMPTS = 1
  CONFIG = '{"target": "prod", "pipeline": "Load_SalesDW"}'
  COMMENT = 'Replaces SQL Agent job running Load_SalesDW.dtsx'
AS
  INSERT INTO AUDIT.PIPELINE_RUN (RUN_GROUP_ID, PIPELINE, STATUS, STARTED_AT)
  SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'), 'Load_SalesDW', 'RUNNING', CURRENT_TIMESTAMP();

-- Dimensions (was SEQ - Dimensions)
CREATE OR REPLACE TASK T_DBT_DIMENSIONS
  WAREHOUSE = WH_TRANSFORM
  AFTER T_ROOT_SALES_DW
AS
  EXECUTE DBT PROJECT PLATFORM.DBT.SALES_DW
    ARGS = 'build --target prod --select +snap_customer +dim_customer +dim_product dim_date';

-- Facts (was DFT - FactSales); depends on dims like the SSIS precedence constraint
CREATE OR REPLACE TASK T_DBT_FACTS
  WAREHOUSE = WH_TRANSFORM
  AFTER T_DBT_DIMENSIONS
AS
  EXECUTE DBT PROJECT PLATFORM.DBT.SALES_DW
    ARGS = 'build --target prod --select stg_orders_cdc+ stg_order_lines_cdc+ --exclude +dim_customer +dim_product dim_date';

-- Post load (was SQL - Update Watermark)
CREATE OR REPLACE TASK T_POST_LOAD
  WAREHOUSE = WH_LOAD
  AFTER T_DBT_FACTS
AS
  MERGE INTO RAW.LOAD_WATERMARK t
  USING (SELECT 'FACT_SALES' AS TABLE_NAME, MAX(SOURCE_MODIFIED_AT) AS HWM, COUNT(*) AS N
         FROM MARTS.FCT_SALES) s
  ON t.TABLE_NAME = s.TABLE_NAME
  WHEN MATCHED THEN UPDATE SET HIGH_WATERMARK = s.HWM, ROWS_LOADED = s.N, UPDATED_AT = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT VALUES (s.TABLE_NAME, s.HWM, s.N, CURRENT_TIMESTAMP());

-- Finalizer: always runs (success or failure) - replaces OnError event handler + Send Mail
CREATE OR REPLACE TASK T_FINALIZER
  WAREHOUSE = WH_LOAD
  FINALIZE = T_ROOT_SALES_DW
AS
DECLARE
  run_group VARCHAR DEFAULT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
  failed_tasks VARCHAR;
  status VARCHAR;
BEGIN
  SELECT LISTAGG(NAME || ': ' || COALESCE(ERROR_MESSAGE, STATE), '\n')
    INTO :failed_tasks
    FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
           SCHEDULED_TIME_RANGE_START => DATEADD('hour', -12, CURRENT_TIMESTAMP())))
   WHERE GRAPH_RUN_GROUP_ID = :run_group
     AND STATE IN ('FAILED', 'CANCELLED');

  status := IFF(failed_tasks IS NULL, 'SUCCEEDED', 'FAILED');

  UPDATE AUDIT.PIPELINE_RUN
     SET STATUS = :status, FINISHED_AT = CURRENT_TIMESTAMP(), ERROR_DETAIL = :failed_tasks
   WHERE RUN_GROUP_ID = :run_group;

  CALL SYSTEM$SEND_EMAIL('NI_DATA_OPS_EMAIL', 'data-ops@yourcompany.com',
       'Load_SalesDW ' || :status,
       'Run group: ' || :run_group || '\n' || COALESCE(:failed_tasks, 'All tasks succeeded.'));
END;

-- Resume children first, root last
ALTER TASK T_FINALIZER RESUME;
ALTER TASK T_POST_LOAD RESUME;
ALTER TASK T_DBT_FACTS RESUME;
ALTER TASK T_DBT_DIMENSIONS RESUME;
ALTER TASK T_ROOT_SALES_DW RESUME;

-- Manual trigger for the POC demo:
-- EXECUTE TASK T_ROOT_SALES_DW;
