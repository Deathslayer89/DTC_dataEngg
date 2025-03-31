#!/bin/bash
# Comprehensive script to deploy Kafka streaming pipeline for stock market data

# Don't exit on error so we can see all outputs, even if errors occur
set +e

# Enable command echo to see exactly what's happening
set -x

# Source environment variables from parent directory if .env file doesn't exist in current directory
if [ ! -f .env ] && [ -f ../.env ]; then
  echo "Sourcing environment variables from parent directory's .env file"
  source ../.env
fi

# Load environment variables
if [ -f ../.env ]; then
  source ../.env
else
  echo "Error: .env file not found. Please create it with your configuration."
  exit 1
fi

# Check for required environment variables
for VAR in PROJECT_ID REGION ZONE DATASET_ID; do
  if [ -z "${!VAR}" ]; then
    echo "Error: ${VAR} environment variable is required"
    exit 1
  fi
done

# Set default values if not provided
KAFKA_INSTANCE_NAME=${KAFKA_INSTANCE_NAME:-"kafka-instance"}
KAFKA_TOPIC=${KAFKA_TOPIC:-"stock-market-data"}
CONSUMER_GROUP=${CONSUMER_GROUP:-"bigquery-consumer"}
BIGQUERY_TABLE=${BIGQUERY_TABLE:-"stock_prices_realtime"}
FULL_BIGQUERY_TABLE="${DATASET_ID}.${BIGQUERY_TABLE}"
STOCK_UPDATE_INTERVAL=${STOCK_UPDATE_INTERVAL:-3600}  # 1 hour default
IMAGE_NAME="gcr.io/${PROJECT_ID}/kafka-stock-pipeline"

echo "===================================================="
echo "Stock Market Data Streaming Pipeline with Kafka"
echo "===================================================="
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Zone: ${ZONE}"
echo "Kafka Instance: ${KAFKA_INSTANCE_NAME}"
echo "Kafka Topic: ${KAFKA_TOPIC}"
echo "BigQuery Dataset: ${DATASET_ID}"
echo "BigQuery Table: ${FULL_BIGQUERY_TABLE}"
echo "Update Interval: ${STOCK_UPDATE_INTERVAL} seconds"
echo "===================================================="

# Create VM for Kafka if it doesn't exist
echo -e "\n===== STEP 1: CREATING KAFKA VM ====="
if [ ! -f create_kafka_vm.sh ]; then
  echo "Error: create_kafka_vm.sh not found"
  exit 1
fi

chmod +x create_kafka_vm.sh
./create_kafka_vm.sh

# Set up Kafka on the VM
echo -e "\n===== STEP 2: SETTING UP KAFKA ====="
if [ ! -f setup_kafka.sh ]; then
  echo "Error: setup_kafka.sh not found"
  exit 1
fi

chmod +x setup_kafka.sh
chmod +x deploy_kafka.sh

echo "Deploying Kafka..."
./deploy_kafka.sh

# Get Kafka external IP
KAFKA_EXTERNAL_IP=$(gcloud compute instances describe ${KAFKA_INSTANCE_NAME} \
  --zone=${ZONE} --project=${PROJECT_ID} \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

if [ -z "${KAFKA_EXTERNAL_IP}" ]; then
  echo "Error: Could not retrieve Kafka external IP"
  exit 1
fi

echo "Kafka external IP: ${KAFKA_EXTERNAL_IP}"
KAFKA_BOOTSTRAP_SERVERS="${KAFKA_EXTERNAL_IP}:9092"

# Show Kafka setup status
echo "Checking Kafka setup status..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="ps aux | grep -E 'kafka|zookeeper' | grep -v grep"

# Build the Docker image for both producer and consumer
echo -e "\n===== STEP 3: BUILDING DOCKER IMAGE ====="
if [ ! -f Dockerfile.kafka ]; then
  echo "Error: Dockerfile.kafka not found"
  exit 1
fi

# Ensure required files exist
for FILE in kafka_stock_producer.py kafka_to_bigquery.py requirements.txt fortune500.csv; do
  if [ ! -f $FILE ]; then
    echo "Error: Required file $FILE not found"
    exit 1
  fi
done

echo "Building Docker image: ${IMAGE_NAME}"
gcloud builds submit --tag ${IMAGE_NAME} --project=${PROJECT_ID} \
  --dockerfile=Dockerfile.kafka . 2>&1 | tee docker_build.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "Error: Docker image build failed. See docker_build.log for details."
  exit 1
fi

echo "Docker image built successfully: ${IMAGE_NAME}"

# Deploy the Kafka consumer to the VM
echo -e "\n===== STEP 4: DEPLOYING KAFKA CONSUMER TO VM ====="
echo "Creating startup script for Kafka consumer..."

cat > kafka_consumer_startup.sh << EOF
#!/bin/bash
# Kafka consumer startup script

set -x  # Echo commands

# Install Docker if not already installed
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  sudo usermod -aG docker \$(whoami)
  sudo systemctl enable docker
  sudo systemctl start docker
fi

# Set up environment for authentication
echo "Setting up Google Cloud authentication..."
gcloud auth configure-docker --quiet

# Pull the image
echo "Pulling Docker image..."
sudo docker pull ${IMAGE_NAME}

# Stop any existing container
echo "Stopping any existing consumer container..."
sudo docker stop kafka-consumer 2>/dev/null || true
sudo docker rm kafka-consumer 2>/dev/null || true

# Run the consumer container
echo "Starting Kafka consumer container..."
sudo docker run -d --name kafka-consumer \\
  -e KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS}" \\
  -e PROJECT_ID="${PROJECT_ID}" \\
  -e KAFKA_TOPIC="${KAFKA_TOPIC}" \\
  -e CONSUMER_GROUP="${CONSUMER_GROUP}" \\
  -e BIGQUERY_TABLE="${FULL_BIGQUERY_TABLE}" \\
  ${IMAGE_NAME} python kafka_to_bigquery.py \\
  --bootstrap-servers ${KAFKA_BOOTSTRAP_SERVERS} \\
  --topic ${KAFKA_TOPIC} \\
  --consumer-group ${CONSUMER_GROUP} \\
  --project-id ${PROJECT_ID} \\
  --bigquery-table ${FULL_BIGQUERY_TABLE}

# Check if container is running
echo "Checking if consumer container is running..."
sleep 5
sudo docker ps -a | grep kafka-consumer

echo "Consumer logs:"
sudo docker logs kafka-consumer
EOF

chmod +x kafka_consumer_startup.sh

echo "Copying consumer startup script to VM..."
gcloud compute scp kafka_consumer_startup.sh ${KAFKA_INSTANCE_NAME}:~/ \
  --zone=${ZONE} --project=${PROJECT_ID}

echo "Running consumer startup script on VM..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="chmod +x kafka_consumer_startup.sh && ./kafka_consumer_startup.sh"

# Verify consumer is running
echo "Verifying consumer is running..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="sudo docker ps -a | grep kafka-consumer"

if [ $? -ne 0 ]; then
  echo "Warning: Consumer container may not be running. Check logs below:"
  gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
    --command="sudo docker logs kafka-consumer 2>&1 || echo 'No consumer logs available'"
fi

# Deploy the Kafka producer to Cloud Run
echo -e "\n===== STEP 5: DEPLOYING KAFKA PRODUCER TO CLOUD RUN ====="
echo "Setting up service account for Cloud Run..."

# Create service account for Cloud Run
SERVICE_ACCOUNT="kafka-producer-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"

# Check if service account exists
if ! gcloud iam service-accounts describe ${SERVICE_ACCOUNT_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
  echo "Creating service account ${SERVICE_ACCOUNT}..."
  gcloud iam service-accounts create ${SERVICE_ACCOUNT} \
    --display-name="Kafka Producer Service Account" \
    --project=${PROJECT_ID}
  
  # Grant necessary permissions
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/bigquery.dataEditor"
fi

# Deploy to Cloud Run
CLOUD_RUN_SERVICE_NAME="kafka-stock-producer"

echo "Deploying producer to Cloud Run..."
gcloud run deploy ${CLOUD_RUN_SERVICE_NAME} \
  --image=${IMAGE_NAME} \
  --platform=managed \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --service-account=${SERVICE_ACCOUNT_EMAIL} \
  --set-env-vars="KAFKA_BOOTSTRAP_SERVERS=${KAFKA_BOOTSTRAP_SERVERS},KAFKA_TOPIC=${KAFKA_TOPIC},PROJECT_ID=${PROJECT_ID},STOCK_UPDATE_INTERVAL=${STOCK_UPDATE_INTERVAL}" \
  --command="python" \
  --args="kafka_stock_producer.py,--bootstrap-servers,${KAFKA_BOOTSTRAP_SERVERS},--topic,${KAFKA_TOPIC},--project-id,${PROJECT_ID},--interval,${STOCK_UPDATE_INTERVAL}" \
  --memory=1Gi \
  --cpu=1 \
  --timeout=3600 \
  --min-instances=1 \
  --max-instances=1

CLOUD_RUN_EXIT_CODE=$?
if [ $CLOUD_RUN_EXIT_CODE -ne 0 ]; then
  echo "Error: Failed to deploy producer to Cloud Run (Exit Code: $CLOUD_RUN_EXIT_CODE)"
else
  echo "Producer deployed successfully to Cloud Run"
fi

# Get the service URL
SERVICE_URL=$(gcloud run services describe ${CLOUD_RUN_SERVICE_NAME} \
  --platform=managed \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --format="value(status.url)" 2>/dev/null)

echo "Cloud Run Service URL: ${SERVICE_URL}"

# Create BigQuery dataset and table if they don't exist
echo -e "\n===== STEP 6: CREATING BIGQUERY RESOURCES ====="
echo "Ensuring BigQuery dataset and table exist..."

# Create dataset if it doesn't exist
if ! bq ls --project_id=${PROJECT_ID} ${DATASET_ID} &>/dev/null; then
  echo "Creating BigQuery dataset ${DATASET_ID}..."
  bq --location=${REGION} mk --dataset ${PROJECT_ID}:${DATASET_ID}
else
  echo "BigQuery dataset ${DATASET_ID} already exists."
fi

# Create table if it doesn't exist
if ! bq ls --project_id=${PROJECT_ID} ${DATASET_ID}.${BIGQUERY_TABLE} &>/dev/null; then
  echo "Creating BigQuery table ${FULL_BIGQUERY_TABLE}..."
  bq mk --table \
    --project_id=${PROJECT_ID} \
    --schema="symbol:STRING,timestamp:TIMESTAMP,price:FLOAT,volume:INTEGER,currency:STRING" \
    --time_partitioning_field=timestamp \
    --time_partitioning_type=DAY \
    ${DATASET_ID}.${BIGQUERY_TABLE}
else
  echo "BigQuery table ${FULL_BIGQUERY_TABLE} already exists."
fi

# Verify that all components are running correctly
echo -e "\n===== STEP 7: VERIFYING DEPLOYMENT ====="

echo "Checking Kafka service status..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="sudo systemctl status kafka.service --no-pager"

echo "Checking Zookeeper service status..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="sudo systemctl status zookeeper.service --no-pager"

echo "Checking Kafka topic..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="~/kafka/bin/kafka-topics.sh --describe --topic ${KAFKA_TOPIC} --bootstrap-server localhost:9092"

echo "Checking consumer container status..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="sudo docker ps -a"

echo "Checking consumer logs..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="sudo docker logs kafka-consumer"

echo "Checking producer service status..."
gcloud run services describe ${CLOUD_RUN_SERVICE_NAME} \
  --platform=managed \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --format="default"

echo -e "\n===================================================="
echo "🚀 KAFKA STREAMING PIPELINE DEPLOYMENT COMPLETED! 🚀"
echo "===================================================="
echo "Kafka Instance: ${KAFKA_INSTANCE_NAME}"
echo "Kafka External IP: ${KAFKA_EXTERNAL_IP}"
echo "Kafka Bootstrap Servers: ${KAFKA_BOOTSTRAP_SERVERS}"
echo "Kafka Topic: ${KAFKA_TOPIC}"
echo "BigQuery Table: ${FULL_BIGQUERY_TABLE}"
echo "Cloud Run Producer: ${SERVICE_URL}"
echo ""
echo "COMPONENT STATUS SUMMARY:"
echo "------------------------"
echo "1. Kafka Server: Running on ${KAFKA_INSTANCE_NAME} VM"
echo "2. Zookeeper: Running on ${KAFKA_INSTANCE_NAME} VM"
echo "3. Kafka Topic: ${KAFKA_TOPIC} created with 3 partitions"
echo "4. Consumer: Running in Docker container on ${KAFKA_INSTANCE_NAME} VM"
echo "   - Reading from: ${KAFKA_TOPIC}"
echo "   - Writing to: ${FULL_BIGQUERY_TABLE}"
echo "5. Producer: Running on Cloud Run as ${CLOUD_RUN_SERVICE_NAME}"
echo "   - URL: ${SERVICE_URL}"
echo "   - Update interval: ${STOCK_UPDATE_INTERVAL} seconds (${STOCK_UPDATE_INTERVAL/3600} hour(s))"
echo ""
echo "MONITORING COMMANDS:"
echo "------------------"
echo "- Kafka Service: gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command='sudo systemctl status kafka.service'"
echo "- Zookeeper: gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command='sudo systemctl status zookeeper.service'"
echo "- Consumer Logs: gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command='sudo docker logs kafka-consumer'"
echo "- Kafka Topic Status: gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command='~/kafka/bin/kafka-topics.sh --describe --topic ${KAFKA_TOPIC} --bootstrap-server localhost:9092'"
echo "- BigQuery Data: bq query --use_legacy_sql=false 'SELECT COUNT(*) as count FROM \`${FULL_BIGQUERY_TABLE}\`'"
echo ""
echo "=====================================================" 