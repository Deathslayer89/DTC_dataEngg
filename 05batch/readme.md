# Yellow Taxi Data Analysis with PySpark

[View My Analysis Notebook](05_batch_hw.ipynb)

## Setup

I used a Linux environment with Python 3.10 and created a virtual environment named 'zoomcamp'. I installed PySpark 3.4.1 along with the necessary dependencies.

```bash
python3 -m venv zoomcamp
source zoomcamp/bin/activate
pip install pyspark==3.4.1 jupyter pandas
```

## Data

I used the following datasets stored in `/home/dineshswain2001/data/`:
- `yellow_tripdata_2024-10.parquet`: Main taxi trip dataset
- `taxi_zone_lookup.csv`: Location ID mapping table

## Question Solutions

### Question 1: Schema Exploration

I first set up a Spark session and loaded the yellow taxi dataset:

```python
spark = SparkSession.builder \
    .appName("Yellow Taxi Analysis") \
    .master("local[*]") \
    .getOrCreate()

df = spark.read.parquet("/home/dineshswain2001/data/yellow_tripdata_2024-10.parquet")
df.printSchema()
```

This showed me all the columns in the dataset including timestamps, passenger details, and payment information.

### Question 2: Data Repartitioning

I repartitioned the dataset into 4 files and saved them to a new location:

```python
df_repartitioned = df.repartition(4)
output_path = "/home/dineshswain2001/data/yellow_tripdata_repartitioned"
df_repartitioned.write.mode('overwrite').parquet(output_path)
```

Then I calculated the file statistics:

```python
parquet_files = [f for f in os.listdir(output_path) if f.endswith('.parquet')]
total_size_bytes = sum(os.path.getsize(os.path.join(output_path, f)) for f in parquet_files)
avg_size_mb = (total_size_bytes / len(parquet_files)) / (1024 * 1024)
```

This showed that the 4 parquet files had an average size of 23.04 MB.

### Question 3: Trip Count for October 15th

I used date functions to filter trips that occurred on October 15th, 2024:

```python
from pyspark.sql.functions import dayofmonth, month, year

oct_15_trips = df.filter(
    (year(df.tpep_pickup_datetime) == 2024) & 
    (month(df.tpep_pickup_datetime) == 10) & 
    (dayofmonth(df.tpep_pickup_datetime) == 15)
)

trip_count = oct_15_trips.count()
```

This revealed 128,893 trips occurred on that specific day.

### Question 4: Longest Trip Duration

To find the longest trip, I calculated the duration between pickup and dropoff times in hours:

```python
from pyspark.sql.functions import col, unix_timestamp, max

df_with_duration = df.withColumn(
    "trip_duration_seconds", 
    unix_timestamp(col("tpep_dropoff_datetime")) - unix_timestamp(col("tpep_pickup_datetime"))
)

df_with_duration = df_with_duration.withColumn(
    "trip_duration_hours", 
    col("trip_duration_seconds") / 3600
)

max_duration = df_with_duration.select(max("trip_duration_hours")).collect()[0][0]
```

I found that the longest trip was 162.62 hours (about 6.8 days).

### Question 5: Least Frequent Pickup Zone

I loaded the zone lookup table and joined it with the trip data to find zones with the fewest pickups:

```python
zones_df = spark.read.option("header", "true").csv("/home/dineshswain2001/data/taxi_zone_lookup.csv")
zones_df.createOrReplaceTempView("zones")
df.createOrReplaceTempView("trips")

query = """
SELECT z.Zone, COUNT(*) as trip_count
FROM trips t
JOIN zones z ON t.PULocationID = z.LocationID
GROUP BY z.Zone
ORDER BY trip_count ASC
LIMIT 1
"""

least_frequent_zone = spark.sql(query)
```

This showed that "Governor's Island/Ellis Island/Liberty Island" had only 1 pickup, making it the least frequent pickup zone in the dataset.