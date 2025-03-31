#!/bin/bash
# Script to deploy Kafka on a Google Cloud VM

# Don't exit on error so we can see all outputs
set +e

# Enable command echo to see exactly what's happening
set -x

# Source environment variables from parent directory if .env file doesn't exist in current directory
if [ ! -f .env ] && [ -f ../.env ]; then
  echo "Sourcing environment variables from parent directory's .env file"
  source ../.env
fi

# Check for required environment variables
for VAR in PROJECT_ID REGION ZONE KAFKA_INSTANCE_NAME; do
  if [ -z "${!VAR}" ]; then
    echo "Error: ${VAR} environment variable is required"
    exit 1
  fi
done

echo "===================================================="
echo "Deploying Kafka on VM ${KAFKA_INSTANCE_NAME}"
echo "===================================================="
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Zone: ${ZONE}"
echo "===================================================="

# Copy the setup script to the VM
echo "Copying Kafka setup script to VM..."
gcloud compute scp setup_kafka.sh ${KAFKA_INSTANCE_NAME}:~/ \
  --zone=${ZONE} --project=${PROJECT_ID}

if [ $? -ne 0 ]; then
  echo "Error: Failed to copy setup script to VM"
  exit 1
fi

# Make the script executable and run it
echo "Running Kafka setup script on VM..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="chmod +x setup_kafka.sh && ./setup_kafka.sh"

SETUP_EXIT_CODE=$?
if [ $SETUP_EXIT_CODE -ne 0 ]; then
  echo "Error: Kafka setup script exited with code ${SETUP_EXIT_CODE}"
  echo "Checking if Kafka service is running despite the error..."
  gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
    --command="sudo systemctl status kafka.service --no-pager"
else
  echo "Kafka setup script completed successfully"
fi

# Check if Kafka and Zookeeper services are running
echo "Verifying Kafka services are running..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="sudo systemctl status kafka.service zookeeper.service --no-pager"

# Create the 'stock-market-data' topic if it doesn't exist
echo "Creating Kafka topic if it doesn't exist..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="~/kafka/bin/kafka-topics.sh --create --if-not-exists --topic stock-market-data --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1"

if [ $? -ne 0 ]; then
  echo "Warning: Failed to create Kafka topic. It might already exist."
  echo "Checking topics list:"
  gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
    --command="~/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"
fi

# Check if Kafka is reachable externally
echo "Checking if Kafka is externally accessible..."
KAFKA_EXTERNAL_IP=$(gcloud compute instances describe ${KAFKA_INSTANCE_NAME} \
  --zone=${ZONE} --project=${PROJECT_ID} \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "Kafka External IP: ${KAFKA_EXTERNAL_IP}"

# Create firewall rule for Kafka if it doesn't exist
echo "Creating firewall rule for Kafka if it doesn't exist..."
FIREWALL_EXISTS=$(gcloud compute firewall-rules list --project=${PROJECT_ID} --filter="name=allow-kafka" --format="value(name)")
if [ -z "$FIREWALL_EXISTS" ]; then
  gcloud compute firewall-rules create allow-kafka \
    --project=${PROJECT_ID} \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:9092 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=kafka
fi

echo "===================================================="
echo "Kafka deployment completed on VM ${KAFKA_INSTANCE_NAME}"
echo "Kafka External IP: ${KAFKA_EXTERNAL_IP}"
echo "Bootstrap Server: ${KAFKA_EXTERNAL_IP}:9092"
echo "Topic: stock-market-data"
echo "===================================================="

# Test Kafka connectivity
echo "Testing Kafka connectivity (this might fail if advertised.listeners is not set to external IP)..."
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} \
  --command="nc -zv ${KAFKA_EXTERNAL_IP} 9092"

echo "Kafka Deployment Status: Complete" 