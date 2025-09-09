with source as (
    select *
    from {{ ref('t_link_transactions') }}
),

select 
    customer_pk,
    record_source,
    sum(amount) as total_amount
from source
group by 1, 2
