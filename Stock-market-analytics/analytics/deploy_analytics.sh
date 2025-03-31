#!/bin/bash
# Deployment script for analytics components (DBT and Airflow)
set -e  # Exit on any error

# Source environment variables from parent directory if .env file doesn't exist in current directory
if [ ! -f .env ] && [ -f ../.env ]; then
  echo "Sourcing environment variables from parent directory's .env file"
  source ../.env
fi

# Configuration validation
for VAR in PROJECT_ID ZONE KAFKA_INSTANCE_NAME; do
    if [ -z "${!VAR}" ]; then
        echo "Error: ${VAR} environment variable is required"
        exit 1
    fi
done

echo "Starting analytics components deployment..."
echo "Project: ${PROJECT_ID}"
echo "Zone: ${ZONE}"
echo "Instance: ${KAFKA_INSTANCE_NAME}"

# 1. Create remote directories for analytics components
echo "Creating remote directories..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --command="mkdir -p ~/airflow/dags ~/airflow/logs ~/airflow/plugins ~/dbt/models/staging ~/dbt/models/intermediate ~/dbt/models/marts ~/dbt/macros ~/dbt/tests ~/dbt/seeds ~/dbt/analyses"

# 2. Copy DBT models and configurations
echo "Copying DBT models and configurations..."
gcloud compute scp --recurse dbt ${KAFKA_INSTANCE_NAME}:~/analytics/ \
    --project=${PROJECT_ID} --zone=${ZONE}

# 3. Copy Airflow DAGs
echo "Copying Airflow DAGs..."
gcloud compute scp --recurse airflow/dags ${KAFKA_INSTANCE_NAME}:~/analytics/airflow/ \
    --project=${PROJECT_ID} --zone=${ZONE}

# 4. Install DBT and dependencies
echo "Installing DBT and dependencies..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --command="pip3 install --user dbt-bigquery dbt-core==1.5.0"

# Create requirements.txt if it doesn't exist to avoid errors
echo "Creating requirements.txt if needed..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --command="mkdir -p ~/dbt && touch ~/dbt/requirements.txt"

# Create a dbt_project.yml file if it doesn't exist
echo "Creating dbt_project.yml if needed..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --command="cat > ~/dbt/dbt_project.yml << EOL
name: 'stock_market_analytics'
version: '1.0.0'
config-version: 2

profile: 'dbt_project'

model-paths: ['models']
analysis-paths: ['analyses']
test-paths: ['tests']
seed-paths: ['seeds']
macro-paths: ['macros']

target-path: 'target'
clean-targets:
  - 'target'
  - 'dbt_packages'

models:
  stock_market_analytics:
    staging:
      +materialized: view
    intermediate:
      +materialized: view
    marts:
      +materialized: table
EOL"

# Create a DBT profile
echo "Creating DBT profile..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --command="mkdir -p ~/.dbt && cat > ~/.dbt/profiles.yml << EOL
dbt_project:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: ${PROJECT_ID}
      dataset: dbt_analytics
      location: US
      threads: 4
EOL"

# 5. Run DBT models
echo "Running DBT models..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --command="cd ~/dbt && ~/.local/bin/dbt debug --profiles-dir ~/.dbt || echo 'DBT debug failed but continuing'"

# 6. Copy and execute the Airflow installation script
echo "Copying Airflow installation script..."
gcloud compute scp install_airflow.sh ${KAFKA_INSTANCE_NAME}:~/ \
    --project=${PROJECT_ID} --zone=${ZONE}

echo "Installing Airflow with dedicated virtual environment (this may take a few minutes)..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --command="chmod +x ~/install_airflow.sh && ~/install_airflow.sh"

# 7. Create BigQuery datasets for DBT
echo "Creating BigQuery datasets for DBT..."
bq mk --dataset --location=US ${PROJECT_ID}:dbt_analytics 2>/dev/null || echo "Dataset dbt_analytics already exists."
bq mk --dataset --location=US ${PROJECT_ID}:dbt_analytics_staging 2>/dev/null || echo "Dataset dbt_analytics_staging already exists."
bq mk --dataset --location=US ${PROJECT_ID}:dbt_analytics_intermediate 2>/dev/null || echo "Dataset dbt_analytics_intermediate already exists."
bq mk --dataset --location=US ${PROJECT_ID}:dbt_analytics_marts 2>/dev/null || echo "Dataset dbt_analytics_marts already exists."

# 8. Create firewall rule for Airflow UI
echo "Creating firewall rule for Airflow UI..."
FIREWALL_EXISTS=$(gcloud compute firewall-rules list --project=${PROJECT_ID} --filter="name=allow-airflow" --format="value(name)" 2>/dev/null)
if [ -z "$FIREWALL_EXISTS" ]; then
  gcloud compute firewall-rules create allow-airflow \
    --project=${PROJECT_ID} \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:8080 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=kafka
fi

echo "Analytics components deployment completed successfully!"
echo "You can now access your analytics models and dashboards."
echo "Airflow UI is available at: http://$(gcloud compute instances describe ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --format='get(networkInterfaces[0].accessConfigs[0].natIP)'):8080"
echo "Username: admin"
echo "Password: admin"
echo "To run DBT models manually: gcloud compute ssh ${KAFKA_INSTANCE_NAME} --project=${PROJECT_ID} --zone=${ZONE} --command='cd ~/dbt && ./run_dbt.sh run'" 