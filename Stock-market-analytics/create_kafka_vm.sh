#!/bin/bash
# Script to create a VM for Kafka using gcloud CLI

set -e  # Exit on any error

# Load environment variables if available
if [ -f ../.env ]; then
  source ../.env
fi

# Variables with defaults
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
KAFKA_INSTANCE_NAME=${KAFKA_INSTANCE_NAME:-"kafka-instance"}
MACHINE_TYPE=${MACHINE_TYPE:-"e2-standard-4"}  # 4 vCPUs, 16 GB RAM
DISK_SIZE=${DISK_SIZE:-"50"}  # 50 GB disk
NETWORK=${NETWORK:-"default"}
BOOT_DISK_TYPE=${BOOT_DISK_TYPE:-"pd-balanced"}

# Check if required environment variables are set
if [ -z "$PROJECT_ID" ]; then
  echo "Error: PROJECT_ID is not set. Please set it in .env file or export it."
  exit 1
fi

echo "Creating Kafka VM instance..."
echo "Project: ${PROJECT_ID}"
echo "Zone: ${ZONE}"
echo "Instance Name: ${KAFKA_INSTANCE_NAME}"
echo "Machine Type: ${MACHINE_TYPE}"

# Check if VM instance already exists
if gcloud compute instances describe ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} &>/dev/null; then
  echo "VM instance ${KAFKA_INSTANCE_NAME} already exists."
  echo "To recreate it, first delete it with:"
  echo "gcloud compute instances delete ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID}"
  
  # Get external IP
  EXTERNAL_IP=$(gcloud compute instances describe ${KAFKA_INSTANCE_NAME} \
    --zone=${ZONE} --project=${PROJECT_ID} \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
  
  echo "External IP: ${EXTERNAL_IP}"
  
  exit 0
fi

# Create VM instance
echo "Creating VM instance..."
gcloud compute instances create ${KAFKA_INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE} \
  --machine-type=${MACHINE_TYPE} \
  --network-interface=network=${NETWORK},subnet=${NETWORK},network-tier=PREMIUM \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --create-disk=auto-delete=yes,boot=yes,device-name=${KAFKA_INSTANCE_NAME},image=projects/debian-cloud/global/images/debian-11-bullseye-v20240312,mode=rw,size=${DISK_SIZE},type=projects/${PROJECT_ID}/zones/${ZONE}/diskTypes/${BOOT_DISK_TYPE} \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --reservation-affinity=any \
  --tags=kafka,http-server,https-server

# Create firewall rules if they don't exist
FIREWALL_RULES=$(gcloud compute firewall-rules list --project=${PROJECT_ID} --format="value(name)")

# Create Kafka firewall rule if it doesn't exist
if ! echo "${FIREWALL_RULES}" | grep -q "allow-kafka"; then
  echo "Creating firewall rule for Kafka..."
  gcloud compute firewall-rules create allow-kafka \
    --project=${PROJECT_ID} \
    --direction=INGRESS \
    --priority=1000 \
    --network=${NETWORK} \
    --action=ALLOW \
    --rules=tcp:9092,tcp:2181 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=kafka
fi

# Create SSH firewall rule if it doesn't exist
if ! echo "${FIREWALL_RULES}" | grep -q "allow-ssh"; then
  echo "Creating firewall rule for SSH..."
  gcloud compute firewall-rules create allow-ssh \
    --project=${PROJECT_ID} \
    --direction=INGRESS \
    --priority=1000 \
    --network=${NETWORK} \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0
fi

# Get external IP of the created VM
EXTERNAL_IP=$(gcloud compute instances describe ${KAFKA_INSTANCE_NAME} \
  --zone=${ZONE} --project=${PROJECT_ID} \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "==========================================================="
echo "VM Instance Created Successfully!"
echo "==========================================================="
echo "Instance Name: ${KAFKA_INSTANCE_NAME}"
echo "External IP: ${EXTERNAL_IP}"
echo ""
echo "To SSH into the VM:"
echo "gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID}"
echo "===========================================================" 