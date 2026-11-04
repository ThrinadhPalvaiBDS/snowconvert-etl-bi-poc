# Legacy SSIS package: Load_SalesDW.dtsx (as-is design)

Control flow
1. `SQL - Get Watermark` (Execute SQL Task) → `SELECT MAX(LoadDate) FROM etl.Watermark` into `User::LastLoad`
2. `SEQ - Dimensions` (Sequence Container)
   * `DFT - DimProduct`  : OLE DB Source → Derived Column (ISNULL Category → 'Unknown') → SCD (Type 1) → OLE DB Destination
   * `DFT - DimCustomer` : OLE DB Source → Derived Column (FirstName + " " + LastName) → Lookup (CountryRegion) → SCD Wizard (Type 2 on City, Segment) → OLE DB Destination
3. `DFT - FactSales`
   * OLE DB Source (`SalesOrderHeader JOIN SalesOrderDetail WHERE ModifiedDate > ?`)
   * Data Conversion (MONEY → DECIMAL(19,4))
   * Derived Column (SalesAmount, DiscountAmount, OrderStatus CASE)
   * Lookup DimCustomer (IsCurrent = 1) / Lookup DimProduct — no-match → error path
   * Conditional Split: `Quantity <= 0 || UnitPrice < 0` → `FactSales_Error`
   * OLE DB Destination (fast load) → `dbo.FactSales`
4. `SQL - Update Watermark` (Execute SQL Task)
5. `Send Mail - Success` / OnError event handler → `Send Mail - Failure`

Pain points that justify *replatforming* rather than lift-and-shift
* Row-by-row SCD component, slow and lock-heavy
* Business logic hidden in package XML; no tests, no lineage, no code review
* Lookup caches sized by hand; failures surface only through email
