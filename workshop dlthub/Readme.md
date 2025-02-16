# Data Ingestion with dlt: Homework Solution

[Link to solution notebook](DEZoomcamp_dlt_Homework.ipynb)

## Question 1: dlt Version
Installed dlt with DuckDB support and checked version:
```bash
pip install dlt[duckdb]
dlt --version
```
```python
import dlt
print("dlt version:", dlt.__version__)
```
Answer:  dlt 1.6.1

## Question 2: Define & Run the Pipeline
Created pipeline for NYC Taxi API data:
```python
import dlt
from dlt.sources.helpers.rest_client import RESTClient
from dlt.sources.helpers.rest_client.paginators import PageNumberPaginator

@dlt.resource(name="rides")
def ny_taxi():
    client = RESTClient(
        base_url=API_URL,
        paginator=PageNumberPaginator(
            base_page=1,
            total_path=None
        )
    )
    for page in client.paginate("data_engineering_zoomcamp_api"):
        yield page

pipeline = dlt.pipeline(destination="duckdb")
load_info = pipeline.run(ny_taxi, write_disposition="replace")
```

Connected to DuckDB and examined tables:
```python
conn = duckdb.connect(f"{pipeline.pipeline_name}.duckdb")
conn.sql(f"SET search_path = '{pipeline.dataset_name}'")
conn.sql("DESCRIBE").df()
```
Answer: 4 tables were created

## Question 3: Explore the loaded data
Examined the rides table:
```python
df = pipeline.dataset(dataset_type="default").rides.df()
```
Answer: 10000 total records extracted

## Question 4: Trip Duration Analysis
Calculated average trip duration:
```sql
SELECT AVG(date_diff('minute', trip_pickup_date_time, trip_dropoff_date_time))
FROM rides;
```
Answer: 12.3049 minutes average trip duration