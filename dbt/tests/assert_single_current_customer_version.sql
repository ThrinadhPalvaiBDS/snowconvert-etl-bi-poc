-- SCD2 integrity: exactly one current row per customer
select customer_id, count(*) as current_rows
from {{ ref('dim_customer') }}
where is_current and customer_id <> -1
group by customer_id
having count(*) <> 1
