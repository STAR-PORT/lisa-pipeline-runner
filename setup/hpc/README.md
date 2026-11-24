# HPC Setup

This directory contains the Deucalion-side InterLink Slurm setup. `main.sh` loads `setup/hpc/.env` and runs:

- `setup/hpc/2-data.sh` — installs the MinIO client and creates shared data paths
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

- Job containers share `/users` from the configured HPC data directory and have the `mc` client mounted at `/usr/local/bin/mc`.
- The old job wrapper and global-storage credentials are no longer used. Argo's sync module transfers data directly to/from cluster-local MinIO over the SSH reverse forward.


## Cleanup

To remove the HPC user services and generated runtime files, run:

```sh
bash setup/hpc/cleanup.sh
```
