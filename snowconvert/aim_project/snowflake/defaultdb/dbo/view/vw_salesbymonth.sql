USE DATABASE <%defaultdb%>;

CREATE OR REPLACE VIEW dbo.vw_SalesByMonth
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
AS
SELECT
       d.Year,
       d.Month,
       d.MonthName,
       c.Region,
       p.Category,
       SUM(f.SalesAmount) AS SalesAmount,
       SUM(f.MarginAmount) AS MarginAmount
FROM
       dbo.FactSales f
JOIN
              dbo.DimDate d
              ON d.DateKey = f.OrderDateKey
JOIN
              dbo.DimCustomer c
              ON c.CustomerKey = f.CustomerKey
JOIN
              dbo.DimProduct p
              ON p.ProductKey = f.ProductKey
GROUP BY
       d.Year,
       d.Month,
       --** SSC-FDM-TS0191 - TEXT COMPARISON ON A COLUMN DECLARED WITHOUT COLLATE IS CASE AND ACCENT SENSITIVE IN SNOWFLAKE; RESULTS DIFFER IF THE SOURCE DEFAULT COLLATION IS CASE OR ACCENT INSENSITIVE **
       d.MonthName,
       --** SSC-FDM-TS0191 - TEXT COMPARISON ON A COLUMN DECLARED WITHOUT COLLATE IS CASE AND ACCENT SENSITIVE IN SNOWFLAKE; RESULTS DIFFER IF THE SOURCE DEFAULT COLLATION IS CASE OR ACCENT INSENSITIVE **
       c.Region,
       --** SSC-FDM-TS0191 - TEXT COMPARISON ON A COLUMN DECLARED WITHOUT COLLATE IS CASE AND ACCENT SENSITIVE IN SNOWFLAKE; RESULTS DIFFER IF THE SOURCE DEFAULT COLLATION IS CASE OR ACCENT INSENSITIVE **
       p.Category;