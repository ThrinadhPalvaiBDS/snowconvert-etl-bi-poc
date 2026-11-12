USE ${salesdw};
GO

IF SCHEMA_ID('etl') IS NULL
  EXEC (/*<<BRANCH:~src=Q1JFQVRFIFNDSEVNQSBldGw=*/  CREATE SCHEMA etl /*>>BRANCH:*/

  );

IF NOT EXISTS (
  SELECT
    1
  FROM
    etl.Watermark
  WHERE
    TableName = N'FactSales'
)
  INSERT etl.Watermark (TableName, LoadDate) VALUES (N'FactSales', '1900-01-01');

MERGE etl.CountryRegion AS t
USING (VALUES('IN', N'India', N'APAC'), ('SG', N'Singapore', N'APAC'), ('AU', N'Australia', N'APAC'), ('JP', N'Japan', N'APAC'), ('US', N'United States', N'NA'), ('CA', N'Canada', N'NA'), ('GB', N'United Kingdom', N'EMEA'), ('DE', N'Germany', N'EMEA'), ('FR', N'France', N'EMEA'), ('AE', N'United Arab Emirates', N'EMEA'), ('BR', N'Brazil', N'LATAM'), ('MX', N'Mexico', N'LATAM')) AS s (
  CountryCode,
  Country,
  Region
)
ON t.CountryCode = s.CountryCode
WHEN MATCHED THEN
  UPDATE SET
    Country = s.Country,
    Region = s.Region
WHEN NOT MATCHED THEN
  INSERT (CountryCode, Country, Region)
  VALUES (s.CountryCode, s.Country, s.Region);

IF NOT EXISTS (
  SELECT
    1
  FROM
    dbo.DimCustomer
  WHERE
    CustomerKey = -1
)
  BEGIN
    SET IDENTITY_INSERT dbo.DimCustomer ON;
    INSERT dbo.DimCustomer (CustomerKey, CustomerID, CustomerCode, CustomerName, Email, City, Country, Region, Segment, RowStartDate, RowEndDate, IsCurrent) VALUES (-1, -1, N'UNKNOWN', N'Unknown', NULL, N'Unknown', N'Unknown', N'Unknown', N'Unknown', '1900-01-01', NULL, 1);
    SET IDENTITY_INSERT dbo.DimCustomer OFF;
  END;