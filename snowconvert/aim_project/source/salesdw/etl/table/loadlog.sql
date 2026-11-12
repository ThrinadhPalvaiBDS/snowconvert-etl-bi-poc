USE SalesDW;

GO

IF OBJECT_ID('etl.LoadLog') IS NULL
CREATE TABLE etl.LoadLog (
    LoadLogID     INT IDENTITY(1,1) PRIMARY KEY,
    RunID         UNIQUEIDENTIFIER NOT NULL,
    StepName      NVARCHAR(100)    NOT NULL,
    Status        NVARCHAR(20)     NOT NULL,   -- Started / Succeeded / Failed
    RowsAffected  INT              NULL,
    ErrorMessage  NVARCHAR(4000)   NULL,
    LoggedAt      DATETIME2(3)     NOT NULL DEFAULT SYSDATETIME()
);
