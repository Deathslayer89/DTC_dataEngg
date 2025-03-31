#!/bin/bash
# Consolidated deployment script for analytics environment
set -e

# Check for required environment variables
if [ -z "$INSTANCE_NAME" ]; then
    echo "Error: INSTANCE_NAME environment variable is required"
    exit 1
fi

if [ -z "$ZONE" ]; then
    echo "Error: ZONE environment variable is required"
    exit 1
fi

if [ -z "$PROJECT_ID" ]; then
    echo "Error: PROJECT_ID environment variable is required"
    exit 1
fi

if [ -z "$DATASET_ID" ]; then
    echo "Error: DATASET_ID environment variable is required"
    exit 1
fi

# Use environment variables with defaults
LOCAL_REPO_PATH=${LOCAL_REPO_PATH:-"/home/dinesh/Programming/project1"}
LOCAL_ANALYTICS_PATH=${LOCAL_ANALYTICS_PATH:-"${LOCAL_REPO_PATH}/analytics"}
LOCAL_DBT_PATH=${LOCAL_DBT_PATH:-"${LOCAL_ANALYTICS_PATH}/dbt"}
LOCAL_AIRFLOW_PATH=${LOCAL_AIRFLOW_PATH:-"${LOCAL_ANALYTICS_PATH}/airflow"}
REMOTE_BASE_PATH=${REMOTE_BASE_PATH:-"/home/dinesh/analytics"}
AIRFLOW_DB_USER=${AIRFLOW_DB_USER:-"airflow"}
AIRFLOW_DB_PASSWORD=${AIRFLOW_DB_PASSWORD:-"airflow"}
AIRFLOW_DB_NAME=${AIRFLOW_DB_NAME:-"airflow"}

echo "Starting analytics deployment..."
echo "Instance: ${INSTANCE_NAME}"
echo "Zone: ${ZONE}"
echo "Project: ${PROJECT_ID}"
echo "Dataset: ${DATASET_ID}"
echo "Local Repo Path: ${LOCAL_REPO_PATH}"
echo "Local Analytics Path: ${LOCAL_ANALYTICS_PATH}"
echo "Local DBT Path: ${LOCAL_DBT_PATH}"
echo "Local Airflow Path: ${LOCAL_AIRFLOW_PATH}"
echo "Remote Base Path: ${REMOTE_BASE_PATH}"

# Create a temporary directory for deployment files
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: ${TEMP_DIR}"

# Create setup script for the remote instance
cat > ${TEMP_DIR}/setup_remote.sh << 'EOF'
#!/bin/bash
set -e

# Base directory for analytics
ANALYTICS_DIR="$HOME/analytics"
mkdir -p $ANALYTICS_DIR
cd $ANALYTICS_DIR

# Create directories
mkdir -p dbt airflow/dags scripts

# Install necessary packages
echo "Installing required system packages..."
sudo apt-get update
sudo apt-get install -y python3-venv python3-dev postgresql postgresql-contrib libpq-dev

# Set up PostgreSQL
echo "Setting up PostgreSQL database for Airflow..."
sudo -u postgres psql -c "CREATE DATABASE ${AIRFLOW_DB_NAME};"
sudo -u postgres psql -c "CREATE USER ${AIRFLOW_DB_USER} WITH PASSWORD '${AIRFLOW_DB_PASSWORD}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${AIRFLOW_DB_NAME} TO ${AIRFLOW_DB_USER};"

# Create Python virtual environment
echo "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip

# Install dependencies with specific versions to avoid compatibility issues
echo "Installing Python dependencies..."
pip install markupsafe==2.0.1
pip install sqlalchemy==1.4.46
pip install flask==2.2.3
pip install werkzeug==2.2.3
pip install alembic==1.10.2
pip install jinja2==3.1.2
pip install importlib-metadata==6.0.0
pip install numpy==1.24.3
pip install protobuf==3.20.3
pip install apache-airflow==2.5.3 --no-deps
pip install apache-airflow-providers-google==10.0.0 --no-deps
pip install google-cloud-bigquery==3.11.4
pip install dbt-bigquery==1.5.0 --no-deps
pip install google-cloud-storage==2.8.0
pip install psycopg2-binary

# Set up Airflow home
export AIRFLOW_HOME=$ANALYTICS_DIR/airflow
echo "export AIRFLOW_HOME=$ANALYTICS_DIR/airflow" >> $HOME/.bashrc

# Create a minimal airflow.cfg to reduce resource usage
cat > $AIRFLOW_HOME/airflow.cfg << EOC
[core]
dags_folder = $AIRFLOW_HOME/dags
load_examples = False
executor = LocalExecutor
max_active_runs_per_dag = 1

[database]
sql_alchemy_conn = postgresql+psycopg2://${AIRFLOW_DB_USER}:${AIRFLOW_DB_PASSWORD}@localhost/${AIRFLOW_DB_NAME}
sql_alchemy_pool_size = 5
sql_alchemy_max_overflow = 10
sql_alchemy_pool_recycle = 1800

[scheduler]
min_file_process_interval = 60
dag_dir_list_interval = 60
print_stats_interval = 30
scheduler_heartbeat_sec = 10
max_threads = 2

[webserver]
web_server_worker_timeout = 120
workers = 2
worker_refresh_batch_size = 1
worker_refresh_interval = 30
EOC

# Initialize Airflow database
airflow db init

# Create Airflow user
airflow users create \
  --username admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com \
  --password admin

# Create systemd service files
mkdir -p $HOME/.config/systemd/user/

# Webserver service
cat > $HOME/.config/systemd/user/airflow-webserver.service << EOC
[Unit]
Description=Airflow webserver
After=network.target postgresql.service

[Service]
Environment=AIRFLOW_HOME=$ANALYTICS_DIR/airflow
Type=simple
ExecStart=$ANALYTICS_DIR/venv/bin/airflow webserver --port 8080
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOC

# Scheduler service
cat > $HOME/.config/systemd/user/airflow-scheduler.service << EOC
[Unit]
Description=Airflow scheduler
After=network.target postgresql.service

[Service]
Environment=AIRFLOW_HOME=$ANALYTICS_DIR/airflow
Type=simple
ExecStart=$ANALYTICS_DIR/venv/bin/airflow scheduler
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOC

# Enable and start services
systemctl --user daemon-reload
systemctl --user enable airflow-webserver.service
systemctl --user enable airflow-scheduler.service
systemctl --user start airflow-webserver.service
systemctl --user start airflow-scheduler.service

echo "Airflow setup complete!"
EOF

# Make the script executable
chmod +x ${TEMP_DIR}/setup_remote.sh

# Copy the setup script to the instance
echo "Copying setup script to the instance..."
gcloud compute scp ${TEMP_DIR}/setup_remote.sh ${INSTANCE_NAME}:~/ --zone=${ZONE}

# Execute the setup script on the instance
echo "Running setup script on the instance..."
gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --command="bash ~/setup_remote.sh"

# Modify the DAG file to use the correct paths
echo "Preparing DAG file with correct paths..."
cp ${LOCAL_AIRFLOW_PATH}/dags/stock_analytics_dag.py ${TEMP_DIR}/
sed -i "s|/home/dinesh/Programming/project1/analytics/dbt|/home/dinesh/analytics/dbt|g" ${TEMP_DIR}/stock_analytics_dag.py

# Copy the modified DAG file to the instance
echo "Copying DAG file to the instance..."
gcloud compute scp ${TEMP_DIR}/stock_analytics_dag.py ${INSTANCE_NAME}:~/analytics/airflow/dags/ --zone=${ZONE}

# Copy the DBT project to the instance
echo "Copying DBT project to the instance..."
gcloud compute scp --recurse ${LOCAL_DBT_PATH}/* ${INSTANCE_NAME}:~/analytics/dbt/ --zone=${ZONE}

# Create profiles.yml for DBT
cat > ${TEMP_DIR}/profiles.yml << EOF
stock_market_analytics:
  target: prod
  outputs:
    prod:
      type: bigquery
      method: oauth
      project: ${PROJECT_ID}
      dataset: dbt_analytics
      threads: 4
      timeout_seconds: 300
      location: US
      priority: interactive
EOF

# Copy profiles.yml to the instance
echo "Copying DBT profiles to the instance..."
gcloud compute scp ${TEMP_DIR}/profiles.yml ${INSTANCE_NAME}:~/analytics/dbt/ --zone=${ZONE}

# Copy the dataset analysis script
echo "Copying dataset analysis script..."
gcloud compute scp ${LOCAL_ANALYTICS_PATH}/scripts/analyze_datasets.py ${INSTANCE_NAME}:~/analytics/scripts/ --zone=${ZONE}

# Clean up temporary directory
rm -rf ${TEMP_DIR}

echo "Deployment complete!"
echo "Airflow UI should be available at http://$(gcloud compute instances describe ${INSTANCE_NAME} --zone=${ZONE} --format='get(networkInterfaces[0].accessConfigs[0].natIP)'):8080"
echo "Username: admin"
echo "Password: admin" 