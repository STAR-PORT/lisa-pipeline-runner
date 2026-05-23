# LISA Pipeline Runner

A setup and testing framework for the LISA pipeline infrastructure, supporting Kubernetes, HPC, and cloud storage configurations.

## Overview

This repository provides automated setup scripts and test utilities for deploying and validating the LISA pipeline across different infrastructure environments.

## Important Notes
- This repository currently contains placeholder account keys only.
- Personal account key files required by the code are not present in the repository, so it is not possible to fully replicate the setup.
- The values shown in the scripts are not the real MinIO credentials and should be replaced with valid keys before running the storage setup and access.
> Later there will be variables for defining this account specific files.

## Directory Structure

- **setup/** - Infrastructure setup scripts
  - `global_storage/` - Cloud storage deployment. Contains `README.md`, `main.sh`, `cleanup.sh`, and `.env.example`
  - `hpc/` - High-Performance Computing deployment. Contains `README.md`, `main.sh`, `cleanup.sh`, and `.env.example`
  - `kubernetes/` - Kubernetes cluster deployment. Contains `README.md`, `main.sh`, `cleanup.sh`, and `.env.example`
  
- **tests/** - Test suites and validation
  - `argo/` - Argo workflow templates and tests
  - `pods/` - Kubernetes pod tests

## Setup

### Prerequisites
- Kubernetes cluster machine access (ssh)
- HPC environment access (ssh)
- Access to cloud storage credentials

### Installation

Run the setup scripts in order:

```bash
# Global storage setup
./setup/global_storage/main.sh

# For Kubernetes
./setup/kubernetes/main.sh

# For HPC
./setup/hpc/main.sh
```
Each setup subdirectory includes its own `README.md` and a `cleanup.sh` helper.

## Testing

Run tests to validate your setup:

```bash
# Pod tests
kubectl apply -f /tests/pods/interlink-test.sh
kubectl apply -f /tests/pods/data-test.sh

# Argo workflow tests
kubectl apply -f /tests/argo/argo_template.yaml
kubectl apply -f /tests/argo/argo_test.yaml
```