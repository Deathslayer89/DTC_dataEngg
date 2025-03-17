import pandas as pd
import json
from kafka import KafkaProducer
from time import time

def json_serializer(data):
    # Convert datetime objects to string format
    for key, value in data.items():
        if pd.isna(value):  # Handle NaN values
            data[key] = None
        elif isinstance(value, pd.Timestamp):
            data[key] = value.strftime('%Y-%m-%d %H:%M:%S')
    return json.dumps(data).encode('utf-8')

# Initialize producer
producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=json_serializer
)

# Columns we want to keep
columns = [
    'lpep_pickup_datetime',
    'lpep_dropoff_datetime',
    'PULocationID',
    'DOLocationID',
    'passenger_count',
    'trip_distance',
    'tip_amount'
]

t0 = time()

# Read the gzipped CSV file
print("Starting to read CSV file...")
df = pd.read_csv(
    'green_tripdata_2019-10.csv.gz',
    compression='gzip',
    usecols=columns,
    parse_dates=['lpep_pickup_datetime', 'lpep_dropoff_datetime']
)

print(f"Found {len(df)} records. Starting to send messages...")

# Send each row as a message
for idx, row in df.iterrows():
    message = row.to_dict()
    producer.send('green-trips', value=message)
    
    # Print progress every 10000 records
    if (idx + 1) % 10000 == 0:
        print(f"Sent {idx + 1} messages...")

# Ensure all messages are sent
producer.flush()

t1 = time()
took = t1 - t0
print(f"Total time taken: {took:.2f} seconds")
print("All messages sent successfully!")