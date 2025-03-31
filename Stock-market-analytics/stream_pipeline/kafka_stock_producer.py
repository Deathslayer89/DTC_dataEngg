#!/usr/bin/env python3
"""
Kafka Stock Producer
Fetches stock prices and publishes them to a Kafka topic
"""
import os
import sys
import csv
import json
import time
import logging
import argparse
import threading
import socket
import ssl
from datetime import datetime
import backoff
import requests
import yfinance as yf
from kafka import KafkaProducer
from kafka.errors import KafkaError

# Configure logging
logging.basicConfig(level=logging.INFO,
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('kafka_stock_producer')

# Default configuration
DEFAULT_BOOTSTRAP_SERVERS = "localhost:9092"
DEFAULT_KAFKA_TOPIC = "stock-market-data"
DEFAULT_UPDATE_INTERVAL = 3600  # 1 hour default
DEFAULT_SYMBOLS_FILE = "fortune500.csv"
DEFAULT_MAX_RETRY_ATTEMPTS = 5
DEFAULT_BATCH_SIZE = 25  # Process stocks in batches

class KafkaStockProducer:
    def __init__(self, bootstrap_servers, topic, update_interval, symbols_file, 
                max_retries, batch_size):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.update_interval = update_interval
        self.symbols_file = symbols_file
        self.max_retries = max_retries
        self.batch_size = batch_size
        self.running = False
        self.producer = None

    def load_symbols(self):
        """Load stock symbols from CSV file"""
        symbols = []
        if not os.path.exists(self.symbols_file):
            logger.warning(f"Symbols file not found at {self.symbols_file}. Using default symbols.")
            return ["AAPL", "MSFT", "GOOGL", "AMZN", "META"]

        with open(self.symbols_file, 'r') as f:
            reader = csv.reader(f)
            for row in reader:
                if row and row[0].strip():  # Skip empty rows
                    symbols.append(row[0].strip())
        
        if not symbols:
            logger.warning("No valid symbols found in CSV. Using default symbols.")
            return ["AAPL", "MSFT", "GOOGL", "AMZN", "META"]
        
        logger.info(f"Loaded {len(symbols)} symbols from {self.symbols_file}")
        return symbols

    def connect_kafka(self):
        """Connect to Kafka broker"""
        try:
            self.producer = KafkaProducer(
                bootstrap_servers=self.bootstrap_servers,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                retries=self.max_retries,
                acks='all',
                batch_size=16384,
                linger_ms=100,
                request_timeout_ms=60000
            )
            logger.info(f"Connected to Kafka at {self.bootstrap_servers}")
            return True
        except KafkaError as e:
            logger.error(f"Failed to connect to Kafka: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error connecting to Kafka: {e}")
            return False

    @backoff.on_exception(
        backoff.expo,
        (requests.exceptions.RequestException, ssl.SSLError, socket.timeout, ConnectionError),
        max_tries=5,
        jitter=backoff.full_jitter,
        on_backoff=lambda details: logger.warning(
            f"Backing off {details['wait']:0.1f} seconds after {details['tries']} tries. Error: {details['exception']}"
        )
    )
    def get_stock_data(self, symbol):
        """Fetch stock data from Yahoo Finance with enhanced retry"""
        try:
            # Set a timeout for the request
            stock = yf.Ticker(symbol)
            
            # Try to get the information with a timeout
            info = stock.fast_info
            
            data = {
                'symbol': symbol,
                'timestamp': datetime.now().isoformat(),
                'price': info.last_price if hasattr(info, 'last_price') else None,
                'volume': info.last_volume if hasattr(info, 'last_volume') else None,
                'currency': info.currency if hasattr(info, 'currency') else 'USD'
            }
            
            if data['price'] is None:
                logger.warning(f"Symbol {symbol} appears to be delisted or not available. No price data found.")
            
            return data
        except (requests.exceptions.SSLError, ssl.SSLError) as e:
            logger.error(f"SSL error fetching data for {symbol}: {e}")
            raise  # Let backoff handle the retry
        except requests.exceptions.ConnectionError as e:
            logger.error(f"Connection error fetching data for {symbol}: {e}")
            raise  # Let backoff handle the retry
        except socket.timeout as e:
            logger.error(f"Timeout error fetching data for {symbol}: {e}")
            raise  # Let backoff handle the retry
        except Exception as e:
            logger.error(f"Error fetching data for {symbol}: {e}")
            # Return None for non-connection related errors
            return None

    def send_to_kafka(self, data):
        """Send data to Kafka"""
        if not data or not data.get('price'):
            logger.warning(f"Skipping invalid data: {data}")
            return False
        
        try:
            future = self.producer.send(
                self.topic, 
                value=data, 
                key=data['symbol'].encode('utf-8')
            )
            # Block to ensure the message was sent (with timeout)
            record_metadata = future.get(timeout=10)
            
            logger.info(f"Published {data['symbol']} to topic {record_metadata.topic}, "
                        f"partition {record_metadata.partition}, offset {record_metadata.offset}")
            return True
        except KafkaError as e:
            logger.error(f"Error sending to Kafka: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error sending to Kafka: {e}")
            return False

    def process_batch(self, symbols_batch):
        """Process a batch of symbols"""
        successful = 0
        total = len(symbols_batch)
        
        for symbol in symbols_batch:
            try:
                data = self.get_stock_data(symbol)
                if data:
                    success = self.send_to_kafka(data)
                    if success:
                        successful += 1
                
                # Add a small delay between calls to avoid rate limiting
                time.sleep(0.5 + 0.5 * (successful % 2))  # Vary delay slightly
            
            except Exception as e:
                logger.error(f"Failed to process {symbol}: {e}")
                continue  # Continue with next symbol
        
        logger.info(f"Batch completed. Successfully processed {successful}/{total} symbols.")
        return successful

    def start(self):
        """Start the stock data producer"""
        if self.running:
            logger.warning("Producer is already running")
            return
        
        # Load symbols and connect to Kafka
        symbols = self.load_symbols()
        if not symbols:
            logger.error("No symbols to process. Exiting.")
            return
        
        if not self.connect_kafka():
            logger.error("Failed to connect to Kafka. Exiting.")
            return
        
        self.running = True
        logger.info(f"Starting stock producer with {len(symbols)} symbols, "
                    f"update interval: {self.update_interval} seconds")
        
        try:
            while self.running:
                start_time = time.time()
                total_symbols = len(symbols)
                processed_symbols = 0
                
                # Process symbols in batches
                for i in range(0, total_symbols, self.batch_size):
                    batch = symbols[i:i+self.batch_size]
                    logger.info(f"Processing batch {i//self.batch_size + 1}/{(total_symbols+self.batch_size-1)//self.batch_size}: {len(batch)} symbols")
                    
                    processed = self.process_batch(batch)
                    processed_symbols += processed
                    
                    # Early exit if stopped
                    if not self.running:
                        break
                
                logger.info(f"Completed processing cycle. Successfully processed {processed_symbols}/{total_symbols} symbols.")
                
                # Calculate sleep time (or early exit if a cycle took longer than the interval)
                elapsed = time.time() - start_time
                if elapsed < self.update_interval and self.running:
                    sleep_time = self.update_interval - elapsed
                    logger.info(f"Waiting {sleep_time:.1f} seconds until next update cycle")
                    
                    # Sleep in smaller increments to allow for cleaner shutdown
                    for _ in range(int(sleep_time / 10) + 1):
                        if not self.running:
                            break
                        time.sleep(min(10, sleep_time))
                        sleep_time -= 10
        
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received. Shutting down...")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
        finally:
            self.stop()
    
    def stop(self):
        """Stop the producer"""
        if not self.running:
            return
        
        self.running = False
        logger.info("Stopping stock producer...")
        
        if self.producer:
            self.producer.flush()  # Ensure all messages are sent
            self.producer.close(timeout=5)
            logger.info("Kafka producer closed")

def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Kafka Stock Price Producer')
    parser.add_argument('--bootstrap-servers', type=str, default=os.getenv('KAFKA_BOOTSTRAP_SERVERS', DEFAULT_BOOTSTRAP_SERVERS),
                        help='Kafka bootstrap servers')
    parser.add_argument('--topic', type=str, default=os.getenv('KAFKA_TOPIC', DEFAULT_KAFKA_TOPIC),
                        help='Kafka topic')
    parser.add_argument('--interval', type=int, default=int(os.getenv('STOCK_UPDATE_INTERVAL', DEFAULT_UPDATE_INTERVAL)),
                        help='Update interval in seconds')
    parser.add_argument('--symbols-file', type=str, default=os.getenv('SYMBOLS_FILE', DEFAULT_SYMBOLS_FILE),
                        help='CSV file with stock symbols')
    parser.add_argument('--max-retries', type=int, default=int(os.getenv('MAX_RETRY_ATTEMPTS', DEFAULT_MAX_RETRY_ATTEMPTS)),
                        help='Maximum retry attempts')
    parser.add_argument('--batch-size', type=int, default=int(os.getenv('BATCH_SIZE', DEFAULT_BATCH_SIZE)),
                        help='Number of symbols to process in one batch')
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()
    
    producer = KafkaStockProducer(
        bootstrap_servers=args.bootstrap_servers,
        topic=args.topic,
        update_interval=args.interval,
        symbols_file=args.symbols_file,
        max_retries=args.max_retries,
        batch_size=args.batch_size
    )
    
    try:
        producer.start()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    finally:
        producer.stop() 