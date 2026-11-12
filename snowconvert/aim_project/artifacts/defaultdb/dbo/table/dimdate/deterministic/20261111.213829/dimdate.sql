USE DATABASE <%defaultdb%>;
-- yyyymmdd
CREATE OR REPLACE TABLE dbo.DimDate (
    DateKey INT PRIMARY KEY,
    Date DATE NOT NULL,
    Year SMALLINT NOT NULL,
    Quarter TINYINT NOT NULL,
    Month TINYINT NOT NULL,
    MonthName NVARCHAR(12) NOT NULL,
    DayOfWeek TINYINT NOT NULL,
    IsWeekend BOOLEAN NOT NULL
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;