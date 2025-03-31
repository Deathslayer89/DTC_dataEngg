#!/usr/bin/env python3
"""
Kafka to BigQuery Consumer
Reads stock data from Kafka topic and writes to BigQuery
"""
import os
import sys
import json
import time
import logging
import argparse
import threading
import signal
from datetime import datetime
import backoff
from google.cloud import bigquery
from google.api_core import retry, exceptions
from kafka import KafkaConsumer
from kafka.errors import KafkaError

# Configure logging
logging.basicConfig(level=logging.INFO,
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('kafka_bigquery_consumer')

# Default configuration
DEFAULT_BOOTSTRAP_SERVERS = "localhost:9092"
DEFAULT_KAFKA_TOPIC = "stock-market-data"
DEFAULT_CONSUMER_GROUP = "bigquery-consumer"
DEFAULT_BIGQUERY_TABLE = "stock_market_analytics.stock_prices_realtime"
DEFAULT_MAX_RETRY_ATTEMPTS = 5
DEFAULT_BATCH_SIZE = 100  # Number of messages to batch for BigQuery
DEFAULT_BATCH_TIMEOUT = 60  # Max seconds between BigQuery inserts

class KafkaToBigQueryConsumer:
    def __init__(self, bootstrap_servers, topic, consumer_group, project_id, 
                 bigquery_table, max_retries, batch_size, batch_timeout):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.consumer_group = consumer_group
        self.project_id = project_id
        self.bigquery_table = bigquery_table
        self.max_retries = max_retries
        self.batch_size = batch_size
        self.batch_timeout = batch_timeout
        self.running = False
        self.consumer = None
        self.bq_client = None
        self.message_buffer = []
        self.last_insert_time = time.time()

    def connect_kafka(self):
        """Connect to Kafka as a consumer"""
        try:
            self.consumer = KafkaConsumer(
                self.topic,
                bootstrap_servers=self.bootstrap_servers,
                group_id=self.consumer_group,
                auto_offset_reset='latest',
                enable_auto_commit=False,  # Manual commit for better control
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                session_timeout_ms=30000,
                request_timeout_ms=60000,
                max_poll_interval_ms=300000,  # 5 minutes
                max_poll_records=self.batch_size
            )
            logger.info(f"Connected to Kafka at {self.bootstrap_servers}")
            logger.info(f"Subscribed to topic: {self.topic}")
            return True
        except KafkaError as e:
            logger.error(f"Failed to connect to Kafka: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error connecting to Kafka: {e}")
            return False

    def connect_bigquery(self):
        """Connect to BigQuery"""
        try:
            self.bq_client = bigquery.Client(project=self.project_id)
            
            # Check if table exists, create it if not
            try:
                self.bq_client.get_table(self.bigquery_table)
                logger.info(f"BigQuery table {self.bigquery_table} exists")
            except exceptions.NotFound:
                logger.info(f"Creating BigQuery table {self.bigquery_table}")
                
                # Parse dataset and table from the full table name
                dataset_id, table_id = self.bigquery_table.split('.')
                dataset_ref = self.bq_client.dataset(dataset_id)
                table_ref = dataset_ref.table(table_id)
                
                schema = [
                    bigquery.SchemaField("symbol", "STRING", mode="REQUIRED"),
                    bigquery.SchemaField("timestamp", "TIMESTAMP", mode="REQUIRED"),
                    bigquery.SchemaField("price", "FLOAT", mode="NULLABLE"),
                    bigquery.SchemaField("volume", "INTEGER", mode="NULLABLE"),
                    bigquery.SchemaField("currency", "STRING", mode="NULLABLE"),
                ]
                
                table = bigquery.Table(table_ref, schema=schema)
                table.time_partitioning = bigquery.TimePartitioning(
                    type_=bigquery.TimePartitioningType.DAY,
                    field="timestamp"
                )
                
                self.bq_client.create_table(table)
                logger.info(f"Created BigQuery table {self.bigquery_table}")
            
            return True
        except Exception as e:
            logger.error(f"Failed to connect to BigQuery: {e}")
            return False

    @backoff.on_exception(
        backoff.expo,
        exceptions.GoogleAPIError,
        max_tries=5,
        jitter=backoff.full_jitter,
        on_backoff=lambda details: logger.warning(
            f"Backing off BigQuery insert {details['wait']:0.1f} seconds after {details['tries']} tries"
        )
    )
    def write_to_bigquery(self, messages):
        """Write batch of messages to BigQuery"""
        if not messages:
            return True
        
        try:
            rows_to_insert = []
            for msg in messages:
                row = {
                    'symbol': msg['symbol'],
                    'timestamp': msg['timestamp'],
                    'price': msg['price'],
                    'volume': msg['volume'],
                    'currency': msg['currency']
                }
                rows_to_insert.append(row)
            
            # Use custom retry with the insert_rows_json call
            retry_config = retry.Retry(
                initial=1.0,
                maximum=60.0,
                multiplier=2.0,
                predicate=retry.if_exception_type(
                    exceptions.ServiceUnavailable,
                    exceptions.InternalServerError,
                    exceptions.TooManyRequests,
                ),
                deadline=300.0  # 5 minutes total deadline
            )
            
            errors = self.bq_client.insert_rows_json(
                self.bigquery_table, 
                rows_to_insert,
                retry=retry_config
            )
            
            if errors:
                logger.error(f"Errors inserting to BigQuery: {errors}")
                return False
            else:
                symbol_count = {}
                for msg in messages:
                    symbol = msg['symbol']
                    symbol_count[symbol] = symbol_count.get(symbol, 0) + 1
                
                symbols_str = ', '.join([f"{s}({c})" for s, c in symbol_count.items()])
                logger.info(f"Successfully wrote {len(messages)} records to BigQuery: {symbols_str}")
                return True
        
        except Exception as e:
            logger.error(f"Error writing to BigQuery: {e}")
            raise
    
    def process_messages(self):
        """Process messages from buffer and commit offsets"""
        if not self.message_buffer:
            return
        
        try:
            # Write messages to BigQuery
            success = self.write_to_bigquery(self.message_buffer)
            
            if success:
                # Commit offsets to Kafka
                self.consumer.commit()
                logger.info(f"Committed offsets after processing {len(self.message_buffer)} messages")
                
                # Clear the buffer after successful write and commit
                self.message_buffer = []
                self.last_insert_time = time.time()
            else:
                logger.error("Failed to write to BigQuery, will retry on next batch")
        except Exception as e:
            logger.error(f"Error processing message batch: {e}")
            # We don't clear the buffer so we can retry

    def start(self):
        """Start the Kafka to BigQuery consumer"""
        if self.running:
            logger.warning("Consumer is already running")
            return
        
        # Connect to Kafka and BigQuery
        if not self.connect_kafka():
            logger.error("Failed to connect to Kafka. Exiting.")
            return
        
        if not self.connect_bigquery():
            logger.error("Failed to connect to BigQuery. Exiting.")
            return
        
        self.running = True
        logger.info(f"Starting Kafka to BigQuery consumer on topic {self.topic}, "
                    f"writing to {self.bigquery_table}")
        
        try:
            while self.running:
                # Poll for messages
                poll_response = self.consumer.poll(timeout_ms=1000)
                
                if not poll_response:
                    # Check if it's time to process a partial batch due to timeout
                    if self.message_buffer and (time.time() - self.last_insert_time) > self.batch_timeout:
                        logger.info(f"Processing {len(self.message_buffer)} messages due to batch timeout")
                        self.process_messages()
                    continue
                
                # Process messages from each partition
                for tp, messages in poll_response.items():
                    for message in messages:
                        try:
                            # Add the message value to our buffer
                            self.message_buffer.append(message.value)
                            
                            # Debug log
                            if len(self.message_buffer) % 10 == 0:
                                logger.debug(f"Buffer size: {len(self.message_buffer)}")
                        except Exception as e:
                            logger.error(f"Error processing message: {e}")
                
                # Process messages if we have enough or enough time has passed
                if len(self.message_buffer) >= self.batch_size:
                    logger.info(f"Processing batch of {len(self.message_buffer)} messages")
                    self.process_messages()
                elif self.message_buffer and (time.time() - self.last_insert_time) > self.batch_timeout:
                    logger.info(f"Processing {len(self.message_buffer)} messages due to batch timeout")
                    self.process_messages()
        
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received. Shutting down...")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
        finally:
            self.stop()
    
    def stop(self):
        """Stop the consumer"""
        if not self.running:
            return
        
        self.running = False
        logger.info("Stopping Kafka to BigQuery consumer...")
        
        # Process any remaining messages
        if self.message_buffer:
            logger.info(f"Processing {len(self.message_buffer)} remaining messages")
            self.process_messages()
        
        # Close connections
        if self.consumer:
            try:
                self.consumer.close()
                logger.info("Kafka consumer closed")
            except Exception as e:
                logger.error(f"Error closing Kafka consumer: {e}")
        
        if self.bq_client:
            logger.info("BigQuery client closed")

def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Kafka to BigQuery Consumer')
    parser.add_argument('--bootstrap-servers', type=str, default=os.getenv('KAFKA_BOOTSTRAP_SERVERS', DEFAULT_BOOTSTRAP_SERVERS),
                        help='Kafka bootstrap servers')
    parser.add_argument('--topic', type=str, default=os.getenv('KAFKA_TOPIC', DEFAULT_KAFKA_TOPIC),
                        help='Kafka topic')
    parser.add_argument('--consumer-group', type=str, default=os.getenv('CONSUMER_GROUP', DEFAULT_CONSUMER_GROUP),
                        help='Kafka consumer group ID')
    parser.add_argument('--project-id', type=str, required=True,
                        help='GCP project ID')
    parser.add_argument('--bigquery-table', type=str, default=os.getenv('BIGQUERY_TABLE', DEFAULT_BIGQUERY_TABLE),
                        help='BigQuery table ID (dataset.table)')
    parser.add_argument('--max-retries', type=int, default=int(os.getenv('MAX_RETRY_ATTEMPTS', DEFAULT_MAX_RETRY_ATTEMPTS)),
                        help='Maximum retry attempts')
    parser.add_argument('--batch-size', type=int, default=int(os.getenv('BATCH_SIZE', DEFAULT_BATCH_SIZE)),
                        help='Number of messages to batch for BigQuery')
    parser.add_argument('--batch-timeout', type=int, default=int(os.getenv('BATCH_TIMEOUT', DEFAULT_BATCH_TIMEOUT)),
                        help='Maximum seconds between BigQuery inserts')
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()
    
    # Set up signal handlers
    def signal_handler(sig, frame):
        logger.info(f"Received signal {sig}, shutting down...")
        if consumer and consumer.running:
            consumer.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Create and run the consumer
    consumer = KafkaToBigQueryConsumer(
        bootstrap_servers=args.bootstrap_servers,
        topic=args.topic,
        consumer_group=args.consumer_group,
        project_id=args.project_id,
        bigquery_table=args.bigquery_table,
        max_retries=args.max_retries,
        batch_size=args.batch_size,
        batch_timeout=args.batch_timeout
    )
    
    try:
        consumer.start()
    except Exception as e:
        logger.error(f"Error running consumer: {e}")
    finally:
        if consumer.running:
            consumer.stop() 