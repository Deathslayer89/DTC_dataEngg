#!/bin/bash
# Comprehensive deployment script for Spark Pipeline
set -e  # Exit on any error

# Configuration validation
for VAR in PROJECT_ID REGION SPARK_CLUSTER_NAME BUCKET_NAME DATASET_ID; do
    if [ -z "${!VAR}" ]; then
        echo "Error: ${VAR} environment variable is required"
        exit 1
    fi
done

echo "Starting Spark Pipeline deployment..."
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Cluster: ${SPARK_CLUSTER_NAME}"

# 1. Upload application files to GCS
echo "Uploading application files to GCS..."
gsutil cp run_processor_4y.py "gs://${BUCKET_NAME}/spark/"
gsutil cp requirements.txt "gs://${BUCKET_NAME}/spark/"
gsutil cp fortune500.csv "gs://${BUCKET_NAME}/data/"

# Remove old files if they exist from previous runs
gsutil rm "gs://${BUCKET_NAME}/spark/install_pip.py" || true # Ignore error if it doesn't exist

# 2. Check Dataproc cluster initialization action
echo "Checking Dataproc cluster ${SPARK_CLUSTER_NAME} for initialization action..."
# Check if the cluster already has our init action
INIT_ACTIONS=$(gcloud dataproc clusters describe "${SPARK_CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --format="value(config.initializationActions.executableFile)" 2>/dev/null || echo "")

if [[ "${INIT_ACTIONS}" == *"gs://${BUCKET_NAME}/spark/dataproc_init.sh"* ]]; then
  echo "Initialization action already present on cluster. Proceeding..."
else
  echo "WARNING: Cluster ${SPARK_CLUSTER_NAME} does not have the required initialization action."
  echo "Initialization actions can only be set during cluster creation, not updated later."
  echo "Continuing anyway - consider updating your Terraform configuration."
fi

# 3. Set up service account permissions
echo "Setting up Dataproc service account permissions..."

# Get the Dataproc service account
DATAPROC_SA=$(gcloud dataproc clusters describe "${SPARK_CLUSTER_NAME}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --format="value(config.gceClusterConfig.serviceAccount)")

if [ -z "$DATAPROC_SA" ]; then
    echo "Warning: Could not retrieve Dataproc service account. Using default compute service account."
    DATAPROC_SA="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')-compute@developer.gserviceaccount.com"
fi

echo "Granting storage permissions to Dataproc service account: $DATAPROC_SA"

# Grant the Dataproc service account access to the GCS bucket
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="serviceAccount:$DATAPROC_SA" \
    --role="roles/storage.objectAdmin"

# Also grant BigQuery permissions to the service account
echo "Granting BigQuery access to Dataproc service account..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:$DATAPROC_SA" \
    --role="roles/bigquery.dataEditor" \
    --quiet

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:$DATAPROC_SA" \
    --role="roles/bigquery.jobUser" \
    --quiet

echo "Waiting for permissions to propagate..."
sleep 30

# 4. Submit the Spark job for data processing
echo "Submitting Spark job for data processing..."
gcloud dataproc jobs submit pyspark \
    --cluster="${SPARK_CLUSTER_NAME}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --properties="spark.pyspark.python=/usr/bin/python3.7,spark.pyspark.driver.python=/usr/bin/python3.7,spark.jars.packages=org.apache.spark:spark-avro_2.12:3.3.2" \
    --jars="gs://spark-lib/bigquery/spark-bigquery-latest_2.12.jar" \
    "gs://${BUCKET_NAME}/spark/run_processor_4y.py" \
    -- \
    --project_id="${PROJECT_ID}" \
    --dataset_id="${DATASET_ID}"

echo "Spark Pipeline deployment completed successfully!" 