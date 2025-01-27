# Terraform Configuration for GCP

This directory contains Terraform configuration to set up the required GCP infrastructure for the NYC Taxi Data project.

## Prerequisites

1. Install Terraform
2. Set up a Google Cloud Project
3. Create a service account & download credentials
4. Enable required APIs in GCP:
   - Identity and Access Management (IAM) API
   - Cloud Storage
   - BigQuery

## Files

- `main.tf`: Main infrastructure configuration
- `variables.tf`: Variable definitions
- `terraform.tfvars`: Variable values (you need to modify this)

## Setup Steps

1. Copy your GCP service account key to `./keys/my-creds.json`

2. Modify `terraform.tfvars` with your specific values:
```hcl
credentials      = "./keys/my-creds.json"
project          = "your-project-id"
region           = "your-preferred-region"
gcs_bucket_name  = "your-bucket-name"
bq_dataset_name  = "your_dataset_name"
```

## Running Terraform

1. Initialize Terraform and download providers:
```bash
terraform init
```


2. Preview the changes:
```bash
terraform plan
```


3. Apply the changes:
```bash
terraform apply -auto-approve
```

4. When you're done, destroy the infrastructure:
```bash
terraform destroy
```


## Resources Created

- Google Cloud Storage bucket
  - Standard storage class
  - Uniform bucket-level access
  - 30-day lifecycle rule
  - Versioning enabled

- BigQuery Dataset
  - Located in the specified region
  - Will be destroyed with contents when running destroy

## Notes

- The bucket name must be globally unique
- Make sure your service account has the necessary permissions
- Keep your credentials secure and never commit them to version control