

  create or replace view `stockmarket-455214`.`dbt_analytics_staging`.`stg_daily_prices`
  OPTIONS()
  as 

WITH source_data AS (
    SELECT
        Symbol,
        Date,
        Open,
        High,
        Low,
        Close,
        Volume
    FROM
        `stockmarket-455214.stock_market_analytics.daily_prices`
)

SELECT
    Symbol as symbol,
    Date as date,
    Open as open_price,
    High as high_price,
    Low as low_price,
    Close as close_price,
    Volume as volume,
    (Close - Open) as daily_change,
    ((Close - Open) / Open) * 100 as daily_change_pct
FROM
    source_data;

