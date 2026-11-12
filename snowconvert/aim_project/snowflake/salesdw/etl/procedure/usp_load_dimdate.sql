USE DATABASE <%salesdw%>;

--** SSC-FDM-0007 - MISSING DEPENDENT OBJECT "SalesDW.dbo.DimDate" **
CREATE OR REPLACE PROCEDURE etl.usp_Load_DimDate (STARTDATE DATE, ENDDATE DATE, ROWSADDED OUT INT)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
EXECUTE AS CALLER
AS
$$
    DECLARE
        D DATE;
    BEGIN
--        --** SSC-FDM-TS0029 - SET NOCOUNT STATEMENT IS COMMENTED OUT, WHICH IS NOT APPLICABLE IN SNOWFLAKE. **
--        SET NOCOUNT ON;
        ALTER SESSION SET WEEK_START = 7;                 -- Sunday = 1, so DayOfWeek is stable

        D := :STARTDATE;
        ROWSADDED := 0;
        WHILE (:D <= :ENDDATE) LOOP
            IF (NOT EXISTS (SELECT 1 FROM
                    <%salesdw%>.dbo.DimDate
                WHERE
                    DateKey = CAST(LEFT(TO_VARCHAR(:D, 'yyyymmdd'), 8) AS INT)
            )) THEN
                BEGIN
                    INSERT INTO <%salesdw%>.dbo.DimDate (DateKey, Date, Year, Quarter, Month, MonthName, DayOfWeek, IsWeekend) VALUES (CAST(LEFT(TO_VARCHAR(:D, 'yyyymmdd'), 8) AS INT), :D, YEAR(:D :: TIMESTAMP), DATE_PART(QUARTER, :D :: TIMESTAMP), MONTH(:D :: TIMESTAMP), TO_CHAR(:D, 'MMMM'), <%AIM_DB%>.PUBLIC.DATE_PART_WEEK_DAY_UDF(:D),
                            CASE WHEN <%AIM_DB%>.PUBLIC.DATE_PART_WEEK_DAY_UDF(:D) IN (1, 7) THEN 1 ELSE 0 END);
                    ROWSADDED := ROWSADDED + 1;
                END;
            END IF;
            D := DATEADD(DAY, 1, :D);
        END LOOP;
    END;
$$;