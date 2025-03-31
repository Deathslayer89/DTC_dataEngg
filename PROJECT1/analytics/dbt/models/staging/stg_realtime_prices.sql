{{ config(
    materialized = 'view',
    schema = 'staging'
) }}

WITH source_data AS (
    SELECT
        symbol,
        timestamp,
        price,
        volume,
        currency
    FROM
        `stockmarket-455214.stock_market_analytics.stock_prices_realtime`
    WHERE
        price IS NOT NULL
)

SELECT
    symbol,
    timestamp, -- Already in TIMESTAMP format, no need to parse
    CAST(price AS FLOAT64) as price,
    CAST(volume AS INT64) as volume,
    currency,
    EXTRACT(DATE FROM timestamp) as date,
    EXTRACT(HOUR FROM timestamp) as hour
FROM
    source_data
