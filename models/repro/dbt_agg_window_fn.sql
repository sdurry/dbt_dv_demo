--{# Complex Aggregations with Advanced Window Functions #}
--{# Designed to stress test XL SQL Warehouse Serverless with massive computational load #}
--{# DEPENDS ON: dbt_massive_join (for Fusion state-aware orchestration testing) #}
 
WITH upstream_dependency AS (
  -- Reference upstream model to create dbt dependency chain
  -- This enables Fusion state-aware orchestration testing
  SELECT DISTINCT customer_id
  FROM {{ ref('dbt_massive_join') }}
  LIMIT 1  -- Minimal data pull to establish dependency only
),
 
base_query AS (
SELECT
  customer_id,
  product_category,
  transaction_year,
  transaction_month,
  transaction_date,
  amount,
 
  --{# Basic aggregations as window functions #}
  COUNT(*) OVER (PARTITION BY customer_id, product_category, transaction_year, transaction_month) as transaction_count,
  SUM(amount) OVER (PARTITION BY customer_id, product_category, transaction_year, transaction_month) as total_amount,
  AVG(amount) OVER (PARTITION BY customer_id, product_category, transaction_year, transaction_month) as avg_amount,
 
  --{# Ultra-Complex Window Functions with massive frames (stress testing) #}
  AVG(amount) OVER (
    PARTITION BY customer_id
    ORDER BY transaction_date
    ROWS BETWEEN 2000 PRECEDING AND CURRENT ROW
  ) as rolling_avg_2000_day,
 
  SUM(amount) OVER (
    PARTITION BY product_category
    ORDER BY transaction_date
    ROWS BETWEEN 1000 PRECEDING AND 500 FOLLOWING
  ) as centered_sum_1500_window,
 
  --{# Multiple percentile calculations (computationally expensive) #}
  PERCENTILE_APPROX(amount, 0.25) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 500 PRECEDING AND CURRENT ROW
  ) as rolling_p25,
 
  PERCENTILE_APPROX(amount, 0.5) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 500 PRECEDING AND CURRENT ROW
  ) as rolling_median,
 
  PERCENTILE_APPROX(amount, 0.75) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 500 PRECEDING AND CURRENT ROW
  ) as rolling_p75,
 
  PERCENTILE_APPROX(amount, 0.9) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 500 PRECEDING AND CURRENT ROW
  ) as rolling_p90,
 
  PERCENTILE_APPROX(amount, 0.95) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 500 PRECEDING AND CURRENT ROW
  ) as rolling_p95,
 
  PERCENTILE_APPROX(amount, 0.99) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 500 PRECEDING AND CURRENT ROW
  ) as rolling_p99,
 
  PERCENTILE_APPROX(amount, 0.999) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 500 PRECEDING AND CURRENT ROW
  ) as rolling_p999,
 
  --{# Complex mathematical operations with trigonometric functions #}
  SIN(SUM(amount) OVER (
    PARTITION BY customer_id
    ORDER BY transaction_date
    ROWS BETWEEN 100 PRECEDING AND CURRENT ROW
  ) / 1000.0) as sin_rolling_sum,
 
  COS(AVG(amount) OVER (
    PARTITION BY product_category
    ORDER BY transaction_date
    ROWS BETWEEN 200 PRECEDING AND CURRENT ROW
  ) / 100.0) as cos_rolling_avg,
 
  TAN(COUNT(*) OVER (
    PARTITION BY customer_id, product_category
    ORDER BY transaction_date
    ROWS BETWEEN 50 PRECEDING AND CURRENT ROW
  ) / 10.0) as tan_rolling_count,
 
  --{# Nested aggregations and calculations #}
  STDDEV(amount) OVER (
    PARTITION BY customer_id
    ORDER BY transaction_date
    ROWS BETWEEN 300 PRECEDING AND CURRENT ROW
  ) as rolling_stddev,
 
  VARIANCE(amount) OVER (
    PARTITION BY product_category
    ORDER BY transaction_date
    ROWS BETWEEN 400 PRECEDING AND CURRENT ROW
  ) as rolling_variance,
 
  --{# Lead/Lag with large offsets #}
  LAG(amount, 100) OVER (
    PARTITION BY customer_id
    ORDER BY transaction_date
  ) as amount_100_periods_ago,
 
  LEAD(amount, 100) OVER (
    PARTITION BY customer_id
    ORDER BY transaction_date
  ) as amount_100_periods_forward,
 
  --{# Dense rank and row number over large partitions #}
  DENSE_RANK() OVER (
    PARTITION BY product_category, EXTRACT(YEAR FROM transaction_date)
    ORDER BY amount DESC
  ) as amount_rank_in_category_year,
 
  ROW_NUMBER() OVER (
    PARTITION BY customer_id, EXTRACT(MONTH FROM transaction_date)
    ORDER BY amount DESC
  ) as transaction_rank_in_customer_month
 
FROM (
  SELECT
    s.transaction_id,
    s.customer_id,
    s.transaction_date,
    s.amount,
    p.category as product_category,
    EXTRACT(YEAR FROM s.transaction_date) as transaction_year,
    EXTRACT(MONTH FROM s.transaction_date) as transaction_month
  FROM {{ source('synthetic_data','src_sales_transactions') }} s
  JOIN {{ source('synthetic_data','src_products') }} p ON s.product_id = p.product_id
  WHERE s.status = 'completed'
    AND s.transaction_date >= '2022-01-01'
) base_data
)
 
-- Final select with upstream dependency reference (doesn't affect logic, just creates dbt lineage)
SELECT
  base_query.*
FROM base_query
CROSS JOIN (SELECT 1 FROM upstream_dependency LIMIT 1) AS dep  -- Establishes dbt ref() dependency
ORDER BY customer_id, transaction_date
