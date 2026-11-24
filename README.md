# LISA Pipeline Runner

A setup and testing framework for a laptop-hosted Kubernetes cluster connected to the Deucalion HPC plugin.

## Overview

The Kubernetes/Argo cluster runs in a VM on the laptop. The InterLink Slurm sidecar runs on Deucalion. Garage provides S3-compatible object storage in the VM. The VM-initiated SSH tunnel exposes Garage and the Kubernetes API to the Deucalion login node for remote Workflow pods.

## Important Notes
- Set the VM's stable private interface address and Deucalion login-node internal address in the example configuration before setup.
- The example Garage access key and secret are placeholders. Replace them before exposing the reverse-forwarded service.
- Keep the SSH reverse-forward session running while workflows are using Deucalion.

## Directory Structure

- **setup/** - Infrastructure setup scripts
  - `hpc/` - High-Performance Computing deployment. Contains `README.md`, `main.sh`, `cleanup.sh`, and `.env.example`
  - `kubernetes/` - Kubernetes, Argo, Garage, and InterLink setup
  
- **tests/** - Test suites and validation
  - `datasets/` - test datasets for each workflow test
  - `workflows/` - Argo workflow tests

## Setup

### Prerequisites
- Debian-based Kubernetes VM on the laptop
- SSH access to the Deucalion login node and Slurm account
- Deucalion login-node internal bind address (example: `10.1.0.2`)

### Installation

Configure and run the cluster setup in the VM:

```bash
cp setup/kubernetes/.env.example setup/kubernetes/.env
# Edit the VM and Deucalion-specific addresses, SSH key, and Slurm settings.
sudo ./setup/kubernetes/main.sh
```

Run the HPC setup on Deucalion:

```bash
cp setup/hpc/.env.example setup/hpc/.env
bash setup/hpc/main.sh
```

The Kubernetes setup starts a persistent SSH tunnel from the VM to Deucalion. It forwards the sidecar connection locally and exposes the VM's Kubernetes API on port `19002` and Garage's S3 API on port `19001` at the configured login-node internal address.

## Testing

See [tests/README.md](tests/README.md) for running the Garage artifact round-trip workflow on InterLink.