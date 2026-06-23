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
  - `datasets/` - test datasets for each workflow test
  - `workflows/` - Argo workflow tests

## Setup

### Prerequisites
- Kubernetes cluster machine access (ssh)
- HPC environment access (ssh)
- Access to cloud storage credentials

### Installation

Run the setup scripts in order:

```bash
# Global storage setup
sudo ./setup/global_storage/main.sh

# For Kubernetes
sudo ./setup/kubernetes/main.sh

# For HPC
sudo ./setup/hpc/main.sh
```
Each setup subdirectory includes its own `README.md` and a `cleanup.sh` helper.

## Testing

Run tests to validate your setup:
1. Add the files in `/tests/datasets` to the MinIO DB.
2. Run the tests in `/tests/workflows` in the Argo UI.