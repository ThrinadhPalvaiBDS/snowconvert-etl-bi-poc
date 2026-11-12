USE SalesDW;

GO

IF OBJECT_ID('etl.CountryRegion') IS NULL
CREATE TABLE etl.CountryRegion (
    CountryCode CHAR(2)       NOT NULL PRIMARY KEY,
    Country     NVARCHAR(100) NOT NULL,
    Region      NVARCHAR(50)  NOT NULL
);
