USE DATABASE <%salesdw%>;

--** SSC-FDM-0007 - MISSING DEPENDENT OBJECTS "SalesOLTP.dbo.Customer", "SalesDW.dbo.DimCustomer" **
CREATE OR REPLACE PROCEDURE etl.usp_Load_DimCustomer (ROWSAFFECTED OUT INT)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
EXECUTE AS CALLER
AS
$$
    DECLARE
        EXPIRED INT;
        INSERTED INT;
        TYPE1 INT;
    BEGIN
--        --** SSC-FDM-TS0029 - SET NOCOUNT STATEMENT IS COMMENTED OUT, WHICH IS NOT APPLICABLE IN SNOWFLAKE. **
--        SET NOCOUNT ON;
        CREATE OR REPLACE TEMPORARY TABLE <%salesdw%>.PUBLIC.T_src AS
            SELECT
                c.CustomerID,
                LTRIM(RTRIM(c.CustomerCode))                                   AS CustomerCode,
                LTRIM(RTRIM(c.FirstName)) || ' ' || LTRIM(RTRIM(c.LastName))     AS CustomerName,
                LOWER(NULLIF(LTRIM(RTRIM(c.Email)), ''))                       AS Email,
                NVL(NULLIF(LTRIM(RTRIM(c.City)), ''), 'Unknown')           AS City,
                NVL(cr.Country, 'Unknown')                                  AS Country,
                NVL(cr.Region, 'Unknown')                                  AS Region,
                NVL(NULLIF(LTRIM(RTRIM(c.Segment)), ''), 'Unknown')        AS Segment,
                c.ModifiedDate
        FROM
                <%salesoltp%>.dbo.Customer c
        LEFT JOIN
                    <%salesdw%>.etl.CountryRegion cr
               ON
                    --** SSC-FDM-TS0191 - TEXT COMPARISON ON A COLUMN DECLARED WITHOUT COLLATE IS CASE AND ACCENT SENSITIVE IN SNOWFLAKE; RESULTS DIFFER IF THE SOURCE DEFAULT COLLATION IS CASE OR ACCENT INSENSITIVE **
                    cr.CountryCode = UPPER(NULLIF(LTRIM(RTRIM(c.CountryCode)), ''));

        BEGIN TRANSACTION;

        -- Type 2: close the current row when a historical attribute changed
        UPDATE <%salesdw%>.dbo.DimCustomer d
        SET
                RowEndDate = s.ModifiedDate,
                IsCurrent = 0
        FROM
                <%salesdw%>.PUBLIC.T_src s
        WHERE
                s.CustomerID = d.CustomerID
                AND (d.IsCurrent = 1
          AND (NVL(d.City, '')    <> s.City
            OR NVL(d.Country, '') <> s.Country
            OR NVL(d.Region, '')  <> s.Region
            OR NVL(d.Segment, '') <> s.Segment));
        EXPIRED := SQLROWCOUNT;

        -- New customers, and new versions of the ones just closed
        INSERT INTO <%salesdw%>.dbo.DimCustomer (CustomerID, CustomerCode, CustomerName, Email, City, Country, Region, Segment, RowStartDate, RowEndDate, IsCurrent)
        SELECT
        s.CustomerID,
        s.CustomerCode,
        s.CustomerName,
        s.Email,
        s.City,
        s.Country,
        s.Region,
        s.Segment,
        s.ModifiedDate, NULL, 1
        FROM
        <%salesdw%>.PUBLIC.T_src s
        WHERE  NOT EXISTS (SELECT 1 FROM
                    <%salesdw%>.dbo.DimCustomer d
                WHERE
                    d.CustomerID = s.CustomerID
                    AND d.IsCurrent = 1);
        INSERTED := SQLROWCOUNT;

        -- Type 1: overwrite on the current row
        UPDATE <%salesdw%>.dbo.DimCustomer d
        SET
                CustomerCode = s.CustomerCode,
                CustomerName = s.CustomerName,
                Email = s.Email
        FROM
                <%salesdw%>.PUBLIC.T_src s
        WHERE
                s.CustomerID = d.CustomerID
                AND (d.IsCurrent = 1
          AND (d.CustomerCode <> s.CustomerCode
            OR d.CustomerName <> s.CustomerName
            OR NVL(d.Email, '') <> NVL(s.Email, '')));
        TYPE1 := SQLROWCOUNT;
        COMMIT;
        ROWSAFFECTED := :EXPIRED + :INSERTED + :TYPE1;
        DROP TABLE IF EXISTS <%salesdw%>.PUBLIC.T_src;
    END;
$$;