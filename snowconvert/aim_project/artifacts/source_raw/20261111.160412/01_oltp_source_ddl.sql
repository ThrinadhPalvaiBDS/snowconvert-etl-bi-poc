-- Legacy SQL Server OLTP source (SalesOLTP) - input to SnowConvert AI and to ingestion
CREATE TABLE dbo.Customer (
    CustomerID      INT IDENTITY(1,1) PRIMARY KEY,
    CustomerCode    NVARCHAR(20)  NOT NULL,
    FirstName       NVARCHAR(50)  NOT NULL,
    LastName        NVARCHAR(50)  NOT NULL,
    Email           NVARCHAR(255) NULL,
    Phone           NVARCHAR(30)  NULL,
    City            NVARCHAR(100) NULL,
    CountryCode     CHAR(2)       NULL,
    Segment         NVARCHAR(20)  NULL,
    ModifiedDate    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.Product (
    ProductID       INT IDENTITY(1,1) PRIMARY KEY,
    SKU             NVARCHAR(30)  NOT NULL,
    ProductName     NVARCHAR(200) NOT NULL,
    Category        NVARCHAR(50)  NULL,
    SubCategory     NVARCHAR(50)  NULL,
    ListPrice       MONEY         NOT NULL,
    StandardCost    MONEY         NOT NULL,
    IsActive        BIT           NOT NULL DEFAULT 1,
    ModifiedDate    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.SalesOrderHeader (
    SalesOrderID    INT IDENTITY(1,1) PRIMARY KEY,
    OrderNumber     NVARCHAR(25)  NOT NULL,
    CustomerID      INT           NOT NULL REFERENCES dbo.Customer(CustomerID),
    OrderDate       DATETIME2(3)  NOT NULL,
    Status          TINYINT       NOT NULL,   -- 1=Open 2=Shipped 3=Cancelled
    Channel         NVARCHAR(20)  NOT NULL,   -- Web / Store / Partner
    CurrencyCode    CHAR(3)       NOT NULL,
    ModifiedDate    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.SalesOrderDetail (
    SalesOrderDetailID INT IDENTITY(1,1) PRIMARY KEY,
    SalesOrderID    INT           NOT NULL REFERENCES dbo.SalesOrderHeader(SalesOrderID),
    ProductID       INT           NOT NULL REFERENCES dbo.Product(ProductID),
    OrderQty        SMALLINT      NOT NULL,
    UnitPrice       MONEY         NOT NULL,
    UnitPriceDiscount MONEY       NOT NULL DEFAULT 0,
    ModifiedDate    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
