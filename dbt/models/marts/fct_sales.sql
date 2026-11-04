-- Replaces SSIS DFT - FactSales (fast-load OLE DB Destination) with a CDC-driven incremental MERGE.
--  * Inserts/updates: only lines whose line OR header changed since the last run (changed_at).
--  * Deletes: lines deleted in SQL Server, lines of deleted orders, and lines that became
--    invalid (now rejected) are removed by the post-hook.
-- depends_on: {{ ref('stg_order_lines_cdc') }}
-- depends_on: {{ ref('stg_orders_cdc') }}
{{ config(
    materialized='incremental',
    unique_key='sales_order_detail_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    cluster_by=['order_date_key'],
    post_hook=[
      "delete from {{ this }} where sales_order_detail_id in (
           select sales_order_detail_id from {{ ref('stg_order_lines_cdc') }}
           where is_deleted or quantity <= 0 or unit_price < 0
           union
           select l.sales_order_detail_id
           from {{ ref('stg_order_lines_cdc') }} l
           join {{ ref('stg_orders_cdc') }} o on o.sales_order_id = l.sales_order_id
           where o.is_deleted)"
    ]
) }}

with src as (
    select * from {{ ref('int_order_lines_enriched') }}
    where quantity > 0
      and unit_price >= 0
      and not is_product_missing
    {% if is_incremental() %}
      and changed_at >= (
            select dateadd(minute, -10, coalesce(max(changed_at), '1900-01-01'::timestamp_ltz))
            from {{ this }})
    {% endif %}
)
select
    sales_order_detail_id,
    order_number,
    order_date_key,
    customer_key,
    product_key,
    channel,
    order_status,
    quantity,
    unit_price,
    discount_amount,
    sales_amount,
    cost_amount,
    sales_amount - cost_amount        as margin_amount,
    source_modified_at,
    changed_at,
    {{ audit_columns() }}
from src
