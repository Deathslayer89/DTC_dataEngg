# Module 3  Solution: Data Warehouse & BigQuery

## Initial Setup & Data Loading

First, used thisPython script to load the data into my GCS bucket. You can find the script here: [loadtogcp.py](loadtogcp.py)


## Creating Tables in BigQuery

After getting the data in GCS, I created two types of tables:

1. External Table:
```sql
CREATE OR REPLACE EXTERNAL TABLE `zoomcamp-450020.ny_taxidata.yellow_taxi_external`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://dezoomcamp_hw3_2025/yellow_tripdata_2024-*.parquet']
);
```

2. Materialized Table:
```sql
CREATE OR REPLACE TABLE `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized` AS
SELECT * FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_external`;
```

## Solving the Questions

### Question 1: Total Records
I ran a simple count:
```sql
SELECT COUNT(*) FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`;
```
Got **20,332,093** records. 

### Question 2: Comparing Data Processing
Ran the same query on both tables:
```sql
-- On both tables:
SELECT COUNT(DISTINCT PULocationID)
FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_external`;

SELECT COUNT(DISTINCT PULocationID)
FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`;
```
The results showed **0 MB for External Table and 155.12 MB for Materialized Table**. The external table reads less because it's optimized for Parquet format.

### Question 3: Column Reading Test
I tried selecting one column vs two columns:
```sql
-- First tried one column:
SELECT PULocationID 
FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`;

-- Then two columns:
SELECT PULocationID, DOLocationID
FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`;
```
Found out that BigQuery reads more data with two columns because it's a columnar database - each column is stored separately.

### Question 4: Zero Fare Count
```sql
SELECT COUNT(*) 
FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`
WHERE fare_amount = 0;
```
Found **8,333** records with zero fare.

### Question 5: Table Optimization
Created an optimized table:
```sql
CREATE OR REPLACE TABLE `zoomcamp-450020.ny_taxidata.yellow_taxi_optimized`
PARTITION BY DATE(tpep_dropoff_datetime)
CLUSTER BY VendorID AS
SELECT * FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`;
```
Chose to **Partition by tpep_dropoff_datetime and Cluster on VendorID** because this matches our query patterns best.

### Question 6: Testing the Optimization
Ran comparison queries:
```sql
-- On regular table:
SELECT DISTINCT VendorID
FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`
WHERE tpep_dropoff_datetime BETWEEN '2024-03-01' AND '2024-03-15';

-- On optimized table:
SELECT DISTINCT VendorID
FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_optimized`
WHERE tpep_dropoff_datetime BETWEEN '2024-03-01' AND '2024-03-15';
```
Results: **310.24 MB for non-partitioned vs 26.84 MB for partitioned**. Big improvement!

### Question 7: External Table Storage
The external table data is stored in **GCP Bucket**. Makes sense because external tables just point to where the data lives.

### Question 8: Clustering Best Practice
The answer is **False** - we shouldn't always cluster tables. It depends on your use case and can sometimes add unnecessary overhead.

### Question 9: The Zero Bytes Mystery
When I ran:
```sql
SELECT COUNT(*) FROM `zoomcamp-450020.ny_taxidata.yellow_taxi_materialized`;
```
It showed 0 bytes processed! This is because I believe BigQuery keeps track of the row count in table metadata, so it doesn't need to scan the data.
