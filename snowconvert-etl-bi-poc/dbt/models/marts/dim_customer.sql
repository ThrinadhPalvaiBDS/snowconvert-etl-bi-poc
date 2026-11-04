-- Replaces SSIS DFT - DimCustomer (Lookup CountryRegion + SCD2) with snapshot + seed lookup.
-- Type-1 attributes (name, email) are taken from the current staging row for all versions,
-- matching the legacy SCD wizard's "changing attribute" behaviour.
with versions as (
    select
        customer_id, city, segment, country_code,
        dbt_scd_id, dbt_valid_from, dbt_valid_to,
        row_number() over (partition by customer_id order by dbt_valid_from) as version_no
    from {{ ref('snap_customer') }}
),
cur as (
    select * from {{ ref('stg_customers') }}
),
geo as (
    select * from {{ ref('country_region') }}
),
dim as (
    select
        abs(hash(v.dbt_scd_id)) % 2147483647                      as customer_key,
        v.customer_id,
        c.customer_code,
        c.customer_name,
        c.email,
        v.city,
        coalesce(g.country_name, 'Unknown')                        as country,
        coalesce(g.region, 'Unknown')                              as region,
        v.segment,
        iff(v.version_no = 1, '1900-01-01'::timestamp_ntz, v.dbt_valid_from) as valid_from,
        v.dbt_valid_to                                             as valid_to,
        v.dbt_valid_to is null                                     as is_current
    from versions v
    join cur c on c.customer_id = v.customer_id
    left join geo g on g.country_code = v.country_code
)
select *, {{ audit_columns() }} from dim
union all
-- Unknown member (SSIS used -1 for lookup no-match rows)
select {{ var('unknown_member_key') }}, -1, 'UNKNOWN', 'Unknown', null, 'Unknown', 'Unknown', 'Unknown', 'Unknown',
       '1900-01-01'::timestamp_ntz, null, true, {{ audit_columns() }}
