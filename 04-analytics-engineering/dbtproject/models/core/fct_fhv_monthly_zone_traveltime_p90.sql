{{
    config(
        materialized='table'
    )
}}

WITH fhv_trips AS (
    SELECT 
        pickup_datetime,
        dropoff_datetime,
        pickup_locationid,
        dropoff_locationid,
        TIMESTAMP_DIFF(dropoff_datetime, pickup_datetime, SECOND) AS trip_duration,
        pickup_zone,
        dropoff_zone,
        year,
        month
    FROM {{ ref('dim_fhv_trips') }}
    WHERE 
        dropoff_datetime > pickup_datetime -- Ensure valid trip durations
        AND pickup_locationid IS NOT NULL
        AND dropoff_locationid IS NOT NULL
),

-- Calculate P90 trip durations
p90_trip_durations AS (
    SELECT
        year,
        month,
        pickup_locationid,
        dropoff_locationid,
        pickup_zone,
        dropoff_zone,
        PERCENTILE_CONT(trip_duration, 0.90) OVER (
            PARTITION BY year, month, pickup_locationid, dropoff_locationid
        ) AS p90_duration
    FROM fhv_trips
),

-- Get distinct P90 values
distinct_p90_durations AS (
    SELECT DISTINCT
        year,
        month,
        pickup_locationid,
        pickup_zone,
        dropoff_locationid,
        dropoff_zone,
        p90_duration
    FROM p90_trip_durations
),

-- Rank P90 durations for each pickup location
ranked_durations AS (
    SELECT
        year,
        month,
        pickup_zone,
        dropoff_zone,
        p90_duration,
        DENSE_RANK() OVER (
            PARTITION BY year, month, pickup_zone
            ORDER BY p90_duration DESC
        ) AS duration_rank
    FROM distinct_p90_durations
)

-- Final selection
SELECT
    year,
    month,
    pickup_zone,
    dropoff_zone,
    p90_duration,
    duration_rank
FROM ranked_durations
ORDER BY 
    year, 
    month, 
    pickup_zone, 
    duration_rank