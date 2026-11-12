USE DATABASE <%salesdw%>;

--** SSC-FDM-0007 - MISSING DEPENDENT OBJECTS "SalesOLTP.dbo.SalesOrderDetail", "SalesOLTP.dbo.SalesOrderHeader", "SalesDW.dbo.DimCustomer", "SalesDW.dbo.DimProduct", "SalesDW.dbo.FactSales_Error", "SalesDW.dbo.FactSales" **
CREATE OR REPLACE PROCEDURE etl.usp_Load_FactSales (ROWSLOADED OUT INT, ROWSREJECTED OUT INT)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
EXECUTE AS CALLER
AS
$$
    DECLARE
        WM TIMESTAMP_NTZ(3);
        NEWWM TIMESTAMP_NTZ(3);
    BEGIN
--        --** SSC-FDM-TS0029 - SET NOCOUNT STATEMENT IS COMMENTED OUT, WHICH IS NOT APPLICABLE IN SNOWFLAKE. **
--        SET NOCOUNT ON;
        LET WM_RESULTSET_1 RESULTSET :=
        (

            SELECT
                LoadDate AS WM_VALUE
            FROM
                <%salesdw%>.etl.Watermark
            WHERE
                --** SSC-FDM-TS0191 - TEXT COMPARISON ON A COLUMN DECLARED WITHOUT COLLATE IS CASE AND ACCENT SENSITIVE IN SNOWFLAKE; RESULTS DIFFER IF THE SOURCE DEFAULT COLLATION IS CASE OR ACCENT INSENSITIVE **
                TableName = 'FactSales'
        );
        FOR WM_ROW_1 IN WM_RESULTSET_1 DO
            WM := WM_ROW_1.WM_VALUE;
        END FOR;
        WM := NVL(:WM, '1900-01-01');
        -- Source: lines whose line or header changed since the last load
        CREATE OR REPLACE TEMPORARY TABLE <%salesdw%>.PUBLIC.T_lines AS
            SELECT
                d.SalesOrderDetailID,
                h.OrderNumber,
                h.OrderDate,
                h.CustomerID,
                d.ProductID,
                h.Channel,
                h.Status,
                d.OrderQty,
                d.UnitPrice,
                d.UnitPriceDiscount,
                CASE WHEN d.ModifiedDate > h.ModifiedDate
                        THEN d.ModifiedDate
                    ELSE h.ModifiedDate
                END AS ChangeDate
        FROM
                <%salesoltp%>.dbo.SalesOrderDetail d
        JOIN
                    <%salesoltp%>.dbo.SalesOrderHeader h
                    ON h.SalesOrderID = d.SalesOrderID
        WHERE
                d.ModifiedDate > :WM
                OR h.ModifiedDate > :WM;
        -- Lookups (no match -> NULL key, caught by the split below)
        CREATE OR REPLACE TEMPORARY TABLE <%salesdw%>.PUBLIC.T_enriched AS
            SELECT
                l.*,
                c.CustomerKey,
                p.ProductKey,
                p.StandardCost
              FROM
                <%salesdw%>.PUBLIC.T_lines l
              LEFT JOIN
                    <%salesdw%>.dbo.DimCustomer c
                    ON c.CustomerID = l.CustomerID
                    AND c.IsCurrent = 1
              LEFT JOIN
                    <%salesdw%>.dbo.DimProduct p
                    ON p.ProductID = l.ProductID;

        BEGIN TRANSACTION;
        -- Reprocessed lines: clear earlier errors so each line has one outcome
        DELETE FROM
            <%salesdw%>.dbo.FactSales_Error e
        USING <%salesdw%>.PUBLIC.T_enriched x
        WHERE
            x.SalesOrderDetailID = e.SalesOrderDetailID;

        -- Conditional Split: error output
        INSERT INTO <%salesdw%>.dbo.FactSales_Error (SalesOrderDetailID, ErrorReason, LoadDate)
        SELECT
            SalesOrderDetailID,
               CASE WHEN OrderQty <= 0       THEN 'Non-positive quantity'
                    WHEN UnitPrice < 0       THEN 'Negative unit price'
                    WHEN ProductKey IS NULL  THEN 'Product lookup no match'
                    WHEN CustomerKey IS NULL THEN 'Customer lookup no match'
            END,
            CURRENT_TIMESTAMP() /*** SSC-FDM-TS0186 - SYSDATETIME() RETURNS THE LOCAL TIME OF THE SQL SERVER HOST; THE CONVERTED CALL FOLLOWS THE SNOWFLAKE SESSION TIMEZONE. SET TIMEZONE TO THE SOURCE SERVER'S ZONE FOR THE USERS THAT RUN THIS CODE ***/
        FROM
            <%salesdw%>.PUBLIC.T_enriched
        WHERE
            OrderQty <= 0 OR UnitPrice < 0 OR ProductKey IS NULL OR CustomerKey IS NULL;
        ROWSREJECTED := SQLROWCOUNT;
        -- A line that has become invalid must not stay in the fact table
        DELETE FROM
            <%salesdw%>.dbo.FactSales f
        USING <%salesdw%>.PUBLIC.T_enriched x
        WHERE
            x.OrderQty <= 0 OR x.UnitPrice < 0 OR x.ProductKey IS NULL
            AND x.SalesOrderDetailID = f.SalesOrderDetailID;
        -- Conditional Split: default output -> FactSales (upsert)
        MERGE INTO <%salesdw%>.dbo.FactSales AS t
        USING (
            SELECT
                SalesOrderDetailID,
                OrderNumber,
                CAST(LEFT(TO_VARCHAR(OrderDate, 'yyyymmdd'), 8) AS INT) AS OrderDateKey,
                NVL(CustomerKey, -1)                                             AS CustomerKey,
                ProductKey,
                Channel,
                    CASE
                    Status
                    WHEN 1 THEN 'Open'
                    WHEN 2 THEN 'Shipped'
                                WHEN 3 THEN 'Cancelled'
                    ELSE 'Unknown'
                END            AS OrderStatus,
                    CAST(OrderQty AS INT)                                               AS Quantity,
                    CAST(UnitPrice AS DECIMAL(19, 4))                                    AS UnitPrice,
                    CAST(ROUND(OrderQty * UnitPrice * UnitPriceDiscount, 4) AS DECIMAL(19, 4)) AS DiscountAmount,
                    CAST(ROUND(OrderQty * UnitPrice * (1 - UnitPriceDiscount), 4) AS DECIMAL(19, 4)) AS SalesAmount,
                    CAST(ROUND(OrderQty * StandardCost, 4) AS DECIMAL(19, 4))            AS CostAmount
            FROM
                <%salesdw%>.PUBLIC.T_enriched
            WHERE
                OrderQty > 0 AND UnitPrice >= 0 AND ProductKey IS NOT NULL
        ) AS s
        ON t.SalesOrderDetailID = s.SalesOrderDetailID
        WHEN MATCHED THEN
            UPDATE SET
                OrderNumber = s.OrderNumber,
                OrderDateKey = s.OrderDateKey,
                CustomerKey = s.CustomerKey,
                ProductKey = s.ProductKey,
                Channel = s.Channel,
                OrderStatus = s.OrderStatus,
                Quantity = s.Quantity,
                UnitPrice = s.UnitPrice,
                DiscountAmount = s.DiscountAmount,
                SalesAmount = s.SalesAmount,
                CostAmount = s.CostAmount,
                MarginAmount = s.SalesAmount - s.CostAmount,
                LoadDate = CURRENT_TIMESTAMP() /*** SSC-FDM-TS0186 - SYSDATETIME() RETURNS THE LOCAL TIME OF THE SQL SERVER HOST; THE CONVERTED CALL FOLLOWS THE SNOWFLAKE SESSION TIMEZONE. SET TIMEZONE TO THE SOURCE SERVER'S ZONE FOR THE USERS THAT RUN THIS CODE ***/
        WHEN NOT MATCHED THEN
            INSERT
            (SalesOrderDetailID, OrderNumber, OrderDateKey, CustomerKey, ProductKey, Channel, OrderStatus, Quantity, UnitPrice, DiscountAmount, SalesAmount, CostAmount, MarginAmount, LoadDate)
            VALUES
            (s.SalesOrderDetailID, s.OrderNumber, s.OrderDateKey, s.CustomerKey, s.ProductKey, s.Channel, s.OrderStatus, s.Quantity, s.UnitPrice, s.DiscountAmount, s.SalesAmount, s.CostAmount, s.SalesAmount - s.CostAmount, CURRENT_TIMESTAMP() /*** SSC-FDM-TS0186 - SYSDATETIME() RETURNS THE LOCAL TIME OF THE SQL SERVER HOST; THE CONVERTED CALL FOLLOWS THE SNOWFLAKE SESSION TIMEZONE. SET TIMEZONE TO THE SOURCE SERVER'S ZONE FOR THE USERS THAT RUN THIS CODE ***/);
        ROWSLOADED := SQLROWCOUNT;

        -- Update Watermark (Execute SQL Task)
        SELECT
            MAX(ChangeDate)
        INTO
            :NEWWM
 FROM
            <%salesdw%>.PUBLIC.T_lines;
        IF (:NEWWM IS NOT NULL) THEN
            UPDATE <%salesdw%>.etl.Watermark
                SET
                    LoadDate = :NEWWM
                WHERE
                    --** SSC-FDM-TS0191 - TEXT COMPARISON ON A COLUMN DECLARED WITHOUT COLLATE IS CASE AND ACCENT SENSITIVE IN SNOWFLAKE; RESULTS DIFFER IF THE SOURCE DEFAULT COLLATION IS CASE OR ACCENT INSENSITIVE **
                    TableName = 'FactSales';
        END IF;
        COMMIT;
        DROP TABLE IF EXISTS <%salesdw%>.PUBLIC.T_enriched;
        DROP TABLE IF EXISTS <%salesdw%>.PUBLIC.T_lines;
    END;
$$;