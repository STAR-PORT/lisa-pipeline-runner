### Overview

This directory contains the Kubernetes setup workflow for the LISA pipeline.
The main entrypoint is `setup/kubernetes/main.sh`, which loads user overrides from
`setup/kubernetes/.env` and then runs the three stage scripts:

- `setup/kubernetes/1-kubernetes.sh` — prepare the Debian node and install Kubernetes
- `setup/kubernetes/2-argo.sh` — install Calico + Argo workflows in the cluster
- `setup/kubernetes/3-bridge.sh` — install InterLink and create the SSH bridge to HPC

Each stage script has its own sensible defaults, so the wrapper only loads user-provided values.

### Usage

1. Copy the example configuration:

```sh
cp setup/kubernetes/.env.example setup/kubernetes/.env
```

2. Edit `setup/kubernetes/.env` with any values you want to override.

3. Run the wrapper script as root:

```sh
sudo bash setup/kubernetes/main.sh
```

### Notes

- If a variable is not defined in `.env`, the respective stage script will use its built-in default.
- Do not edit the stage scripts unless you need to change default behavior.
- The wrapper is the recommended entrypoint for the full flow.

### Cleanup

To remove the Kubernetes cluster and InterLink bridge from the host, run:

```sh
sudo bash setup/kubernetes/cleanup.sh
```