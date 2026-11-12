USE DATABASE <%defaultdb%>;

CREATE OR REPLACE TABLE dbo.Product (
    ProductID INT IDENTITY(1,1) ORDER PRIMARY KEY,
    SKU NVARCHAR(30) NOT NULL,
    ProductName NVARCHAR(200) NOT NULL,
    Category NVARCHAR(50) NULL,
    SubCategory NVARCHAR(50) NULL,
    ListPrice NUMBER(38, 4) NOT NULL,
    StandardCost NUMBER(38, 4) NOT NULL,
    IsActive BOOLEAN NOT NULL DEFAULT true,
    ModifiedDate TIMESTAMP_NTZ(3) NOT NULL DEFAULT SYSDATE() :: TIMESTAMP_NTZ(3)
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;