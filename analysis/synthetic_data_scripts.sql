{{
    config(
        static_analysis='off'
    )
}}

CREATE OR REPLACE TABLE dbt_sdurry.src_sales_transactions AS
SELECT
  row_number() OVER (ORDER BY rand()) as transaction_id,
  date_add('2020-01-01', cast(rand() * 1461 as int)) as transaction_date,
  cast(rand() * 10000 as int) as customer_id,
  cast(rand() * 1000 as int) as product_id,
  cast(rand() * 500 as int) as store_id,
  round(rand() * 1000 + 10, 2) as amount,
  cast(rand() * 10 as int) as quantity,
  case
    when rand() < 0.1 then 'returned'
    when rand() < 0.05 then 'cancelled'
    else 'completed'
  end as status,
  case
    when rand() < 0.3 then 'online'
    else 'in_store'
  end as channel
FROM range(100000000);

CREATE OR REPLACE TABLE dbt_sdurry.src_customers AS
SELECT
  row_number() OVER (ORDER BY rand()) as customer_id,
  concat('Customer_', cast(row_number() OVER (ORDER BY rand()) as string)) as customer_name,
  case
    when rand() < 0.2 then 'Premium'
    when rand() < 0.5 then 'Standard'
    else 'Basic'
  end as tier,
  date_add('1950-01-01', cast(rand() * 25000 as int)) as birth_date,
  case when rand() < 0.5 then 'M' else 'F' end as gender,
  round(rand() * 200000 + 30000, 2) as annual_income,
  cast(rand() * 50 as int) + 1 as state_id
FROM range(10000);

CREATE OR REPLACE TABLE dbt_sdurry.src_products AS
SELECT
  row_number() OVER (ORDER BY rand()) as product_id,
  concat('Product_', cast(row_number() OVER (ORDER BY rand()) as string)) as product_name,
  case
    when rand() < 0.2 then 'Electronics'
    when rand() < 0.4 then 'Clothing'
    when rand() < 0.6 then 'Home'
    when rand() < 0.8 then 'Sports'
    else 'Books'
  end as category,
  round(rand() * 500 + 5, 2) as cost,
  round(rand() * 1000 + 10, 2) as price
FROM range(1000);

CREATE OR REPLACE TABLE dbt_sdurry.src_iot_readings AS
SELECT
  concat('sensor_', cast(cast(rand() * 1000 as int) as string)) as sensor_id,
  date_add(timestamp('2023-01-01 00:00:00'), cast(rand() * 365 as int)) as reading_timestamp,
  round(rand() * 100, 2) as temperature,
  round(rand() * 100, 2) as humidity,
  round(rand() * 1000, 2) as pressure,
  round(rand() * 50, 2) as wind_speed,
  case when rand() < 0.05 then 'ERROR' else 'OK' end as status,
  cast(rand() * 100 as int) as location_id
FROM range(1000000000);
 
CREATE OR REPLACE TABLE dbt_sdurry.src_locations AS
SELECT
  row_number() OVER (ORDER BY rand()) as location_id,
  concat('Location_', cast(row_number() OVER (ORDER BY rand()) as string)) as location_name,
  round(rand() * 180 - 90, 6) as latitude,
  round(rand() * 360 - 180, 6) as longitude,
  case
    when rand() < 0.3 then 'Urban'
    when rand() < 0.7 then 'Suburban'
    else 'Rural'
  end as area_type
 
FROM range(100);
