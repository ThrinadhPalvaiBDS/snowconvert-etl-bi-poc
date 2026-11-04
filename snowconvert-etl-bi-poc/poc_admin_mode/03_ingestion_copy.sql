-- =====================================================================
-- 02 INGESTION (file path): parquet extracts on STG_LANDING -> RAW via COPY INTO.
-- Used when the extractor writes files instead of write_pandas; also the target
-- for SnowConvert-converted Bulk Insert Tasks. For production CDC from SQL Server,
-- evaluate Snowflake Openflow / a CDC connector and keep RAW contracts unchanged.
-- The extractor writes _BATCH_ID / _SOURCE_SYSTEM into the parquet files themselves.
-- =====================================================================
USE ROLE LOADER;
USE WAREHOUSE WH_LOAD;
USE SCHEMA SALES_DW_PROD.RAW;

CREATE OR REPLACE PROCEDURE SP_COPY_RAW(TABLE_NAME VARCHAR, BATCH_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  stmt VARCHAR;
  res  RESULTSET;
BEGIN
  stmt := 'COPY INTO RAW.' || TABLE_NAME ||
          ' FROM @RAW.STG_LANDING/' || LOWER(TABLE_NAME) || '/' || BATCH_ID || '/' ||
          ' FILE_FORMAT = (FORMAT_NAME = RAW.FF_PARQUET)' ||
          ' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE ON_ERROR = ABORT_STATEMENT';
  res := (EXECUTE IMMEDIATE :stmt);
  RETURN OBJECT_CONSTRUCT('table', TABLE_NAME, 'batch', BATCH_ID, 'status', 'loaded');
END;
$$;

-- Example:
-- CALL SP_COPY_RAW('SALESORDERDETAIL', '20261103T0200');
