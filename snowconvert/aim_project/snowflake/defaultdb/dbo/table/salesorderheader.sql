USE DATABASE <%defaultdb%>;
-- 1=Open 2=Shipped 3=Cancelled
-- Web / Store / Partner
CREATE OR REPLACE TABLE dbo.SalesOrderHeader (
    SalesOrderID INT IDENTITY(1,1) ORDER PRIMARY KEY,
    OrderNumber NVARCHAR(25) NOT NULL,
    CustomerID INT NOT NULL REFERENCES dbo.Customer (CustomerID),
    OrderDate TIMESTAMP_NTZ(3) NOT NULL,
    Status TINYINT NOT NULL,
    Channel NVARCHAR(20) NOT NULL,
    CurrencyCode CHAR(3) NOT NULL,
    ModifiedDate TIMESTAMP_NTZ(3) NOT NULL DEFAULT SYSDATE() :: TIMESTAMP_NTZ(3)
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;