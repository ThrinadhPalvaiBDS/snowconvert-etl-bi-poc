// Illustrative shape of a repointed query (what to expect when reviewing SnowConvert's
// repointing_output). Exact generated code depends on the SnowConvert AI version.
// Parameters (SnowflakeServer, SnowflakeWarehouse, SnowflakeDatabase) are what
// powerbi/pbi_cutover.py sets per environment through the REST API.
let
    Source    = Snowflake.Databases(SnowflakeServer, SnowflakeWarehouse, [Implementation = "2.0"]),
    Db        = Source{[Name = SnowflakeDatabase, Kind = "Database"]}[Data],
    Dbo       = Db{[Name = "DBO", Kind = "Schema"]}[Data],
    FactSales = Dbo{[Name = "FACTSALES", Kind = "Table"]}[Data],
    // column-case mapping so existing visuals/measures keep working without a rebuild
    Renamed   = Table.RenameColumns(FactSales, {
        {"SALESORDERDETAILID", "SalesOrderDetailID"}, {"ORDERNUMBER", "OrderNumber"},
        {"ORDERDATEKEY", "OrderDateKey"}, {"CUSTOMERKEY", "CustomerKey"}, {"PRODUCTKEY", "ProductKey"},
        {"CHANNEL", "Channel"}, {"ORDERSTATUS", "OrderStatus"}, {"QUANTITY", "Quantity"},
        {"UNITPRICE", "UnitPrice"}, {"DISCOUNTAMOUNT", "DiscountAmount"}, {"SALESAMOUNT", "SalesAmount"},
        {"COSTAMOUNT", "CostAmount"}, {"MARGINAMOUNT", "MarginAmount"}, {"LOADDATE", "LoadDate"}})
in
    Renamed

// Embedded SQL case: SnowConvert extracts the T-SQL, migrates it (TOP 100 PERCENT / NOLOCK
// removed, brackets -> unquoted) and re-inserts it via Value.NativeQuery.
let
    Source = Value.NativeQuery(
        Snowflake.Databases(SnowflakeServer, SnowflakeWarehouse){[Name = SnowflakeDatabase]}[Data],
        "SELECT YEAR, MONTH, MONTHNAME, REGION, CATEGORY, SALESAMOUNT, MARGINAMOUNT
         FROM DBO.VW_SALESBYMONTH ORDER BY YEAR, MONTH",
        null, [EnableFolding = true])
in
    Source
