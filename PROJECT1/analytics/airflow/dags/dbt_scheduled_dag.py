"""
DBT Scheduled Transformations DAG
---------------------------------
This DAG runs the DBT transformations twice a day to keep analytics data up to date.
It skips the batch processing and only runs the DBT models.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

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
    'dbt_scheduled_transformations',
    default_args=default_args,
    description='Run DBT transformations twice a day',
    schedule_interval='0 1,13 * * *',  # Run at 1 AM and 1 PM every day
    start_date=datetime(2025, 3, 28),
    catchup=False,
    tags=['dbt', 'analytics', 'transformations'],
)

# Define DBT parameters
DBT_PROJECT_DIR = '/home/dinesh/dbt'
DBT_PROFILES_DIR = '/home/dinesh/.dbt'
DBT_TARGET = 'dev'

# 1. Run DBT models in stages for better resource usage
# Stage 1: Run staging models
run_dbt_staging = BashOperator(
    task_id='run_dbt_staging',
    bash_command=f'cd {DBT_PROJECT_DIR} && ~/.local/bin/dbt run --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET} --select staging',
    dag=dag,
)

# Stage 2: Run intermediate models
run_dbt_intermediate = BashOperator(
    task_id='run_dbt_intermediate',
    bash_command=f'cd {DBT_PROJECT_DIR} && ~/.local/bin/dbt run --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET} --select intermediate',
    dag=dag,
)

# Stage 3: Run mart models
run_dbt_marts = BashOperator(
    task_id='run_dbt_marts',
    bash_command=f'cd {DBT_PROJECT_DIR} && ~/.local/bin/dbt run --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET} --select marts',
    dag=dag,
)

# 4. Run DBT tests
run_dbt_tests = BashOperator(
    task_id='run_dbt_tests',
    bash_command=f'cd {DBT_PROJECT_DIR} && ~/.local/bin/dbt test --profiles-dir {DBT_PROFILES_DIR} --target {DBT_TARGET}',
    dag=dag,
)

# Define task dependencies
run_dbt_staging >> run_dbt_intermediate >> run_dbt_marts >> run_dbt_tests 