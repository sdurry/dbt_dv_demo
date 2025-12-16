{{
    config(
        static_analysis='off'
    )
}}

--{# Multi-Pass Analytics with Recursive Customer Journey Analysis #}
--{# Designed for extremely expensive multi-pass computational operations #}
--{# DEPENDS ON: dbt_agg_window_fn (for Fusion state-aware orchestration testing) #}
 
WITH upstream_dependency AS (
  -- Reference upstream model to create dbt dependency chain
  -- This enables Fusion state-aware orchestration testing
  SELECT DISTINCT customer_id
  FROM {{ ref('dbt_agg_window_fn') }}
  LIMIT 1  -- Minimal data pull to establish dependency only
),
 
customer_transaction_base AS (
  SELECT
    s.customer_id,
    s.transaction_id,
    s.transaction_date,
    s.amount,
    s.quantity,
    s.channel,
    c.customer_name,
    c.tier as customer_tier,
    c.annual_income,
    p.product_name,
    p.category as product_category,
   
    --{# Create customer journey sequencing #}
    ROW_NUMBER() OVER (
      PARTITION BY s.customer_id
      ORDER BY s.transaction_date
    ) as customer_transaction_sequence,
   
    --{# Calculate days between transactions #}
    LAG(s.transaction_date) OVER (
      PARTITION BY s.customer_id
      ORDER BY s.transaction_date
    ) as previous_transaction_date
   
  FROM {{ source('synthetic_data','src_sales_transactions') }} s
  JOIN {{ source('synthetic_data','src_customers') }} c ON s.customer_id = c.customer_id
  JOIN {{ source('synthetic_data','src_products') }} p ON s.product_id = p.product_id
  WHERE s.status = 'completed'
    AND s.transaction_date >= '2020-01-01'
),
 
--{# First pass: Customer lifetime metrics calculation #}
first_pass_customer_metrics AS (
  SELECT
    customer_id,
    customer_name,
    customer_tier,
    annual_income,
   
    --{# Lifetime value calculations #}
    COUNT(*) as lifetime_transactions,
    SUM(amount) as lifetime_value,
    AVG(amount) as avg_transaction_value,
    MAX(amount) as max_transaction_value,
    MIN(amount) as min_transaction_value,
    STDDEV(amount) as transaction_value_stddev,
   
    --{# Time-based calculations #}
    MIN(transaction_date) as first_transaction_date,
    MAX(transaction_date) as last_transaction_date,
    DATEDIFF(DAY, MIN(transaction_date), MAX(transaction_date)) as customer_lifetime_days,
   
    --{# Product diversity #}
    COUNT(DISTINCT product_category) as unique_categories_purchased,
    COUNT(DISTINCT channel) as unique_channels_used,
   
    --{# Behavioral patterns #}
    AVG(DATEDIFF(DAY, previous_transaction_date, transaction_date)) as avg_days_between_transactions,
    COUNT(CASE WHEN channel = 'online' THEN 1 END) as online_transactions,
    COUNT(CASE WHEN channel = 'in_store' THEN 1 END) as in_store_transactions
   
  FROM customer_transaction_base
  WHERE previous_transaction_date IS NOT NULL  --{# Exclude first transaction for day calculations #}
  GROUP BY customer_id, customer_name, customer_tier, annual_income
),
 
--{# Second pass: Category preference analysis per customer #}
second_pass_category_analysis AS (
  SELECT
    c.customer_id,
    c.product_category,
   
    --{# Category-specific metrics #}
    COUNT(*) as category_transactions,
    SUM(c.amount) as category_spend,
    AVG(c.amount) as category_avg_spend,
   
    --{# Calculate category preference scores #}
    COUNT(*) / fm.lifetime_transactions::DECIMAL * 100 as category_transaction_share_pct,
    SUM(c.amount) / fm.lifetime_value * 100 as category_spend_share_pct,
   
    --{# Rank categories by customer preference #}
    DENSE_RANK() OVER (
      PARTITION BY c.customer_id
      ORDER BY SUM(c.amount) DESC
    ) as customer_category_preference_rank,
   
    --{# Time analysis within category #}
    MIN(c.transaction_date) as first_category_purchase,
    MAX(c.transaction_date) as last_category_purchase,
    DATEDIFF(DAY, MIN(c.transaction_date), MAX(c.transaction_date)) as category_engagement_days
   
  FROM customer_transaction_base c
  JOIN first_pass_customer_metrics fm ON c.customer_id = fm.customer_id
  GROUP BY
    c.customer_id,
    c.product_category,
    fm.lifetime_transactions,
    fm.lifetime_value
),
 
-- Third pass: Customer segmentation and cohort analysis
third_pass_customer_segmentation AS (
  SELECT
    fm.*,
   
    --{# Customer value segmentation #}
    CASE
      WHEN fm.lifetime_value >= PERCENTILE_APPROX(fm.lifetime_value, 0.95) OVER () THEN 'VIP'
      WHEN fm.lifetime_value >= PERCENTILE_APPROX(fm.lifetime_value, 0.80) OVER () THEN 'HIGH_VALUE'
      WHEN fm.lifetime_value >= PERCENTILE_APPROX(fm.lifetime_value, 0.60) OVER () THEN 'MEDIUM_VALUE'
      WHEN fm.lifetime_value >= PERCENTILE_APPROX(fm.lifetime_value, 0.40) OVER () THEN 'LOW_VALUE'
      ELSE 'BASIC'
    END as value_segment,
   
    --{# Frequency segmentation #}
    CASE
      WHEN fm.lifetime_transactions >= PERCENTILE_APPROX(fm.lifetime_transactions, 0.90) OVER () THEN 'VERY_FREQUENT'
      WHEN fm.lifetime_transactions >= PERCENTILE_APPROX(fm.lifetime_transactions, 0.70) OVER () THEN 'FREQUENT'
      WHEN fm.lifetime_transactions >= PERCENTILE_APPROX(fm.lifetime_transactions, 0.40) OVER () THEN 'MODERATE'
      ELSE 'INFREQUENT'
    END as frequency_segment,
   
    -- Recency segmentation
    CASE
      WHEN DATEDIFF(DAY, fm.last_transaction_date, CURRENT_DATE()) <= 30 THEN 'VERY_RECENT'
      WHEN DATEDIFF(DAY, fm.last_transaction_date, CURRENT_DATE()) <= 90 THEN 'RECENT'
      WHEN DATEDIFF(DAY, fm.last_transaction_date, CURRENT_DATE()) <= 180 THEN 'MODERATE'
      WHEN DATEDIFF(DAY, fm.last_transaction_date, CURRENT_DATE()) <= 365 THEN 'OLD'
      ELSE 'VERY_OLD'
    END as recency_segment,
   
    -- Cohort assignment based on first transaction
    CASE
      WHEN fm.first_transaction_date >= '2023-01-01' THEN '2023_COHORT'
      WHEN fm.first_transaction_date >= '2022-01-01' THEN '2022_COHORT'
      WHEN fm.first_transaction_date >= '2021-01-01' THEN '2021_COHORT'
      ELSE 'EARLY_COHORT'
    END as customer_cohort,
   
    -- Calculate percentile ranks across multiple dimensions
    PERCENT_RANK() OVER (ORDER BY fm.lifetime_value) as value_percentile_rank,
    PERCENT_RANK() OVER (ORDER BY fm.lifetime_transactions) as frequency_percentile_rank,
    PERCENT_RANK() OVER (ORDER BY fm.avg_transaction_value) as avg_value_percentile_rank,
    PERCENT_RANK() OVER (ORDER BY fm.unique_categories_purchased) as diversity_percentile_rank
   
  FROM first_pass_customer_metrics fm
),
 
-- Fourth pass: Complex cross-customer comparative analysis
fourth_pass_comparative_analysis AS (
  SELECT
    tps.*,
   
    -- Compare against tier averages
    AVG(tps.lifetime_value) OVER (PARTITION BY tps.customer_tier) as tier_avg_lifetime_value,
    AVG(tps.lifetime_transactions) OVER (PARTITION BY tps.customer_tier) as tier_avg_transactions,
    AVG(tps.avg_transaction_value) OVER (PARTITION BY tps.customer_tier) as tier_avg_transaction_value,
   
    -- Compare against cohort averages
    AVG(tps.lifetime_value) OVER (PARTITION BY tps.customer_cohort) as cohort_avg_lifetime_value,
    AVG(tps.lifetime_transactions) OVER (PARTITION BY tps.customer_cohort) as cohort_avg_transactions,
   
    -- Compare against segment averages
    AVG(tps.lifetime_value) OVER (PARTITION BY tps.value_segment) as value_segment_avg,
    AVG(tps.lifetime_transactions) OVER (PARTITION BY tps.frequency_segment) as frequency_segment_avg,
   
    -- Calculate customer similarity scores (computationally expensive)
    COUNT(*) OVER (
      PARTITION BY tps.value_segment, tps.frequency_segment, tps.recency_segment
    ) as similar_customers_count,
   
    -- Rank within various groupings
    DENSE_RANK() OVER (
      PARTITION BY tps.customer_tier, tps.value_segment
      ORDER BY tps.lifetime_value DESC
    ) as tier_value_rank,
   
    DENSE_RANK() OVER (
      PARTITION BY tps.customer_cohort, tps.frequency_segment
      ORDER BY tps.lifetime_transactions DESC
    ) as cohort_frequency_rank,
   
    -- Calculate deviation from peer groups
    (tps.lifetime_value - AVG(tps.lifetime_value) OVER (PARTITION BY tps.customer_tier)) /
      NULLIF(STDDEV(tps.lifetime_value) OVER (PARTITION BY tps.customer_tier), 0) as tier_value_z_score,
   
    (tps.lifetime_transactions - AVG(tps.lifetime_transactions) OVER (PARTITION BY tps.customer_cohort)) /
      NULLIF(STDDEV(tps.lifetime_transactions) OVER (PARTITION BY tps.customer_cohort), 0) as cohort_frequency_z_score
   
  FROM third_pass_customer_segmentation tps
),
 
-- Fifth pass: Category preferences integration with customer profiles
fifth_pass_integrated_analysis AS (
  SELECT
    fpa.customer_id,
    fpa.customer_name,
    fpa.customer_tier,
    fpa.annual_income,
    fpa.value_segment,
    fpa.frequency_segment,
    fpa.recency_segment,
    fpa.customer_cohort,
    fpa.lifetime_value,
    fpa.lifetime_transactions,
    fpa.avg_transaction_value,
   
    -- Aggregate category preferences
    STRING_AGG(
      CASE WHEN spa.customer_category_preference_rank <= 3
      THEN spa.product_category END, ', '
    ) as top_3_categories,
   
    -- Calculate category concentration
    MAX(spa.category_spend_share_pct) as max_category_concentration_pct,
    COUNT(CASE WHEN spa.category_spend_share_pct >= 20 THEN 1 END) as concentrated_categories_count,
   
    -- Category diversity metrics
    COUNT(DISTINCT spa.product_category) as total_categories_engaged,
    STDDEV(spa.category_spend_share_pct) as category_spend_distribution_stddev,
   
    -- Time-based category analysis
    AVG(spa.category_engagement_days) as avg_category_engagement_duration,
    MAX(spa.category_engagement_days) as max_category_engagement_duration,
   
    --{# Peer comparison on category behavior #}
    fpa.tier_value_rank,
    fpa.cohort_frequency_rank,
    fpa.tier_value_z_score,
    fpa.cohort_frequency_z_score,
    fpa.similar_customers_count,
    fpa.tier_avg_lifetime_value,
    fpa.cohort_avg_transactions,
   
    --{# Complex derived metrics #}
    (fpa.lifetime_value - fpa.tier_avg_lifetime_value) / NULLIF(fpa.tier_avg_lifetime_value, 0) * 100 as tier_value_performance_pct,
    (fpa.lifetime_transactions - fpa.cohort_avg_transactions) / NULLIF(fpa.cohort_avg_transactions, 0) * 100 as cohort_frequency_performance_pct
   
  FROM fourth_pass_comparative_analysis fpa
  LEFT JOIN second_pass_category_analysis spa ON fpa.customer_id = spa.customer_id
  GROUP BY
    fpa.customer_id, fpa.customer_name, fpa.customer_tier, fpa.annual_income,
    fpa.value_segment, fpa.frequency_segment, fpa.recency_segment, fpa.customer_cohort,
    fpa.lifetime_value, fpa.lifetime_transactions, fpa.avg_transaction_value,
    fpa.tier_value_rank, fpa.cohort_frequency_rank, fpa.tier_value_z_score,
    fpa.cohort_frequency_z_score, fpa.similar_customers_count,
    fpa.tier_avg_lifetime_value, fpa.cohort_avg_transactions
),
 
-- Final pass: Customer scoring and recommendations
final_customer_intelligence AS (
  SELECT
    *,
   
    -- Comprehensive customer score calculation
    (
      (CASE value_segment
        WHEN 'VIP' THEN 100
        WHEN 'HIGH_VALUE' THEN 80
        WHEN 'MEDIUM_VALUE' THEN 60
        WHEN 'LOW_VALUE' THEN 40
        ELSE 20 END) * 0.4 +
      (CASE frequency_segment
        WHEN 'VERY_FREQUENT' THEN 100
        WHEN 'FREQUENT' THEN 80
        WHEN 'MODERATE' THEN 60
        ELSE 40 END) * 0.3 +
      (CASE recency_segment
        WHEN 'VERY_RECENT' THEN 100
        WHEN 'RECENT' THEN 80
        WHEN 'MODERATE' THEN 60
        WHEN 'OLD' THEN 40
        ELSE 20 END) * 0.2 +
      (CASE WHEN total_categories_engaged >= 4 THEN 100
            WHEN total_categories_engaged >= 3 THEN 80
            WHEN total_categories_engaged >= 2 THEN 60
            ELSE 40 END) * 0.1
    ) as comprehensive_customer_score,
   
    -- Risk assessment
    CASE
      WHEN recency_segment IN ('OLD', 'VERY_OLD') AND frequency_segment = 'INFREQUENT' THEN 'HIGH_CHURN_RISK'
      WHEN recency_segment = 'MODERATE' AND tier_value_performance_pct < -20 THEN 'MEDIUM_CHURN_RISK'
      WHEN cohort_frequency_performance_pct < -30 THEN 'PERFORMANCE_DECLINE_RISK'
      ELSE 'LOW_RISK'
    END as churn_risk_category,
   
    -- Recommendation engine
    CASE
      WHEN value_segment = 'VIP' AND max_category_concentration_pct < 50 THEN 'CROSS_SELL_PREMIUM'
      WHEN frequency_segment = 'VERY_FREQUENT' AND recency_segment NOT IN ('VERY_RECENT', 'RECENT') THEN 'RE_ENGAGEMENT_CAMPAIGN'
      WHEN total_categories_engaged <= 2 AND lifetime_value > tier_avg_lifetime_value THEN 'CATEGORY_EXPANSION'
      WHEN tier_value_z_score > 1.5 THEN 'LOYALTY_REWARD'
      WHEN cohort_frequency_z_score < -1 THEN 'FREQUENCY_BOOST_CAMPAIGN'
      ELSE 'STANDARD_MARKETING'
    END as recommended_action,
   
    --{# Final ranking #}
    DENSE_RANK() OVER (ORDER BY (
      (CASE value_segment
        WHEN 'VIP' THEN 100
        WHEN 'HIGH_VALUE' THEN 80
        WHEN 'MEDIUM_VALUE' THEN 60
        WHEN 'LOW_VALUE' THEN 40
        ELSE 20 END) * 0.4 +
      (CASE frequency_segment
        WHEN 'VERY_FREQUENT' THEN 100
        WHEN 'FREQUENT' THEN 80
        WHEN 'MODERATE' THEN 60
        ELSE 40 END) * 0.3 +
      (CASE recency_segment
        WHEN 'VERY_RECENT' THEN 100
        WHEN 'RECENT' THEN 80
        WHEN 'MODERATE' THEN 60
        WHEN 'OLD' THEN 40
        ELSE 20 END) * 0.2 +
      (CASE WHEN total_categories_engaged >= 4 THEN 100
            WHEN total_categories_engaged >= 3 THEN 80
            WHEN total_categories_engaged >= 2 THEN 60
            ELSE 40 END) * 0.1
    ) DESC) as overall_customer_rank
   
  FROM fifth_pass_integrated_analysis
)
 
-- Final output with all multi-pass analytical results
SELECT
  fci.customer_id,
  fci.customer_name,
  fci.customer_tier,
  fci.annual_income,
  fci.customer_cohort,
  fci.value_segment,
  fci.frequency_segment,
  fci.recency_segment,
  fci.lifetime_value,
  fci.lifetime_transactions,
  fci.avg_transaction_value,
  fci.top_3_categories,
  fci.total_categories_engaged,
  fci.max_category_concentration_pct,
  fci.comprehensive_customer_score,
  fci.churn_risk_category,
  fci.recommended_action,
  fci.overall_customer_rank,
  fci.tier_value_performance_pct,
  fci.cohort_frequency_performance_pct,
  fci.similar_customers_count,
  fci.tier_value_z_score,
  fci.cohort_frequency_z_score
 
FROM final_customer_intelligence fci
LEFT JOIN upstream_dependency
  ON 1=0  -- Always false, no actual join, just establishes dbt ref() dependency
WHERE fci.comprehensive_customer_score IS NOT NULL
ORDER BY fci.comprehensive_customer_score DESC, fci.lifetime_value DESC
 