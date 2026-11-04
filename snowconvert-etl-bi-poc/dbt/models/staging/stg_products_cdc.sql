-- CDC current-state table: one row per product_id, latest change wins (ordered by LSN, seqval).
-- Deletes are kept as is_deleted = true so downstream models can remove them.
-- Processes only change rows landed since the last run (small overlap; merge is idempotent).
{{ config(materialized='incremental', unique_key='product_id', incremental_strategy='merge',
          on_schema_change='append_new_columns') }}
with changes as (
    select * from {{ source('raw', 'product_ct') }}
    {% if is_incremental() %}
    where _loaded_at >= (select dateadd(minute, -10, coalesce(max(cdc_loaded_at), '1900-01-01'::timestamp_ltz)) from {{ this }})
    {% endif %}
),
latest as (
    select *
    from changes
    qualify row_number() over (partition by productid order by _cdc_lsn desc, _cdc_seqval desc, _loaded_at desc) = 1
)
select
    productid::integer                              as product_id,
    trim(sku)                                       as sku,
    trim(productname)                               as product_name,
    {{ ssis_default_unknown('category') }}          as category,
    {{ ssis_default_unknown('subcategory') }}       as sub_category,
    {{ money_to_decimal('listprice') }}             as list_price,
    {{ money_to_decimal('standardcost') }}          as standard_cost,
    coalesce(isactive, true)                        as is_active,
    modifieddate                                    as source_modified_at,
    _cdc_op = 'D'                   as is_deleted,
    _cdc_op                         as cdc_operation,
    _cdc_lsn                        as cdc_lsn,
    _cdc_commit_ts                  as cdc_commit_ts,
    _loaded_at                      as cdc_loaded_at
from latest
{% if is_incremental() %}
-- never let an older change overwrite a newer one already applied
where not exists (select 1 from {{ this }} t where t.product_id = latest.productid::integer and t.cdc_lsn > latest._cdc_lsn)
{% endif %}
