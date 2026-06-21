with hub_order as (

    select *
    from {{ ref('hub_order') }}

), link as (

    select *
    from {{ ref('link_customer_order') }}

), joined as (

    select 
        l.order_pk
        ,l.customer_pk
        ,l.load_date
    from hub_order as h
    join link_customer_order as l
        on h.order_pk = l.order_pk

), month_aggregate as (

    select
        date_trunc('month', load_date) as month_at
        ,count(order_pk) as order_count
        ,count(distinct customer_pk) as customer_count
    from joined
    group by 1

)

select *
from month_aggregate
