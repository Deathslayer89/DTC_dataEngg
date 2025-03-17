from pyflink.table import (
    EnvironmentSettings, TableEnvironment, DataTypes
)
from pyflink.table.expressions import col

def create_kafka_source_ddl():
    return """
        CREATE TABLE green_trips (
            lpep_pickup_datetime TIMESTAMP(3),
            lpep_dropoff_datetime TIMESTAMP(3),
            PULocationID INT,
            DOLocationID INT,
            passenger_count INT,
            trip_distance DOUBLE,
            tip_amount DOUBLE,
            event_time AS lpep_dropoff_datetime,
            WATERMARK FOR event_time AS event_time - INTERVAL '5' SECONDS
        ) WITH (
            'connector' = 'kafka',
            'topic' = 'green-trips',
            'properties.bootstrap.servers' = 'redpanda-1:29092',
            'properties.group.id' = 'test_group',
            'scan.startup.mode' = 'earliest-offset',
            'format' = 'json'
        )
    """

def create_postgres_sink_ddl():
    return """
        CREATE TABLE taxi_sessions (
            pu_location_id INT,
            do_location_id INT,
            trip_count BIGINT,
            window_start TIMESTAMP(3),
            window_end TIMESTAMP(3),
            PRIMARY KEY (pu_location_id, do_location_id, window_start) NOT ENFORCED
        ) WITH (
            'connector' = 'jdbc',
            'url' = 'jdbc:postgresql://postgres:5432/postgres',
            'table-name' = 'taxi_sessions',
            'username' = 'postgres',
            'password' = 'postgres',
            'driver' = 'org.postgresql.Driver'
        )
    """

def create_session_window_query():
    return """
        INSERT INTO taxi_sessions
        SELECT 
            PULocationID as pu_location_id,
            DOLocationID as do_location_id,
            COUNT(*) as trip_count,
            SESSION_START(event_time, INTERVAL '5' MINUTES) as window_start,
            SESSION_END(event_time, INTERVAL '5' MINUTES) as window_end
        FROM green_trips
        GROUP BY 
            PULocationID, 
            DOLocationID,
            SESSION(event_time, INTERVAL '5' MINUTES)
    """

def main():
    # Create a Table Environment
    env_settings = EnvironmentSettings.in_streaming_mode()
    t_env = TableEnvironment.create(env_settings)
    
    # Add Kafka and JDBC connectors to the classpath
    kafka_jar = "file:///opt/flink/lib/flink-sql-connector-kafka-1.16.0.jar"
    jdbc_jar = "file:///opt/flink/lib/flink-connector-jdbc-1.16.0.jar"
    postgres_jar = "file:///opt/flink/lib/postgresql-42.2.24.jar"
    
    t_env.get_config().set("pipeline.jars", f"{kafka_jar};{jdbc_jar};{postgres_jar}")
    
    # Create Kafka source table
    t_env.execute_sql(create_kafka_source_ddl())
    
    # Create Postgres sink table
    t_env.execute_sql(create_postgres_sink_ddl())
    
    # Execute session window query
    t_env.execute_sql(create_session_window_query())

if __name__ == '__main__':
    main()