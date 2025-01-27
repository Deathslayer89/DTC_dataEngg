import pandas as pd
from sqlalchemy import create_engine

# Create PostgreSQL connection
engine = create_engine('postgresql://postgres:postgres@localhost:5433/ny_taxi')

# Read and ingest taxi zone lookup data
df_zones = pd.read_csv('data/taxi_zone_lookup.csv')
df_zones.to_sql('taxi_zone_lookup', engine, if_exists='replace', index=False)

# Read and ingest trip data
df_trips = pd.read_csv('data/green_tripdata_2019-10.csv')
df_trips.to_sql('green_taxi_trips', engine, if_exists='replace', index=False)