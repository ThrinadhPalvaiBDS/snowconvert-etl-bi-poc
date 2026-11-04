-- Every accepted staging line must land in fct_sales and totals must balance to the cent.
-- Fails (returns rows) on any difference.
with expected as (
    select count(*) as n, sum(round(l.quantity * l.unit_price * (1 - l.unit_price_discount), 4)) as amt
    from {{ ref('stg_order_lines') }} l
    join {{ ref('stg_orders') }} o on o.sales_order_id = l.sales_order_id
    where l.sales_order_detail_id not in (select sales_order_detail_id from {{ ref('int_order_lines_rejected') }}
                                          where error_reason <> 'Customer lookup no match')
),
actual as (
    select count(*) as n, sum(sales_amount) as amt from {{ ref('fct_sales') }}
)
select e.n as expected_rows, a.n as actual_rows, e.amt as expected_amount, a.amt as actual_amount
from expected e cross join actual a
where e.n <> a.n or abs(coalesce(e.amt, 0) - coalesce(a.amt, 0)) > 0.01
