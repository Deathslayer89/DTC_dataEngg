terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }
}

# Variables
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The zone to deploy resources"
  type        = string
  default     = "us-central1-a"
}

variable "bucket_name" {
  description = "The name of the GCS bucket for raw data"
  type        = string
}

variable "dataset_id" {
  description = "The BigQuery dataset ID"
  type        = string
  default     = "stock_market_analytics"
}

variable "spark_cluster_name" {
  description = "Name of the Dataproc cluster"
  type        = string
  default     = "stock-market-cluster"
}

variable "kafka_instance_name" {
  description = "Name of the VM instance for Kafka"
  type        = string
  default     = "stock-market-kafka"
}

# Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Data source for project information
data "google_project" "project" {
  project_id = var.project_id
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "dataproc.googleapis.com",
    "bigquery.googleapis.com",
    "artifactregistry.googleapis.com",
    "composer.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dataflow.googleapis.com",
    "redis.googleapis.com",
    "iam.googleapis.com"
  ])
  
  service = each.key
  disable_on_destroy = false
}

# Network resources
resource "google_compute_network" "vpc" {
  name                    = "stock-network"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.required_apis]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "stock-market-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  
  # Secondary ranges for GKE and services
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.10.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.20.0.0/20"
  }
  
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.30.0.0/24"
  }
  
  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "10.2.0.0/24"
  }
  
  private_ip_google_access = true
  depends_on               = [google_compute_network.vpc]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "stock-market-allow-internal"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "icmp"
  }
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  source_ranges = ["10.0.0.0/24"]
  depends_on    = [google_compute_network.vpc]
}

# Create a firewall rule to allow external access to Kafka and Airflow
resource "google_compute_firewall" "allow_external" {
  name    = "stock-market-allow-external"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22", "8080", "9092", "2181", "3000", "9091"]  # SSH, Airflow UI, Kafka, Zookeeper, Grafana, Prometheus
  }
  
  source_ranges = ["0.0.0.0/0"]  # This allows access from anywhere, restrict if needed
  depends_on    = [google_compute_network.vpc]
}

# Private services access
resource "google_compute_global_address" "private_ip_address" {
  name          = "google-managed-services-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
  depends_on    = [google_compute_network.vpc]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  depends_on              = [google_compute_global_address.private_ip_address, google_project_service.required_apis]
}

# Storage resources
resource "google_storage_bucket" "data_bucket" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 90  # Days
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery resources
resource "google_bigquery_dataset" "analytics_dataset" {
  dataset_id                  = var.dataset_id
  friendly_name               = "Stock Market Analytics"
  description                 = "Dataset for stock market analytics"
  location                    = var.region
  delete_contents_on_destroy  = true
  
  depends_on = [google_project_service.required_apis]
}

# Create tables based on DBT models structure
resource "google_bigquery_table" "daily_prices" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "daily_prices"
  
  time_partitioning {
    type = "DAY"
    field = "date"
  }
  
  schema = <<EOF
[
  {
    "name": "symbol",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Stock symbol"
  },
  {
    "name": "date",
    "type": "DATE",
    "mode": "REQUIRED",
    "description": "Trading date"
  },
  {
    "name": "open",
    "type": "FLOAT",
    "mode": "NULLABLE",
    "description": "Opening price"
  },
  {
    "name": "high",
    "type": "FLOAT",
    "mode": "NULLABLE",
    "description": "High price"
  },
  {
    "name": "low",
    "type": "FLOAT",
    "mode": "NULLABLE",
    "description": "Low price"
  },
  {
    "name": "close",
    "type": "FLOAT",
    "mode": "NULLABLE",
    "description": "Closing price"
  },
  {
    "name": "volume",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "Trading volume"
  }
]
EOF

  depends_on = [google_bigquery_dataset.analytics_dataset]
}

resource "google_bigquery_table" "realtime_prices" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "realtime_stock_prices"
  
  time_partitioning {
    type = "HOUR"
    field = "timestamp"
  }
  
  schema = <<EOF
[
  {
    "name": "symbol",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Stock symbol"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "Timestamp of the price"
  },
  {
    "name": "price",
    "type": "FLOAT",
    "mode": "NULLABLE",
    "description": "Current price"
  },
  {
    "name": "volume",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "Trading volume"
  },
  {
    "name": "currency",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Currency code"
  }
]
EOF

  depends_on = [google_bigquery_dataset.analytics_dataset]
}

# Artifact Registry
resource "google_artifact_registry_repository" "stock_analytics" {
  location      = var.region
  repository_id = "stock-analytics"
  description   = "Docker repository for stock analytics services"
  format        = "DOCKER"
  
  depends_on = [google_project_service.required_apis]
}

# Cloud SQL for PostgreSQL (metadata storage)
resource "google_sql_database_instance" "postgres" {
  name             = "stock-market-db"
  database_version = "POSTGRES_13"
  region           = var.region
  
  settings {
    tier = "db-f1-micro"
    disk_size = 10
    
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
    
    backup_configuration {
      enabled = true
      start_time = "02:00"
    }
  }
  
  deletion_protection = false
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]
}

resource "google_sql_database" "database" {
  name     = "stockmarket"
  instance = google_sql_database_instance.postgres.name
}

# Redis for caching (Memorystore)
resource "google_redis_instance" "cache" {
  name           = "stock-market-cache"
  tier           = "BASIC"
  memory_size_gb = 1
  
  region                  = var.region
  authorized_network      = google_compute_network.vpc.id
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]
}

# Service account for Composer
resource "google_service_account" "composer_service_account" {
  account_id   = "composer-sa"
  display_name = "Composer Service Account"
  description  = "Service account for Cloud Composer environment"
}

# Grant necessary roles to the Composer service account
resource "google_project_iam_member" "composer_sa_worker" {
  project = var.project_id
  role    = "roles/composer.worker"
  member  = "serviceAccount:${google_service_account.composer_service_account.email}"
}

resource "google_project_iam_member" "composer_sa_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.composer_service_account.email}"
}

resource "google_project_iam_member" "composer_sa_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.composer_service_account.email}"
}

resource "google_project_iam_member" "composer_sa_dataflow" {
  project = var.project_id
  role    = "roles/dataflow.admin"
  member  = "serviceAccount:${google_service_account.composer_service_account.email}"
}

# Grant required IAM permissions for Cloud Composer service account
resource "google_project_iam_member" "composer_agent_v2_ext" {
  project = var.project_id
  role    = "roles/composer.ServiceAgentV2Ext"
  member  = "serviceAccount:service-${data.google_project.project.number}@cloudcomposer-accounts.iam.gserviceaccount.com"
  
  depends_on = [google_project_service.required_apis]
}

# Dataproc cluster for Spark processing
resource "google_dataproc_cluster" "spark_cluster" {
  name     = var.spark_cluster_name
  region   = var.region
  
  cluster_config {
    staging_bucket = google_storage_bucket.data_bucket.name
    
    master_config {
      num_instances = 1
      machine_type  = "n1-standard-4"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 50
      }
    }
    
    worker_config {
      num_instances = 2
      machine_type  = "n1-standard-4"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 50
      }
    }
    
    software_config {
      image_version = "2.0-debian10"
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "false"
      }
      
      optional_components = [
        "JUPYTER", "ZEPPELIN"
      ]
    }
    
    gce_cluster_config {
      subnetwork = google_compute_subnetwork.subnet.id
      internal_ip_only = false  # To allow external access
      
      # Add service account with necessary permissions
      service_account_scopes = [
        "cloud-platform"
      ]
    }
  }
  
  depends_on = [
    google_compute_subnetwork.subnet,
    google_storage_bucket.data_bucket,
    google_project_service.required_apis
  ]
}

# GCE instance for Kafka
resource "google_compute_instance" "kafka_instance" {
  name         = var.kafka_instance_name
  machine_type = "n1-standard-4"
  zone         = var.zone
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 50
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    
    access_config {
      // Ephemeral public IP
    }
  }
  
  service_account {
    scopes = ["cloud-platform"]
  }
  
  depends_on = [
    google_compute_subnetwork.subnet,
    google_project_service.required_apis
  ]
}

# Output values
output "network_id" {
  value = google_compute_network.vpc.id
  description = "The ID of the VPC network"
}

output "data_bucket_url" {
  value = google_storage_bucket.data_bucket.url
  description = "The URL of the data bucket"
}

output "bigquery_dataset_id" {
  value = google_bigquery_dataset.analytics_dataset.id
  description = "The ID of the BigQuery dataset"
}

output "spark_cluster_name" {
  value = google_dataproc_cluster.spark_cluster.name
  description = "The name of the Spark cluster"
}

output "kafka_instance_name" {
  value = google_compute_instance.kafka_instance.name
  description = "The name of the Kafka instance"
}

output "kafka_instance_external_ip" {
  value = google_compute_instance.kafka_instance.network_interface[0].access_config[0].nat_ip
  description = "The external IP of the Kafka instance"
}

output "postgres_connection_name" {
  value = google_sql_database_instance.postgres.connection_name
  description = "The connection name of the PostgreSQL instance"
}

output "redis_host" {
  value = google_redis_instance.cache.host
  description = "The IP address of the Redis instance"
}