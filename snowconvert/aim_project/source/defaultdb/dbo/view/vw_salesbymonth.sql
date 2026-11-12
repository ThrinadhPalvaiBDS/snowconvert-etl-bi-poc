USE defaultdb

GO

CREATE VIEW dbo.vw_SalesByMonth AS
SELECT d.[Year], d.[Month], d.MonthName, c.Region, p.Category,
       SUM(f.SalesAmount) AS SalesAmount, SUM(f.MarginAmount) AS MarginAmount
FROM dbo.FactSales f
JOIN dbo.DimDate d     ON d.DateKey = f.OrderDateKey
JOIN dbo.DimCustomer c ON c.CustomerKey = f.CustomerKey
JOIN dbo.DimProduct p  ON p.ProductKey = f.ProductKey
GROUP BY d.[Year], d.[Month], d.MonthName, c.Region, p.Category;
