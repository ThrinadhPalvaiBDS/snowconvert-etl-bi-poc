USE ${defaultdb}
GO

CREATE TABLE dbo.FactSales_Error (
  SalesOrderDetailID INT,
  ErrorReason NVARCHAR(200),
  LoadDate DATETIME2(3)
);