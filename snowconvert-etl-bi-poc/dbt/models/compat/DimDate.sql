{{ config(alias='DIMDATE') }}
select
    date_key        as datekey,
    date            as date,
    year            as year,
    quarter         as quarter,
    month           as month,
    month_name      as monthname,
    day_of_week     as dayofweek,
    is_weekend      as isweekend
from {{ ref('dim_date') }}
