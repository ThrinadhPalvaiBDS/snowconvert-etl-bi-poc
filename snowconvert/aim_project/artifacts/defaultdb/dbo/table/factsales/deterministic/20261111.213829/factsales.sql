USE DATABASE <%defaultdb%>;

CREATE OR REPLACE TABLE dbo.FactSales (
    SalesOrderDetailID INT PRIMARY KEY,
    OrderNumber NVARCHAR(25) NOT NULL,
    OrderDateKey INT NOT NULL,
    CustomerKey INT NOT NULL,
    ProductKey INT NOT NULL,
    Channel NVARCHAR(20) NOT NULL,
    OrderStatus NVARCHAR(20) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(19, 4) NOT NULL,
    DiscountAmount DECIMAL(19, 4) NOT NULL,
    SalesAmount DECIMAL(19, 4) NOT NULL,
    CostAmount DECIMAL(19, 4) NOT NULL,
    MarginAmount DECIMAL(19, 4) NOT NULL,
    LoadDate TIMESTAMP_NTZ(3) NOT NULL
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;