# Module 2 Homework Solutions

## Project Structure
```
.
├── README.md
├── gcp_config.yaml
├── kestra
│   └── docker-compose.yaml
├── pgadmin
│   └── docker-compose.yaml
└── postgres-taxi.yaml
```

## Links to Code
- [PostgreSQL Taxi Flow](./postgres-taxi.yaml)
- [GCP Configuration](./gcp_config.yaml)
- [Kestra Docker Setup](./kestra/docker-compose.yaml)
- [PgAdmin Docker Setup](./pgadmin/docker-compose.yaml)

## Setup
1. Used Docker Compose with services:
   - PostgreSQL
   - Kestra
   - pgAdmin
2. Configured GCP project and loaded data using Kestra flows

## Questions and Answers

### Question 1
Within the execution for `Yellow` Taxi data for the year `2020` and month `12`: what is the uncompressed file size?

**Answer**: 134.5 MB

### Question 2
What is the rendered value of the variable `file`?

**Answer**: `green_tripdata_2020-04.csv`

### Question 3
Yellow Taxi rows for 2020

**Answer**: 24,648,499

**SQL Query**:
```sql
SELECT COUNT(*) as total_rows
FROM ny_taxi.yellow_tripdata_2020;
```

### Question 4
Green Taxi rows for 2020

**Answer**: 1,342,034

**SQL Query**:
```sql
SELECT COUNT(*) as total_rows
FROM ny_taxi.green_tripdata_2020;
```

### Question 5
Yellow Taxi rows for March 2021

**Answer**: 1,925,152

**SQL Query**:
```sql
SELECT COUNT(*) as total_rows
FROM ny_taxi.yellow_tripdata_2021
WHERE EXTRACT(MONTH FROM pickup_datetime) = 3;
```

### Question 6
How to configure timezone to New York in Schedule trigger?

**Answer**: Add a `timezone` property set to `America/New_York` in the Schedule trigger configuration

## Implementation Steps

1. **Environment Setup**
   ```bash
   # Start Kestra environment
   cd kestra
   docker-compose up -d
   ```

2. **Data Loading**
   - Used [GCP Configuration](./gcp_config.yaml) to load data into BigQuery
   - Created dataset and tables using Kestra flows
   - Executed data loading for both taxi types

3. **Data Processing**
   - Implemented in [PostgreSQL Taxi Flow](./postgres-taxi.yaml)
   - Used staging tables for data transformation
   - Added unique IDs for deduplication

4. **Verification**
   - Used BigQuery console to run count queries
   - Validated data integrity using provided SQL queries

## Tools Used
- Kestra for workflow orchestration
- GCP (BigQuery & Cloud Storage)
- Docker for containerization
- Git for version control