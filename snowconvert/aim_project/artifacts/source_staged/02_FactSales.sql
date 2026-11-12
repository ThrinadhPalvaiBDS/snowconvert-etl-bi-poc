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
