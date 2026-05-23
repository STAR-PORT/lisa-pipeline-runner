# Global Storage Setup

This directory contains the MinIO setup for the global storage server.
The main installation script is `setup/global_storage/main.sh`.

## Overview

The script installs Docker and runs a MinIO container with configurable credentials and ports.
The values can be customized through `setup/global_storage/.env`.

## Usage

1. Copy the example configuration:

```sh
cp setup/global_storage/.env.example setup/global_storage/.env
```

2. Edit `setup/global_storage/.env` to set your MinIO root user, password, and ports.

3. Run the setup script as root:

```sh
sudo bash setup/global_storage/main.sh
```

## Notes

- If `.env` is not present, the script uses the defaults defined in `main.sh`.
- Make sure the chosen ports are available before running the script.
- This setup installs MinIO in a Docker container and enables the Docker service.
 
## Cleanup

To stop and remove the MinIO container, run:

```sh
sudo bash setup/global_storage/cleanup.sh
```
