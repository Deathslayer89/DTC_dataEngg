{{
    config(
        materialized='table'
    )
}}

WITH quarterly_revenue AS (
    SELECT 
        service_type,
        year,
        quarter,
        year_quarter,
        SUM(total_amount) AS revenue
    FROM {{ ref('fact_trips') }}
    WHERE year IN (2019, 2020)
    GROUP BY service_type, year, quarter, year_quarter
),
revenue_with_prior_year AS (
    SELECT 
        current_year.service_type,
        current_year.year,
        current_year.quarter,
        current_year.year_quarter,
        current_year.revenue AS current_revenue,
        prior_year.revenue AS prior_revenue
    FROM quarterly_revenue AS current_year
    LEFT JOIN quarterly_revenue AS prior_year
        ON current_year.service_type = prior_year.service_type
        AND current_year.quarter = prior_year.quarter
        AND prior_year.year = current_year.year - 1
    WHERE current_year.year = 2020
)
SELECT 
    service_type,
    year,
    quarter,
    year_quarter,
    current_revenue AS quarterly_revenue,
    prior_revenue AS prev_year_revenue,
    CASE 
        WHEN prior_revenue IS NOT NULL AND prior_revenue != 0
        THEN ROUND((current_revenue - prior_revenue) / prior_revenue * 100, 2)
        ELSE NULL 
    END AS yoy_growth_percentage
FROM revenue_with_prior_year
ORDER BY service_type, quarter