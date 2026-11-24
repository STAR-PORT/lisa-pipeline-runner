# HPC Setup

This directory contains the Deucalion-side InterLink Slurm setup. `main.sh` loads `setup/hpc/.env` and runs:

- `setup/hpc/1-bridge.sh` — installs and starts the InterLink Slurm sidecar

## Usage

1. Copy the example configuration:

```sh
cp setup/hpc/.env.example setup/hpc/.env
```

2. Edit `setup/hpc/.env` with your environment-specific values.

3. Run the setup script as your Deucalion user:

```sh
bash setup/hpc/main.sh
```

## Notes

- Workflow pods use Argo's native artifact init/wait containers to pull and push data to Garage over the SSH reverse forward.
- The standard setup installs no S3 client or custom data-sync wrapper on Deucalion.


## Cleanup

To remove the HPC user services and generated runtime files, run:

```sh
bash setup/hpc/cleanup.sh
```
