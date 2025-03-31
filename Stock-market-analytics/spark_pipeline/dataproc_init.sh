#!/bin/bash
# Initialization action for Dataproc cluster nodes

set -e

ROLE=$(/usr/share/google/get_metadata_value attributes/dataproc-role)
if [[ "${ROLE}" == 'Master' ]]; then
  # Run on master node only (or all nodes if needed)
  echo "Updating packages and installing prerequisites on ${HOSTNAME}..."
  sudo apt-get update
  sudo apt-get install -y python3-distutils python3.7-pip
  
  echo "Installing Python packages using pip3..."
  # Assuming requirements are copied to the bucket
  # Get bucket name from metadata
  BUCKET_NAME=$(/usr/share/google/get_metadata_value attributes/dataproc-bucket)
  if [ -z "${BUCKET_NAME}" ]; then
    echo "Error: Could not retrieve Dataproc bucket name from metadata." >&2
    exit 1
  fi
  
  echo "Copying requirements file from gs://${BUCKET_NAME}/spark/requirements-dataproc.txt"
  gsutil cp gs://${BUCKET_NAME}/spark/requirements-dataproc.txt /tmp/
  
  # Use the correct pip for python3.7
  sudo pip3 install --upgrade pip
  sudo pip3 install -r /tmp/requirements-dataproc.txt
  
  echo "Python package installation complete on ${HOSTNAME}."
fi

echo "Initialization action finished for ${HOSTNAME}." 