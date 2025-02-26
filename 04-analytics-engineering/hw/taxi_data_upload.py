import os
import requests
import tempfile
from google.cloud import storage
from google.cloud import bigquery


# GCP settings
PROJECT_ID = "zoomcamp-450020"
BUCKET_NAME = "zoomcamp_taxi_bucket"
DATASET_NAME = "trips_data_all"

# Base URL for GitHub releases
BASE_URL = "https://github.com/DataTalksClub/nyc-tlc-data/releases/download"

# Function to generate download URLs
def generate_taxi_urls(taxi_type, years, months):
    """Generate download URLs for taxi data"""
    urls = []
    for year in years:
        for month in months:
            month_str = str(month).zfill(2)
            filename = f"{taxi_type}_tripdata_{year}-{month_str}.csv.gz"
            url = f"{BASE_URL}/{taxi_type}/{filename}"
            urls.append(url)
    return urls

# Function to download and upload a file directly to GCS
def download_and_upload_to_gcs(url, bucket_name, destination_blob_name):
    """Downloads a file and uploads it directly to GCS bucket"""
    filename = url.split('/')[-1]
    print(f"Processing {filename}...")
    
    # Create a temporary directory to store the file
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_file_path = os.path.join(temp_dir, filename)
        
        # Download the file
        print(f"Downloading {url}")
        response = requests.get(url)
        if response.status_code == 200:
            with open(temp_file_path, 'wb') as f:
                f.write(response.content)
            
            # Upload to GCS
            storage_client = storage.Client()
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(destination_blob_name)
            
            blob.upload_from_filename(temp_file_path)
            print(f"Uploaded {filename} to gs://{bucket_name}/{destination_blob_name}")
            return True
        else:
            print(f"Failed to download {url}. Status code: {response.status_code}")
            return False

# Function to create external table in BigQuery
def create_external_table(table_id, gcs_uri, schema):
    """Creates an external table in BigQuery pointing to GCS URI"""
    client = bigquery.Client()
    
    external_config = bigquery.ExternalConfig("CSV")
    external_config.source_uris = [gcs_uri]
    external_config.schema = schema
    external_config.options.skip_leading_rows = 1  # Skip header row
    external_config.compression = "GZIP"
    
    table = bigquery.Table(table_id, schema=schema)
    table.external_data_configuration = external_config
    
    table = client.create_table(table, exists_ok=True)
    print(f"Created external table {table_id}")

# Define schemas for the tables
def get_green_taxi_schema():
    """Returns the schema for green taxi data"""
    return [
        bigquery.SchemaField("VendorID", "INTEGER"),
        bigquery.SchemaField("lpep_pickup_datetime", "TIMESTAMP"),
        bigquery.SchemaField("lpep_dropoff_datetime", "TIMESTAMP"),
        bigquery.SchemaField("store_and_fwd_flag", "STRING"),
        bigquery.SchemaField("RatecodeID", "INTEGER"),
        bigquery.SchemaField("PULocationID", "INTEGER"),
        bigquery.SchemaField("DOLocationID", "INTEGER"),
        bigquery.SchemaField("passenger_count", "INTEGER"),
        bigquery.SchemaField("trip_distance", "FLOAT"),
        bigquery.SchemaField("fare_amount", "FLOAT"),
        bigquery.SchemaField("extra", "FLOAT"),
        bigquery.SchemaField("mta_tax", "FLOAT"),
        bigquery.SchemaField("tip_amount", "FLOAT"),
        bigquery.SchemaField("tolls_amount", "FLOAT"),
        bigquery.SchemaField("ehail_fee", "FLOAT"),
        bigquery.SchemaField("improvement_surcharge", "FLOAT"),
        bigquery.SchemaField("total_amount", "FLOAT"),
        bigquery.SchemaField("payment_type", "INTEGER"),
        bigquery.SchemaField("trip_type", "INTEGER"),
        bigquery.SchemaField("congestion_surcharge", "FLOAT"),
    ]

def get_yellow_taxi_schema():
    """Returns the schema for yellow taxi data"""
    return [
        bigquery.SchemaField("VendorID", "INTEGER"),
        bigquery.SchemaField("tpep_pickup_datetime", "TIMESTAMP"),
        bigquery.SchemaField("tpep_dropoff_datetime", "TIMESTAMP"),
        bigquery.SchemaField("passenger_count", "INTEGER"),
        bigquery.SchemaField("trip_distance", "FLOAT"),
        bigquery.SchemaField("RatecodeID", "INTEGER"),
        bigquery.SchemaField("store_and_fwd_flag", "STRING"),
        bigquery.SchemaField("PULocationID", "INTEGER"),
        bigquery.SchemaField("DOLocationID", "INTEGER"),
        bigquery.SchemaField("payment_type", "INTEGER"),
        bigquery.SchemaField("fare_amount", "FLOAT"),
        bigquery.SchemaField("extra", "FLOAT"),
        bigquery.SchemaField("mta_tax", "FLOAT"),
        bigquery.SchemaField("tip_amount", "FLOAT"),
        bigquery.SchemaField("tolls_amount", "FLOAT"),
        bigquery.SchemaField("improvement_surcharge", "FLOAT"),
        bigquery.SchemaField("total_amount", "FLOAT"),
        bigquery.SchemaField("congestion_surcharge", "FLOAT"),
    ]

# Main execution
def main():
    # Generate URLs for green and yellow taxi data
    years = [2019,2020]
    months = range(1, 13)  # 1 to 12
    
    yellow_taxi_urls = generate_taxi_urls("yellow", years, months)
    
    # Create GCS bucket if it doesn't exist
    storage_client = storage.Client()
    try:
        storage_client.get_bucket(BUCKET_NAME)
    except Exception:
        print(f"Creating bucket {BUCKET_NAME}")
        storage_client.create_bucket(BUCKET_NAME)
    
    # Create BigQuery dataset if it doesn't exist
    bq_client = bigquery.Client()
    dataset_id = f"{PROJECT_ID}.{DATASET_NAME}"
    try:
        bq_client.get_dataset(dataset_id)
        print(f"Dataset {dataset_id} already exists")
    except Exception:
        print(f"Creating dataset {dataset_id}")
        dataset = bigquery.Dataset(dataset_id)
        dataset.location = "US"
        bq_client.create_dataset(dataset)
    
    # Process green taxi data
    for url in green_taxi_urls:
        filename = url.split('/')[-1]
        destination_blob_name = f"green/{filename}"
        download_and_upload_to_gcs(url, BUCKET_NAME, destination_blob_name)
    
    # Process yellow taxi data
    for url in yellow_taxi_urls:
        filename = url.split('/')[-1]
        destination_blob_name = f"yellow/{filename}"
        download_and_upload_to_gcs(url, BUCKET_NAME, destination_blob_name)
    
    # Create external tables in BigQuery
    green_schema = get_green_taxi_schema()
    yellow_schema = get_yellow_taxi_schema()
    
    # Create external table for green taxi data
    green_table_id = f"{PROJECT_ID}.{DATASET_NAME}.ext_green_taxi"
    green_gcs_uri = f"gs://{BUCKET_NAME}/green/*.csv.gz"
    create_external_table(green_table_id, green_gcs_uri, green_schema)
    
    # Create external table for yellow taxi data
    yellow_table_id = f"{PROJECT_ID}.{DATASET_NAME}.ext_yellow_taxi"
    yellow_gcs_uri = f"gs://{BUCKET_NAME}/yellow/*.csv.gz"
    create_external_table(yellow_table_id, yellow_gcs_uri, yellow_schema)
    
    # Validate record counts
    print("Validating record counts...")
    green_count_query = f"SELECT COUNT(*) as count FROM `{green_table_id}`"
    yellow_count_query = f"SELECT COUNT(*) as count FROM `{yellow_table_id}`"
    
    green_count_job = bq_client.query(green_count_query)
    yellow_count_job = bq_client.query(yellow_count_query)
    
    green_count = list(green_count_job)[0][0]
    yellow_count = list(yellow_count_job)[0][0]
    
    print(f"Green taxi record count: {green_count}")
    print(f"Yellow taxi record count: {yellow_count}")
    
    # Check if record counts match expected
    if green_count == 7778101:
        print("✅ Green taxi record count matches expected (7,778,101)")
    else:
        print(f"❌ Green taxi record count {green_count} doesn't match expected 7,778,101")
        
    if yellow_count == 109047518:
        print("✅ Yellow taxi record count matches expected (109,047,518)")
    else:
        print(f"❌ Yellow taxi record count {yellow_count} doesn't match expected 109,047,518")

if __name__ == "__main__":
    main()