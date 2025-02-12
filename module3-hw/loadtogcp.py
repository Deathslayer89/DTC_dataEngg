# import subprocess
# import os
# from google.cloud import storage
# import time

# # Configuration
# BUCKET_NAME = "ny-taxidata-bucket"  # Change this to your bucket name
# CREDENTIALS_FILE = "C:\\Users\\dines\\Downloads\\zoomcamp-450020-df164a1333c8.json"  # Your service account key file
# BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-"
# MONTHS = [f"{i:02d}" for i in range(1, 7)]


# # Initialize GCS client
# client = storage.Client.from_service_account_json(CREDENTIALS_FILE)
# bucket = client.bucket(BUCKET_NAME)

# def download_and_upload(month):
#     url = f"{BASE_URL}{month}.parquet"
#     filename = f"yellow_tripdata_2024-{month}.parquet"
    
#     try:
#         # Use wget to download (more reliable for large files)
#         print(f"Downloading {filename}...")
#         subprocess.run(['wget', '--no-verbose', url, '-O', filename], check=True)
        
#         # Upload to GCS
#         print(f"Uploading {filename} to GCS...")
#         blob = bucket.blob(filename)
#         blob.upload_from_filename(filename)
        
#         # Verify upload
#         if blob.exists():
#             print(f"Successfully uploaded {filename}")
            
#         # Clean up local file
#         os.remove(filename)
#         print(f"Cleaned up local file {filename}")
        
#         return True
        
#     except Exception as e:
#         print(f"Error processing {filename}: {e}")
#         # Clean up in case of failure
#         if os.path.exists(filename):
#             os.remove(filename)
#         return False

# def main():
#     print(f"Starting uploads to bucket: {BUCKET_NAME}")
    
#     results = []
#     for month in MONTHS:
#         success = download_and_upload(month)
#         results.append(success)
#         # Add small delay between files
#         time.sleep(2)
    
#     # Summary
#     successful = sum(1 for r in results if r)
#     print(f"\nUpload Summary:")
#     print(f"Successfully uploaded: {successful}/{len(MONTHS)} files")
#     print(f"Failed uploads: {len(MONTHS) - successful}")

# if __name__ == "__main__":
#     main()

import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from google.cloud import storage
import time


#Change this to your bucket name
BUCKET_NAME = "ny-taxidata-bucket"

#If you authenticated through the GCP SDK you can comment out these two lines
CREDENTIALS_FILE = "C:\\Users\\dines\\Downloads\\zoomcamp-450020-df164a1333c8.json" 
client = storage.Client.from_service_account_json(CREDENTIALS_FILE)


BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-"
MONTHS = [f"{i:02d}" for i in range(1, 7)] 
DOWNLOAD_DIR = "."

CHUNK_SIZE = 8 * 1024 * 1024  

os.makedirs(DOWNLOAD_DIR, exist_ok=True)

bucket = client.bucket(BUCKET_NAME)


def download_file(month):
    url = f"{BASE_URL}{month}.parquet"
    file_path = os.path.join(DOWNLOAD_DIR, f"yellow_tripdata_2024-{month}.parquet")

    try:
        print(f"Downloading {url}...")
        urllib.request.urlretrieve(url, file_path)
        print(f"Downloaded: {file_path}")
        return file_path
    except Exception as e:
        print(f"Failed to download {url}: {e}")
        return None


def verify_gcs_upload(blob_name):
    return storage.Blob(bucket=bucket, name=blob_name).exists(client)


def upload_to_gcs(file_path, max_retries=3):
    blob_name = os.path.basename(file_path)
    blob = bucket.blob(blob_name)
    blob.chunk_size = CHUNK_SIZE  
    
    for attempt in range(max_retries):
        try:
            print(f"Uploading {file_path} to {BUCKET_NAME} (Attempt {attempt + 1})...")
            blob.upload_from_filename(file_path)
            print(f"Uploaded: gs://{BUCKET_NAME}/{blob_name}")
            
            if verify_gcs_upload(blob_name):
                print(f"Verification successful for {blob_name}")
                return
            else:
                print(f"Verification failed for {blob_name}, retrying...")
        except Exception as e:
            print(f"Failed to upload {file_path} to GCS: {e}")
        
        time.sleep(5)  
    
    print(f"Giving up on {file_path} after {max_retries} attempts.")


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=4) as executor:
        file_paths = list(executor.map(download_file, MONTHS))

    with ThreadPoolExecutor(max_workers=4) as executor:
        executor.map(upload_to_gcs, filter(None, file_paths))  # Remove None values

    print("All files processed and verified.")