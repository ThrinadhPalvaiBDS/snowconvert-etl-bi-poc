-- =====================================================================
-- Enable SQL Server Change Data Capture on the OLTP source (run by a DBA)
-- Requirements: SQL Server Standard/Enterprise (2016 SP1+), SQL Server Agent RUNNING
-- (the capture + cleanup jobs are Agent jobs), sysadmin for step 1, db_owner for step 2.
-- =====================================================================
USE SalesOLTP;
GO
-- 1. Enable CDC on the database
IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = 'SalesOLTP') = 0
    EXEC sys.sp_cdc_enable_db;
GO
-- 2. Read-gating role for the extractor login
IF DATABASE_PRINCIPAL_ID('cdc_reader') IS NULL CREATE ROLE cdc_reader;
ALTER ROLE cdc_reader ADD MEMBER svc_migration;
GO
-- 3. Enable CDC per table (net changes need a primary key / unique index)
DECLARE @t TABLE (name sysname);
INSERT @t VALUES ('Customer'), ('Product'), ('SalesOrderHeader'), ('SalesOrderDetail');
DECLARE @n sysname;
DECLARE c CURSOR FOR SELECT name FROM @t;
OPEN c; FETCH NEXT FROM c INTO @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID('dbo.' + @n))
        EXEC sys.sp_cdc_enable_table
             @source_schema = N'dbo',
             @source_name   = @n,
             @role_name     = N'cdc_reader',
             @supports_net_changes = 1;          -- capture instance = dbo_<Table>
    FETCH NEXT FROM c INTO @n;
END
CLOSE c; DEALLOCATE c;
GO
-- 4. Retention: default cleanup keeps 3 days (4320 min). Give the extractor slack.
EXEC sys.sp_cdc_change_job @job_type = N'cleanup', @retention = 10080;   -- 7 days
GO
-- 5. Verify
SELECT capture_instance, source_object_id, start_lsn, supports_net_changes FROM cdc.change_tables;
SELECT sys.fn_cdc_get_max_lsn() AS current_max_lsn;
EXEC sys.sp_cdc_help_jobs;
-- Extractor login needs: SELECT on dbo tables (snapshot) + membership in cdc_reader.
