# NYC Taxi Data Analysis - Module 1 Homework

Solutions for Module 1 homework of the #DEZoomcamp Data Engineering Zoomcamp. Code and queries available in the repository: [ingest_data.py](./ingest_data.py), [docker-compose.yaml](./docker-compose.yaml)

## Question 1: Understanding Docker First Run

Ran Python Docker image to check pip version:
```bash
docker run -it --entrypoint=bash python:3.12.8 -c "pip --version"
```

Answer: 24.3.1

## Question 2: Docker Networking

From the [docker-compose.yaml](./docker-compose.yaml), when connecting to Postgres from pgAdmin:
- Host: `db` (service name)
- Port: `5432` (internal port)

Answer: `db:5432`

## Question 3: Trip Segmentation Count

First, I wrote a Python script [ingest_data.py](./ingest_data.py) to load the data into PostgreSQL:

```python
import pandas as pd
from sqlalchemy import create_engine

# Create PostgreSQL connection
engine = create_engine('postgresql://postgres:postgres@localhost:5433/ny_taxi')

# Read and ingest taxi zone lookup data
df_zones = pd.read_csv('data/taxi_zone_lookup.csv')
df_zones.to_sql('taxi_zone_lookup', engine, if_exists='replace', index=False)

# Read and ingest trip data
df_trips = pd.read_csv('data/green_tripdata_2019-10.csv')
df_trips.to_sql('green_taxi_trips', engine, if_exists='replace', index=False)
```

Then I used this query to analyze trip distances:
```sql
SELECT 
    COUNT(CASE WHEN trip_distance <= 1 THEN 1 END) as upto_1_mile,
    COUNT(CASE WHEN trip_distance > 1 AND trip_distance <= 3 THEN 1 END) as from_1_to_3_miles,
    COUNT(CASE WHEN trip_distance > 3 AND trip_distance <= 7 THEN 1 END) as from_3_to_7_miles,
    COUNT(CASE WHEN trip_distance > 7 AND trip_distance <= 10 THEN 1 END) as from_7_to_10_miles,
    COUNT(CASE WHEN trip_distance > 10 THEN 1 END) as over_10_miles
FROM green_taxi_trips
WHERE lpep_pickup_datetime >= '2019-10-01' 
    AND lpep_pickup_datetime < '2019-11-01'
    AND lpep_dropoff_datetime < '2019-11-01';
```

Answer: 104,802; 198,924; 109,603; 27,678; 35,189

## Question 4: Longest Trip for Each Day

Looking for the pickup day with the longest trip distance:
```sql
SELECT 
    DATE(lpep_pickup_datetime) as pickup_day,
    MAX(trip_distance) as max_distance
FROM 
    green_taxi_trips
WHERE 
    EXTRACT(MONTH FROM lpep_pickup_datetime) = 10
    AND EXTRACT(YEAR FROM lpep_pickup_datetime) = 2019
GROUP BY 
    DATE(lpep_pickup_datetime)
ORDER BY 
    max_distance DESC
LIMIT 1;
```

Answer: 2019-10-31

## Question 5: Three Biggest Pickup Zones

Finding top pickup zones by total amount:
```sql
SELECT 
    zpu."Zone" as pickup_zone,
    SUM(gt.total_amount) as total_amount
FROM 
    green_taxi_trips gt
    JOIN taxi_zone_lookup zpu ON gt."PULocationID" = zpu."LocationID"
WHERE 
    DATE(lpep_pickup_datetime) = '2019-10-18'
GROUP BY 
    zpu."Zone"
HAVING 
    SUM(gt.total_amount) > 13000
ORDER BY 
    total_amount DESC;
```

Answer: East Harlem North, East Harlem South, Morningside Heights

## Question 6: Largest Tip

Finding drop-off zone with largest tip from East Harlem North:
```sql
SELECT 
    zdo."Zone" as dropoff_zone,
    MAX(gt.tip_amount) as max_tip
FROM 
    green_taxi_trips gt
    JOIN taxi_zone_lookup zpu ON gt."PULocationID" = zpu."LocationID"
    JOIN taxi_zone_lookup zdo ON gt."DOLocationID" = zdo."LocationID"
WHERE 
    zpu."Zone" = 'East Harlem North'
    AND EXTRACT(MONTH FROM lpep_pickup_datetime) = 10
    AND EXTRACT(YEAR FROM lpep_pickup_datetime) = 2019
GROUP BY 
    zdo."Zone"
ORDER BY 
    max_tip DESC
LIMIT 1;
```

Answer: JFK Airport

## Question 7: Terraform Workflow

The correct sequence for:
1. Downloading provider plugins and setting up backend
2. Generating proposed changes and auto-executing the plan
3. Removing all resources managed by terraform

Answer: `terraform init, terraform apply -auto-approve, terraform destroy`

You can find my Terraform configuration in the [terraform](./terraform) directory:

- [main.tf](./terraform/main.tf) - Main Terraform configuration file that sets up:
  - Google Cloud Storage bucket for data lake
  - BigQuery dataset for analytics
- [variables.tf](./terraform/variables.tf) - Variable definitions
- [terraform.tfvars](./terraform/terraform.tfvars) - Variable values
