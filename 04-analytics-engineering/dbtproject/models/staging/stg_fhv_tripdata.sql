{{
    config(
        materialized='view'
    )
}}

SELECT
    -- identifiers
    dispatching_base_num,
    {{ dbt.safe_cast("pulocationid", api.Column.translate_type("integer")) }} AS pickup_locationid,
    {{ dbt.safe_cast("dolocationid", api.Column.translate_type("integer")) }} AS dropoff_locationid,
    
    -- timestamps
    CAST(pickup_datetime AS TIMESTAMP) AS pickup_datetime,
    CAST(dropoff_datetime AS TIMESTAMP) AS dropoff_datetime,
    
    -- trip info
    SR_Flag AS sr_flag,
    Affiliated_base_number AS affiliated_base_number,
    
    -- Create a unique trip ID
    {{ dbt.concat(["dispatching_base_num", "CAST(pickup_datetime AS STRING)"]) }} AS tripid
FROM {{ source('staging', 'ext_fhv_taxi') }}
WHERE dispatching_base_num IS NOT NULL