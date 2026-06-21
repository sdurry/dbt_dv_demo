--{# Massive Join Operations with Controlled Data Multiplication #}
--{# Designed to stress test join performance without dangerous explosions #}
 
WITH transaction_base AS (
  SELECT
    s.transaction_id,
    s.customer_id,
    s.product_id,
    s.store_id,
    s.transaction_date,
    s.amount,
    s.quantity,
    s.channel,
   
    {# Create time dimensions for complex joins #}
    EXTRACT(HOUR FROM s.transaction_date) as transaction_hour,
    EXTRACT(DAY FROM s.transaction_date) as transaction_day,
    EXTRACT(WEEK FROM s.transaction_date) as transaction_week,
    EXTRACT(MONTH FROM s.transaction_date) as transaction_month,
    EXTRACT(QUARTER FROM s.transaction_date) as transaction_quarter,
    EXTRACT(YEAR FROM s.transaction_date) as transaction_year,
    DAYOFWEEK(s.transaction_date) as day_of_week,
    DAYOFYEAR(s.transaction_date) as day_of_year,
   
    {# ULTRA-conservative join keys - NO SELF-JOINS for guaranteed 1-hour target #}
    MOD(s.customer_id, 1) as customer_group_1,     {# No customer self-join - all in same group #}
    MOD(s.product_id, 3) as product_group_3,       {# Keep product grouping for complexity #}
    MOD(s.store_id, 25) as store_group_25
   
  FROM {{ source('synthetic_data','src_sales_transactions') }} s
  WHERE s.status = 'completed'
    AND s.transaction_date >= '2022-01-01'  {# Reduced to 2 years for better performance #}
),
 
{# Create multiple dimension tables for complex joins #}
customer_dimension_extended AS (
  SELECT
    c.*,
    {# Create additional grouping dimensions #}
    CASE
      WHEN c.annual_income >= 100000 THEN 'HIGH_INCOME'
      WHEN c.annual_income >= 50000 THEN 'MEDIUM_INCOME'
      ELSE 'LOW_INCOME'
    END as income_bracket,
   
    CASE
      WHEN DATEDIFF(YEAR, c.birth_date, CURRENT_DATE()) >= 65 THEN 'SENIOR'
      WHEN DATEDIFF(YEAR, c.birth_date, CURRENT_DATE()) >= 35 THEN 'MIDDLE_AGE'
      WHEN DATEDIFF(YEAR, c.birth_date, CURRENT_DATE()) >= 25 THEN 'YOUNG_ADULT'
      ELSE 'YOUTH'
    END as age_group,
   
    MOD(c.customer_id, 1) as customer_group_1
   
  FROM {{ source('synthetic_data','src_customers') }} c
),
 
product_dimension_extended AS (
  SELECT
    p.*,
    {# Create product groupings for complex joins #}
    CASE
      WHEN p.price >= 500 THEN 'PREMIUM'
      WHEN p.price >= 100 THEN 'STANDARD'
      ELSE 'BUDGET'
    END as price_tier,
   
    MOD(p.product_id, 3) as product_group_3,
   
    {# Create artificial product families #}
    CASE
      WHEN p.category = 'Electronics' AND p.price >= 200 THEN 'HIGH_TECH'
      WHEN p.category = 'Clothing' AND p.price >= 100 THEN 'FASHION'
      WHEN p.category = 'Home' AND p.price >= 150 THEN 'PREMIUM_HOME'
      ELSE 'STANDARD_ITEM'
    END as product_family
   
  FROM {{ source('synthetic_data','src_products') }} p
),
 
{# Multiple complex joins without dangerous explosion #}
massive_join_base AS (
  SELECT
    t.transaction_id,
    t.transaction_date,
    t.amount,
    t.quantity,
    t.channel,
    t.transaction_hour,
    t.transaction_month,
    t.transaction_quarter,
    t.transaction_year,
    t.day_of_week,
    t.customer_group_1,
    t.product_group_3,
    t.store_group_25,
   
    {# Customer dimension data #}
    c.customer_id,
    c.customer_name,
    c.tier as customer_tier,
    c.annual_income,
    c.gender,
    c.income_bracket,
    c.age_group,
   
    {# Product dimension data #}
    p.product_id,
    p.product_name,
    p.category as product_category,
    p.cost as product_cost,
    p.price as product_price,
    p.price_tier,
    p.product_family,
   
    {# Store dimension (artificial expansion) #}
    s.store_id,
    CONCAT('Store_', s.store_id) as store_name,
    MOD(s.store_id, 10) as store_region,
   
    {# Calculate multiple derived metrics #}
    (t.amount - p.cost * t.quantity) as profit,
    (t.amount - p.cost * t.quantity) / NULLIF(t.amount, 0) * 100 as profit_margin_pct,
    t.amount / NULLIF(t.quantity, 0) as unit_price,
   
    {# Complex calculated fields #}
    CASE
      WHEN c.tier = 'Premium' AND p.price_tier = 'PREMIUM' THEN t.amount * 1.5
      WHEN c.tier = 'Standard' AND p.price_tier = 'STANDARD' THEN t.amount * 1.2
      ELSE t.amount
    END as tier_adjusted_value
   
  FROM transaction_base t
 
  {# Multiple joins to stress the join engine #}
  JOIN customer_dimension_extended c ON t.customer_id = c.customer_id
  JOIN product_dimension_extended p ON t.product_id = p.product_id
 
  {# NO SELF-JOINS - Focus on complex aggregations and window functions instead #}
  {# REMOVED all self-joins to prevent any row explosion #}
 
  {# Store dimension join (create store table on the fly) #}
  LEFT JOIN (
    SELECT DISTINCT
      store_id,
      MOD(store_id, 25) as store_group_25,
      CASE
        WHEN MOD(store_id, 5) = 0 THEN 'FLAGSHIP'
        WHEN MOD(store_id, 3) = 0 THEN 'STANDARD'
        ELSE 'OUTLET'
      END as store_type
    FROM {{ source('synthetic_data','src_sales_transactions') }} 
  ) s ON t.store_id = s.store_id
),
 
{# Enhanced aggregations with peer analysis #}
enhanced_aggregation_metrics AS (
  SELECT
    m.customer_id,
    m.customer_name,
    m.customer_tier,
    m.income_bracket,
    m.age_group,
    m.product_category,
    m.price_tier,
    m.product_family,
    m.transaction_year,
    m.transaction_quarter,
    m.transaction_month,
    m.store_region,
   
    {# Primary transaction metrics #}
    COUNT(*) as total_transactions,
    COUNT(DISTINCT m.transaction_id) as unique_transactions,
    SUM(m.amount) as total_amount,
    SUM(m.quantity) as total_quantity,
    SUM(m.profit) as total_profit,
    AVG(m.amount) as avg_amount,
    AVG(m.profit_margin_pct) as avg_profit_margin,
    AVG(m.tier_adjusted_value) as avg_tier_adjusted_value,
   
    {# Peer comparison metrics - simulated without self-joins #}
    COUNT(DISTINCT m.customer_id) as similar_customers_count,  {# Use customer count as proxy #}
    AVG(m.annual_income) as peer_avg_income,  {# Use actual income instead of peer income #}
    {# Removed product peer metrics since we eliminated that self-join #}
   
    {# Statistical calculations #}
    STDDEV(m.amount) as amount_stddev,
    VARIANCE(m.profit_margin_pct) as profit_variance,
   
    {# Percentile calculations #}
    PERCENTILE_APPROX(m.amount, 0.5) as median_amount,
    PERCENTILE_APPROX(m.profit_margin_pct, 0.9) as p90_profit_margin,
    PERCENTILE_APPROX(m.tier_adjusted_value, 0.75) as p75_tier_adjusted,
   
    {# Min/Max calculations #}
    MIN(m.transaction_date) as first_transaction_date,
    MAX(m.transaction_date) as last_transaction_date,
    MIN(m.amount) as min_amount,
    MAX(m.amount) as max_amount,
   
    {# Channel analysis #}
    COUNT(CASE WHEN m.channel = 'online' THEN 1 END) as online_transactions,
    COUNT(CASE WHEN m.channel = 'in_store' THEN 1 END) as in_store_transactions,
   
    {# Time-based patterns #}
    COUNT(CASE WHEN m.day_of_week IN (1, 7) THEN 1 END) as weekend_transactions,
    COUNT(CASE WHEN m.day_of_week BETWEEN 2 AND 6 THEN 1 END) as weekday_transactions,
   
    {# Cross-tier analysis #}
    SUM(CASE WHEN m.customer_tier = 'Premium' AND m.price_tier = 'PREMIUM' THEN m.amount ELSE 0 END) as premium_premium_amount,
    COUNT(CASE WHEN m.customer_tier = 'Premium' AND m.price_tier = 'PREMIUM' THEN 1 END) as premium_premium_count
   
  FROM (
    SELECT
      mjb.*
      {# NO peer variables since we eliminated all self-joins #}
    FROM massive_join_base mjb
    {# NO self-joins - using base data only for guaranteed performance #}
  ) m
  GROUP BY
    m.customer_id, m.customer_name, m.customer_tier, m.income_bracket, m.age_group,
    m.product_category, m.price_tier, m.product_family,
    m.transaction_year, m.transaction_quarter, m.transaction_month, m.store_region
)
 
{# Final analysis with complex window functions and rankings #}
SELECT
  eam.*,
 
  {# Calculate performance ratios #}
  eam.total_profit / NULLIF(eam.total_amount, 0) * 100 as actual_profit_margin,
  eam.online_transactions / NULLIF(eam.total_transactions, 0) * 100 as online_transaction_pct,
  eam.weekend_transactions / NULLIF(eam.total_transactions, 0) * 100 as weekend_transaction_pct,
  eam.premium_premium_amount / NULLIF(eam.total_amount, 0) * 100 as premium_alignment_pct,
 
  {# Peer comparison ratios (simulated without self-joins) #}
  eam.avg_amount / NULLIF(AVG(eam.avg_amount) OVER (PARTITION BY eam.product_category), 0) as category_avg_ratio,
  eam.similar_customers_count / 1.0 as peer_density_score,  {# No actual peers, use count as proxy #}
 
  {# Complex window functions for ranking and comparison #}
  DENSE_RANK() OVER (
    PARTITION BY eam.product_category, eam.transaction_year
    ORDER BY eam.total_amount DESC
  ) as category_year_amount_rank,
 
  DENSE_RANK() OVER (
    PARTITION BY eam.customer_tier, eam.income_bracket
    ORDER BY eam.avg_tier_adjusted_value DESC
  ) as tier_income_performance_rank,
 
  DENSE_RANK() OVER (
    PARTITION BY eam.age_group, eam.price_tier
    ORDER BY eam.total_transactions DESC
  ) as age_price_frequency_rank,
 
  {# Running totals and moving averages #}
  SUM(eam.total_amount) OVER (
    PARTITION BY eam.customer_id
    ORDER BY eam.transaction_year, eam.transaction_quarter
    ROWS UNBOUNDED PRECEDING
  ) as customer_running_total,
 
  AVG(eam.avg_amount) OVER (
    PARTITION BY eam.product_category
    ORDER BY eam.transaction_year, eam.transaction_month
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
  ) as category_3month_avg_amount,
 
  {# Market share calculations #}
  eam.total_amount / SUM(eam.total_amount) OVER (
    PARTITION BY eam.product_category, eam.transaction_year
  ) * 100 as category_market_share_pct,
 
  eam.total_transactions / SUM(eam.total_transactions) OVER (
    PARTITION BY eam.store_region, eam.transaction_quarter
  ) * 100 as regional_transaction_share_pct,
 
  {# Percentile rankings #}
  PERCENT_RANK() OVER (
    PARTITION BY eam.transaction_year
    ORDER BY eam.total_amount
  ) as annual_amount_percentile,
 
  PERCENT_RANK() OVER (
    PARTITION BY eam.customer_tier
    ORDER BY eam.avg_profit_margin
  ) as tier_profitability_percentile,
 
  {# Z-score calculations for outlier detection #}
  (eam.total_amount - AVG(eam.total_amount) OVER (PARTITION BY eam.product_category)) /
    NULLIF(STDDEV(eam.total_amount) OVER (PARTITION BY eam.product_category), 0) as category_amount_z_score,
   
  (eam.avg_profit_margin - AVG(eam.avg_profit_margin) OVER (PARTITION BY eam.customer_tier)) /
    NULLIF(STDDEV(eam.avg_profit_margin) OVER (PARTITION BY eam.customer_tier), 0) as tier_margin_z_score
 
FROM enhanced_aggregation_metrics eam
WHERE eam.total_transactions >= 5  {# Filter for meaningful transaction volumes #}
  AND eam.total_amount > 0
ORDER BY
  eam.customer_tier,
  eam.product_category,
  eam.transaction_year DESC,
  eam.total_amount DESC
