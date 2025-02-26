
# NYC Taxi Data Analysis with dbt - Module 4 Homework

This repository contains my solutions to the Module 4 Homework for the Data Engineering Zoomcamp. The assignment focuses on using dbt to transform and analyze NYC taxi data.

## Setup

I set up the environment by loading the required datasets to Google Cloud Platform:

1. First, I uploaded the Green and Yellow Taxi datasets using the [taxi_data_upload.py](./hw/taxi_data_upload.py) script
2. Then, I uploaded the For-Hire Vehicle (FHV) dataset using the [load_fhv.py](./hw/load_fhv.py) script
3. Created external tables in BigQuery for all three datasets
4. Verified the correct record counts:
   - Green Taxi: 7,778,101 records
   - Yellow Taxi: 109,047,518 records
   - FHV: 43,244,696 records
5. my projectId - zoomcamp-450020
6. my dataset -dbt_kumar

so you will be seeing these two values in my queries in solutions

## dbt Project Structure

After setting up the data sources, I built my dbt models following the recommended structure:
- Created staging models for Green and Yellow Taxi data
- Built dimension and fact models by joining with `dim_zones`
- Added additional dimensions like year, quarter, and month to facilitate filtering

## Homework Solutions

### Question 1: Understanding dbt model resolution

**Answer**: `select * from myproject.raw_nyc_tripdata.ext_green_taxi`



### Question 2: dbt Variables & Dynamic Models

**Answer**: `Update the WHERE clause to pickup_datetime >= CURRENT_DATE - INTERVAL '{{ var("days_back", env_var("DAYS_BACK", "30")) }}' DAY`

 correct precedence:
1. Command line arguments (via var)
2. Environment variables (via env_var)
3. Default value ("30")

### Question 3: dbt Data Lineage and Execution

**Answer**: `dbt run --select models/staging/+`

After analyzing the lineage graph, I think this command would NOT apply for materializing `fct_taxi_monthly_zone_revenue` because it only selects staging models and their descendants. Since `taxi_zone_lookup` is a seed file (not in staging), this command would miss the necessary dependency.

### Question 4: dbt Macros and Jinja

**Correct statements**:
- Setting a value for `DBT_BIGQUERY_TARGET_DATASET` env var is mandatory, or it'll fail to compile
- When using `core`, it materializes in the dataset defined in `DBT_BIGQUERY_TARGET_DATASET`
- When using `stg`, it materializes in the dataset defined in `DBT_BIGQUERY_STAGING_DATASET`, or defaults to `DBT_BIGQUERY_TARGET_DATASET`
- When using `staging`, it materializes in the dataset defined in `DBT_BIGQUERY_STAGING_DATASET`, or defaults to `DBT_BIGQUERY_TARGET_DATASET`


### Question 5: Taxi Quarterly Revenue Growth

To find the best and worst quarterly YoY growth in 2020 for Green and Yellow taxis, I ran:

```sql
SELECT 
  service_type,
  quarter,
  year_quarter,
  yoy_growth_percentage
FROM `zoomcamp-450020.dbt_dkumar.fct_taxi_trips_quarterly_revenue`
WHERE year = 2020
ORDER BY service_type, yoy_growth_percentage ASC;
```

The results showed that:
- Green: {best: 2020/Q1, worst: 2020/Q2}
- Yellow: {best: 2020/Q1, worst: 2020/Q2}

### Question 6: P97/P95/P90 Taxi Monthly Fare

I queried the percentiles for April 2020:

```sql
SELECT 
  service_type,
  p97, p95, p90
FROM `zoomcamp-450020.dbt_dkumar.fct_taxi_trips_monthly_fare_p95`
WHERE year = 2020 AND month = 4
ORDER BY service_type;
```

The results were:
- green: {p97: 55.0, p95: 45.0, p90: 26.5}
- yellow: {p97: 31.5, p95: 25.5, p90: 19.0}

### Question 7: Top #Nth longest P90 travel time Location for FHV

I ran the following query to find the 2nd longest dropoff zones for each pickup zone:

```sql
WITH ranked_destinations AS (
  SELECT
    pickup_zone,
    dropoff_zone,
    p90_duration,
    DENSE_RANK() OVER (PARTITION BY pickup_zone ORDER BY p90_duration DESC) AS duration_rank
  FROM `zoomcamp-450020.dbt_dkumar.fct_fhv_monthly_zone_traveltime_p90`
  WHERE 
    year = 2019 
    AND month = 11
    AND pickup_zone IN ('Newark Airport', 'SoHo', 'Yorkville East')
)
SELECT
  pickup_zone,
  dropoff_zone,
  p90_duration
FROM ranked_destinations
WHERE duration_rank = 2
ORDER BY pickup_zone
```

The results showed the 2nd longest p90 trip_duration dropoff zones were:
- Newark Airport: LaGuardia Airport
- SoHo: Park Slope
- Yorkville East: Clinton East


**Answer** : LaGuardia Airport, Chinatown, Garment District