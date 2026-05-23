# HPC Setup

This directory contains HPC-side setup scripts for the LISA pipeline.
The main entrypoint is `setup/hpc/main.sh`, which loads user overrides from `setup/hpc/.env` and runs:

- `setup/hpc/1-bridge.sh`
- `setup/hpc/2-data.sh`

## Usage

1. Copy the example configuration:

```sh
cp setup/hpc/.env.example setup/hpc/.env
```

2. Edit `setup/hpc/.env` with your environment-specific values.

3. Run the wrapper script:

```sh
bash setup/hpc/main.sh
```

## Notes

- The wrapper loads values from `.env` if provided.
- Each stage script still keeps its own default values for missing variables.
- This setup supports custom project paths, InterLink release links, MinIO credentials, and user names.


## Cleanup

To remove the HPC user services and generated runtime files, run:

```sh
bash setup/hpc/cleanup.sh
```
