USE DATABASE <%salesdw%>;
-- Started / Succeeded / Failed
CREATE TABLE IF NOT EXISTS etl.LoadLog (
    LoadLogID INT IDENTITY(1,1) ORDER PRIMARY KEY,
    RunID VARCHAR NOT NULL,
    StepName NVARCHAR(100) NOT NULL,
    Status NVARCHAR(20) NOT NULL,
    RowsAffected INT NULL,
    ErrorMessage NVARCHAR(4000) NULL,
    LoggedAt TIMESTAMP_NTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP() /*** SSC-FDM-TS0186 - SYSDATETIME() RETURNS THE LOCAL TIME OF THE SQL SERVER HOST; THE CONVERTED CALL FOLLOWS THE SNOWFLAKE SESSION TIMEZONE. SET TIMEZONE TO THE SOURCE SERVER'S ZONE FOR THE USERS THAT RUN THIS CODE ***/ :: TIMESTAMP_NTZ(3)
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;