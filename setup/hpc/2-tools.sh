#!/usr/bin/env bash
set -euo pipefail

# Install Argo CLI and cache its executor image on shared HPC storage.

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner}"
HPC_TOOLS_DIR="${HPC_PROJECT_ROOT}/tools"
ARGO_VERSION="${ARGO_VERSION:-v3.7.12}"
ARGO_EXECUTOR_SIF="${HPC_TOOLS_DIR}/argoexec-${ARGO_VERSION}.sif"

mkdir -p "$HPC_TOOLS_DIR"

for cmd in gzip wget; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Required command '$cmd' is missing. Install it before running this script." >&2
		exit 1
	fi
done

if [[ ! -x "$HPC_TOOLS_DIR/argo" ]]; then
	ARGO_CLI_ARCHIVE="$HPC_TOOLS_DIR/argo-linux-amd64.gz"
	wget -qO "$ARGO_CLI_ARCHIVE" \
		"https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/argo-linux-amd64.gz"
	gzip -dc "$ARGO_CLI_ARCHIVE" > "$HPC_TOOLS_DIR/argo"
	chmod 755 "$HPC_TOOLS_DIR/argo"
	rm -f "$ARGO_CLI_ARCHIVE"
fi

if [[ ! -s "$ARGO_EXECUTOR_SIF" ]]; then
	CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"
	if [[ -z "$CONTAINER_RUNTIME" ]]; then
		if command -v apptainer >/dev/null 2>&1; then
			CONTAINER_RUNTIME=apptainer
		elif command -v singularity >/dev/null 2>&1; then
			CONTAINER_RUNTIME=singularity
		else
			echo "Neither apptainer nor singularity is available to pull the executor image. Load a site module or copy a prebuilt SIF to $ARGO_EXECUTOR_SIF." >&2
			exit 1
		fi
	elif ! command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1; then
		echo "Configured container runtime '$CONTAINER_RUNTIME' was not found in PATH." >&2
		exit 1
	fi

	"$CONTAINER_RUNTIME" pull "$ARGO_EXECUTOR_SIF" \
		"docker://quay.io/argoproj/argoexec:${ARGO_VERSION}"
fi

echo "Argo CLI: $HPC_TOOLS_DIR/argo"
echo "Argo executor image: $ARGO_EXECUTOR_SIF"