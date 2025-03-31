#!/bin/bash
# Script to set up Kafka on a VM instance

# Enable command echo to see all commands executed
set -x

# Don't exit immediately on error to see all output
set +e

# Default variables
KAFKA_VERSION="3.5.1"
SCALA_VERSION="2.13"
ZOOKEEPER_PORT=2181
KAFKA_PORT=9092
KAFKA_DATA_DIR="/opt/kafka-data"
KAFKA_LOG_DIRS="/opt/kafka-logs"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --kafka-version)
      KAFKA_VERSION="$2"
      shift
      shift
      ;;
    --scala-version)
      SCALA_VERSION="$2"
      shift
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "===================================================="
echo "Setting up Kafka ${KAFKA_VERSION} with Scala ${SCALA_VERSION}"
echo "===================================================="
echo "Zookeeper Port: ${ZOOKEEPER_PORT}"
echo "Kafka Port: ${KAFKA_PORT}"
echo "Data Directory: ${KAFKA_DATA_DIR}"
echo "Log Directories: ${KAFKA_LOG_DIRS}"
echo "===================================================="

# Install Java
echo "Installing Java..."
sudo apt-get update -y
sudo apt-get install -y openjdk-11-jdk wget net-tools netcat unzip

echo "Checking Java installation..."
java -version
if [ $? -ne 0 ]; then
  echo "WARNING: Java installation may have issues"
fi

# Create directories for Kafka data and logs
echo "Creating Kafka directories..."
sudo mkdir -p $KAFKA_DATA_DIR
sudo mkdir -p $KAFKA_LOG_DIRS
sudo chmod 777 $KAFKA_DATA_DIR
sudo chmod 777 $KAFKA_LOG_DIRS

echo "Verifying directories were created..."
ls -la $KAFKA_DATA_DIR
ls -la $KAFKA_LOG_DIRS

# Download and extract Kafka
echo "Downloading Kafka ${KAFKA_VERSION}..."
wget -q --show-progress "https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
if [ $? -ne 0 ]; then
  echo "Error downloading Kafka. Retrying with archive.apache.org..."
  wget -q --show-progress "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
fi

echo "Extracting Kafka..."
tar -xzf "kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
EXTRACT_STATUS=$?
if [ $EXTRACT_STATUS -ne 0 ]; then
  echo "Error extracting Kafka archive (status: $EXTRACT_STATUS)"
  echo "Listing downloaded file:"
  ls -la "kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
  exit $EXTRACT_STATUS
fi

mv "kafka_${SCALA_VERSION}-${KAFKA_VERSION}" kafka
rm "kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"

# List Kafka directory contents
echo "Checking Kafka installation directory..."
ls -la kafka

# Configure Kafka
echo "Configuring Kafka..."
cat > kafka/config/server.properties << EOF
broker.id=0
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=${KAFKA_LOG_DIRS}
num.partitions=1
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=localhost:${ZOOKEEPER_PORT}
zookeeper.connection.timeout.ms=18000
advertised.listeners=PLAINTEXT://localhost:${KAFKA_PORT}
listener.security.protocol.map=PLAINTEXT:PLAINTEXT
EOF

echo "Kafka configuration created:"
cat kafka/config/server.properties

# Create systemd service for Zookeeper
echo "Creating Zookeeper service..."
sudo tee /etc/systemd/system/zookeeper.service > /dev/null << EOF
[Unit]
Description=Apache Zookeeper server
Documentation=https://zookeeper.apache.org
Requires=network.target
After=network.target

[Service]
Type=simple
User=$(whoami)
Environment="KAFKA_HEAP_OPTS=-Xmx512M -Xms512M"
ExecStart=$(pwd)/kafka/bin/zookeeper-server-start.sh $(pwd)/kafka/config/zookeeper.properties
ExecStop=$(pwd)/kafka/bin/zookeeper-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

echo "Zookeeper service created:"
cat /etc/systemd/system/zookeeper.service

# Create systemd service for Kafka
echo "Creating Kafka service..."
sudo tee /etc/systemd/system/kafka.service > /dev/null << EOF
[Unit]
Description=Apache Kafka Server
Documentation=https://kafka.apache.org/documentation
Requires=zookeeper.service
After=zookeeper.service

[Service]
Type=simple
User=$(whoami)
Environment="KAFKA_HEAP_OPTS=-Xmx1G -Xms1G"
ExecStart=$(pwd)/kafka/bin/kafka-server-start.sh $(pwd)/kafka/config/server.properties
ExecStop=$(pwd)/kafka/bin/kafka-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

echo "Kafka service created:"
cat /etc/systemd/system/kafka.service

# Reload systemd, enable and start services
echo "Starting Zookeeper and Kafka services..."
sudo systemctl daemon-reload
sudo systemctl enable zookeeper.service
sudo systemctl enable kafka.service
sudo systemctl start zookeeper.service

echo "Zookeeper service started. Waiting for 10 seconds..."
sleep 10  # Wait for Zookeeper to start

echo "Starting Kafka service..."
sudo systemctl start kafka.service

echo "Waiting for Kafka to start (20 seconds)..."
sleep 20  # Wait for Kafka to start

# Create a topic for stock data
echo "Creating Kafka topic for stock data..."
./kafka/bin/kafka-topics.sh --create --topic stock-market-data --bootstrap-server localhost:${KAFKA_PORT} --partitions 3 --replication-factor 1 || {
  echo "Error creating topic. Checking if Kafka is running properly..."
  sudo systemctl status kafka.service
  echo "Checking existing topics..."
  ./kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:${KAFKA_PORT}
}

# Check if Kafka is running
echo "Checking if Kafka is running..."
if nc -z localhost ${KAFKA_PORT}; then
  echo "SUCCESS: Kafka is running on port ${KAFKA_PORT}"
else
  echo "ERROR: Kafka is not running on port ${KAFKA_PORT}"
  echo "Checking logs:"
  echo "--- Kafka Logs ---"
  sudo journalctl -u kafka --no-pager | tail -n 30
  echo "--- Zookeeper Logs ---"
  sudo journalctl -u zookeeper --no-pager | tail -n 30
  exit 1
fi

# Display service status
echo "Zookeeper service status:"
sudo systemctl status zookeeper.service --no-pager
echo "Kafka service status:"
sudo systemctl status kafka.service --no-pager

echo "Kafka topic list:"
./kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:${KAFKA_PORT}

echo "Checking network ports:"
netstat -tulpn | grep -E '9092|2181'

echo "Kafka setup completed successfully!" 