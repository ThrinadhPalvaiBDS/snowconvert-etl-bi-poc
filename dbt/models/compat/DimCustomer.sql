-- Compatibility contract for repointed Power BI: same object + columns as SnowConvert-migrated
-- dbo.DimCustomer (unquoted -> upper case). SnowConvert's repointing maps column case back for the report.
{{ config(alias='DIMCUSTOMER') }}
select
    customer_key            as customerkey,
    customer_id             as customerid,
    customer_code           as customercode,
    customer_name           as customername,
    email                   as email,
    city                    as city,
    country                 as country,
    region                  as region,
    segment                 as segment,
    valid_from              as rowstartdate,
    valid_to                as rowenddate,
    is_current              as iscurrent
from {{ ref('dim_customer') }}
