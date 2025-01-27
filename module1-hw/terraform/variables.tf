variable "credentials" {
  description = "Path to your service account key file"
  type        = string
}

variable "project" {
  description = "Your GCP Project ID"
  type        = string
}

variable "region" {
  description = "Region for GCP resources"
  default     = "us-central1"
  type        = string
}

variable "gcs_bucket_name" {
  description = "Storage Bucket name"
  type        = string
}

variable "bq_dataset_name" {
  description = "BigQuery Dataset name"
  type        = string
}