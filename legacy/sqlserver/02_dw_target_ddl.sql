-- Legacy SQL Server DW (SalesDW) - what SSIS loads and what Power BI reads today.
-- These names/columns are reproduced 1:1 by dbt/models/compat so reports need no rebuild.
CREATE TABLE dbo.DimCustomer (
    CustomerKey     INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID      INT           NOT NULL,
    CustomerCode    NVARCHAR(20)  NOT NULL,
    CustomerName    NVARCHAR(101) NOT NULL,
    Email           NVARCHAR(255) NULL,
    City            NVARCHAR(100) NULL,
    Country         NVARCHAR(100) NULL,
    Region          NVARCHAR(50)  NULL,
    Segment         NVARCHAR(20)  NULL,
    RowStartDate    DATETIME2(3)  NOT NULL,
    RowEndDate      DATETIME2(3)  NULL,
    IsCurrent       BIT           NOT NULL
);

CREATE TABLE dbo.DimProduct (
    ProductKey      INT IDENTITY(1,1) PRIMARY KEY,
    ProductID       INT           NOT NULL,
    SKU             NVARCHAR(30)  NOT NULL,
    ProductName     NVARCHAR(200) NOT NULL,
    Category        NVARCHAR(50)  NOT NULL,
    SubCategory     NVARCHAR(50)  NOT NULL,
    ListPrice       DECIMAL(19,4) NOT NULL,
    StandardCost    DECIMAL(19,4) NOT NULL,
    IsActive        BIT           NOT NULL
);

CREATE TABLE dbo.DimDate (
    DateKey         INT PRIMARY KEY,         -- yyyymmdd
    [Date]          DATE NOT NULL,
    [Year]          SMALLINT NOT NULL,
    [Quarter]       TINYINT NOT NULL,
    [Month]         TINYINT NOT NULL,
    MonthName       NVARCHAR(12) NOT NULL,
    DayOfWeek       TINYINT NOT NULL,
    IsWeekend       BIT NOT NULL
);

CREATE TABLE dbo.FactSales (
    SalesOrderDetailID INT PRIMARY KEY,
    OrderNumber     NVARCHAR(25)  NOT NULL,
    OrderDateKey    INT           NOT NULL,
    CustomerKey     INT           NOT NULL,
    ProductKey      INT           NOT NULL,
    Channel         NVARCHAR(20)  NOT NULL,
    OrderStatus     NVARCHAR(20)  NOT NULL,
    Quantity        INT           NOT NULL,
    UnitPrice       DECIMAL(19,4) NOT NULL,
    DiscountAmount  DECIMAL(19,4) NOT NULL,
    SalesAmount     DECIMAL(19,4) NOT NULL,
    CostAmount      DECIMAL(19,4) NOT NULL,
    MarginAmount    DECIMAL(19,4) NOT NULL,
    LoadDate        DATETIME2(3)  NOT NULL
);

CREATE TABLE dbo.FactSales_Error (
    SalesOrderDetailID INT, ErrorReason NVARCHAR(200), LoadDate DATETIME2(3)
);

-- Report-facing view used by Power BI "Sales Performance" report (embedded SQL case)
CREATE VIEW dbo.vw_SalesByMonth AS
SELECT d.[Year], d.[Month], d.MonthName, c.Region, p.Category,
       SUM(f.SalesAmount) AS SalesAmount, SUM(f.MarginAmount) AS MarginAmount
FROM dbo.FactSales f
JOIN dbo.DimDate d     ON d.DateKey = f.OrderDateKey
JOIN dbo.DimCustomer c ON c.CustomerKey = f.CustomerKey
JOIN dbo.DimProduct p  ON p.ProductKey = f.ProductKey
GROUP BY d.[Year], d.[Month], d.MonthName, c.Region, p.Category;
