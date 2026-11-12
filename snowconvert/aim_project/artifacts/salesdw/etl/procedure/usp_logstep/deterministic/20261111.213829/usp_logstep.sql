USE DATABASE <%salesdw%>;

CREATE OR REPLACE PROCEDURE etl.usp_LogStep (RUNID VARCHAR, STEPNAME STRING, STATUS STRING, ROWSAFFECTED INT DEFAULT NULL, ERRORMESSAGE STRING DEFAULT NULL)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
EXECUTE AS CALLER
AS
$$
    BEGIN
--        --** SSC-FDM-TS0029 - SET NOCOUNT STATEMENT IS COMMENTED OUT, WHICH IS NOT APPLICABLE IN SNOWFLAKE. **
--        SET NOCOUNT ON;
        INSERT INTO <%salesdw%>.etl.LoadLog (RunID, StepName, Status, RowsAffected, ErrorMessage) VALUES (:RUNID, :STEPNAME, :STATUS, :ROWSAFFECTED, :ERRORMESSAGE);
    END;
$$;