USE DATABASE <%defaultdb%>;

CREATE OR REPLACE TABLE dbo.DimCustomer (
    CustomerKey INT IDENTITY(1,1) ORDER PRIMARY KEY,
    CustomerID INT NOT NULL,
    CustomerCode NVARCHAR(20) NOT NULL,
    CustomerName NVARCHAR(101) NOT NULL,
    Email NVARCHAR(255) NULL,
    City NVARCHAR(100) NULL,
    Country NVARCHAR(100) NULL,
    Region NVARCHAR(50) NULL,
    Segment NVARCHAR(20) NULL,
    RowStartDate TIMESTAMP_NTZ(3) NOT NULL,
    RowEndDate TIMESTAMP_NTZ(3) NULL,
    IsCurrent BOOLEAN NOT NULL
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;