
# Workflow Test

`11-interlink-stress.yaml` tests the native Argo artifact lifecycle against Garage without pre-seeding data:

1. A pod on `interlink-node` writes an input file; Argo's `wait` container uploads it.
2. A second InterLink pod receives the file through Argo's `init` container, runs a bounded stress test, and has its output uploaded by `wait`.
3. A third InterLink pod pulls that output through `init` and verifies it.

Keep the VM-to-Deucalion SSH tunnel running. Update the workflow's Slurm account, partition, and reverse-forward API host/port parameters to match your setup, then submit it:

If Deucalion compute nodes cannot pull `quay.io/argoproj/argoexec:v3.7.12`, place that version's Apptainer image on shared storage and set `ARGO_EXECUTOR_IMAGE` in `setup/kubernetes/.env` to its absolute `.sif` path. Rerun `setup/kubernetes/main.sh` so Argo uses that image for its injected init and wait containers.

The HPC workflow's BusyBox and stress-ng images are also expected as SIFs in the shared `tools` directory because compute nodes may not reach Docker Hub. `setup/hpc/2-tools.sh` pulls them when possible; otherwise copy the matching images to the paths configured by the workflow parameters. It also creates a hosts file mapping `kubernetes.default.svc` to the reverse-forward address and the sidecar binds it into Slurm containers.

```sh
kubectl create -f tests/workflows/11-interlink-stress.yaml
```

The workflow selects the `artifact-repositories-hpc` ConfigMap, whose S3 endpoint is `http://<login-node-internal-address>:19001`. The default `artifact-repositories` ConfigMap points to Garage's cluster Service for future workflows that perform ingestion inside Kubernetes.
