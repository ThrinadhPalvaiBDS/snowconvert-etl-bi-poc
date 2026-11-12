USE DATABASE <%defaultdb%>;

CREATE OR REPLACE TABLE dbo.DimProduct (
    ProductKey INT IDENTITY(1,1) ORDER PRIMARY KEY,
    ProductID INT NOT NULL,
    SKU NVARCHAR(30) NOT NULL,
    ProductName NVARCHAR(200) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    SubCategory NVARCHAR(50) NOT NULL,
    ListPrice DECIMAL(19, 4) NOT NULL,
    StandardCost DECIMAL(19, 4) NOT NULL,
    IsActive BOOLEAN NOT NULL
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;