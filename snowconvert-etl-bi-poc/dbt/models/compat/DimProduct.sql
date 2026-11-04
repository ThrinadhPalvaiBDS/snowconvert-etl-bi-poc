{{ config(alias='DIMPRODUCT') }}
select
    product_key     as productkey,
    product_id      as productid,
    sku             as sku,
    product_name    as productname,
    category        as category,
    sub_category    as subcategory,
    list_price      as listprice,
    standard_cost   as standardcost,
    is_active       as isactive
from {{ ref('dim_product') }}
