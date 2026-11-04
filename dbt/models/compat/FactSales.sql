{{ config(alias='FACTSALES') }}
select
    sales_order_detail_id   as salesorderdetailid,
    order_number            as ordernumber,
    order_date_key          as orderdatekey,
    customer_key            as customerkey,
    product_key             as productkey,
    channel                 as channel,
    order_status            as orderstatus,
    quantity                as quantity,
    unit_price              as unitprice,
    discount_amount         as discountamount,
    sales_amount            as salesamount,
    cost_amount             as costamount,
    margin_amount           as marginamount,
    _dbt_loaded_at::timestamp_ntz as loaddate
from {{ ref('fct_sales') }}
