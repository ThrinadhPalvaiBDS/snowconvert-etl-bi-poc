USE DATABASE <%defaultdb%>;

CREATE OR REPLACE TABLE dbo.SalesOrderDetail (
    SalesOrderDetailID INT IDENTITY(1,1) ORDER PRIMARY KEY,
    SalesOrderID INT NOT NULL REFERENCES dbo.SalesOrderHeader (SalesOrderID),
    ProductID INT NOT NULL REFERENCES dbo.Product (ProductID),
    OrderQty SMALLINT NOT NULL,
    UnitPrice NUMBER(38, 4) NOT NULL,
    UnitPriceDiscount NUMBER(38, 4) NOT NULL DEFAULT 0,
    ModifiedDate TIMESTAMP_NTZ(3) NOT NULL DEFAULT SYSDATE() :: TIMESTAMP_NTZ(3)
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;