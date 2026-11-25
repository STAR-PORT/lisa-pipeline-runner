#!/usr/bin/env bash
set -euo pipefail

# Install Argo CLI and cache its executor image on shared HPC storage.

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/F202500007HPCVLABUPORTO/isabelmoutinho/lisa-pipeline-runner}"
HPC_TOOLS_DIR="${HPC_TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"
ARGO_VERSION="${ARGO_VERSION:-v3.7.12}"
KUBERNETES_API_HOST="${KUBERNETES_API_HOST:-10.1.0.2}"
ARGO_EXECUTOR_SIF="${HPC_TOOLS_DIR}/argoexec-${ARGO_VERSION}.sif"
BUSYBOX_SIF="${HPC_TOOLS_DIR}/busybox-1.36.sif"
STRESS_SIF="${HPC_TOOLS_DIR}/stress-ng.sif"

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

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"
pull_sif_if_missing() {
	local sif_path="$1"
	local image_uri="$2"
	MKSQUASHFS_WRAPPER_DIR=""

	if [[ -s "$sif_path" ]]; then
		return
	fi

	if [[ -z "$CONTAINER_RUNTIME" ]]; then
		if command -v apptainer >/dev/null 2>&1; then
			CONTAINER_RUNTIME=apptainer
		elif command -v singularity >/dev/null 2>&1; then
			CONTAINER_RUNTIME=singularity
		else
			echo "Neither apptainer nor singularity is available. Copy a prebuilt SIF to $sif_path." >&2
			exit 1
		fi
	elif ! command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1; then
		echo "Configured container runtime '$CONTAINER_RUNTIME' was not found in PATH." >&2
		exit 1
	fi

	if [[ -z "$MKSQUASHFS_WRAPPER_DIR" ]]; then
		local mksquashfs_path
		mksquashfs_path="$(command -v mksquashfs || true)"
		if [[ -z "$mksquashfs_path" ]]; then
			echo "mksquashfs was not found in PATH; cannot build a SIF locally." >&2
			exit 1
		fi

		MKSQUASHFS_WRAPPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mksquashfs-wrapper.XXXXXX")"
		cat > "$MKSQUASHFS_WRAPPER_DIR/mksquashfs" <<EOF
#!/bin/sh
exec "$mksquashfs_path" "\$@" -processors 1
EOF
		chmod 755 "$MKSQUASHFS_WRAPPER_DIR/mksquashfs"
		trap 'rm -rf "$MKSQUASHFS_WRAPPER_DIR"' EXIT
	fi

	PATH="$MKSQUASHFS_WRAPPER_DIR:$PATH" "$CONTAINER_RUNTIME" pull "$sif_path" "$image_uri"
}

printf '%s\n' \
	"127.0.0.1 localhost" \
	"::1 localhost ip6-localhost ip6-loopback" \
	"${KUBERNETES_API_HOST} kubernetes.default.svc" > "$HPC_TOOLS_DIR/hosts"

pull_sif_if_missing "$ARGO_EXECUTOR_SIF" \
	"docker://quay.io/argoproj/argoexec:${ARGO_VERSION}"
pull_sif_if_missing "$BUSYBOX_SIF" "docker://busybox:1.36"
pull_sif_if_missing "$STRESS_SIF" "docker://colinianking/stress-ng:latest"

echo "Argo CLI: $HPC_TOOLS_DIR/argo"
echo "Argo executor image: $ARGO_EXECUTOR_SIF"
echo "BusyBox image: $BUSYBOX_SIF"
echo "stress-ng image: $STRESS_SIF"
echo "Kubernetes API hosts entry: ${KUBERNETES_API_HOST} kubernetes.default.svc"