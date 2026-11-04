-- CDC current-state table: one row per sales_order_id, latest change wins (ordered by LSN, seqval).
-- Deletes are kept as is_deleted = true so downstream models can remove them.
-- Processes only change rows landed since the last run (small overlap; merge is idempotent).
{{ config(materialized='incremental', unique_key='sales_order_id', incremental_strategy='merge',
          on_schema_change='append_new_columns') }}
with changes as (
    select * from {{ source('raw', 'salesorderheader_ct') }}
    {% if is_incremental() %}
    where _loaded_at >= (select dateadd(minute, -10, coalesce(max(cdc_loaded_at), '1900-01-01'::timestamp_ltz)) from {{ this }})
    {% endif %}
),
latest as (
    select *
    from changes
    qualify row_number() over (partition by salesorderid order by _cdc_lsn desc, _cdc_seqval desc, _loaded_at desc) = 1
)
select
    salesorderid::integer          as sales_order_id,
    trim(ordernumber)              as order_number,
    customerid::integer            as customer_id,
    orderdate                      as order_ts,
    cast(orderdate as date)        as order_date,
    case status
        when 1 then 'Open'
        when 2 then 'Shipped'
        when 3 then 'Cancelled'
        else 'Unknown'
    end                            as order_status,
    trim(channel)                  as channel,
    upper(currencycode)            as currency_code,
    modifieddate                   as source_modified_at,
    _cdc_op = 'D'                   as is_deleted,
    _cdc_op                         as cdc_operation,
    _cdc_lsn                        as cdc_lsn,
    _cdc_commit_ts                  as cdc_commit_ts,
    _loaded_at                      as cdc_loaded_at
from latest
{% if is_incremental() %}
-- never let an older change overwrite a newer one already applied
where not exists (select 1 from {{ this }} t where t.sales_order_id = latest.salesorderid::integer and t.cdc_lsn > latest._cdc_lsn)
{% endif %}
