USE ${salesdw};
GO

CREATE OR ALTER PROCEDURE etl.usp_LogStep @RunID UNIQUEIDENTIFIER, @StepName NVARCHAR(100), @Status NVARCHAR(20), @RowsAffected INT = NULL, @ErrorMessage NVARCHAR(4000) = NULL
AS
  BEGIN
    SET NOCOUNT ON;
    INSERT etl.LoadLog (RunID, StepName, Status, RowsAffected, ErrorMessage) VALUES (@RunID, @StepName, @Status, @RowsAffected, @ErrorMessage);
  END;