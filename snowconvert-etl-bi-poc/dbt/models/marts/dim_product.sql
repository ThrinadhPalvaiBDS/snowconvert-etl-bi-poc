-- Replaces SSIS DFT - DimProduct (SCD Type 1 = overwrite) -> simple rebuilt table
select
    product_id                  as product_key,      -- stable natural key keeps report joins stable
    product_id,
    sku,
    product_name,
    category,
    sub_category,
    list_price,
    standard_cost,
    is_active,
    {{ audit_columns() }}
from {{ ref('stg_products') }}
union all
select {{ var('unknown_member_key') }}, -1, 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown', 0, 0, false, {{ audit_columns() }}
