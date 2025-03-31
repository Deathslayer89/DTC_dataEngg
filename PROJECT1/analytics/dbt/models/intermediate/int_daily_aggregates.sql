{{ config(
    materialized = 'view',
    schema = 'intermediate'
) }}

WITH daily_batch_data AS (
    SELECT
        symbol,
        date,
        open_price,
        high_price,
        low_price,
        close_price,
        volume,
        daily_change,
        daily_change_pct
    FROM
        {{ ref('stg_daily_prices') }}
),

daily_streaming_data AS (
    SELECT
        symbol,
        date,
        AVG(price) as avg_price,
        MAX(price) as max_price,
        MIN(price) as min_price,
        ARRAY_AGG(price ORDER BY timestamp DESC LIMIT 1)[OFFSET(0)] as last_price,
        SUM(volume) as total_volume,
        COUNT(*) as update_count
    FROM
        {{ ref('stg_realtime_prices') }}
    GROUP BY
        symbol, date
)

SELECT
    COALESCE(b.symbol, s.symbol) as symbol,
    COALESCE(b.date, s.date) as date,
    
    -- Prefer batch data for historical metrics, fall back to streaming
    COALESCE(b.open_price, s.min_price) as open_price,
    COALESCE(b.high_price, s.max_price) as high_price,
    COALESCE(b.low_price, s.min_price) as low_price,
    COALESCE(b.close_price, s.last_price) as close_price,
    COALESCE(b.volume, s.total_volume) as volume,
    
    -- Calculate change metrics
    COALESCE(b.daily_change, (s.last_price - s.min_price)) as daily_change,
    COALESCE(b.daily_change_pct, 
             CASE WHEN s.min_price > 0 
                  THEN ((s.last_price - s.min_price) / s.min_price) * 100 
                  ELSE 0 
             END) as daily_change_pct,
    
    -- Add source tracking
    CASE 
        WHEN b.symbol IS NOT NULL AND s.symbol IS NOT NULL THEN 'both'
        WHEN b.symbol IS NOT NULL THEN 'batch'
        ELSE 'streaming'
    END as data_source,
    
    -- Add streaming-specific metrics when available
    s.update_count as streaming_updates,
    s.avg_price as avg_streaming_price
FROM
    daily_batch_data b
    FULL OUTER JOIN daily_streaming_data s
        ON b.symbol = s.symbol AND b.date = s.date
