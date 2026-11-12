USE DATABASE <%defaultdb%>;

CREATE OR REPLACE TABLE dbo.Customer (
    CustomerID INT IDENTITY(1,1) ORDER PRIMARY KEY,
    CustomerCode NVARCHAR(20) NOT NULL,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(255) NULL,
    Phone NVARCHAR(30) NULL,
    City NVARCHAR(100) NULL,
    CountryCode CHAR(2) NULL,
    Segment NVARCHAR(20) NULL,
    ModifiedDate TIMESTAMP_NTZ(3) NOT NULL DEFAULT SYSDATE() :: TIMESTAMP_NTZ(3)
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;