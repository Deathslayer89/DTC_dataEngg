

WITH daily_data AS (
    SELECT
        symbol,
        date,
        close_price,
        volume,
        daily_change_pct
    FROM
        `stockmarket-455214`.`dbt_analytics_intermediate`.`int_daily_aggregates`
    WHERE
        close_price IS NOT NULL
),

-- Calculate moving averages
moving_avgs AS (
    SELECT
        symbol,
        date,
        close_price,
        volume,
        daily_change_pct,
        AVG(close_price) OVER(PARTITION BY symbol ORDER BY date ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) as ma_5,
        AVG(close_price) OVER(PARTITION BY symbol ORDER BY date ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) as ma_10,
        AVG(close_price) OVER(PARTITION BY symbol ORDER BY date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) as ma_20,
        AVG(close_price) OVER(PARTITION BY symbol ORDER BY date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) as ma_50,
        AVG(volume) OVER(PARTITION BY symbol ORDER BY date ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) as volume_ma_10
    FROM
        daily_data
),

-- Calculate Relative Strength Index (RSI)
price_changes AS (
    SELECT
        symbol,
        date,
        close_price,
        LAG(close_price) OVER(PARTITION BY symbol ORDER BY date) as prev_close,
        close_price - LAG(close_price) OVER(PARTITION BY symbol ORDER BY date) as price_change
    FROM
        daily_data
),

gains_losses AS (
    SELECT
        symbol,
        date,
        close_price,
        price_change,
        CASE WHEN price_change > 0 THEN price_change ELSE 0 END as gain,
        CASE WHEN price_change < 0 THEN ABS(price_change) ELSE 0 END as loss
    FROM
        price_changes
    WHERE
        price_change IS NOT NULL
),

avg_gains_losses AS (
    SELECT
        symbol,
        date,
        close_price,
        gain,
        loss,
        AVG(gain) OVER(PARTITION BY symbol ORDER BY date ROWS BETWEEN 13 PRECEDING AND CURRENT ROW) as avg_gain_14,
        AVG(loss) OVER(PARTITION BY symbol ORDER BY date ROWS BETWEEN 13 PRECEDING AND CURRENT ROW) as avg_loss_14
    FROM
        gains_losses
),

rsi_calc AS (
    SELECT
        symbol,
        date,
        close_price,
        CASE 
            WHEN avg_loss_14 = 0 THEN 100
            ELSE 100 - (100 / (1 + (avg_gain_14 / NULLIF(avg_loss_14, 0))))
        END as rsi_14
    FROM
        avg_gains_losses
)

-- Final output with all indicators
SELECT
    m.symbol,
    m.date,
    m.close_price,
    m.volume,
    m.daily_change_pct,
    
    -- Moving Averages
    m.ma_5,
    m.ma_10,
    m.ma_20,
    m.ma_50,
    m.volume_ma_10,
    
    -- RSI
    r.rsi_14,
    
    -- Trend indicators
    CASE 
        WHEN m.close_price > m.ma_50 THEN 'ABOVE_MA50'
        ELSE 'BELOW_MA50'
    END as ma50_trend,
    
    CASE 
        WHEN m.ma_5 > m.ma_20 THEN 'BULLISH'
        ELSE 'BEARISH'
    END as ma_trend,
    
    -- Volatility (simple calculation)
    STDDEV(m.close_price) OVER(PARTITION BY m.symbol ORDER BY m.date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) as volatility_20d
FROM
    moving_avgs m
LEFT JOIN
    rsi_calc r ON m.symbol = r.symbol AND m.date = r.date