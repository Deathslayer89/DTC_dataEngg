

WITH stock_performance AS (
    SELECT
        symbol,
        date,
        close_price,
        volume,
        daily_change_pct,
        weekly_return_pct,
        monthly_return_pct,
        quarterly_return_pct,
        yearly_return_pct,
        volatility_20d
    FROM
        `stockmarket-455214`.`dbt_analytics_marts`.`mart_stock_performance`
),

-- Simplified sector mapping (in production, you would use a proper sector mapping table)
-- This is a placeholder - in a real implementation, you would join with a sector mapping table
sector_mapping AS (
    SELECT
        symbol,
        CASE
            WHEN symbol IN ('AAPL', 'MSFT', 'GOOGL', 'GOOG', 'META', 'AMZN', 'NVDA', 'INTC', 'AMD', 'CRM') THEN 'Technology'
            WHEN symbol IN ('JPM', 'BAC', 'WFC', 'C', 'GS', 'MS', 'AXP', 'V', 'MA', 'BLK') THEN 'Financials'
            WHEN symbol IN ('JNJ', 'PFE', 'MRK', 'ABBV', 'LLY', 'BMY', 'TMO', 'ABT', 'UNH', 'AMGN') THEN 'Healthcare'
            WHEN symbol IN ('XOM', 'CVX', 'COP', 'EOG', 'SLB', 'PXD', 'OXY', 'MPC', 'PSX', 'VLO') THEN 'Energy'
            WHEN symbol IN ('PG', 'KO', 'PEP', 'WMT', 'COST', 'TGT', 'HD', 'LOW', 'MCD', 'SBUX') THEN 'Consumer'
            WHEN symbol IN ('BA', 'LMT', 'GE', 'HON', 'CAT', 'DE', 'MMM', 'UPS', 'FDX', 'RTX') THEN 'Industrials'
            ELSE 'Other'
        END as sector
    FROM
        (SELECT DISTINCT symbol FROM stock_performance)
),

-- Join performance data with sector information
sector_performance AS (
    SELECT
        s.date,
        m.sector,
        COUNT(DISTINCT s.symbol) as stock_count,
        AVG(s.close_price) as avg_price,
        SUM(s.volume) as total_volume,
        AVG(s.daily_change_pct) as avg_daily_return,
        AVG(s.weekly_return_pct) as avg_weekly_return,
        AVG(s.monthly_return_pct) as avg_monthly_return,
        AVG(s.quarterly_return_pct) as avg_quarterly_return,
        AVG(s.yearly_return_pct) as avg_yearly_return,
        AVG(s.volatility_20d) as avg_volatility
    FROM
        stock_performance s
    JOIN
        sector_mapping m ON s.symbol = m.symbol
    GROUP BY
        s.date, m.sector
),

-- Calculate market-wide metrics for comparison
market_performance AS (
    SELECT
        date,
        COUNT(DISTINCT symbol) as stock_count,
        AVG(close_price) as avg_price,
        SUM(volume) as total_volume,
        AVG(daily_change_pct) as avg_daily_return,
        AVG(weekly_return_pct) as avg_weekly_return,
        AVG(monthly_return_pct) as avg_monthly_return,
        AVG(quarterly_return_pct) as avg_quarterly_return,
        AVG(yearly_return_pct) as avg_yearly_return,
        AVG(volatility_20d) as avg_volatility
    FROM
        stock_performance
    GROUP BY
        date
)

SELECT
    sp.date,
    sp.sector,
    sp.stock_count,
    sp.avg_price,
    sp.total_volume,
    sp.avg_daily_return,
    sp.avg_weekly_return,
    sp.avg_monthly_return,
    sp.avg_quarterly_return,
    sp.avg_yearly_return,
    sp.avg_volatility,
    
    -- Compare sector performance to overall market
    sp.avg_daily_return - mp.avg_daily_return as daily_return_vs_market,
    sp.avg_weekly_return - mp.avg_weekly_return as weekly_return_vs_market,
    sp.avg_monthly_return - mp.avg_monthly_return as monthly_return_vs_market,
    sp.avg_quarterly_return - mp.avg_quarterly_return as quarterly_return_vs_market,
    sp.avg_yearly_return - mp.avg_yearly_return as yearly_return_vs_market,
    
    -- Sector strength indicators
    CASE 
        WHEN sp.avg_daily_return > mp.avg_daily_return THEN 'OUTPERFORMING'
        WHEN sp.avg_daily_return < mp.avg_daily_return THEN 'UNDERPERFORMING'
        ELSE 'NEUTRAL'
    END as daily_market_relation,
    
    CASE 
        WHEN sp.avg_monthly_return > mp.avg_monthly_return THEN 'OUTPERFORMING'
        WHEN sp.avg_monthly_return < mp.avg_monthly_return THEN 'UNDERPERFORMING'
        ELSE 'NEUTRAL'
    END as monthly_market_relation,
    
    -- Sector momentum (simple calculation)
    LAG(sp.avg_weekly_return, 1) OVER(PARTITION BY sp.sector ORDER BY sp.date) as prev_week_return,
    
    -- Sector volatility comparison
    sp.avg_volatility / NULLIF(mp.avg_volatility, 0) as relative_volatility
FROM
    sector_performance sp
JOIN
    market_performance mp ON sp.date = mp.date