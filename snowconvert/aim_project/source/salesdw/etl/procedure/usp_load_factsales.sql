USE SalesDW;

GO

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
    WHERE  x.OrderQty <= 0 OR x.UnitPrice < 0 OR x.ProductKey IS NULL;

    -- Conditional Split: default output -> FactSales (upsert)
    MERGE dbo.FactSales AS t
    USING (
        SELECT  SalesOrderDetailID,
                OrderNumber,
                CONVERT(INT, CONVERT(CHAR(8), OrderDate, 112))                      AS OrderDateKey,
                ISNULL(CustomerKey, -1)                                             AS CustomerKey,
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
        WHERE   OrderQty > 0 AND UnitPrice >= 0 AND ProductKey IS NOT NULL
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
