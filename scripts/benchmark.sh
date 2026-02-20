#!/usr/bin/env bash
set -euo pipefail

TARGET="${BENCH_TARGET:-http://localhost:8000}"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/benchmark-k6.js"

echo "Running k6 against ${TARGET}"
docker run --rm -i -e TARGET="${TARGET}" grafana/k6:0.54.0 run - < "${SCRIPT_PATH}"
