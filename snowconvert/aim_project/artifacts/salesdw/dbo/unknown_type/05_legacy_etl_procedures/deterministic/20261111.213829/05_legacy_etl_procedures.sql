USE DATABASE <%salesdw%>;

BEGIN
    IF (SCHEMA_ID('etl') !!!RESOLVE EWI!!! /*** SSC-EWI-0073 - PENDING FUNCTIONAL EQUIVALENCE REVIEW FOR 'SCHEMA_ID' NODE ***/!!! IS NULL) THEN
        !!!RESOLVE EWI!!! /*** SSC-EWI-0073 - PENDING FUNCTIONAL EQUIVALENCE REVIEW FOR 'CREATE SCHEMA' NODE ***/!!!
        EXECUTE IMMEDIATE '
CREATE SCHEMA IF NOT EXISTS etl ';
    END IF;
    IF (NOT EXISTS (SELECT 1 FROM
            etl.Watermark
        WHERE
            TableName = 'FactSales'
    )) THEN
        INSERT INTO etl.Watermark (TableName, LoadDate) VALUES ('FactSales', '1900-01-01');
            END IF;
            MERGE INTO etl.CountryRegion AS t
            USING (VALUES ('IN', 'India', 'APAC'),
                         ('SG', 'Singapore', 'APAC'),
                         ('AU', 'Australia', 'APAC'),
                         ('JP', 'Japan', 'APAC'),
                         ('US', 'United States', 'NA'),
                         ('CA', 'Canada', 'NA'),
                         ('GB', 'United Kingdom', 'EMEA'),
                         ('DE', 'Germany', 'EMEA'),
                         ('FR', 'France', 'EMEA'),
                         ('AE', 'United Arab Emirates', 'EMEA'),
                         ('BR', 'Brazil', 'LATAM'),
                         ('MX', 'Mexico', 'LATAM')) AS s (
        CountryCode,
        Country,
        Region
            )
            ON t.CountryCode = s.CountryCode
            WHEN MATCHED THEN
        UPDATE SET
            Country = s.Country,
            Region = s.Region
            WHEN NOT MATCHED THEN
        INSERT (CountryCode, Country, Region) VALUES (s.CountryCode, s.Country, s.Region);
            --** SSC-FDM-0007 - MISSING DEPENDENT OBJECT "SalesDW.dbo.DimCustomer" **
            IF (NOT EXISTS (SELECT 1 FROM
            dbo.DimCustomer
        WHERE
            CustomerKey = -1)) THEN
        BEGIN
--            --** SSC-FDM-TS0047 - SET IDENTITY_INSERT COMMENTED OUT. SNOWFLAKE ALLOWS EXPLICIT INSERTS INTO IDENTITY/AUTOINCREMENT COLUMNS BY DEFAULT, BUT THE SEQUENCE COUNTER DOES NOT ADJUST TO EXPLICITLY INSERTED VALUES. **
--            SET IDENTITY_INSERT dbo.DimCustomer ON;
            INSERT INTO dbo.DimCustomer (CustomerKey, CustomerID, CustomerCode, CustomerName, Email, City, Country, Region, Segment, RowStartDate, RowEndDate, IsCurrent) VALUES (-1, -1, 'UNKNOWN', 'Unknown', NULL, 'Unknown', 'Unknown', 'Unknown', 'Unknown',
                    '1900-01-01', NULL, 1);
--            --** SSC-FDM-TS0047 - SET IDENTITY_INSERT COMMENTED OUT. SNOWFLAKE DOES NOT SUPPORT RESTRICTING EXPLICIT INSERTS INTO IDENTITY/AUTOINCREMENT COLUMNS. **
--            SET IDENTITY_INSERT dbo.DimCustomer OFF;
        END;
            END IF;
END;