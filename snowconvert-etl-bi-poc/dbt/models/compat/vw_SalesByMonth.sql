-- Same logic as legacy dbo.vw_SalesByMonth, used by the report's embedded-SQL query
-- (SnowConvert rewrites the embedded T-SQL; this view must exist for it to resolve).
{{ config(alias='VW_SALESBYMONTH') }}
select d.year, d.month, d.monthname, c.region, p.category,
       sum(f.salesamount)  as salesamount,
       sum(f.marginamount) as marginamount
from {{ ref('FactSales') }} f
join {{ ref('DimDate') }} d     on d.datekey = f.orderdatekey
join {{ ref('DimCustomer') }} c on c.customerkey = f.customerkey
join {{ ref('DimProduct') }} p  on p.productkey = f.productkey
group by d.year, d.month, d.monthname, c.region, p.category
