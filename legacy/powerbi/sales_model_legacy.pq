// Legacy Power Query (M) inside "Sales Performance.pbix" - SQL Server connector.
// SnowConvert AI rewrites these to the Snowflake connector during repointing.
let
    Source      = Sql.Database("legacy-sql01", "SalesDW"),
    FactSales   = Source{[Schema = "dbo", Item = "FactSales"]}[Data]
in
    FactSales

// Embedded-SQL query (second table in the model)
let
    Source = Sql.Database("legacy-sql01", "SalesDW",
        [Query = "SELECT TOP 100 PERCENT [Year],[Month],MonthName,Region,Category,SalesAmount,MarginAmount
                  FROM dbo.vw_SalesByMonth WITH (NOLOCK) ORDER BY [Year],[Month]"])
in
    Source
