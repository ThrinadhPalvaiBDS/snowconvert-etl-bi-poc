-- =====================================================================
-- 05 LEGACY ETL (T-SQL) - SalesOLTP -> SalesDW
-- The legacy load written as stored procedures. It does what the SSIS
-- package Load_SalesDW does, and is the input for SnowConvert AI (Stage 3)
-- in place of a full .dtsx:
--   Control flow : Get Watermark -> Sequence (DimProduct, DimCustomer)
--                  -> FactSales -> Update Watermark, with OnError logging + email
--   Data flows   : Derived Column, Data Conversion, Lookups (country/region,
--                  customer, product), SCD (DimCustomer), Conditional Split
--                  (valid rows -> FactSales, bad rows -> FactSales_Error)
-- Runs in SalesDW and reads SalesOLTP through three-part names.
-- Business rules match the POC dbt models (stg_*, dim_*, fct_sales,
-- int_order_lines_rejected) so the Stage 3.9 comparison is like for like.
-- =====================================================================
USE SalesDW;
GO

IF SCHEMA_ID('etl') IS NULL EXEC ('CREATE SCHEMA etl');
GO

-- ---------------------------------------------------------------------
-- ETL control tables
-- ---------------------------------------------------------------------
IF OBJECT_ID('etl.Watermark') IS NULL
CREATE TABLE etl.Watermark (
    TableName   NVARCHAR(50) NOT NULL PRIMARY KEY,
    LoadDate    DATETIME2(3) NOT NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM etl.Watermark WHERE TableName = N'FactSales')
    INSERT etl.Watermark (TableName, LoadDate) VALUES (N'FactSales', '1900-01-01');
GO

-- Replaces the SSIS log provider / OnError event handler
IF OBJECT_ID('etl.LoadLog') IS NULL
CREATE TABLE etl.LoadLog (
    LoadLogID     INT IDENTITY(1,1) PRIMARY KEY,
    RunID         UNIQUEIDENTIFIER NOT NULL,
    StepName      NVARCHAR(100)    NOT NULL,
    Status        NVARCHAR(20)     NOT NULL,   -- Started / Succeeded / Failed
    RowsAffected  INT              NULL,
    ErrorMessage  NVARCHAR(4000)   NULL,
    LoggedAt      DATETIME2(3)     NOT NULL DEFAULT SYSDATETIME()
);
GO

-- Reference data used by the country/region Lookup (dbt: seeds/country_region.csv)
IF OBJECT_ID('etl.CountryRegion') IS NULL
CREATE TABLE etl.CountryRegion (
    CountryCode CHAR(2)       NOT NULL PRIMARY KEY,
    Country     NVARCHAR(100) NOT NULL,
    Region      NVARCHAR(50)  NOT NULL
);
GO

MERGE etl.CountryRegion AS t
USING (VALUES ('IN', N'India',                N'APAC'),
              ('SG', N'Singapore',            N'APAC'),
              ('AU', N'Australia',            N'APAC'),
              ('JP', N'Japan',                N'APAC'),
              ('US', N'United States',        N'NA'),
              ('CA', N'Canada',               N'NA'),
              ('GB', N'United Kingdom',       N'EMEA'),
              ('DE', N'Germany',              N'EMEA'),
              ('FR', N'France',               N'EMEA'),
              ('AE', N'United Arab Emirates', N'EMEA'),
              ('BR', N'Brazil',               N'LATAM'),
              ('MX', N'Mexico',               N'LATAM')) AS s (CountryCode, Country, Region)
ON t.CountryCode = s.CountryCode
WHEN MATCHED THEN UPDATE SET Country = s.Country, Region = s.Region
WHEN NOT MATCHED THEN INSERT (CountryCode, Country, Region) VALUES (s.CountryCode, s.Country, s.Region);
GO

-- ---------------------------------------------------------------------
-- Logging helper
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_LogStep
    @RunID        UNIQUEIDENTIFIER,
    @StepName     NVARCHAR(100),
    @Status       NVARCHAR(20),
    @RowsAffected INT            = NULL,
    @ErrorMessage NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT etl.LoadLog (RunID, StepName, Status, RowsAffected, ErrorMessage)
    VALUES (@RunID, @StepName, @Status, @RowsAffected, @ErrorMessage);
END;
GO

-- ---------------------------------------------------------------------
-- DimDate: add any missing days between two dates
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_Load_DimDate
    @StartDate DATE,
    @EndDate   DATE,
    @RowsAdded INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET DATEFIRST 7;                 -- Sunday = 1, so DayOfWeek is stable
    DECLARE @d DATE = @StartDate;
    SET @RowsAdded = 0;

    WHILE @d <= @EndDate
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.DimDate WHERE DateKey = CONVERT(INT, CONVERT(CHAR(8), @d, 112)))
        BEGIN
            INSERT dbo.DimDate (DateKey, [Date], [Year], [Quarter], [Month], MonthName, DayOfWeek, IsWeekend)
            VALUES (CONVERT(INT, CONVERT(CHAR(8), @d, 112)),
                    @d,
                    YEAR(@d),
                    DATEPART(QUARTER, @d),
                    MONTH(@d),
                    DATENAME(MONTH, @d),
                    DATEPART(WEEKDAY, @d),
                    CASE WHEN DATEPART(WEEKDAY, @d) IN (1, 7) THEN 1 ELSE 0 END);
            SET @RowsAdded += 1;
        END;
        SET @d = DATEADD(DAY, 1, @d);
    END;
END;
GO

-- ---------------------------------------------------------------------
-- DFT - DimProduct: Type 1 (overwrite) load
-- Derived Column: Unknown defaults. Data Conversion: MONEY -> DECIMAL(19,4)
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_Load_DimProduct
    @RowsAffected INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.DimProduct AS t
    USING (
        SELECT ProductID,
               LTRIM(RTRIM(SKU))                                        AS SKU,
               LTRIM(RTRIM(ProductName))                                AS ProductName,
               ISNULL(NULLIF(LTRIM(RTRIM(Category)), N''), N'Unknown')    AS Category,
               ISNULL(NULLIF(LTRIM(RTRIM(SubCategory)), N''), N'Unknown') AS SubCategory,
               CAST(ListPrice    AS DECIMAL(19,4))                      AS ListPrice,
               CAST(StandardCost AS DECIMAL(19,4))                      AS StandardCost,
               IsActive
        FROM SalesOLTP.dbo.Product WITH (NOLOCK)
    ) AS s
    ON t.ProductID = s.ProductID
    WHEN MATCHED AND (t.SKU <> s.SKU OR t.ProductName <> s.ProductName OR t.Category <> s.Category
                      OR t.SubCategory <> s.SubCategory OR t.ListPrice <> s.ListPrice
                      OR t.StandardCost <> s.StandardCost OR t.IsActive <> s.IsActive)
        THEN UPDATE SET SKU = s.SKU, ProductName = s.ProductName, Category = s.Category,
                        SubCategory = s.SubCategory, ListPrice = s.ListPrice,
                        StandardCost = s.StandardCost, IsActive = s.IsActive
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (ProductID, SKU, ProductName, Category, SubCategory, ListPrice, StandardCost, IsActive)
             VALUES (s.ProductID, s.SKU, s.ProductName, s.Category, s.SubCategory, s.ListPrice, s.StandardCost, s.IsActive);

    SET @RowsAffected = @@ROWCOUNT;
END;
GO

-- ---------------------------------------------------------------------
-- DFT - DimCustomer: Slowly Changing Dimension
--   Type 2 (history) : City, Country, Region, Segment
--   Type 1 (overwrite): CustomerCode, CustomerName, Email
-- Lookup: CountryCode -> Country, Region (no match -> 'Unknown')
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_Load_DimCustomer
    @RowsAffected INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expired INT, @inserted INT, @type1 INT;

    SELECT  c.CustomerID,
            LTRIM(RTRIM(c.CustomerCode))                                   AS CustomerCode,
            LTRIM(RTRIM(c.FirstName)) + N' ' + LTRIM(RTRIM(c.LastName))     AS CustomerName,
            LOWER(NULLIF(LTRIM(RTRIM(c.Email)), N''))                       AS Email,
            ISNULL(NULLIF(LTRIM(RTRIM(c.City)), N''), N'Unknown')           AS City,
            ISNULL(cr.Country, N'Unknown')                                  AS Country,
            ISNULL(cr.Region,  N'Unknown')                                  AS Region,
            ISNULL(NULLIF(LTRIM(RTRIM(c.Segment)), N''), N'Unknown')        AS Segment,
            c.ModifiedDate
    INTO    #src
    FROM    SalesOLTP.dbo.Customer c WITH (NOLOCK)
    LEFT JOIN etl.CountryRegion cr
           ON cr.CountryCode = UPPER(NULLIF(LTRIM(RTRIM(c.CountryCode)), ''));

    BEGIN TRAN;

    -- Type 2: close the current row when a historical attribute changed
    UPDATE d
    SET    RowEndDate = s.ModifiedDate,
           IsCurrent  = 0
    FROM   dbo.DimCustomer d
    JOIN   #src s ON s.CustomerID = d.CustomerID
    WHERE  d.IsCurrent = 1
      AND (ISNULL(d.City, N'')    <> s.City
        OR ISNULL(d.Country, N'') <> s.Country
        OR ISNULL(d.Region, N'')  <> s.Region
        OR ISNULL(d.Segment, N'') <> s.Segment);
    SET @expired = @@ROWCOUNT;

    -- New customers, and new versions of the ones just closed
    INSERT dbo.DimCustomer (CustomerID, CustomerCode, CustomerName, Email, City, Country, Region, Segment,
                            RowStartDate, RowEndDate, IsCurrent)
    SELECT s.CustomerID, s.CustomerCode, s.CustomerName, s.Email, s.City, s.Country, s.Region, s.Segment,
           s.ModifiedDate, NULL, 1
    FROM   #src s
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.DimCustomer d WHERE d.CustomerID = s.CustomerID AND d.IsCurrent = 1);
    SET @inserted = @@ROWCOUNT;

    -- Type 1: overwrite on the current row
    UPDATE d
    SET    CustomerCode = s.CustomerCode,
           CustomerName = s.CustomerName,
           Email        = s.Email
    FROM   dbo.DimCustomer d
    JOIN   #src s ON s.CustomerID = d.CustomerID
    WHERE  d.IsCurrent = 1
      AND (d.CustomerCode <> s.CustomerCode
        OR d.CustomerName <> s.CustomerName
        OR ISNULL(d.Email, N'') <> ISNULL(s.Email, N''));
    SET @type1 = @@ROWCOUNT;

    COMMIT;

    SET @RowsAffected = @expired + @inserted + @type1;
    DROP TABLE #src;
END;
GO

-- ---------------------------------------------------------------------
-- DFT - FactSales: incremental load from the watermark
--   Lookups      : DimCustomer (current row), DimProduct
--   Derived Cols : OrderDateKey, OrderStatus, amounts
--   Cond. Split  : bad rows -> FactSales_Error (same rules and order as
--                  dbt int_order_lines_rejected), good rows -> FactSales
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_Load_FactSales
    @RowsLoaded   INT OUTPUT,
    @RowsRejected INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @wm DATETIME2(3), @newWm DATETIME2(3);

    SELECT @wm = LoadDate FROM etl.Watermark WHERE TableName = N'FactSales';
    SET @wm = ISNULL(@wm, '1900-01-01');

    -- Source: lines whose line or header changed since the last load
    SELECT  d.SalesOrderDetailID,
            h.OrderNumber,
            h.OrderDate,
            h.CustomerID,
            d.ProductID,
            h.Channel,
            h.Status,
            d.OrderQty,
            d.UnitPrice,
            d.UnitPriceDiscount,
            CASE WHEN d.ModifiedDate > h.ModifiedDate THEN d.ModifiedDate ELSE h.ModifiedDate END AS ChangeDate
    INTO    #lines
    FROM    SalesOLTP.dbo.SalesOrderDetail d WITH (NOLOCK)
    JOIN    SalesOLTP.dbo.SalesOrderHeader h WITH (NOLOCK) ON h.SalesOrderID = d.SalesOrderID
    WHERE   d.ModifiedDate > @wm OR h.ModifiedDate > @wm;

    -- Lookups (no match -> NULL key, caught by the split below)
    SELECT  l.*,
            c.CustomerKey,
            p.ProductKey,
            p.StandardCost
    INTO    #enriched
    FROM    #lines l
    LEFT JOIN dbo.DimCustomer c ON c.CustomerID = l.CustomerID AND c.IsCurrent = 1
    LEFT JOIN dbo.DimProduct  p ON p.ProductID  = l.ProductID;

    BEGIN TRAN;

    -- Reprocessed lines: clear earlier errors so each line has one outcome
    DELETE e
    FROM   dbo.FactSales_Error e
    JOIN   #enriched x ON x.SalesOrderDetailID = e.SalesOrderDetailID;

    -- Conditional Split: error output
    INSERT dbo.FactSales_Error (SalesOrderDetailID, ErrorReason, LoadDate)
    SELECT SalesOrderDetailID,
           CASE WHEN OrderQty <= 0       THEN N'Non-positive quantity'
                WHEN UnitPrice < 0       THEN N'Negative unit price'
                WHEN ProductKey IS NULL  THEN N'Product lookup no match'
                WHEN CustomerKey IS NULL THEN N'Customer lookup no match' END,
           SYSDATETIME()
    FROM   #enriched
    WHERE  OrderQty <= 0 OR UnitPrice < 0 OR ProductKey IS NULL OR CustomerKey IS NULL;
    SET @RowsRejected = @@ROWCOUNT;

    -- A line that has become invalid must not stay in the fact table
    DELETE f
    FROM   dbo.FactSales f
    JOIN   #enriched x ON x.SalesOrderDetailID = f.SalesOrderDetailID
    WHERE  x.OrderQty <= 0 OR x.UnitPrice < 0 OR x.ProductKey IS NULL OR x.CustomerKey IS NULL;

    -- Conditional Split: default output -> FactSales (upsert)
    MERGE dbo.FactSales AS t
    USING (
        SELECT  SalesOrderDetailID,
                OrderNumber,
                CONVERT(INT, CONVERT(CHAR(8), OrderDate, 112))                      AS OrderDateKey,
                CustomerKey,
                ProductKey,
                Channel,
                CASE Status WHEN 1 THEN N'Open' WHEN 2 THEN N'Shipped'
                            WHEN 3 THEN N'Cancelled' ELSE N'Unknown' END            AS OrderStatus,
                CAST(OrderQty AS INT)                                               AS Quantity,
                CAST(UnitPrice AS DECIMAL(19,4))                                    AS UnitPrice,
                CAST(ROUND(OrderQty * UnitPrice * UnitPriceDiscount, 4) AS DECIMAL(19,4)) AS DiscountAmount,
                CAST(ROUND(OrderQty * UnitPrice * (1 - UnitPriceDiscount), 4) AS DECIMAL(19,4)) AS SalesAmount,
                CAST(ROUND(OrderQty * StandardCost, 4) AS DECIMAL(19,4))            AS CostAmount
        FROM    #enriched
        WHERE   OrderQty > 0 AND UnitPrice >= 0 AND ProductKey IS NOT NULL AND CustomerKey IS NOT NULL
    ) AS s
    ON t.SalesOrderDetailID = s.SalesOrderDetailID
    WHEN MATCHED THEN UPDATE SET
        OrderNumber = s.OrderNumber, OrderDateKey = s.OrderDateKey, CustomerKey = s.CustomerKey,
        ProductKey = s.ProductKey, Channel = s.Channel, OrderStatus = s.OrderStatus,
        Quantity = s.Quantity, UnitPrice = s.UnitPrice, DiscountAmount = s.DiscountAmount,
        SalesAmount = s.SalesAmount, CostAmount = s.CostAmount,
        MarginAmount = s.SalesAmount - s.CostAmount, LoadDate = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (SalesOrderDetailID, OrderNumber, OrderDateKey, CustomerKey, ProductKey, Channel, OrderStatus,
         Quantity, UnitPrice, DiscountAmount, SalesAmount, CostAmount, MarginAmount, LoadDate)
        VALUES
        (s.SalesOrderDetailID, s.OrderNumber, s.OrderDateKey, s.CustomerKey, s.ProductKey, s.Channel, s.OrderStatus,
         s.Quantity, s.UnitPrice, s.DiscountAmount, s.SalesAmount, s.CostAmount,
         s.SalesAmount - s.CostAmount, SYSDATETIME());
    SET @RowsLoaded = @@ROWCOUNT;

    -- Update Watermark (Execute SQL Task)
    SELECT @newWm = MAX(ChangeDate) FROM #lines;
    IF @newWm IS NOT NULL
        UPDATE etl.Watermark SET LoadDate = @newWm WHERE TableName = N'FactSales';

    COMMIT;

    DROP TABLE #enriched;
    DROP TABLE #lines;
END;
GO

-- ---------------------------------------------------------------------
-- Package entry point (what the SQL Agent job runs)
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_Load_SalesDW
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunID UNIQUEIDENTIFIER = NEWID();
    DECLARE @Step NVARCHAR(100), @Rows INT, @Rejected INT;
    DECLARE @MinDate DATE, @MaxDate DATE;

    BEGIN TRY
        SET @Step = N'Package';
        EXEC etl.usp_LogStep @RunID, @Step, N'Started';

        -- Make sure every order date has a DimDate row
        SET @Step = N'Load DimDate';
        SELECT @MinDate = CAST(MIN(OrderDate) AS DATE), @MaxDate = CAST(MAX(OrderDate) AS DATE)
        FROM SalesOLTP.dbo.SalesOrderHeader WITH (NOLOCK);
        IF @MinDate IS NOT NULL
        BEGIN
            EXEC etl.usp_Load_DimDate @MinDate, @MaxDate, @Rows OUTPUT;
            EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;
        END;

        -- Sequence container: dimensions
        SET @Step = N'DFT - DimProduct';
        EXEC etl.usp_Load_DimProduct @Rows OUTPUT;
        EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;

        SET @Step = N'DFT - DimCustomer';
        EXEC etl.usp_Load_DimCustomer @Rows OUTPUT;
        EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;

        -- Fact + watermark
        SET @Step = N'DFT - FactSales';
        EXEC etl.usp_Load_FactSales @Rows OUTPUT, @Rejected OUTPUT;
        EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;
        EXEC etl.usp_LogStep @RunID, N'FactSales rejected rows', N'Succeeded', @Rejected;

        EXEC etl.usp_LogStep @RunID, N'Package', N'Succeeded';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        DECLARE @Err NVARCHAR(4000) =
            CONCAT(N'Step "', @Step, N'" failed: ', ERROR_MESSAGE(),
                   N' (error ', ERROR_NUMBER(), N', line ', ERROR_LINE(), N')');
        EXEC etl.usp_LogStep @RunID, @Step, N'Failed', NULL, @Err;

        -- OnError event handler: Send Mail Task
        DECLARE @Subject NVARCHAR(255) = CONCAT(N'Load_SalesDW FAILED at ', FORMAT(SYSDATETIME(), 'yyyy-MM-dd HH:mm'));
        EXEC msdb.dbo.sp_send_dbmail
             @profile_name = N'DataOps',
             @recipients   = N'thrinadhp@booleandata.ai',
             @subject      = @Subject,
             @body         = @Err;

        THROW;
    END CATCH;
END;
GO

-- Run the load:
-- EXEC etl.usp_Load_SalesDW;
-- SELECT * FROM etl.LoadLog ORDER BY LoadLogID DESC;