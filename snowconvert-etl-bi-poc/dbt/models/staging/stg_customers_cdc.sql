-- CDC current-state table: one row per customer_id, latest change wins (ordered by LSN, seqval).
-- Deletes are kept as is_deleted = true so downstream models can remove them.
-- Processes only change rows landed since the last run (small overlap; merge is idempotent).
{{ config(materialized='incremental', unique_key='customer_id', incremental_strategy='merge',
          on_schema_change='append_new_columns') }}
with changes as (
    select * from {{ source('raw', 'customer_ct') }}
    {% if is_incremental() %}
    where _loaded_at >= (select dateadd(minute, -10, coalesce(max(cdc_loaded_at), '1900-01-01'::timestamp_ltz)) from {{ this }})
    {% endif %}
),
latest as (
    select *
    from changes
    qualify row_number() over (partition by customerid order by _cdc_lsn desc, _cdc_seqval desc, _loaded_at desc) = 1
)
select
    customerid::integer                                  as customer_id,
    trim(customercode)                                   as customer_code,
    trim(firstname)                                      as first_name,
    trim(lastname)                                       as last_name,
    trim(firstname) || ' ' || trim(lastname)             as customer_name,
    lower(nullif(trim(email), ''))                       as email,
    nullif(trim(phone), '')                              as phone,
    {{ ssis_default_unknown('city') }}                   as city,
    upper(nullif(trim(countrycode), ''))                 as country_code,
    {{ ssis_default_unknown('segment') }}                as segment,
    modifieddate                                         as source_modified_at,
    _cdc_op = 'D'                   as is_deleted,
    _cdc_op                         as cdc_operation,
    _cdc_lsn                        as cdc_lsn,
    _cdc_commit_ts                  as cdc_commit_ts,
    _loaded_at                      as cdc_loaded_at
from latest
{% if is_incremental() %}
-- never let an older change overwrite a newer one already applied
where not exists (select 1 from {{ this }} t where t.customer_id = latest.customerid::integer and t.cdc_lsn > latest._cdc_lsn)
{% endif %}
