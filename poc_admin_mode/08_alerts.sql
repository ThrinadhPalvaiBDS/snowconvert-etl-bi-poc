-- =====================================================================
-- 08 ALERTS: run AFTER the first successful dbt build (needs MARTS.FCT_SALES)
-- =====================================================================
USE ROLE POC_ADMIN;
USE SECONDARY ROLES ALL;
USE SCHEMA SALES_DW_PROD.AUDIT;

-- Freshness alert: fct_sales not loaded today by 04:00 IST
CREATE OR REPLACE ALERT ALR_FCT_SALES_FRESHNESS
  WAREHOUSE = WH_LOAD
  SCHEDULE = 'USING CRON 0 4 * * * Asia/Kolkata'
  IF (EXISTS (
        SELECT 1 FROM SALES_DW_PROD.MARTS.FCT_SALES
        HAVING MAX(_DBT_LOADED_AT) < DATEADD('hour', -6, CURRENT_TIMESTAMP())))
  THEN CALL SYSTEM$SEND_EMAIL('NI_DATA_OPS_EMAIL', 'thrinadhp@booleandata.ai',
        'FCT_SALES freshness breach', 'FCT_SALES has not been refreshed in the last 6 hours.');
ALTER ALERT ALR_FCT_SALES_FRESHNESS RESUME;
