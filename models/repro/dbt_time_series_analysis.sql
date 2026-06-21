--{# Advanced Time Series Analysis with Anomaly Detection #}
--{# Designed for complex time series computations on IoT sensor data #}
--{# DEPENDS ON: dbt_multipass_analytics (for Fusion state-aware orchestration testing) #}
 
WITH upstream_dependency AS (
  -- Reference upstream model to create dbt dependency chain
  -- This enables Fusion state-aware orchestration testing
  SELECT DISTINCT customer_id
  FROM {{ ref('dbt_multipass_analytics') }}
  LIMIT 1  -- Minimal data pull to establish dependency only
),
 
sensor_baseline AS (
  SELECT
    sensor_id,
    location_id,
    DATE_TRUNC('hour', reading_timestamp) as hour_timestamp,
    AVG(temperature) as avg_temperature,
    AVG(humidity) as avg_humidity,
    AVG(pressure) as avg_pressure,
    AVG(wind_speed) as avg_wind_speed,
    COUNT(*) as reading_count,
    COUNT(CASE WHEN status = 'ERROR' THEN 1 END) as error_count
  FROM {{ source('synthetic_data','src_iot_readings') }}
  WHERE reading_timestamp >= '2023-01-01'
    AND reading_timestamp < '2024-01-01'
  GROUP BY sensor_id, location_id, DATE_TRUNC('hour', reading_timestamp)
),
 
time_series_features AS (
  SELECT
    sensor_id,
    location_id,
    hour_timestamp,
    avg_temperature,
    avg_humidity,
    avg_pressure,
    avg_wind_speed,
    reading_count,
    error_count,
   
    --{# Complex moving averages with varying windows #}
    AVG(avg_temperature) OVER (
      PARTITION BY sensor_id
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW  --{# 7 days #}
    ) as temp_7day_ma,
   
    AVG(avg_temperature) OVER (
      PARTITION BY sensor_id
      ORDER BY hour_timestamp
      ROWS BETWEEN 720 PRECEDING AND CURRENT ROW  --{# 30 days #}
    ) as temp_30day_ma,
   
    --{# Standard deviation calculations #}
    STDDEV(avg_temperature) OVER (
      PARTITION BY sensor_id
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
    ) as temp_7day_stddev,
   
    --{# Lag/Lead comparisons for trend analysis #}
    LAG(avg_temperature, 1) OVER (PARTITION BY sensor_id ORDER BY hour_timestamp) as temp_1h_ago,
    LAG(avg_temperature, 24) OVER (PARTITION BY sensor_id ORDER BY hour_timestamp) as temp_24h_ago,
    LAG(avg_temperature, 168) OVER (PARTITION BY sensor_id ORDER BY hour_timestamp) as temp_7d_ago,
   
    --{# Percentile calculations for outlier detection #}
    PERCENTILE_APPROX(avg_temperature, 0.25) OVER (
      PARTITION BY sensor_id
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
    ) as temp_q1,
   
    PERCENTILE_APPROX(avg_temperature, 0.75) OVER (
      PARTITION BY sensor_id
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
    ) as temp_q3,
   
    --{# Seasonal decomposition components #}
    AVG(avg_temperature) OVER (
      PARTITION BY sensor_id, EXTRACT(HOUR FROM hour_timestamp)
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
    ) as hourly_seasonal_avg,
   
    AVG(avg_temperature) OVER (
      PARTITION BY sensor_id, EXTRACT(DAYOFWEEK FROM hour_timestamp)
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
    ) as weekly_seasonal_avg
   
  FROM sensor_baseline
),
 
anomaly_detection AS (
  SELECT
    *,
   
    --{# Temperature anomaly detection #}
    CASE
      WHEN temp_7day_stddev > 0 THEN
        ABS(avg_temperature - temp_7day_ma) / temp_7day_stddev
      ELSE 0
    END as temp_z_score,
   
    --{# IQR-based outlier detection #}
    (temp_q3 - temp_q1) as temp_iqr,
    CASE
      WHEN (temp_q3 - temp_q1) > 0 THEN
        CASE
          WHEN avg_temperature > temp_q3 + 1.5 * (temp_q3 - temp_q1) THEN 'HIGH_OUTLIER'
          WHEN avg_temperature < temp_q1 - 1.5 * (temp_q3 - temp_q1) THEN 'LOW_OUTLIER'
          ELSE 'NORMAL'
        END
      ELSE 'INSUFFICIENT_DATA'
    END as temp_outlier_status,
   
    --{# Trend analysis #}
    (avg_temperature - temp_1h_ago) as temp_1h_change,
    (avg_temperature - temp_24h_ago) as temp_24h_change,
    (avg_temperature - temp_7d_ago) as temp_7d_change,
   
    --{# Seasonal deviation #}
    (avg_temperature - hourly_seasonal_avg) as hourly_seasonal_deviation,
    (avg_temperature - weekly_seasonal_avg) as weekly_seasonal_deviation,
   
    --{# Multi-variate correlations (computationally expensive) #}
    CORR(avg_temperature, avg_humidity) OVER (
      PARTITION BY sensor_id
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
    ) as temp_humidity_correlation,
   
    CORR(avg_pressure, avg_wind_speed) OVER (
      PARTITION BY sensor_id
      ORDER BY hour_timestamp
      ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
    ) as pressure_wind_correlation
   
  FROM time_series_features
),
 
sensor_health_metrics AS (
  SELECT
    sensor_id,
    location_id,
    hour_timestamp,
   
    --{# Environmental readings #}
    avg_temperature,
    avg_humidity,
    avg_pressure,
    avg_wind_speed,
   
    --{# Anomaly flags #}
    temp_z_score,
    temp_outlier_status,
    temp_1h_change,
    temp_24h_change,
    temp_7d_change,
   
    --{# Seasonal analysis #}
    hourly_seasonal_deviation,
    weekly_seasonal_deviation,
   
    --{# Correlations #}
    temp_humidity_correlation,
    pressure_wind_correlation,
   
    --{# Sensor reliability metrics #}
    reading_count,
    error_count,
    error_count / NULLIF(reading_count, 0) * 100 as error_rate_pct,
   
    --{# Complex health scoring #}
    CASE
      WHEN error_count / NULLIF(reading_count, 0) > 0.1 THEN 0  --{# High error rate #}
      WHEN temp_z_score > 3 THEN 20  --{# Extreme outlier #}
      WHEN temp_z_score > 2 THEN 50  --{# Moderate outlier #}
      WHEN temp_outlier_status IN ('HIGH_OUTLIER', 'LOW_OUTLIER') THEN 60
      WHEN ABS(temp_1h_change) > 10 THEN 70  --{# Rapid change #}
      WHEN ABS(hourly_seasonal_deviation) > 5 THEN 80  --{# Seasonal anomaly #}
      ELSE 100  --{# Normal #}
    END as sensor_health_score,
   
    --{# Location-based aggregations #}
    AVG(avg_temperature) OVER (
      PARTITION BY location_id, DATE_TRUNC('day', hour_timestamp)
    ) as location_daily_avg_temp,
   
    STDDEV(avg_temperature) OVER (
      PARTITION BY location_id, DATE_TRUNC('day', hour_timestamp)
    ) as location_daily_temp_variance
   
  FROM anomaly_detection
)
 
--{# Final comprehensive time series analysis #}
SELECT
  s.*,
  l.location_name,
  l.area_type,
  l.latitude,
  l.longitude,
 
  --{# Additional derived metrics #}
  CASE
    WHEN sensor_health_score < 50 THEN 'CRITICAL'
    WHEN sensor_health_score < 70 THEN 'WARNING'
    WHEN sensor_health_score < 90 THEN 'ATTENTION'
    ELSE 'HEALTHY'
  END as health_status,
 
  --{# Complex ranking across multiple dimensions #}
  DENSE_RANK() OVER (
    PARTITION BY s.location_id, DATE_TRUNC('day', s.hour_timestamp)
    ORDER BY sensor_health_score ASC
  ) as daily_health_rank,
 
  --{# Percentile ranking for comparative analysis #}
  PERCENT_RANK() OVER (
    PARTITION BY area_type
    ORDER BY temp_z_score
  ) as area_type_anomaly_percentile,
 
  --{# Time-based aggregations for pattern detection #}
  COUNT(CASE WHEN temp_outlier_status != 'NORMAL' THEN 1 END) OVER (
    PARTITION BY sensor_id
    ORDER BY hour_timestamp
    ROWS BETWEEN 168 PRECEDING AND CURRENT ROW
  ) as outliers_past_week,
 
  --{# Computational intensive mathematical transformations #}
  LOG(ABS(temp_1h_change) + 1) as log_temp_change,
  POWER(temp_z_score, 2) as squared_z_score,
  SQRT(ABS(hourly_seasonal_deviation)) as sqrt_seasonal_dev
 
FROM sensor_health_metrics s
JOIN {{ source('synthetic_data','src_locations') }} l ON s.location_id = l.location_id
LEFT JOIN upstream_dependency
  ON 1=0  -- Always false, no actual join, just establishes dbt ref() dependency
WHERE s.reading_count >= 10  --{# Ensure sufficient data quality #}
ORDER BY
  sensor_health_score ASC,  --{# Show problematic sensors first #}
  sensor_id,
  hour_timestamp
