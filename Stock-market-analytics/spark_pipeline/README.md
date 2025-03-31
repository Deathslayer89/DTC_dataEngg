# Fortune 500 Stock Data Pipeline

This project implements a data pipeline for collecting and analyzing historical stock data for Fortune 500 companies using Apache Spark and Google Cloud Platform.

## How the Pipeline Works

### Architecture Overview
```
[Yahoo Finance API] → [Dataproc (PySpark)] → [BigQuery]
     Data Source      Processing Layer    Storage Layer
```

### Pipeline Steps

1. **Data Source Setup**
   - Fortune 500 company symbols are stored in `data/fortune500.csv`
   - Each symbol is used to query Yahoo Finance API via yfinance library
   - Rate limiting (60 requests/minute) is implemented to respect API constraints

2. **Data Collection Process**
   - Companies are processed in batches of 10 to manage API load
   - For each company:
     a. Create YFinance Ticker object
     b. Fetch historical data using `history()` method
     c. Convert timestamps to dates
     d. Extract OHLCV (Open, High, Low, Close, Volume) data
   - Intelligent duplicate prevention checks existing data ranges

3. **Data Processing (PySpark)**
   - Spark job runs on Google Cloud Dataproc cluster
   - Schema enforcement:
     ```python
     StructType([
         StructField("Symbol", StringType(), True),
         StructField("Date", DateType(), True),
         StructField("Open", DoubleType(), True),
         StructField("High", DoubleType(), True),
         StructField("Low", DoubleType(), True),
         StructField("Close", DoubleType(), True),
         StructField("Volume", DoubleType(), True)
     ])
     ```
   - Data type conversions and validations
   - Batch processing with error handling

4. **Data Storage**
   - Processed data is written to BigQuery table
   - Table: `stock_data.daily_prices`
   - Supports both overwrite and append modes
   - Current size: 749,391 rows spanning 4 years

5. **Error Handling**
   - Individual stock failures don't stop the pipeline
   - Rate limit handling with time.sleep()
   - Exception logging for debugging
   - Data validation before BigQuery insertion

6. **Execution Modes**
   - Synchronous: Waits for job completion
   - Asynchronous: Runs in background (--async flag)
   - Supports both initial load and incremental updates

## Project Structure

```
spark_pipeline/
├── data/
│   └── fortune500.csv         # List of Fortune 500 company stock symbols
├── src/
│   └── batch/
│       ├── run_processor.py   # Initial 2-year data collection
│       └── run_processor_4y.py # Extended 4-year data collection
├── init-action.sh            # Dataproc cluster initialization script
├── setup.py                  # Python package configuration
└── requirements.txt          # Python dependencies
```

## Features

### 1. Historical Data Collection
- Fetches 4 years of daily stock data for all Fortune 500 companies
- Uses Yahoo Finance API through yfinance library
- Implements rate limiting and error handling
- Processes companies in batches of 10 to respect API limits
- Intelligent duplicate prevention by checking existing data ranges

### 2. Data Processing
- Uses Apache Spark on Google Cloud Dataproc
- Converts raw data into structured format
- Handles data type conversions and validations
- Implements efficient batch processing
- Supports asynchronous job execution

### 3. Data Storage
- Stores data in Google BigQuery
- Schema:
  - Symbol (STRING)
  - Date (DATE)
  - Open (FLOAT64)
  - High (FLOAT64)
  - Low (FLOAT64)
  - Close (FLOAT64)
  - Volume (FLOAT64)

## Current Status
- Successfully collected 749,391 rows of daily stock data
- Covers 501 Fortune 500 companies
- Data spans 4 years (2021-03-29 to 2025-03-27)
- All data is stored in BigQuery table: `stock_data.daily_prices`

## Usage

1. Upload code to GCS:
```bash
gsutil cp src/batch/run_processor_4y.py gs://stock-market-raw-dev/src/batch/
```

2. Submit Spark job (async mode):
```bash
gcloud dataproc jobs submit pyspark \
    --cluster=fortune500-cluster \
    --region=us-central1 \
    --async \
    gs://stock-market-raw-dev/src/batch/run_processor_4y.py \
    --jars=gs://spark-lib/bigquery/spark-bigquery-latest_2.12.jar \
    --properties="spark.jars.packages=com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.30.0" \
    -- --project_id=zoomcamp-454918
```

3. Monitor job status:
```bash
gcloud dataproc jobs list --region=us-central1 --state-filter=active,pending
```

## Next Steps
1. Implement data quality checks
2. Add data transformation pipeline
3. Create visualization dashboard
4. Set up automated daily updates after historical data fetching
   - Schedule daily batch job to fetch previous day's data
   - Implement incremental loading strategy
   - Configure appropriate retry mechanisms
   - Integrate with monitoring system
