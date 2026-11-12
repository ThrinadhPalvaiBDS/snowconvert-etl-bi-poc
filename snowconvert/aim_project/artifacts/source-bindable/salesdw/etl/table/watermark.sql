USE ${salesdw};
GO

IF OBJECT_ID('etl.Watermark') IS NULL
  CREATE TABLE etl.Watermark (
    TableName NVARCHAR(50) NOT NULL PRIMARY KEY,
    LoadDate DATETIME2(3) NOT NULL
  );