{{ config(alias='FACTSALES_ERROR') }}
select
    sales_order_detail_id         as salesorderdetailid,
    error_reason                  as errorreason,
    _dbt_loaded_at::timestamp_ntz as loaddate
from {{ ref('int_order_lines_rejected') }}
