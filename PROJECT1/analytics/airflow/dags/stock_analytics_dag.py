"""
Stock Market Analytics DAG
--------------------------
This DAG orchestrates the entire analytics pipeline:
1. Triggers daily batch processing for historical data
2. Runs DBT transformations on the data
3. Performs data quality checks
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.providers.google.cloud.operators.dataproc import (
    DataprocSubmitJobOperator,
)
from airflow.providers.google.cloud.hooks.bigquery import BigQueryHook
from airflow.models import Variable

# Default arguments
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define the DAG
dag = DAG(
    'stock_market_analytics',
    default_args=default_args,
    description='Stock Market Analytics Pipeline',
    schedule_interval='0 1,13 * * *',  # Run at 1 AM and 1 PM every day
    start_date=datetime(2025, 3, 28),
    catchup=False,
    tags=['stock', 'analytics', 'dbt'],
)

# Define GCP parameters
GCP_PROJECT = 'stockmarket-455214'
GCP_REGION = 'us-central1'
DATAPROC_CLUSTER = 'fortune500-cluster'
GCS_BUCKET = 'stock-market-raw-dev'
GCS_TEMP_BUCKET = 'stock-market-raw-dev'

# Define DBT parameters
DBT_PROJECT_DIR = '/home/dinesh/analytics/dbt'
DBT_PROFILES_DIR = '/home/dinesh/analytics/dbt'
DBT_TARGET = 'dev'

# 1. Run daily batch processing to fetch latest stock data
pyspark_job = {
    "reference": {"project_id": GCP_PROJECT},
    "placement": {"cluster_name": DATAPROC_CLUSTER},
    "pyspark_job": {
        "main_python_file_uri": f"gs://{GCS_BUCKET}/src/batch/run_processor.py",
        "jar_file_uris": ["gs://spark-lib/bigquery/spark-bigquery-latest_2.12.jar"],
        "properties": {
            "spark.jars.packages": "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.30.0"
        },
        "args": [
            "--project_id", GCP_PROJECT,
            "--mode", "daily"  # Add a mode parameter to only fetch the latest day's data
        ]
    },
}

run_batch_job = DataprocSubmitJobOperator(
    task_id='run_daily_batch_job',
    project_id=GCP_PROJECT,
    region=GCP_REGION,
    job=pyspark_job,
    dag=dag,
)

# 2. Check if batch job completed successfully and data exists
def check_batch_data_exists(**kwargs):
    """Check if the batch data for today exists in BigQuery"""
    bq_hook = BigQueryHook(gcp_conn_id='google_cloud_default')
    today = datetime.now().strftime('%Y-%m-%d')
    
    query = f"""
    SELECT COUNT(*) as count
    FROM `{GCP_PROJECT}.stock_market_analytics.daily_prices`
    WHERE Date = '{today}'
    """
    
    result = bq_hook.get_pandas_df(query)
    count = result['count'].iloc[0]
    
    if count == 0:
        raise ValueError(f"No batch data found for {today}")
    
    return count

check_batch_data = PythonOperator(
    task_id='check_batch_data',
    python_callable=check_batch_data_exists,
    dag=dag,
)

# 3. Run DBT models in stages for better resource usage
# Stage 1: Run staging models
run_dbt_staging = BashOperator(
    task_id='run_dbt_staging',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET} --select staging',
    dag=dag,
)

# Stage 2: Run intermediate models
run_dbt_intermediate = BashOperator(
    task_id='run_dbt_intermediate',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET} --select intermediate',
    dag=dag,
)

# Stage 3: Run mart models
run_dbt_marts = BashOperator(
    task_id='run_dbt_marts',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET} --select marts',
    dag=dag,
)

# 4. Run DBT tests
run_dbt_tests = BashOperator(
    task_id='run_dbt_tests',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt test --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET}',
    dag=dag,
)

# 5. Generate DBT documentation
generate_dbt_docs = BashOperator(
    task_id='generate_dbt_docs',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt docs generate --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET}',
    dag=dag,
)

# 6. Check data quality in final marts
def check_data_quality(**kwargs):
    """Run basic data quality checks on the final mart tables"""
    bq_hook = BigQueryHook(gcp_conn_id='google_cloud_default')
    today = datetime.now().strftime('%Y-%m-%d')
    
    # Check if mart_stock_performance has data for today
    performance_query = f"""
    SELECT COUNT(*) as count
    FROM `{GCP_PROJECT}.dbt_analytics.mart_stock_performance`
    WHERE date = '{today}'
    """
    
    performance_result = bq_hook.get_pandas_df(performance_query)
    performance_count = performance_result['count'].iloc[0]
    
    # Check if mart_sector_analysis has data for today
    sector_query = f"""
    SELECT COUNT(*) as count
    FROM `{GCP_PROJECT}.dbt_analytics.mart_sector_analysis`
    WHERE date = '{today}'
    """
    
    sector_result = bq_hook.get_pandas_df(sector_query)
    sector_count = sector_result['count'].iloc[0]
    
    if performance_count == 0 or sector_count == 0:
        raise ValueError(f"Data quality check failed: Missing data for {today}")
    
    return f"Data quality check passed: {performance_count} performance records, {sector_count} sector records"

check_mart_data = PythonOperator(
    task_id='check_mart_data',
    python_callable=check_data_quality,
    dag=dag,
)

# Define task dependencies with staged DBT runs for better resource usage
run_batch_job >> check_batch_data >> run_dbt_staging >> run_dbt_intermediate >> run_dbt_marts >> run_dbt_tests >> generate_dbt_docs >> check_mart_data
