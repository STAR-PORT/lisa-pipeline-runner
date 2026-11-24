
# Workflow Test

`11-interlink-stress.yaml` tests the native Argo artifact lifecycle against Garage without pre-seeding data:

1. A pod on `interlink-node` writes an input file; Argo's `wait` container uploads it.
2. A second InterLink pod receives the file through Argo's `init` container, runs a bounded stress test, and has its output uploaded by `wait`.
3. A third InterLink pod pulls that output through `init` and verifies it.

Keep the VM-to-Deucalion SSH tunnel running. Update the workflow's Slurm account, partition, and reverse-forward API host/port parameters to match your setup, then submit it:

```sh
kubectl create -f tests/workflows/11-interlink-stress.yaml
```

The workflow selects the `artifact-repositories-hpc` ConfigMap, whose S3 endpoint is `http://<login-node-internal-address>:19001`. The default `artifact-repositories` ConfigMap points to Garage's cluster Service for future workflows that perform ingestion inside Kubernetes.
