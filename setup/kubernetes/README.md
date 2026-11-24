### Overview

This directory configures the Kubernetes VM, Argo Workflows, Garage object storage, and InterLink bridge. `main.sh` loads values from `.env` and runs the setup stages:

- `setup/kubernetes/1-kubernetes.sh` — prepare the Debian node and install Kubernetes
- `setup/kubernetes/2-argo.sh` — install Calico, Argo Workflows, Garage, and artifact repositories
- `setup/kubernetes/3-bridge.sh` — install InterLink and maintain SSH forwards to Deucalion

The VM must use a stable private IP reachable from its own SSH client. Configure it as `K8S_NODE_IP`; kubeadm advertises the API at that address. Garage metadata and objects are persisted on the VM under `GARAGE_DATA_DIR`.

### Prerequisites
- An SSH key with access to the Deucalion login node.
- The login node's internal address reachable by compute nodes (example: `10.1.0.2`).
- A stable VM interface address reachable from the VM itself.

### Usage

1. Copy the example configuration:

```sh
cp setup/kubernetes/.env.example setup/kubernetes/.env
```

2. Set a unique strong `ARGO_ADMIN_PASSWORD` in `setup/kubernetes/.env`; it is required. Edit other environment-specific values as needed.

3. Edit the VM address, login-node address, SSH details, Garage credentials, and Slurm settings. Then run the setup as root:

```sh
sudo bash setup/kubernetes/main.sh
```

The tunnel service runs from the VM to Deucalion. It forwards Deucalion's sidecar port to local port `5000`, Garage's S3 API to `http://<login-node-internal-address>:19001`, and the Kubernetes API to `https://<login-node-internal-address>:19002`. Argo uses Garage's cluster Service for ordinary cluster pods and a second artifact repository through the reverse-forward for InterLink pods.

The setup installs infrastructure only. Workflow definitions are managed and submitted separately; the artifact round-trip example is in `tests/workflows/11-interlink-stress.yaml`.

### Notes

- The reverse-forward bind address must be the login node's internal interface address, not the VM address.
- The SSH service must stay connected while HPC workflows are running.
- Workflow definitions are managed and submitted separately; the artifact round-trip test is in `tests/workflows/11-interlink-stress.yaml`.

### Cleanup

To remove the Kubernetes cluster and InterLink bridge from the host, run:

```sh
sudo bash setup/kubernetes/cleanup.sh
```