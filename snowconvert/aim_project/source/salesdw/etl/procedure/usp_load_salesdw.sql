USE SalesDW;

GO

CREATE OR ALTER PROCEDURE etl.usp_Load_SalesDW
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunID UNIQUEIDENTIFIER = NEWID();
    DECLARE @Step NVARCHAR(100), @Rows INT, @Rejected INT;
    DECLARE @MinDate DATE, @MaxDate DATE;

    BEGIN TRY
        SET @Step = N'Package';
        EXEC etl.usp_LogStep @RunID, @Step, N'Started';

        -- Make sure every order date has a DimDate row
        SET @Step = N'Load DimDate';
        SELECT @MinDate = CAST(MIN(OrderDate) AS DATE), @MaxDate = CAST(MAX(OrderDate) AS DATE)
        FROM SalesOLTP.dbo.SalesOrderHeader WITH (NOLOCK);
        IF @MinDate IS NOT NULL
        BEGIN
            EXEC etl.usp_Load_DimDate @MinDate, @MaxDate, @Rows OUTPUT;
            EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;
        END;

        -- Sequence container: dimensions
        SET @Step = N'DFT - DimProduct';
        EXEC etl.usp_Load_DimProduct @Rows OUTPUT;
        EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;

        SET @Step = N'DFT - DimCustomer';
        EXEC etl.usp_Load_DimCustomer @Rows OUTPUT;
        EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;

        -- Fact + watermark
        SET @Step = N'DFT - FactSales';
        EXEC etl.usp_Load_FactSales @Rows OUTPUT, @Rejected OUTPUT;
        EXEC etl.usp_LogStep @RunID, @Step, N'Succeeded', @Rows;
        EXEC etl.usp_LogStep @RunID, N'FactSales rejected rows', N'Succeeded', @Rejected;

        EXEC etl.usp_LogStep @RunID, N'Package', N'Succeeded';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        DECLARE @Err NVARCHAR(4000) =
            CONCAT(N'Step "', @Step, N'" failed: ', ERROR_MESSAGE(),
                   N' (error ', ERROR_NUMBER(), N', line ', ERROR_LINE(), N')');
        EXEC etl.usp_LogStep @RunID, @Step, N'Failed', NULL, @Err;

        -- OnError event handler: Send Mail Task
        DECLARE @Subject NVARCHAR(255) = CONCAT(N'Load_SalesDW FAILED at ', FORMAT(SYSDATETIME(), 'yyyy-MM-dd HH:mm'));
        EXEC msdb.dbo.sp_send_dbmail
             @profile_name = N'DataOps',
             @recipients   = N'thrinadhp@booleandata.ai',
             @subject      = @Subject,
             @body         = @Err;

        THROW;
    END CATCH;
END;
