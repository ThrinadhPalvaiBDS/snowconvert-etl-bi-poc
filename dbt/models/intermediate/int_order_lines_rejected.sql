-- SSIS: Conditional Split error output + Lookup no-match output -> dbo.FactSales_Error
{{ config(materialized='table') }}
select
    sales_order_detail_id,
    case
        when quantity <= 0       then 'Non-positive quantity'
        when unit_price < 0      then 'Negative unit price'
        when is_product_missing  then 'Product lookup no match'
        when is_customer_missing then 'Customer lookup no match'
    end                                   as error_reason,
    {{ audit_columns() }}
from {{ ref('int_order_lines_enriched') }}
where quantity <= 0
   or unit_price < 0
   or is_product_missing
   or is_customer_missing
