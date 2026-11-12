USE defaultdb

GO

CREATE TABLE dbo.DimDate (
    DateKey         INT PRIMARY KEY,         -- yyyymmdd
    [Date]          DATE NOT NULL,
    [Year]          SMALLINT NOT NULL,
    [Quarter]       TINYINT NOT NULL,
    [Month]         TINYINT NOT NULL,
    MonthName       NVARCHAR(12) NOT NULL,
    DayOfWeek       TINYINT NOT NULL,
    IsWeekend       BIT NOT NULL
);
