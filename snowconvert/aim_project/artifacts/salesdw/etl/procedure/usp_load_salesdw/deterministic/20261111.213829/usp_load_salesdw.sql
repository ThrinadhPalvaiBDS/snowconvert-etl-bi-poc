USE DATABASE <%salesdw%>;

--** SSC-FDM-0007 - MISSING DEPENDENT OBJECT "SalesOLTP.dbo.SalesOrderHeader" **
CREATE OR REPLACE PROCEDURE etl.usp_Load_SalesDW ()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
EXECUTE AS CALLER
AS
$$
    DECLARE
        RUNID VARCHAR;
        STEP NVARCHAR(100);
        _ROWS INT;
        REJECTED INT;
        MINDATE DATE;
        MAXDATE DATE;
        ERR NVARCHAR(4000);

        -- OnError event handler: Send Mail Task
        SUBJECT NVARCHAR(255);
    BEGIN
--        --** SSC-FDM-TS0029 - SET NOCOUNT STATEMENT IS COMMENTED OUT, WHICH IS NOT APPLICABLE IN SNOWFLAKE. **
--        SET NOCOUNT ON;
        !!!RESOLVE EWI!!! /*** SSC-EWI-TS0089 - SET XACT_ABORT ON IS NOT SUPPORTED IN SNOWFLAKE. ***/!!!
        SET XACT_ABORT ON;
        RUNID := UUID_STRING();

        -- OnError event handler: Send Mail Task
        BEGIN
            STEP := 'Package';
            CALL <%salesdw%>.etl.usp_LogStep(RUNID => :RUNID, STEPNAME => :STEP, STATUS => 'Started');

            -- Make sure every order date has a DimDate row
            STEP := 'Load DimDate';
            LET MINDATE_RESULTSET_1 RESULTSET :=
            (
                SELECT
                    --** SSC-FDM-TS0146 - A SIX-DIGIT DATE SUCH AS '691215' WAS READ WITH SQL SERVER'S DEFAULT TWO-DIGIT YEAR CUTOFF OF 2049, SO IT IS 1969-12-15 RATHER THAN THE 2069-12-15 SNOWFLAKE'S YY FORMAT RETURNS. A CONFIGURED CUTOFF OTHER THAN 2049 CHANGES THE CENTURY. **
                    COALESCE(TRY_TO_DATE(TRIM(TO_VARCHAR(MIN(OrderDate))), 'YYYYMMDD'), IFF(REGEXP_LIKE(TRIM(TO_VARCHAR(MIN(OrderDate))), '^[0-9]{6}$'), IFF(TRY_TO_NUMBER(LEFT(TRIM(TO_VARCHAR(MIN(OrderDate))), 2)) > 49, TRY_TO_DATE('19' || TRIM(TO_VARCHAR(MIN(OrderDate))), 'YYYYMMDD'), TRY_TO_DATE('20' || TRIM(TO_VARCHAR(MIN(OrderDate))), 'YYYYMMDD')), null), IFF(REGEXP_LIKE(TRIM(TO_VARCHAR(MIN(OrderDate))), '^[0-9]{4}$'), TRY_TO_DATE(TRIM(TO_VARCHAR(MIN(OrderDate))) || '0101', 'YYYYMMDD'), null), IFF(REGEXP_LIKE(TRIM(TO_VARCHAR(MIN(OrderDate))), '^[0-9]+$'), null, TO_DATE(MIN(OrderDate)))) AS MINDATE_VALUE,
                    --** SSC-FDM-TS0146 - A SIX-DIGIT DATE SUCH AS '691215' WAS READ WITH SQL SERVER'S DEFAULT TWO-DIGIT YEAR CUTOFF OF 2049, SO IT IS 1969-12-15 RATHER THAN THE 2069-12-15 SNOWFLAKE'S YY FORMAT RETURNS. A CONFIGURED CUTOFF OTHER THAN 2049 CHANGES THE CENTURY. **
                    COALESCE(TRY_TO_DATE(TRIM(TO_VARCHAR(MAX(OrderDate))), 'YYYYMMDD'), IFF(REGEXP_LIKE(TRIM(TO_VARCHAR(MAX(OrderDate))), '^[0-9]{6}$'), IFF(TRY_TO_NUMBER(LEFT(TRIM(TO_VARCHAR(MAX(OrderDate))), 2)) > 49, TRY_TO_DATE('19' || TRIM(TO_VARCHAR(MAX(OrderDate))), 'YYYYMMDD'), TRY_TO_DATE('20' || TRIM(TO_VARCHAR(MAX(OrderDate))), 'YYYYMMDD')), null), IFF(REGEXP_LIKE(TRIM(TO_VARCHAR(MAX(OrderDate))), '^[0-9]{4}$'), TRY_TO_DATE(TRIM(TO_VARCHAR(MAX(OrderDate))) || '0101', 'YYYYMMDD'), null), IFF(REGEXP_LIKE(TRIM(TO_VARCHAR(MAX(OrderDate))), '^[0-9]+$'), null, TO_DATE(MAX(OrderDate)))) AS MAXDATE_VALUE
                FROM
                    <%salesoltp%>.dbo.SalesOrderHeader
            );
            FOR MINDATE_ROW_1 IN MINDATE_RESULTSET_1 DO
                MINDATE := MINDATE_ROW_1.MINDATE_VALUE;
                MAXDATE := MINDATE_ROW_1.MAXDATE_VALUE;
            END FOR;
            IF (:MINDATE IS NOT NULL) THEN
                BEGIN
                    CALL <%salesdw%>.etl.usp_Load_DimDate(:MINDATE, :MAXDATE, :_ROWS);
                    CALL <%salesdw%>.etl.usp_LogStep(RUNID => :RUNID, STEPNAME => :STEP, STATUS => 'Succeeded', ROWSAFFECTED => :_ROWS);
                END;
            END IF;
            -- Sequence container: dimensions
            STEP := 'DFT - DimProduct';
            CALL <%salesdw%>.etl.usp_Load_DimProduct(:_ROWS);
            CALL <%salesdw%>.etl.usp_LogStep(RUNID => :RUNID, STEPNAME => :STEP, STATUS => 'Succeeded', ROWSAFFECTED => :_ROWS);
            STEP := 'DFT - DimCustomer';
            CALL <%salesdw%>.etl.usp_Load_DimCustomer(:_ROWS);
            CALL <%salesdw%>.etl.usp_LogStep(RUNID => :RUNID, STEPNAME => :STEP, STATUS => 'Succeeded', ROWSAFFECTED => :_ROWS);

            -- Fact + watermark
            STEP := 'DFT - FactSales';
            CALL <%salesdw%>.etl.usp_Load_FactSales(:_ROWS, :REJECTED);
            CALL <%salesdw%>.etl.usp_LogStep(RUNID => :RUNID, STEPNAME => :STEP, STATUS => 'Succeeded', ROWSAFFECTED => :_ROWS);
            CALL <%salesdw%>.etl.usp_LogStep(RUNID => :RUNID, STEPNAME => 'FactSales rejected rows', STATUS => 'Succeeded', ROWSAFFECTED => :REJECTED);
            CALL <%salesdw%>.etl.usp_LogStep(RUNID => :RUNID, STEPNAME => 'Package', STATUS => 'Succeeded');
        EXCEPTION
            WHEN OTHER THEN
                IF (CURRENT_TRANSACTION() IS NOT NULL) THEN
                    BEGIN
                        ROLLBACK;
                    EXCEPTION
                        WHEN OTHER THEN
                            NULL;
                    END;
                END IF;
                ERR := LEFT(CONCAT('Step "', COALESCE(:STEP :: STRING, ''), '" failed: ', COALESCE(:SQLERRM /*** SSC-FDM-TS0023 - ERROR MESSAGE COULD BE DIFFERENT IN SNOWFLAKE ***/ :: STRING, ''), ' (error ', COALESCE(:SQLCODE /*** SSC-FDM-TS0023 - ERROR NUMBER COULD BE DIFFERENT IN SNOWFLAKE ***/ :: STRING, ''), ', line ', '', ')'), 4000);
                CALL <%salesdw%>.etl.usp_LogStep(:RUNID, :STEP, 'Failed', NULL, :ERR);
                SUBJECT := CONCAT('Load_SalesDW FAILED at ', COALESCE(TO_CHAR(CURRENT_TIMESTAMP() /*** SSC-FDM-TS0186 - SYSDATETIME() RETURNS THE LOCAL TIME OF THE SQL SERVER HOST; THE CONVERTED CALL FOLLOWS THE SNOWFLAKE SESSION TIMEZONE. SET TIMEZONE TO THE SOURCE SERVER'S ZONE FOR THE USERS THAT RUN THIS CODE ***/, 'YYYY-MM-DD HH24:MI') :: STRING, ''));
--                --** SSC-FDM-TS0049 - SP_SEND_DBMAIL TRANSLATED TO SNOWFLAKE NOTIFICATION. REQUIRES A NOTIFICATION INTEGRATION TO BE CONFIGURED. **
--                --** SSC-FDM-TS0052 - SP_SEND_DBMAIL PARAMETERS NOT TRANSLATED: @profile_name. THESE PARAMETERS HAVE NO EQUIVALENT IN SNOWFLAKE SYSTEM$SEND_SNOWFLAKE_NOTIFICATION. **
--        EXEC msdb.dbo.sp_send_dbmail
--             @profile_name = N'DataOps',
--             @recipients   = N'thrinadhp@booleandata.ai',
--             @subject      = @Subject,
--             @body         = @Err;
                CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(:ERR), SNOWFLAKE.NOTIFICATION.EMAIL_INTEGRATION_CONFIG('<your_email_notification_integration>', :SUBJECT, STRTOK_TO_ARRAY('thrinadhp@booleandata.ai', ';')));
                RAISE;
        END;
    END;
$$;