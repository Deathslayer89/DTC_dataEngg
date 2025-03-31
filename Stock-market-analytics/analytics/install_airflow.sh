#!/bin/bash
# Script to install Airflow and DBT on the Kafka VM

set -e  # Exit on any error

echo "=== Installing Airflow and DBT ==="

# Install required system packages
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv libpq-dev build-essential

# Create a Python virtual environment for Airflow
echo "Creating Python virtual environment for Airflow..."
python3 -m venv ~/airflow_env

# Activate the virtual environment
echo "Activating virtual environment..."
source ~/airflow_env/bin/activate

# Install Airflow and dependencies
echo "Installing Airflow and dependencies..."
pip install --upgrade pip

# Install packages with minimal version constraints to avoid dependency conflicts
pip install apache-airflow==2.5.3
pip install dbt-bigquery
pip install google-cloud-bigquery
pip install google-cloud-storage

# Install Airflow Google provider
pip install apache-airflow-providers-google

# Install packages separately if needed
pip install markupsafe

# Configure Airflow
echo "Configuring Airflow..."
export AIRFLOW_HOME=~/airflow
airflow db init

# Create an admin user for Airflow
echo "Creating Airflow admin user..."
airflow users create \
    --username admin \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password admin

# Configure Airflow settings
echo "Customizing Airflow configuration..."
cat > ~/airflow/airflow.cfg << AIRFLOWCFG
[core]
executor = LocalExecutor
dags_folder = ${HOME}/airflow/dags
base_log_folder = ${HOME}/airflow/logs
logging_level = INFO
load_examples = False

[webserver]
web_server_port = 8080
web_server_host = 0.0.0.0
rbac = True

[database]
sql_alchemy_conn = sqlite:///${HOME}/airflow/airflow.db
load_default_connections = True

[scheduler]
dag_dir_list_interval = 30
AIRFLOWCFG

# Create systemd service files for Airflow
echo "Setting up Airflow services..."
cat > ~/airflow-webserver.service << WEBSERVER
[Unit]
Description=Airflow webserver
After=network.target

[Service]
User=${USER}
Group=${USER}
Type=simple
Environment="PATH=${HOME}/airflow_env/bin:${PATH}"
Environment="AIRFLOW_HOME=${HOME}/airflow"
ExecStart=${HOME}/airflow_env/bin/airflow webserver
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
WEBSERVER

cat > ~/airflow-scheduler.service << SCHEDULER
[Unit]
Description=Airflow scheduler
After=network.target

[Service]
User=${USER}
Group=${USER}
Type=simple
Environment="PATH=${HOME}/airflow_env/bin:${PATH}"
Environment="AIRFLOW_HOME=${HOME}/airflow"
ExecStart=${HOME}/airflow_env/bin/airflow scheduler
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SCHEDULER

# Move service files to system directory
echo "Installing systemd services..."
sudo mv ~/airflow-webserver.service /etc/systemd/system/
sudo mv ~/airflow-scheduler.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable and start services
echo "Starting Airflow services..."
sudo systemctl enable airflow-webserver
sudo systemctl enable airflow-scheduler
sudo systemctl start airflow-webserver
sudo systemctl start airflow-scheduler

# Configure the firewall to allow Airflow UI access
echo "Configuring firewall for Airflow UI..."
sudo apt-get install -y ufw
sudo ufw allow 8080/tcp

# Configure DBT
echo "Configuring DBT..."
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << DBTCONFIG
dbt_project:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: $(gcloud config get-value project)
      dataset: dbt_analytics
      location: US
      threads: 4
DBTCONFIG

# Create a convenience script to run DBT with the virtual environment
echo "Creating convenience script for DBT..."
cat > ~/run_dbt.sh << DBTSCRIPT
#!/bin/bash
# Script to run DBT commands with the virtual environment

source ~/airflow_env/bin/activate
cd ~/dbt
dbt \$@
DBTSCRIPT

chmod +x ~/run_dbt.sh

# Create service activation scripts
echo "Creating service scripts..."
cat > ~/start_airflow.sh << 'STARTSCRIPT'
#!/bin/bash
sudo systemctl start airflow-webserver
sudo systemctl start airflow-scheduler
echo "Airflow services started"
STARTSCRIPT

cat > ~/stop_airflow.sh << 'STOPSCRIPT'
#!/bin/bash
sudo systemctl stop airflow-webserver
sudo systemctl stop airflow-scheduler
echo "Airflow services stopped"
STOPSCRIPT

chmod +x ~/start_airflow.sh ~/stop_airflow.sh

# Make sure the PATH includes the virtual environment in .bashrc
echo 'export PATH="$HOME/airflow_env/bin:$PATH"' >> ~/.bashrc

# Get the external IP for access instructions
EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")

echo "=== Installation Complete ==="
echo "Airflow UI available at: http://${EXTERNAL_IP}:8080"
echo "Username: admin"
echo "Password: admin"
echo ""
echo "To run DBT commands: ./run_dbt.sh <command>"
echo "To start/stop Airflow: ./start_airflow.sh or ./stop_airflow.sh" 