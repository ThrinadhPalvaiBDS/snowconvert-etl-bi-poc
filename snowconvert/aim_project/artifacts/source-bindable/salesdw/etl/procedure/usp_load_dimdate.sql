USE ${salesdw};
GO

CREATE OR ALTER PROCEDURE etl.usp_Load_DimDate @StartDate DATE, @EndDate DATE, @RowsAdded INT OUTPUT
AS
  BEGIN
    SET NOCOUNT ON;
    SET DATEFIRST 7; -- Sunday = 1, so DayOfWeek is stable

    DECLARE
      @d DATE = @StartDate;
    SET @RowsAdded = 0;
    WHILE @d <= @EndDate
    BEGIN
      IF NOT EXISTS (
        SELECT
          1
        FROM
          dbo.DimDate
        WHERE
          DateKey = CONVERT(INT, CONVERT(CHAR(8), @d, 112))
      )
        BEGIN
          INSERT dbo.DimDate (DateKey, [Date], [Year], [Quarter], [Month], MonthName, DayOfWeek, IsWeekend) VALUES (CONVERT(INT, CONVERT(CHAR(8), @d, 112)), @d, YEAR(@d), DATEPART(QUARTER, @d), MONTH(@d), DATENAME(MONTH, @d), DATEPART(WEEKDAY, @d), CASE
            WHEN DATEPART(WEEKDAY, @d) IN (1, 7)
              THEN 1
            ELSE 0
          END);
          SET @RowsAdded += 1;
        END;
      SET @d = DATEADD(DAY, 1, @d);
    END;
  END;