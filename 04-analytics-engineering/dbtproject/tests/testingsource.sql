SELECT year, count(*) as record_count
FROM {{ ref('fact_trips') }}
GROUP BY year
ORDER BY year