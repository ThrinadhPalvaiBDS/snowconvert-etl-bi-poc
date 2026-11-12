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
