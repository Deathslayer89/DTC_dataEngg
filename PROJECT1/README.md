# Stock Market Analytics Platform

A comprehensive data pipeline for stock market data processing and analytics on Google Cloud Platform (GCP). This platform integrates batch processing, real-time streaming, and analytics components to deliver insights from stock market data.

## Architecture Overview

The Stock Market Analytics Platform consists of the following components:

```
                                                  +-------------------+
                                                  |                   |
                                                  |  Looker Studio    |
                                                  |  Visualizations   |
                                                  |                   |
                                                  +--------^----------+
                                                           |
                       Batch Pipeline                      |
+---------------+    +----------------+    +---------------v-----------+
|               |    |                |    |                           |
| Stock Market  +--->+ Dataproc       +--->+                           |
| Data Files    |    | (Spark Jobs)   |    |                           |
|               |    |                |    |                           |
+---------------+    +----------------+    |                           |
                                           |                           |
                       Streaming Pipeline  |      BigQuery             |
+---------------+    +----------------+    |     (Data Storage)        |
|               |    |                |    |                           |
| Stock Market  +--->+ Kafka VM       +--->+                           |
| Data Stream   |    | (Producer/     |    |                           |
|               |    |  Consumer)     |    |                           |
+---------------+    +-------+--------+    +-------------^-------------+
                             |                           |
                             |                           |
                     +-------v---------+       +---------+---------+
                     |                 |       |                   |
                     | Airflow + DBT   +------>+ Transformed Data  |
                     | (Analytics)     |       | Models            |
                     |                 |       |                   |
                     +-----------------+       +-------------------+
```

This architecture combines:
1. **Batch Processing**: Using Dataproc (managed Spark) for processing historical data
2. **Real-time Streaming**: Using Kafka for streaming real-time stock market data
3. **Data Storage**: BigQuery for storing raw and processed data
4. **Analytics**: Airflow and DBT for orchestration and data transformation
5. **Visualization**: Connected to Looker Studio for data visualization

## Prerequisites

1. **Google Cloud Platform Account**:
   - An active GCP project with billing enabled
   - Required APIs enabled (Compute Engine, BigQuery, Dataproc, etc.)

2. **Required Tools**:
   - Google Cloud SDK (`gcloud`)
   - Terraform (>= 1.0.0)
   - Git

3. **Authentication**:
   ```bash
   gcloud auth application-default login
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

## Quick Start

1. **Clone this repository**:
   ```bash
   git clone https://github.com/yourusername/stock-market-analytics.git
   cd stock-market-analytics
   ```

2. **Configure your environment**:
   Create a `.env` file with your GCP configuration:
   ```bash
   # Google Cloud settings
   PROJECT_ID=your-project-id
   REGION=us-central1
   ZONE=us-central1-a
   BUCKET_NAME=your-bucket-name
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
   ```

3. **Run the unified deployment script**:
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

4. **Access your analytics platform**:
   - The script will output URLs and credentials for all components
   - Airflow UI will be available at `http://<KAFKA_VM_IP>:8080`
   - Username: `admin`
   - Password: `admin`

## Deployment Options

The unified script supports selective component deployment:

```bash
# Deploy only infrastructure and streaming components
./deploy.sh --enable-terraform true --enable-batch false --enable-streaming true --enable-analytics false

# Deploy only analytics components (assumes infrastructure exists)
./deploy.sh --enable-terraform false --enable-batch false --enable-streaming false --enable-analytics true
```

## Component Details

### Batch Processing (Spark)

- **Purpose**: Process historical stock market data in batch mode
- **Components**: Dataproc cluster running Spark jobs
- **Data Flow**: Raw data from GCS → Spark processing → BigQuery tables

### Streaming Pipeline (Kafka)

- **Purpose**: Ingest and process real-time stock market data
- **Components**: Kafka VM running broker, producer, and consumer services
- **Data Flow**: Real-time data → Kafka topics → BigQuery streaming inserts

### Analytics Layer (Airflow + DBT)

- **Purpose**: Transform raw data into analytics models, orchestrate workflows
- **Components**: Airflow for orchestration, DBT for data transformations
- **Data Flow**: Raw BigQuery tables → DBT transformations → Analytics models
- **Schedule**: DBT models run twice daily (1 AM and 1 PM)

## Usage Guide

### Monitoring Your Pipeline

1. **Check Airflow DAGs**:
   - Access Airflow UI: `http://<KAFKA_VM_IP>:8080`
   - Login with admin/admin
   - Verify DAGs are running

2. **View BigQuery Data**:
   - Go to BigQuery console: https://console.cloud.google.com/bigquery
   - Explore datasets:
     - `stock_market_analytics`: Raw data
     - `dbt_analytics_marts`: Transformed analytics models

3. **SSH into Kafka VM**:
   ```bash
   gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID}
   ```

4. **Check Kafka Topics and Messages**:
   ```bash
   # List topics
   /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
   
   # Consume messages from a topic
   /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic stock-market-data --from-beginning
   ```

### Running DBT Models Manually

```bash
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="cd ~/dbt && ./run_dbt.sh run"
```

### Checking Logs

```bash
# Airflow webserver logs
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="sudo journalctl -u airflow-webserver"

# Airflow scheduler logs
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="sudo journalctl -u airflow-scheduler"

# Kafka logs
gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="cat /opt/kafka/logs/server.log"
```

## Customization

### Adding New Data Sources

1. Modify the Spark job in `spark_pipeline/run_processor_4y.py`
2. Update the Kafka producer in `stream_pipeline/kafka_producer.py`
3. Add new transformations in the DBT models in `analytics/dbt/models/`

### Customizing the Analytics Models

1. Navigate to the DBT project:
   ```bash
   gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID}
   cd ~/dbt
   ```

2. Create or modify models in the `models` directory:
   - `staging/`: Initial data cleaning
   - `intermediate/`: Joined/transformed tables
   - `marts/`: Final analytics models

3. Update the Airflow DAG as needed:
   ```bash
   vi ~/airflow/dags/stock_analytics_dag.py
   ```

## Cleanup

To clean up all resources when you're done:

```bash
./cleanup.sh
```

This will:
1. Delete the Kafka VM
2. Delete the Dataproc cluster
3. Remove Cloud Run services
4. Delete BigQuery datasets
5. Clean up other cloud resources

## Troubleshooting

### Common Issues

1. **Airflow not accessible**:
   ```bash
   # Restart Airflow services
   gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="sudo systemctl restart airflow-webserver airflow-scheduler"
   ```

2. **Kafka issues**:
   ```bash
   # Restart Kafka
   gcloud compute ssh ${KAFKA_INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="sudo systemctl restart kafka zookeeper"
   ```

3. **Spark job failures**:
   - Check Dataproc Jobs in GCP Console
   - See logs in Cloud Logging
