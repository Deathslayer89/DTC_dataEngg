{{ config(
    materialized = 'table',
    schema = 'marts',
    partition_by = {
        'field': 'date',
        'data_type': 'date'
    }
) }}

WITH technical_data AS (
    SELECT
        symbol,
        date,
        close_price,
        volume,
        daily_change_pct,
        ma_5,
        ma_10,
        ma_20,
        ma_50,
        rsi_14,
        ma50_trend,
        ma_trend,
        volatility_20d
    FROM
        {{ ref('int_technical_indicators') }}
),

-- Calculate period returns
returns_calc AS (
    SELECT
        symbol,
        date,
        close_price,
        LAG(close_price, 1) OVER(PARTITION BY symbol ORDER BY date) as prev_day_price,
        LAG(close_price, 7) OVER(PARTITION BY symbol ORDER BY date) as prev_week_price,
        LAG(close_price, 30) OVER(PARTITION BY symbol ORDER BY date) as prev_month_price,
        LAG(close_price, 90) OVER(PARTITION BY symbol ORDER BY date) as prev_quarter_price,
        LAG(close_price, 365) OVER(PARTITION BY symbol ORDER BY date) as prev_year_price,
        FIRST_VALUE(close_price) OVER(PARTITION BY symbol ORDER BY date) as first_price
    FROM
        technical_data
),

performance_metrics AS (
    SELECT
        r.symbol,
        r.date,
        r.close_price,
        
        -- Daily return from technical_data
        t.daily_change_pct,
        
        -- Weekly return
        CASE 
            WHEN prev_week_price IS NOT NULL AND prev_week_price > 0 
            THEN ((r.close_price - prev_week_price) / prev_week_price) * 100 
            ELSE NULL 
        END as weekly_return_pct,
        
        -- Monthly return
        CASE 
            WHEN prev_month_price IS NOT NULL AND prev_month_price > 0 
            THEN ((r.close_price - prev_month_price) / prev_month_price) * 100 
            ELSE NULL 
        END as monthly_return_pct,
        
        -- Quarterly return
        CASE 
            WHEN prev_quarter_price IS NOT NULL AND prev_quarter_price > 0 
            THEN ((r.close_price - prev_quarter_price) / prev_quarter_price) * 100 
            ELSE NULL 
        END as quarterly_return_pct,
        
        -- Yearly return
        CASE 
            WHEN prev_year_price IS NOT NULL AND prev_year_price > 0 
            THEN ((r.close_price - prev_year_price) / prev_year_price) * 100 
            ELSE NULL 
        END as yearly_return_pct,
        
        -- Since inception return
        CASE 
            WHEN first_price IS NOT NULL AND first_price > 0 
            THEN ((r.close_price - first_price) / first_price) * 100 
            ELSE NULL 
        END as inception_return_pct
    FROM
        returns_calc r
    JOIN
        technical_data t ON r.symbol = t.symbol AND r.date = t.date
)

SELECT
    t.symbol,
    t.date,
    t.close_price,
    t.volume,
    t.ma_5,
    t.ma_10,
    t.ma_20,
    t.ma_50,
    t.rsi_14,
    t.ma50_trend,
    t.ma_trend,
    t.volatility_20d,
    
    -- Performance metrics
    p.daily_change_pct,
    p.weekly_return_pct,
    p.monthly_return_pct,
    p.quarterly_return_pct,
    p.yearly_return_pct,
    p.inception_return_pct,
    
    -- Trading signals (simple examples)
    CASE 
        WHEN t.rsi_14 < 30 THEN 'OVERSOLD'
        WHEN t.rsi_14 > 70 THEN 'OVERBOUGHT'
        ELSE 'NEUTRAL'
    END as rsi_signal,
    
    CASE 
        WHEN t.close_price > t.ma_50 AND t.ma_5 > t.ma_20 THEN 'STRONG_BUY'
        WHEN t.close_price > t.ma_50 THEN 'BUY'
        WHEN t.close_price < t.ma_50 AND t.ma_5 < t.ma_20 THEN 'STRONG_SELL'
        WHEN t.close_price < t.ma_50 THEN 'SELL'
        ELSE 'HOLD'
    END as trend_signal,
    
    -- Volatility classification
    CASE 
        WHEN t.volatility_20d / NULLIF(t.close_price, 0) * 100 > 5 THEN 'HIGH'
        WHEN t.volatility_20d / NULLIF(t.close_price, 0) * 100 > 2 THEN 'MEDIUM'
        ELSE 'LOW'
    END as volatility_level
FROM
    technical_data t
LEFT JOIN
    performance_metrics p ON t.symbol = p.symbol AND t.date = p.date
