
# Workflow Tests

The sample workflows use the `lisa` bucket in the MinIO instance deployed with the Kubernetes cluster. From a machine that can reach the VM's private address, configure the MinIO client with the credentials in `setup/kubernetes/.env` and seed the sample files:

```sh
mc alias set lisa-local http://<K8S_NODE_IP>:30900 <OBJECT_STORE_ACCESS_KEY> <OBJECT_STORE_SECRET_KEY>
mc mb --ignore-existing lisa-local/lisa
mc mirror tests/datasets/users lisa-local/lisa/users
```

Keep the VM-to-Deucalion SSH tunnel running, then submit the workflows in `tests/workflows` through the Argo UI. Remote sync jobs reach MinIO at `http://<login-node-internal-address>:19001`; the Kubernetes API is reverse-forwarded at `https://<login-node-internal-address>:19002` for authenticated internal clients.

## InterLink-only stress test

`11-interlink-stress.yaml` is self-contained and does not use object storage. It fans out three bounded CPU/memory Argo pods to the `interlink-node` by default. Update its Slurm account, partition, and reverse-forward API host/port parameters to match your setup, then submit it with:

```sh
kubectl create -f tests/workflows/11-interlink-stress.yaml
```
