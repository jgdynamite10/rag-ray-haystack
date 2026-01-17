# Operations (Public)

This is a public-safe runbook summary. Use placeholders for sensitive values.

## Deploy

```bash
make deploy PROVIDER=<provider> ENV=<env> IMAGE_REGISTRY=ghcr.io/<owner> IMAGE_TAG=0.1.5
```

## Verify

```bash
make verify NAMESPACE=<namespace> RELEASE=<release>
```

## Benchmark

```bash
python -m pip install -r scripts/benchmark/requirements.txt
python scripts/benchmark/stream_bench.py --url http://localhost:8000/query/stream
```

## Notes

- Do not include tokens, kubeconfig paths, or node names.
