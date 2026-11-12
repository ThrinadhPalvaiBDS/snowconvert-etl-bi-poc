USE DATABASE <%salesdw%>;

--** SSC-FDM-0007 - MISSING DEPENDENT OBJECTS "SalesDW.dbo.DimProduct", "SalesOLTP.dbo.Product" **
CREATE OR REPLACE PROCEDURE etl.usp_Load_DimProduct (ROWSAFFECTED OUT INT)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
EXECUTE AS CALLER
AS
$$
    BEGIN
--        --** SSC-FDM-TS0029 - SET NOCOUNT STATEMENT IS COMMENTED OUT, WHICH IS NOT APPLICABLE IN SNOWFLAKE. **
--        SET NOCOUNT ON;
        MERGE INTO <%salesdw%>.dbo.DimProduct AS t
        USING (
                   SELECT
                       ProductID,
                       LTRIM(RTRIM(SKU))                                        AS SKU,
                       LTRIM(RTRIM(ProductName))                                AS ProductName,
                       NVL(NULLIF(LTRIM(RTRIM(Category)), ''), 'Unknown')    AS Category,
                       NVL(NULLIF(LTRIM(RTRIM(SubCategory)), ''), 'Unknown') AS SubCategory,
                          CAST(ListPrice AS DECIMAL(19, 4))                      AS ListPrice,
                          CAST(StandardCost AS DECIMAL(19, 4))                      AS StandardCost,
                       IsActive
                   FROM
                       <%salesoltp%>.dbo.Product
               ) AS s
        ON t.ProductID = s.ProductID
        WHEN MATCHED AND (t.SKU <> s.SKU
        OR t.ProductName <> s.ProductName
        OR t.Category <> s.Category
                                 OR t.SubCategory <> s.SubCategory
        OR t.ListPrice <> s.ListPrice
                                 OR t.StandardCost <> s.StandardCost
        OR t.IsActive <> s.IsActive) THEN
                   UPDATE SET
                       SKU = s.SKU,
                       ProductName = s.ProductName,
                       Category = s.Category,
                       SubCategory = s.SubCategory,
                       ListPrice = s.ListPrice,
                       StandardCost = s.StandardCost,
                       IsActive = s.IsActive
        WHEN NOT MATCHED THEN
                   INSERT (ProductID, SKU, ProductName, Category, SubCategory, ListPrice, StandardCost, IsActive)
                        VALUES (s.ProductID, s.SKU, s.ProductName, s.Category, s.SubCategory, s.ListPrice, s.StandardCost, s.IsActive);
        ROWSAFFECTED := SQLROWCOUNT;
    END;
$$;