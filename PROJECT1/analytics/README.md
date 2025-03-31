# Stock Market Analytics Layer

This component implements the analytics layer for the Fortune 500 stock market data pipeline, combining Airflow for orchestration and DBT for data transformation.

## Architecture

```
Batch Processing (PySpark) ────┐
                               │
                               ▼
                         BigQuery Raw Data
                               │
                               ▼
Streaming Pipeline (Kafka) ────┘
                               │
                               │    ┌─────── Orchestrated by Airflow ───────┐
                               │    │                                       │
                               ▼    ▼                                       │
                          DBT Transformations                               │
                               │                                            │
                               ▼                                            │
                        Analytics Models ◄───────────────────────────────────┘
                               │
                               ▼
                        Looker Studio Dashboards
```

## Components

### 1. DBT Models

The DBT project transforms raw stock data into analytics-ready models:

- **Staging Models**:
  - `stg_daily_prices`: Cleans and standardizes batch-processed historical data
  - `stg_realtime_prices`: Processes streaming data from Kafka

- **Intermediate Models**:
  - `int_daily_aggregates`: Combines batch and streaming data into a unified daily view
  - `int_technical_indicators`: Calculates technical indicators (moving averages, RSI, etc.)

- **Mart Models**:
  - `mart_stock_performance`: Stock-level performance metrics and trading signals
  - `mart_sector_analysis`: Sector-level aggregations and market comparisons

### 2. Airflow DAGs

- **stock_analytics_dag.py**: Orchestrates the entire analytics pipeline:
  1. Triggers daily batch processing for latest stock data
  2. Runs data quality checks on raw data
  3. Executes DBT transformations
  4. Generates documentation
  5. Validates final mart tables

## Setup Instructions

### Prerequisites

1. Google Cloud Platform account with:
   - BigQuery access
   - Dataproc cluster for batch processing
   - Service account with appropriate permissions

2. Local development environment with:
   - Python 3.8+
   - DBT Core installed
   - Airflow 2.5+ installed

### Installation

1. **Set up DBT**:
   ```bash
   cd analytics/dbt
   pip install dbt-bigquery
   dbt deps
   ```

2. **Configure Airflow**:
   ```bash
   cd analytics/airflow
   pip install apache-airflow[gcp]
   export AIRFLOW_HOME=$(pwd)
   airflow db init
   ```

3. **Create BigQuery Datasets**:
   ```bash
   bq mk --dataset zoomcamp-454918:dbt_analytics
   ```

## Usage

### Running DBT Models Manually

```bash
cd analytics/dbt
dbt run --profiles-dir .
```

### Testing DBT Models

```bash
cd analytics/dbt
dbt test
```

### Starting Airflow

```bash
cd analytics/airflow
airflow webserver -p 8080
airflow scheduler
```

## Data Flow

1. **Historical Data**: 
   - Batch processed daily via PySpark
   - Stored in `stock_data.daily_prices`

2. **Real-time Data**:
   - Streamed via Kafka every 60 seconds
   - Stored in `stock_market_analytics.realtime_stock_prices`

3. **Unified View**:
   - Combined in `int_daily_aggregates` (implemented as a view)
   - Technical indicators added in `int_technical_indicators` (implemented as a view)

4. **Analytics Models**:
   - Performance metrics in `mart_stock_performance` (implemented as a time-partitioned table)
   - Sector analysis in `mart_sector_analysis` (implemented as a time-partitioned table)

## View Update Mechanism

### Views vs Tables in Our Implementation

- **Staging and Intermediate Models (Views)**:
  - Implemented as BigQuery views (not tables)
  - Views are SQL queries that don't store data themselves
  - When the Airflow DAG runs, it updates the SQL definition of these views
  - No new views are created each day; the same views are updated to reflect the latest transformations
  - Views always query the latest data from the underlying tables

- **Mart Models (Time-Partitioned Tables)**:
  - Implemented as BigQuery time-partitioned tables
  - Store actual transformed data partitioned by date
  - When the Airflow DAG runs, it adds new data to these tables for the latest date partition
  - Historical data remains unchanged; only new data is added

### Resource Efficiency

- Views don't consume storage space (they're just stored queries)
- Partitioned tables minimize query costs by only scanning relevant date partitions
- The pipeline only processes and stores new data each day, not reprocessing historical data
- Scheduled to run at off-peak hours (1 AM) to minimize resource contention

## Next Steps

1. Implement a seed file for proper sector mapping
2. Add more sophisticated technical indicators
3. Create anomaly detection models
4. Set up Looker Studio dashboards
5. Implement alerting for significant market movements
