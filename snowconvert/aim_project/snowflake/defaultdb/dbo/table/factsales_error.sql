USE DATABASE <%defaultdb%>;

CREATE OR REPLACE TABLE dbo.FactSales_Error (
    SalesOrderDetailID INT,
    ErrorReason NVARCHAR(200),
    LoadDate TIMESTAMP_NTZ(3)
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;