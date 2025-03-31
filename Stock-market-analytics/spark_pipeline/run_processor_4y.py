#!/usr/bin/env python3
import subprocess
import sys
import os
import time
import random
import json
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, DateType
from datetime import datetime, timedelta
from pyspark.sql import Row

# Dependencies are now installed by a separate job
# No need for install_dependencies function anymore

def fetch_stock_data(symbols, start_date, end_date):
    """
    Fetch stock data directly using lower-level HTTP requests instead of yfinance
    to avoid pickle protocol errors in Dataproc environment.
    """
    import requests
    
    # Configure a reliable user agent
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    
    rows = []
    for symbol in symbols:
        try:
            print(f"Fetching data for {symbol}...")
            
            # Format dates for API
            start_str = start_date.strftime('%Y-%m-%d')
            end_str = end_date.strftime('%Y-%m-%d')
            
            # Get stock data directly from Yahoo Finance API
            # Convert start/end to Unix timestamp
            start_ts = int(datetime.strptime(start_str, '%Y-%m-%d').timestamp())
            end_ts = int(datetime.strptime(end_str, '%Y-%m-%d').timestamp())
            
            url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?period1={start_ts}&period2={end_ts}&interval=1d&includePrePost=false"
            
            print(f"Requesting data from URL: {url}")
            response = requests.get(url, headers=headers)
            
            if response.status_code != 200:
                print(f"Error fetching {symbol}: HTTP status {response.status_code}")
                continue
                
            data = response.json()
            
            # Check if we have valid data
            if 'chart' not in data or 'result' not in data['chart'] or not data['chart']['result']:
                print(f"No data available for {symbol}")
                continue
                
            result = data['chart']['result'][0]
            
            if 'timestamp' not in result or not result['timestamp']:
                print(f"No timestamps in data for {symbol}")
                continue
                
            timestamps = result['timestamp']
            quote = result['indicators']['quote'][0]
            
            # Check that we have all required data
            required_fields = ['open', 'high', 'low', 'close', 'volume']
            if not all(field in quote for field in required_fields):
                print(f"Missing required fields in data for {symbol}")
                continue
                
            opens = quote['open']
            highs = quote['high']
            lows = quote['low']
            closes = quote['close']
            volumes = quote['volume']
            
            if len(timestamps) == 0:
                print(f"No data points for {symbol}")
                continue
                
            print(f"Got {len(timestamps)} days of data for {symbol}")
            
            # Create rows for Spark DataFrame
            for i in range(len(timestamps)):
                # Skip None/NaN values
                if None in (opens[i], highs[i], lows[i], closes[i], volumes[i]):
                    continue
                    
                timestamp = timestamps[i]
                date_obj = datetime.fromtimestamp(timestamp).date()
                
                # Only include dates in our target range
                if start_date.date() <= date_obj <= end_date.date():
                    try:
                        rows.append(Row(
                            Symbol=symbol,
                            Date=date_obj,
                            Open=float(opens[i]),
                            High=float(highs[i]),
                            Low=float(lows[i]),
                            Close=float(closes[i]),
                            Volume=int(volumes[i])
                        ))
                    except (ValueError, TypeError) as e:
                        print(f"Skipping data point for {symbol} on {date_obj}: {e}")
                        continue
            
            print(f"Added {len(rows)} rows for {symbol}")
            
        except Exception as e:
            print(f"Error fetching data for {symbol}: {e}")
        
        # Add a delay to avoid rate limiting
        sleep_time = 1 + random.random() * 2
        print(f"Sleeping for {sleep_time:.2f} seconds to avoid rate limiting...")
        time.sleep(sleep_time)
    
    return rows

def get_existing_date_range(spark, dataset_id, table_name="daily_prices"):
    """Get the min and max dates from the existing BigQuery table, along with the symbols present."""
    try:
        # Query existing data's date range
        date_range_df = spark.read.format('bigquery') \
            .option('table', f"{dataset_id}.{table_name}") \
            .load() \
            .select('Date') \
            .agg({'Date': 'min', 'Date': 'max'}) \
            .collect()[0]
        
        min_date = date_range_df['min(Date)']
        max_date = date_range_df['max(Date)']
        
        # Also get the unique symbols and their date ranges to prevent duplicates
        symbol_dates_df = spark.read.format('bigquery') \
            .option('table', f"{dataset_id}.{table_name}") \
            .load() \
            .select('Symbol', 'Date')
        
        # Cache this to avoid repeated BigQuery reads
        symbol_dates_df.cache()
        
        # Count rows to materialize the cache
        row_count = symbol_dates_df.count()
        print(f"Found {row_count} existing records in BigQuery")
        
        print(f"Existing data range: {min_date} to {max_date}")
        return min_date, max_date, symbol_dates_df
    except Exception as e:
        print(f"Error getting existing date range: {e}")
        return None, None, None

def filter_existing_records(new_data_df, existing_data_df):
    """Filter out records that already exist in BigQuery to prevent duplicates."""
    if existing_data_df is None or existing_data_df.count() == 0:
        print("No existing data to filter against, keeping all new records")
        return new_data_df
        
    # Join with existing data and filter out matching records
    print("Filtering out records that already exist in BigQuery...")
    
    # Anti-join to keep only records that don't exist in the current data
    filtered_df = new_data_df.join(
        existing_data_df,
        (new_data_df['Symbol'] == existing_data_df['Symbol']) & 
        (new_data_df['Date'] == existing_data_df['Date']),
        'left_anti'  # Keep only rows that don't match
    )
    
    original_count = new_data_df.count()
    filtered_count = filtered_df.count()
    dropped_count = original_count - filtered_count
    
    print(f"Filtered out {dropped_count} duplicate records")
    print(f"Keeping {filtered_count} new unique records")
    
    return filtered_df

def main():
    try:
        print("Starting stock data processing...")
        
        # Parse command line arguments
        import argparse
        parser = argparse.ArgumentParser(description='Process stock market data')
        parser.add_argument('--project_id', required=True, help='GCP Project ID')
        parser.add_argument('--dataset_id', required=True, help='BigQuery Dataset ID')
        parser.add_argument('--async', default=False, help='Run in async mode')
        args = parser.parse_args()
        
        print("Starting Spark session initialization...")
        spark = SparkSession.builder \
            .appName("Fortune500StockProcessor4Y") \
            .getOrCreate()

        print("Defining schema...")
        schema = StructType([
            StructField("Symbol", StringType(), True),
            StructField("Date", DateType(), True),
            StructField("Open", DoubleType(), True),
            StructField("High", DoubleType(), True),
            StructField("Low", DoubleType(), True),
            StructField("Close", DoubleType(), True),
            StructField("Volume", DoubleType(), True)
        ])

        print("Reading Fortune 500 symbols from CSV...")
        # Read CSV as single column with no header
        fortune500_df = spark.read.csv('gs://stock-market-raw-dev/data/fortune500.csv', header=False)
        # Extract symbols from the first column
        symbols = [row._c0 for row in fortune500_df.collect()]
        
        # Only use test symbols if we have a lot of symbols
        if len(symbols) > 20:  # Only use test symbols if we have a lot of symbols
            print(f"Processing all {len(symbols)} Fortune 500 symbols")
            # Use all symbols (no longer limiting to test symbols)
            # symbols = test_symbols
        
        print(f"Processing {len(symbols)} symbols: {', '.join(symbols[:5])}... and {len(symbols)-5} more")
        
        # Get existing date range and symbol-date pairs
        existing_min_date, existing_max_date, existing_data_df = get_existing_date_range(spark, args.dataset_id)
        
        # Set target date range for 4 years
        end_date = datetime.now()
        target_start_date = end_date - timedelta(days=1460)  # 4 years of data (365*4 = 1460)
        
        if existing_min_date and existing_max_date:
            # Only fetch data for dates we don't have
            if target_start_date.date() < existing_min_date:
                # Need to fetch older data
                end_date = datetime.fromordinal(existing_min_date.toordinal() - 1)
                start_date = datetime.fromordinal(target_start_date.date().toordinal())
                print(f"Fetching older data from {start_date.date()} to {end_date.date()}")
            else:
                print("Already have all historical data needed")
                sys.exit(0)
        else:
            # No existing data, fetch everything
            start_date = target_start_date
            print(f"No existing data found. Fetching full range from {start_date.date()} to {end_date.date()}")
        
        # Process in smaller batches
        batch_size = 10  # Increased from 5 to 10 for faster processing
        rows = []
        total_batches = (len(symbols) + batch_size - 1) // batch_size
        
        for i in range(0, len(symbols), batch_size):
            batch_symbols = symbols[i:i+batch_size]
            print(f"\nProcessing batch {i//batch_size + 1} of {total_batches}")
            batch_rows = fetch_stock_data(batch_symbols, start_date, end_date)
            rows.extend(batch_rows)
            print(f"Batch {i//batch_size + 1} complete - Total rows so far: {len(rows)}")
            # Add a delay between batches
            time.sleep(5)
        
        if rows:
            print("Converting to Spark DataFrame...")
            new_data_df = spark.createDataFrame(rows)
            
            print("\nSample of fetched data:")
            new_data_df.show(5)
            
            # Filter out records that already exist in BigQuery
            if existing_data_df is not None:
                filtered_df = filter_existing_records(new_data_df, existing_data_df)
                
                # If no new records after filtering, exit
                if filtered_df.count() == 0:
                    print("No new unique records to insert. Exiting.")
                    sys.exit(0)
            else:
                filtered_df = new_data_df
                print("No existing data to filter against, proceeding with all new records")
            
            print("\nSaving to BigQuery...")
            # Write to BigQuery in APPEND mode
            filtered_df.write \
                .format('bigquery') \
                .option('table', f"{args.dataset_id}.daily_prices") \
                .option('temporaryGcsBucket', 'stock-market-raw-dev') \
                .mode('append') \
                .save()
            
            print("Data successfully saved to BigQuery!")
        else:
            print("No data was collected!")
            
    except Exception as e:
        print(f"An error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
