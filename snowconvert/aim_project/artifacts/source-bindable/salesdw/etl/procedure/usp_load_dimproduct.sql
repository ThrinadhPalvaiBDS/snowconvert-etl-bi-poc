USE ${salesdw};
GO

CREATE OR ALTER PROCEDURE etl.usp_Load_DimProduct @RowsAffected INT OUTPUT
AS
  BEGIN
    SET NOCOUNT ON;
    MERGE dbo.DimProduct AS t
    USING (
      SELECT
        ProductID,
        LTRIM(RTRIM(SKU)) AS SKU,
        LTRIM(RTRIM(ProductName)) AS ProductName,
        ISNULL(NULLIF(LTRIM(RTRIM(Category)), N''), N'Unknown') AS Category,
        ISNULL(NULLIF(LTRIM(RTRIM(SubCategory)), N''), N'Unknown') AS SubCategory,
        CAST(ListPrice AS DECIMAL(19, 4)) AS ListPrice,
        CAST(StandardCost AS DECIMAL(19, 4)) AS StandardCost,
        IsActive
      FROM
        ${salesoltp}.dbo.Product WITH(NOLOCK)
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
    WHEN NOT MATCHED BY TARGET THEN
      INSERT (ProductID, SKU, ProductName, Category, SubCategory, ListPrice, StandardCost, IsActive)
      VALUES (s.ProductID, s.SKU, s.ProductName, s.Category, s.SubCategory, s.ListPrice, s.StandardCost, s.IsActive);
    SET @RowsAffected = @@ROWCOUNT;
  END;