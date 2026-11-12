USE ${defaultdb}
GO

CREATE TABLE dbo.SalesOrderDetail (
  SalesOrderDetailID INT IDENTITY(1, 1) PRIMARY KEY,
  SalesOrderID INT NOT NULL REFERENCES dbo.SalesOrderHeader (SalesOrderID),
  ProductID INT NOT NULL REFERENCES dbo.Product (ProductID),
  OrderQty SMALLINT NOT NULL,
  UnitPrice MONEY NOT NULL,
  UnitPriceDiscount MONEY NOT NULL DEFAULT 0,
  ModifiedDate DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);