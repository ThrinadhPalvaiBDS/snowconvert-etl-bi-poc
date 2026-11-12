USE ${defaultdb}
GO

CREATE TABLE dbo.SalesOrderHeader (
  SalesOrderID INT IDENTITY(1, 1) PRIMARY KEY,
  OrderNumber NVARCHAR(25) NOT NULL,
  CustomerID INT NOT NULL REFERENCES dbo.Customer (CustomerID),
  OrderDate DATETIME2(3) NOT NULL,
  Status TINYINT NOT NULL, -- 1=Open 2=Shipped 3=Cancelled

  Channel NVARCHAR(20) NOT NULL, -- Web / Store / Partner

  CurrencyCode CHAR(3) NOT NULL,
  ModifiedDate DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);