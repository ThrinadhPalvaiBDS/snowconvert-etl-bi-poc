USE ${salesdw};
GO

CREATE OR ALTER PROCEDURE etl.usp_Load_DimCustomer @RowsAffected INT OUTPUT
AS
  BEGIN
    SET NOCOUNT ON;
    DECLARE
      @expired INT,
      @inserted INT,
      @type1 INT;
    SELECT
      c.CustomerID,
      LTRIM(RTRIM(c.CustomerCode)) AS CustomerCode,
      LTRIM(RTRIM(c.FirstName)) + N' ' + LTRIM(RTRIM(c.LastName)) AS CustomerName,
      LOWER(NULLIF(LTRIM(RTRIM(c.Email)), N'')) AS Email,
      ISNULL(NULLIF(LTRIM(RTRIM(c.City)), N''), N'Unknown') AS City,
      ISNULL(cr.Country, N'Unknown') AS Country,
      ISNULL(cr.Region, N'Unknown') AS Region,
      ISNULL(NULLIF(LTRIM(RTRIM(c.Segment)), N''), N'Unknown') AS Segment,
      c.ModifiedDate
    INTO
      #src
    FROM
      ${salesoltp}.dbo.Customer c WITH(NOLOCK)
      LEFT JOIN
        etl.CountryRegion cr
        ON cr.CountryCode = UPPER(NULLIF(LTRIM(RTRIM(c.CountryCode)), ''));
    BEGIN TRAN;
    -- Type 2: close the current row when a historical attribute changed
    UPDATE d
      SET
        RowEndDate = s.ModifiedDate,
        IsCurrent = 0
      FROM
        dbo.DimCustomer d
        JOIN
          #src s
          ON s.CustomerID = d.CustomerID
      WHERE
        d.IsCurrent = 1
        AND (ISNULL(d.City, N'') <> s.City
        OR ISNULL(d.Country, N'') <> s.Country
        OR ISNULL(d.Region, N'') <> s.Region
        OR ISNULL(d.Segment, N'') <> s.Segment);
    SET @expired = @@ROWCOUNT;
    -- New customers, and new versions of the ones just closed
    INSERT dbo.DimCustomer (CustomerID, CustomerCode, CustomerName, Email, City, Country, Region, Segment, RowStartDate, RowEndDate, IsCurrent)
    SELECT
      s.CustomerID,
      s.CustomerCode,
      s.CustomerName,
      s.Email,
      s.City,
      s.Country,
      s.Region,
      s.Segment,
      s.ModifiedDate,
      NULL,
      1
    FROM
      #src s
    WHERE
      NOT EXISTS (
        SELECT
          1
        FROM
          dbo.DimCustomer d
        WHERE
          d.CustomerID = s.CustomerID
          AND d.IsCurrent = 1
      );
    SET @inserted = @@ROWCOUNT;
    -- Type 1: overwrite on the current row
    UPDATE d
      SET
        CustomerCode = s.CustomerCode,
        CustomerName = s.CustomerName,
        Email = s.Email
      FROM
        dbo.DimCustomer d
        JOIN
          #src s
          ON s.CustomerID = d.CustomerID
      WHERE
        d.IsCurrent = 1
        AND (d.CustomerCode <> s.CustomerCode
        OR d.CustomerName <> s.CustomerName
        OR ISNULL(d.Email, N'') <> ISNULL(s.Email, N''));
    SET @type1 = @@ROWCOUNT;
    COMMIT;
    SET @RowsAffected = @expired + @inserted + @type1;
    DROP TABLE #src;
  END;