#!/bin/bash
# Unified deployment script for Stock Market Analytics Platform
# This script handles infrastructure provisioning, Kafka, streaming, batch processing, and analytics

set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}      STOCK MARKET ANALYTICS PLATFORM DEPLOYMENT       ${NC}"
echo -e "${GREEN}=======================================================${NC}"

# Load environment variables
if [ -f .env ]; then
  echo -e "${GREEN}Loading environment variables from .env file...${NC}"
  source .env
  
  # Export all variables for child scripts - using a safer method
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    if [[ ! "$line" =~ ^#.*$ ]] && [[ -n "$line" ]]; then
      # Extract variable name (everything before the first =)
      varname=$(echo "$line" | cut -d '=' -f 1)
      # Only export if it's a valid variable name
      if [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        export "$varname"
      fi
    fi
  done < .env
else
  echo -e "${RED}Error: .env file not found. Creating a template from .env.example...${NC}"
  if [ -f .env.example ]; then
    cp .env.example .env
    echo -e "${YELLOW}Created .env from template. Please edit it with your configuration and run again.${NC}"
  else
    echo -e "${RED}Error: .env.example file not found.${NC}"
    echo "Creating a basic .env file..."
    cat > .env << EOF
# Google Cloud settings
PROJECT_ID=stockmarket-455214
REGION=us-central1
ZONE=us-central1-a
BUCKET_NAME=stockmarket-455214-data
DATASET_ID=stock_market_analytics

# Deployment flags
ENABLE_TERRAFORM=true
ENABLE_BATCH=true
ENABLE_STREAMING=true
ENABLE_ANALYTICS=true

# Kafka settings
KAFKA_INSTANCE_NAME=kafka-instance

# Spark settings
SPARK_CLUSTER_NAME=stock-market-cluster

# Analytics settings
AIRFLOW_INSTANCE=airflow-instance
EOF
    echo -e "${YELLOW}Created a basic .env file. Please edit it with your configuration and run again.${NC}"
  fi
  exit 1
fi

# Default flags
ENABLE_TERRAFORM=${ENABLE_TERRAFORM:-"true"}
ENABLE_BATCH=${ENABLE_BATCH:-"true"}
ENABLE_STREAMING=${ENABLE_STREAMING:-"true"}
ENABLE_ANALYTICS=${ENABLE_ANALYTICS:-"true"}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --enable-terraform)
      ENABLE_TERRAFORM="$2"
      shift
      shift
      ;;
    --enable-batch)
      ENABLE_BATCH="$2"
      shift
      shift
      ;;
    --enable-streaming)
      ENABLE_STREAMING="$2"
      shift
      shift
      ;;
    --enable-analytics)
      ENABLE_ANALYTICS="$2"
      shift
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Function to check if required variables are set
check_required_vars() {
  local missing=false
  for var in "$@"; do
    if [ -z "${!var}" ]; then
      echo -e "${RED}Error: ${var} is not set in .env file${NC}"
      missing=true
    fi
  done

  if [ "$missing" = true ]; then
    exit 1
  fi
}

# Check required variables
check_required_vars PROJECT_ID REGION ZONE BUCKET_NAME DATASET_ID

# Add conditional checks for component-specific variables
if [ "$ENABLE_BATCH" = "true" ] && [ -z "${SPARK_CLUSTER_NAME}" ]; then
  SPARK_CLUSTER_NAME="stock-market-cluster"
  echo -e "${YELLOW}Using default Spark cluster name: ${SPARK_CLUSTER_NAME}${NC}"
fi

if [ "$ENABLE_STREAMING" = "true" ] && [ -z "${KAFKA_INSTANCE_NAME}" ]; then
  KAFKA_INSTANCE_NAME="kafka-instance"
  echo -e "${YELLOW}Using default Kafka instance name: ${KAFKA_INSTANCE_NAME}${NC}"
fi

echo -e "${GREEN}===== DEPLOYMENT CONFIGURATION =====${NC}"
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Zone: ${ZONE}"
echo "Infrastructure (Terraform): ${ENABLE_TERRAFORM}"
echo "Batch Processing (Spark): ${ENABLE_BATCH}"
echo "Streaming Processing: ${ENABLE_STREAMING}"
echo "Analytics (Airflow/DBT): ${ENABLE_ANALYTICS}"
echo ""

# 1. Deploy infrastructure with Terraform if enabled
if [ "${ENABLE_TERRAFORM}" = "true" ]; then
  echo -e "${GREEN}===== DEPLOYING INFRASTRUCTURE WITH TERRAFORM =====${NC}"
  
  # Check if Terraform is installed
  if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform not found. Please install Terraform first.${NC}"
    exit 1
  fi
  
  cd terraform
  
  # Initialize Terraform if needed
  if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
  fi
  
  # Apply Terraform configuration
  echo "Applying Terraform configuration..."
  terraform apply -var="project_id=${PROJECT_ID}" \
                -var="region=${REGION}" \
                -var="zone=${ZONE}" \
                -var="bucket_name=${BUCKET_NAME}" \
                -var="dataset_id=${DATASET_ID}" \
                -var="spark_cluster_name=${SPARK_CLUSTER_NAME}" \
                -var="kafka_instance_name=${KAFKA_INSTANCE_NAME}" \
                -auto-approve
  
  echo -e "${GREEN}Infrastructure deployment completed.${NC}"
  cd ..
else
  echo -e "${YELLOW}Skipping Terraform infrastructure deployment.${NC}"
fi

# 2. Deploy Spark batch processing pipeline if enabled
if [ "${ENABLE_BATCH}" = "true" ]; then
  echo -e "${GREEN}===== DEPLOYING BATCH PROCESSING PIPELINE =====${NC}"
  
  cd spark_pipeline
  
  # Make the deployment script executable
  chmod +x deploy_spark.sh
  
  # Run the Spark deployment script
  ./deploy_spark.sh
  
  cd ..
  
  echo -e "${GREEN}Batch processing pipeline deployment completed.${NC}"
else
  echo -e "${YELLOW}Skipping batch processing pipeline deployment.${NC}"
fi

# 3. Deploy Kafka and streaming pipeline if enabled
if [ "${ENABLE_STREAMING}" = "true" ]; then
  echo -e "${GREEN}===== DEPLOYING STREAMING PIPELINE WITH KAFKA =====${NC}"
  
  cd stream_pipeline
  
  # Make scripts executable
  chmod +x create_kafka_vm.sh setup_kafka.sh deploy_kafka.sh deploy_streaming_kafka.sh
  
  # Check if VM exists before creating it
  VM_EXISTS=$(gcloud compute instances list --project=${PROJECT_ID} --filter="name=${KAFKA_INSTANCE_NAME}" --format="value(name)")
  
  if [ -z "$VM_EXISTS" ]; then
    echo "Creating Kafka VM..."
    ./create_kafka_vm.sh
  else
    echo "Kafka VM already exists, skipping creation."
  fi
  
  # Setup Kafka
  echo "Setting up Kafka..."
  gcloud compute scp setup_kafka.sh ${KAFKA_INSTANCE_NAME}:~/ --zone=${ZONE} --project=${PROJECT_ID}
  gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="chmod +x setup_kafka.sh && ./setup_kafka.sh"
  
  # Deploy Kafka
  echo "Deploying Kafka..."
  ./deploy_kafka.sh
  
  # Deploy streaming pipeline
  echo "Deploying streaming pipeline..."
  ./deploy_streaming_kafka.sh
  
  cd ..
  
  echo -e "${GREEN}Streaming pipeline deployment completed.${NC}"
else
  echo -e "${YELLOW}Skipping streaming pipeline deployment.${NC}"
fi

# 4. Deploy Airflow and DBT analytics if enabled
if [ "${ENABLE_ANALYTICS}" = "true" ]; then
  echo -e "${GREEN}===== DEPLOYING ANALYTICS PIPELINE (AIRFLOW + DBT) =====${NC}"
  
  cd analytics
  
  # Create BigQuery datasets for DBT if they don't exist
  echo "Creating BigQuery datasets for DBT..."
  bq mk --dataset --location=${REGION} ${PROJECT_ID}:dbt_analytics 2>/dev/null || echo "Dataset dbt_analytics already exists."
  bq mk --dataset --location=${REGION} ${PROJECT_ID}:dbt_analytics_staging 2>/dev/null || echo "Dataset dbt_analytics_staging already exists."
  bq mk --dataset --location=${REGION} ${PROJECT_ID}:dbt_analytics_intermediate 2>/dev/null || echo "Dataset dbt_analytics_intermediate already exists."
  bq mk --dataset --location=${REGION} ${PROJECT_ID}:dbt_analytics_marts 2>/dev/null || echo "Dataset dbt_analytics_marts already exists."
  
  # Make the deploy_analytics.sh script executable
  chmod +x deploy_analytics.sh
  
  # Run the analytics deployment script
  export PROJECT_ID=${PROJECT_ID}
  export ZONE=${ZONE}
  export KAFKA_INSTANCE_NAME=${KAFKA_INSTANCE_NAME}
  ./deploy_analytics.sh
  
  cd ..
  
  echo -e "${GREEN}Analytics deployment completed.${NC}"
else
  echo -e "${YELLOW}Skipping analytics deployment.${NC}"
fi

# Get Kafka VM IP if streaming is enabled
if [ "${ENABLE_STREAMING}" = "true" ]; then
  KAFKA_IP=$(gcloud compute instances describe ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
fi

# Final status output and instructions
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}       DEPLOYMENT COMPLETED SUCCESSFULLY               ${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo ""
echo -e "${GREEN}Your Stock Market Analytics Platform is now running:${NC}"
echo ""

if [ "${ENABLE_BATCH}" = "true" ]; then
  echo -e "${GREEN}Batch Processing:${NC}"
  echo "- Dataproc cluster: ${SPARK_CLUSTER_NAME}"
  echo "- BigQuery dataset: ${DATASET_ID}"
  echo "- GCS bucket: gs://${BUCKET_NAME}"
  echo ""
fi

if [ "${ENABLE_STREAMING}" = "true" ]; then
  echo -e "${GREEN}Streaming with Kafka:${NC}"
  echo "- Kafka VM: ${KAFKA_INSTANCE_NAME} (${KAFKA_IP})"
  echo "- Kafka broker: ${KAFKA_IP}:9092"
  echo "- Zookeeper: ${KAFKA_IP}:2181"
  echo "- BigQuery dataset: ${DATASET_ID}"
  echo ""
fi

if [ "${ENABLE_ANALYTICS}" = "true" ]; then
  echo -e "${GREEN}Analytics:${NC}"
  echo "- Airflow UI: http://${KAFKA_IP}:8080"
  echo "- Username: admin"
  echo "- Password: admin"
  echo "- DBT models: Running twice daily (1 AM and 1 PM)"
  echo "- BigQuery datasets:"
  echo "  * dbt_analytics"
  echo "  * dbt_analytics_staging"
  echo "  * dbt_analytics_intermediate"
  echo "  * dbt_analytics_marts"
  echo ""
fi

echo -e "${GREEN}Next Steps:${NC}"
echo "1. To view the data in BigQuery:"
echo "   - Go to BigQuery console: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
echo "   - Navigate to ${PROJECT_ID} > ${DATASET_ID}"
echo ""
echo "2. To run DBT models manually:"
echo "   gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command=\"cd ~/dbt && ./run_dbt.sh run\""
echo ""
echo "3. To check logs:"
echo "   - Airflow webserver: gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command=\"sudo systemctl status airflow-webserver\""
echo "   - Airflow scheduler: gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command=\"sudo systemctl status airflow-scheduler\""
echo ""
echo ""

echo -e "${GREEN}Deployment completed!${NC}"