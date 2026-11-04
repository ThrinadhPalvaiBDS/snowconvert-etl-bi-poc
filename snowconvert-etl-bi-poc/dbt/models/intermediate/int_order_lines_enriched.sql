-- SSIS: Lookup DimCustomer + Lookup DimProduct + Derived Column measures.
-- Point-in-time join to the SCD2 customer (SSIS always took IsCurrent=1, which mis-attributes
-- history after a customer moves). Document this as an intended behaviour change.
with lines as (
    select * from {{ ref('stg_order_lines') }}
),
orders as (
    select * from {{ ref('stg_orders') }}
),
cust as (
    select customer_key, customer_id, valid_from, valid_to from {{ ref('dim_customer') }}
),
prod as (
    select product_key, product_id, standard_cost from {{ ref('dim_product') }}
)
select
    l.sales_order_detail_id,
    o.order_number,
    o.order_date,
    {{ date_key('o.order_date') }}                                      as order_date_key,
    coalesce(c.customer_key, {{ var('unknown_member_key') }})           as customer_key,
    coalesce(p.product_key,  {{ var('unknown_member_key') }})           as product_key,
    o.channel,
    o.order_status,
    l.quantity,
    l.unit_price,
    round(l.quantity * l.unit_price * l.unit_price_discount, 4)         as discount_amount,
    round(l.quantity * l.unit_price * (1 - l.unit_price_discount), 4)   as sales_amount,
    round(l.quantity * coalesce(p.standard_cost, 0), 4)                 as cost_amount,
    c.customer_key is null                                              as is_customer_missing,
    p.product_key  is null                                              as is_product_missing,
    greatest(l.source_modified_at, o.source_modified_at)                as source_modified_at,
    greatest(l.cdc_loaded_at, o.cdc_loaded_at)                          as changed_at
from lines l
join orders o
  on o.sales_order_id = l.sales_order_id
left join cust c
  on c.customer_id = o.customer_id
 and o.order_ts >= c.valid_from
 and o.order_ts <  coalesce(c.valid_to, '9999-12-31'::timestamp_ntz)
left join prod p
  on p.product_id = l.product_id
