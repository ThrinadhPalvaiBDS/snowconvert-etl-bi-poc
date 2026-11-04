-- Legacy dbo.DimDate was populated by a one-off script; generated here instead.
{{ config(materialized='table') }}
with days as (
    {{ dbt_utils.date_spine(datepart="day",
         start_date="cast('2015-01-01' as date)",
         end_date="dateadd(year, 2, current_date())") }}
)
select
    {{ date_key('date_day') }}                    as date_key,
    cast(date_day as date)                        as date,
    year(date_day)                                as year,
    quarter(date_day)                             as quarter,
    month(date_day)                               as month,
    monthname(date_day)                           as month_short_name,
    to_char(date_day, 'MMMM')                     as month_name,
    dayofweekiso(date_day)                        as day_of_week,
    dayofweekiso(date_day) in (6, 7)              as is_weekend
from days
