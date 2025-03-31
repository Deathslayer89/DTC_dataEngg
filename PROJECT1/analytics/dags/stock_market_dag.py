from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.google.cloud.operators.dataproc import DataprocSubmitJobOperator
from airflow.providers.google.cloud.operators.bigquery import BigQueryOperator
from airflow.providers.google.cloud.sensors.bigquery import BigQueryTableExistenceSensor
from airflow.operators.python import PythonOperator
from airflow.models import Variable
import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from utils.logger import PipelineLogger

# Initialize pipeline logger
pipeline_logger = PipelineLogger(
    project_id=os.getenv('PROJECT_ID'),
    bucket_name=os.getenv('BUCKET_NAME'),
    dataset_id=os.getenv('DATASET_ID')
)

# Default arguments
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# DAG definition
dag = DAG(
    'stock_market_analytics',
    default_args=default_args,
    description='Stock market data processing pipeline',
    schedule_interval='0 0 * * *',  # Run daily at midnight
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['stock_market', 'analytics'],
)

def log_dag_start(**context):
    """Log DAG start"""
    pipeline_logger.log_batch_job(
        job_id=context['run_id'],
        component="airflow_dag",
        message="Starting stock market analytics DAG",
        metadata={
            "execution_date": context['execution_date'].isoformat(),
            "task_instance_key_str": context['task_instance_key_str']
        }
    )

def log_dag_end(**context):
    """Log DAG completion"""
    pipeline_logger.log_batch_job(
        job_id=context['run_id'],
        component="airflow_dag",
        message="Completed stock market analytics DAG",
        metadata={
            "execution_date": context['execution_date'].isoformat(),
            "task_instance_key_str": context['task_instance_key_str']
        },
        status="success"
    )

def log_task_start(**context):
    """Log task start"""
    pipeline_logger.log_batch_job(
        job_id=context['run_id'],
        component=context['task_id'],
        message=f"Starting task: {context['task_id']}",
        metadata={
            "execution_date": context['execution_date'].isoformat(),
            "task_instance_key_str": context['task_instance_key_str']
        }
    )

def log_task_end(**context):
    """Log task completion"""
    status = "success" if not context.get('task_instance').xcom_pull(key='error') else "failed"
    pipeline_logger.log_batch_job(
        job_id=context['run_id'],
        component=context['task_id'],
        message=f"Completed task: {context['task_id']}",
        metadata={
            "execution_date": context['execution_date'].isoformat(),
            "task_instance_key_str": context['task_instance_key_str']
        },
        status=status
    )

# Task definitions
start_task = PythonOperator(
    task_id='start',
    python_callable=log_dag_start,
    provide_context=True,
    dag=dag,
)

end_task = PythonOperator(
    task_id='end',
    python_callable=log_dag_end,
    provide_context=True,
    dag=dag,
)

# Check if source table exists
check_source_table = BigQueryTableExistenceSensor(
    task_id='check_source_table',
    project_id=os.getenv('PROJECT_ID'),
    dataset_id=os.getenv('DATASET_ID'),
    table_id='realtime_stock_prices',
    poke_interval=60,
    timeout=600,
    mode='reschedule',
    dag=dag,
)

# Process daily data
process_daily_data = DataprocSubmitJobOperator(
    task_id='process_daily_data',
    project_id=os.getenv('PROJECT_ID'),
    region=os.getenv('REGION'),
    job={
        'reference': {'project_id': os.getenv('PROJECT_ID')},
        'placement': {'cluster_name': os.getenv('SPARK_CLUSTER_NAME')},
        'spark_job': {
            'jar_file': 'gs://spark-lib/bigquery/spark-bigquery-latest_2.12.jar',
            'main_class': 'org.apache.spark.examples.sql.SparkSQLExample',
            'args': [
                f'--project={os.getenv("PROJECT_ID")}',
                f'--dataset={os.getenv("DATASET_ID")}',
                '--table=realtime_stock_prices',
                '--output=processed_daily_data'
            ]
        }
    },
    dag=dag,
)

# Create daily aggregations
create_daily_aggregations = BigQueryOperator(
    task_id='create_daily_aggregations',
    use_legacy_sql=False,
    write_disposition='WRITE_TRUNCATE',
    create_disposition='CREATE_IF_NEEDED',
    sql="""
    CREATE OR REPLACE TABLE `{{ project }}.{{ dataset }}.daily_aggregations` AS
    SELECT
        DATE(timestamp) as date,
        symbol,
        MIN(price) as min_price,
        MAX(price) as max_price,
        AVG(price) as avg_price,
        SUM(volume) as total_volume
    FROM `{{ project }}.{{ dataset }}.processed_daily_data`
    GROUP BY DATE(timestamp), symbol
    """,
    dag=dag,
)

# Set task dependencies
start_task >> check_source_table >> process_daily_data >> create_daily_aggregations >> end_task

# Add logging callbacks to all tasks
for task in dag.tasks:
    task.pre_execute = log_task_start
    task.post_execute = log_task_end 