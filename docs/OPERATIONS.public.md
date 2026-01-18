# Operations (Public)

This is a public-safe runbook summary. Use placeholders for sensitive values.

## Deploy

```bash
make deploy PROVIDER=<provider> ENV=<env> IMAGE_REGISTRY=ghcr.io/<owner> IMAGE_TAG=0.2.2
```

## Verify

```bash
make verify NAMESPACE=<namespace> RELEASE=<release>
```

## Public access (Akamai dev)

- Frontend Service is `LoadBalancer` (public IP).
- UI: `http://<public-url>/`
- Backend via UI proxy: `http://<public-url>/api/*`

## Benchmark

```bash
python -m pip install -r scripts/benchmark/requirements.txt
python scripts/benchmark/stream_bench.py --url http://localhost:8000/query/stream
```

## Benchmark (in-cluster)

```bash
kubectl -n <namespace> apply -f deploy/benchmark/stream-bench-job.yaml
kubectl -n <namespace> wait --for=condition=complete job/rag-stream-bench --timeout=10m
kubectl -n <namespace> logs job/rag-stream-bench
kubectl -n <namespace> delete job rag-stream-bench
kubectl -n <namespace> delete configmap rag-stream-bench
```

To tune the benchmark, edit env values in `deploy/benchmark/stream-bench-job.yaml`:
`BENCH_URL`, `BENCH_CONCURRENCY`, `BENCH_REQUESTS`, `BENCH_TIMEOUT`, `BENCH_SHOW_ERRORS`.

## Notes

- Do not include tokens, kubeconfig paths, or node names.
