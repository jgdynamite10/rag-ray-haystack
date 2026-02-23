# Benchmark Results

This document tracks benchmark results across all three cloud providers over time.

---

## Median of 7 Runs (February 22, 2026)

**Method:** 7 runs, report **median** per metric per provider (MLPerf/SPEC-aligned)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Environment:** All providers single-zone Central US corridor, identical images (backend 0.3.10, frontend 0.3.5, vLLM v0.6.2, Qdrant v1.12.6), consistent pod-to-node placement (1 GPU + 2 CPU nodes each), 5 Qdrant points each. EKS in us-east-2 (Ohio). All benchmarks ran simultaneously per run.

### North-South Median (7 runs × 500 requests = 3,500 requests per provider)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success (total)** | 3,498/3,500 ✅ | 3,475/3,500 ⚠️ | 3,495/3,500 ✅ |
| **TTFT p50** | 4,556 ms | **1,518 ms** 🏆 | 2,325 ms |
| **TTFT p95** | 9,410 ms | 6,989 ms | **6,391 ms** 🏆 |
| **Latency p50** | **14,245 ms** 🏆 | 15,023 ms | 15,968 ms |
| **Latency p95** | 22,201 ms | **19,983 ms** 🏆 | 20,119 ms |
| **TPOT p50** | **37.9 ms** 🏆 | 54.2 ms | 56.6 ms |
| **TPOT p95** | **45.3 ms** 🏆 | 58.3 ms | 60.8 ms |
| **Tokens/sec** | **17.70** 🏆 | 16.22 | 15.30 |
| **Duration** | **155s** 🏆 | 172s | 181s |

### East-West Network Median (7 runs)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.93 Gbps | **4.87 Gbps** 🏆 | 3.96 Gbps |
| **Retransmits** | 3,663 | 3,234 | **0** 🏆 |

### Cost Comparison

| Provider | Monthly (w/ network) | Hourly | Cost vs LKE |
|----------|---------------------|--------|-------------|
| **Akamai LKE** | **$433** 🏆 | **$0.59** | — |
| **AWS EKS** | $768 | $1.05 | +77% |
| **GCP GKE** | $807 | $1.11 | +86% |

### Key Findings

1. **LKE wins 5 of 8 NS metrics** — Latency p50, both TPOT percentiles, tokens/sec, and duration
2. **EKS wins 2 of 8 NS metrics** — TTFT p50 (1,518 ms) and Latency p95 (19,983 ms)
3. **GKE wins TTFT p95** (6,391 ms) — most consistent tail latency for time-to-first-token
4. **LKE token generation is 32% faster** than EKS and 48% faster than GKE (TPOT p50: 37.9 vs 54.2 vs 56.6 ms)
5. **EKS wins east-west throughput** at 4.87 Gbps median (5.2x LKE, 23% over GKE)
6. **GKE median EW retransmits is 0** — 5 of 7 runs had zero retransmits (bimodal: 0 or 5,000+)
7. **LKE is 44% cheaper than EKS and 46% cheaper than GKE** while winning the majority of NS metrics

### Previous 5-Run Average (February 19, 2026)

> Prior to the EKS region change (us-east-1 → us-east-2). See individual run results below for details.
> LKE won 7/8 NS metrics. GKE won TTFT p50. EKS won EW throughput (4.31 Gbps).
> Full results preserved in the run-by-run sections below.

---

## Benchmark Results (February 22, 2026 – Run 1)

**Timestamp:** 2026-02-21T20:45:36 CST (2026-02-22T02:45:36 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** First run (post-region-change). All providers single-zone, Central US corridor, identical images (backend 0.3.10, frontend 0.3.5, vLLM v0.6.2, Qdrant v1.12.6), consistent pod-to-node placement, 5 Qdrant points each. EKS moved to us-east-2 (Ohio). GKE LB IP updated.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 488/500 ⚠️ | 500/500 ✅ |
| **TTFT p50** | **3,510 ms** 🏆 | 4,145 ms | 4,089 ms |
| **TTFT p95** | 7,650 ms | 35,157 ms | **6,391 ms** 🏆 |
| **Latency p50** | **13,123 ms** 🏆 | 17,060 ms | 17,447 ms |
| **Latency p95** | **22,201 ms** 🏆 | 47,641 ms | 22,937 ms |
| **TPOT p50** | **39.0 ms** 🏆 | 54.2 ms | 56.6 ms |
| **TPOT p95** | **67.7 ms** 🏆 | 67.9 ms | 72.2 ms |
| **Tokens/sec** | **18.10** 🏆 | 14.47 | 14.21 |
| **Duration** | **155s** 🏆 | 210s | 193s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.93 Gbps | **4.91 Gbps** 🏆 | 3.99 Gbps |
| **Retransmits** | 2,091 | 3,398 | **0** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $768 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 22, 2026 – Run 7)

**Timestamp:** 2026-02-21T21:53:15 CST (2026-02-22T03:53:15 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Seventh and final run. LKE had largest outlier of all runs (TTFT p50 15.8s, Lat p50 23.6s, 254s duration, 2 errors). EKS had 13 errors. GKE had 5 errors.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 498/500 ⚠️ | 487/500 ⚠️ | 495/500 ⚠️ |
| **TTFT p50** | 15,777 ms | **729 ms** 🏆 | 1,434 ms |
| **TTFT p95** | 24,915 ms | 5,851 ms | **4,913 ms** 🏆 |
| **Latency p50** | 23,648 ms | **14,848 ms** 🏆 | 15,734 ms |
| **Latency p95** | 32,756 ms | **18,885 ms** | **19,468 ms** |
| **TPOT p50** | **35.7 ms** 🏆 | 55.8 ms | 57.6 ms |
| **TPOT p95** | **48.3 ms** 🏆 | 58.5 ms | 61.3 ms |
| **Tokens/sec** | 11.35 | **16.95** 🏆 | 15.71 |
| **Duration** | 254s | 222s | **176s** 🏆 |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.97 Gbps | **4.87 Gbps** 🏆 | 3.85 Gbps |
| **Retransmits** | **2,774** 🏆 | 3,234 | 6,417 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $768 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 22, 2026 – Run 6)

**Timestamp:** 2026-02-21T21:48:42 CST (2026-02-22T03:48:42 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Sixth run. All providers single-zone, Central US corridor, identical images, 5 Qdrant points each. 500/500 success on all three. LKE had elevated TTFT again (p50 8.2s, p95 17.0s).

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 8,201 ms | **1,505 ms** 🏆 | 2,300 ms |
| **TTFT p95** | 16,997 ms | **6,497 ms** | **6,989 ms** |
| **Latency p50** | 17,805 ms | **15,023 ms** 🏆 | 15,931 ms |
| **Latency p95** | 25,631 ms | **19,983 ms** 🏆 | 20,311 ms |
| **TPOT p50** | **37.9 ms** 🏆 | 53.7 ms | 56.6 ms |
| **TPOT p95** | **43.5 ms** 🏆 | 57.7 ms | 60.8 ms |
| **Tokens/sec** | 14.66 | **16.22** 🏆 | 15.30 |
| **Duration** | 199s | **169s** 🏆 | 181s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.93 Gbps | **4.90 Gbps** 🏆 | 3.96 Gbps |
| **Retransmits** | 3,663 | 3,156 | **0** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $768 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 22, 2026 – Run 5)

**Timestamp:** 2026-02-21T21:34:39 CST (2026-02-22T03:34:39 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Fifth and final run. All providers single-zone, Central US corridor, identical images, 5 Qdrant points each. All 6 benchmarks ran simultaneously. 500/500 success on all three providers. GKE EW retransmits spiked (5,146) after four consecutive 0-retransmit runs.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 4,267 ms | **1,115 ms** 🏆 | 1,953 ms |
| **TTFT p95** | 9,410 ms | 7,285 ms | **6,028 ms** 🏆 |
| **Latency p50** | **14,017 ms** 🏆 | 14,905 ms | 15,927 ms |
| **Latency p95** | **19,303 ms** 🏆 | 20,459 ms | 19,680 ms |
| **TPOT p50** | **37.1 ms** 🏆 | 54.9 ms | 56.7 ms |
| **TPOT p95** | **43.4 ms** 🏆 | 58.3 ms | 60.5 ms |
| **Tokens/sec** | **18.10** 🏆 | 16.49 | 15.46 |
| **Duration** | **153s** 🏆 | 168s | 176s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.97 Gbps | **4.66 Gbps** 🏆 | 3.90 Gbps |
| **Retransmits** | 5,033 | **3,169** 🏆 | 5,146 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $768 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 22, 2026 – Run 4)

**Timestamp:** 2026-02-21T21:22:43 CST (2026-02-22T03:22:43 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Fourth run. All providers single-zone, Central US corridor, identical images, 5 Qdrant points each. All 6 benchmarks ran simultaneously. 500/500 success on all three providers. LKE had an outlier run with elevated TTFT (p50 9.6s, p95 16.4s).

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 9,612 ms | **1,518 ms** 🏆 | 2,325 ms |
| **TTFT p95** | 16,383 ms | **5,743 ms** | **5,921 ms** |
| **Latency p50** | 19,067 ms | **14,804 ms** 🏆 | 15,968 ms |
| **Latency p95** | 25,654 ms | **19,137 ms** | **19,927 ms** |
| **TPOT p50** | **38.2 ms** 🏆 | 54.2 ms | 56.8 ms |
| **TPOT p95** | **46.6 ms** 🏆 | 58.4 ms | 60.8 ms |
| **Tokens/sec** | 14.61 | **16.40** 🏆 | 15.41 |
| **Duration** | 202s | **172s** 🏆 | 180s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.95 Gbps | **4.87 Gbps** 🏆 | 3.97 Gbps |
| **Retransmits** | 5,013 | 3,042 | **0** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $768 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 22, 2026 – Run 3)

**Timestamp:** 2026-02-21T21:12:48 CST (2026-02-22T03:12:48 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Third run. All providers single-zone, Central US corridor, identical images, 5 Qdrant points each. All 6 benchmarks ran simultaneously. 500/500 success on all three providers.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 4,556 ms | **3,229 ms** 🏆 | 3,939 ms |
| **TTFT p95** | 9,236 ms | **6,780 ms** | **6,780 ms** 🏆 |
| **Latency p50** | **14,245 ms** 🏆 | 16,151 ms | 16,924 ms |
| **Latency p95** | **18,759 ms** 🏆 | 20,027 ms | 20,119 ms |
| **TPOT p50** | **37.9 ms** 🏆 | 52.0 ms | 53.8 ms |
| **TPOT p95** | **44.7 ms** 🏆 | 57.4 ms | 60.2 ms |
| **Tokens/sec** | **17.70** 🏆 | 15.79 | 14.91 |
| **Duration** | **155s** 🏆 | 174s | 182s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.91 Gbps | **4.86 Gbps** 🏆 | 3.96 Gbps |
| **Retransmits** | 4,258 | 3,537 | **65** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $768 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 22, 2026 – Run 2)

**Timestamp:** 2026-02-21T20:54:51 CST (2026-02-22T02:54:51 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Second run. All providers single-zone, Central US corridor, identical images, 5 Qdrant points each. All 6 benchmarks ran simultaneously. 500/500 success on all three providers.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 3,652 ms | **3,157 ms** 🏆 | 3,541 ms |
| **TTFT p95** | **5,774 ms** 🏆 | 6,120 ms | 7,403 ms |
| **Latency p50** | **12,978 ms** 🏆 | 15,313 ms | 16,950 ms |
| **Latency p95** | **16,812 ms** 🏆 | 19,333 ms | 21,599 ms |
| **TPOT p50** | **38.5 ms** 🏆 | 51.7 ms | 54.8 ms |
| **TPOT p95** | **45.3 ms** 🏆 | 56.8 ms | 61.0 ms |
| **Tokens/sec** | **19.60** 🏆 | 15.83 | 14.94 |
| **Duration** | **143s** 🏆 | 170s | 185s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.90 Gbps | **4.89 Gbps** 🏆 | 3.73 Gbps |
| **Retransmits** | 2,165 | 3,418 | **0** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $768 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 19, 2026 – Run 5)

**Timestamp:** 2026-02-19T18:59:36 CST (2026-02-20T00:59:36 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Fifth run. All providers single-zone, identical images, consistent pod-to-node placement. All 500/500 success.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 5,115 ms | 4,371 ms | **4,004 ms** 🏆 |
| **TTFT p95** | **7,931 ms** 🏆 | 9,183 ms | 7,890 ms |
| **Latency p50** | **16,511 ms** 🏆 | 19,248 ms | 19,695 ms |
| **Latency p95** | **18,045 ms** 🏆 | 23,338 ms | 22,375 ms |
| **TPOT p50** | **44.1 ms** 🏆 | 58.0 ms | 62.7 ms |
| **TPOT p95** | **51.0 ms** 🏆 | 65.8 ms | 70.1 ms |
| **Tokens/sec** | **15.90** 🏆 | 13.59 | 13.08 |
| **Duration** | **173s** 🏆 | 210s | 211s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.02 Gbps | **4.74 Gbps** 🏆 | 3.88 Gbps |
| **Retransmits** | 2,306 | 2,925 | **0** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $769 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 19, 2026 – Run 4)

**Timestamp:** 2026-02-19T18:42:43 CST (2026-02-20T00:42:43 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Fourth run. All providers single-zone, identical images, consistent pod-to-node placement.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 4,923 ms | 5,290 ms | **4,294 ms** 🏆 |
| **TTFT p95** | **7,398 ms** 🏆 | 8,837 ms | 8,688 ms |
| **Latency p50** | **16,056 ms** 🏆 | 19,872 ms | 20,350 ms |
| **Latency p95** | **18,347 ms** 🏆 | 23,005 ms | 24,061 ms |
| **TPOT p50** | **43.4 ms** 🏆 | 56.3 ms | 62.9 ms |
| **TPOT p95** | **50.6 ms** 🏆 | 64.8 ms | 70.3 ms |
| **Tokens/sec** | **16.25** 🏆 | 13.33 | 12.78 |
| **Duration** | **168s** 🏆 | 212s | 216s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.09 Gbps | **4.83 Gbps** 🏆 | 3.75 Gbps |
| **Retransmits** | 3,028 | **2,606** 🏆 | 5,154 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $769 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 19, 2026 – Run 3)

**Timestamp:** 2026-02-19T14:35:00 CST (2026-02-19T20:35:00 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Third run, same session. Pre-flight verified: all providers single-zone, identical images, consistent pod-to-node placement.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | 5,033 ms | 5,801 ms | **4,724 ms** 🏆 |
| **TTFT p95** | **7,880 ms** 🏆 | 27,301 ms | 8,377 ms |
| **Latency p50** | **16,073 ms** 🏆 | 20,570 ms | 21,063 ms |
| **Latency p95** | **19,247 ms** 🏆 | 43,206 ms | 22,756 ms |
| **TPOT p50** | **43.5 ms** 🏆 | 56.9 ms | 61.7 ms |
| **TPOT p95** | **50.2 ms** 🏆 | 66.2 ms | 70.3 ms |
| **Tokens/sec** | **16.12** 🏆 | 12.68 | 12.72 |
| **Duration** | **168s** 🏆 | 237s | 218s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.06 Gbps | **3.90 Gbps** 🏆 | 3.75 Gbps |
| **Retransmits** | 5,406 | **1,724** 🏆 | 6,284 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $769 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 19, 2026 – Run 2)

**Timestamp:** 2026-02-19T14:21:55 CST (2026-02-19T20:21:55 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** Second run, same session. All providers single-zone. EKS on gp3 storage.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 481/500 ⚠️ |
| **TTFT p50** | 3,864 ms | 5,555 ms | **3,509 ms** 🏆 |
| **TTFT p95** | **6,633 ms** 🏆 | 9,602 ms | 7,374 ms |
| **Latency p50** | **14,940 ms** 🏆 | 20,954 ms | 16,360 ms |
| **Latency p95** | **17,323 ms** 🏆 | 25,529 ms | 20,874 ms |
| **TPOT p50** | **44.7 ms** 🏆 | 58.4 ms | 51.0 ms |
| **TPOT p95** | **50.6 ms** 🏆 | 66.5 ms | 65.7 ms |
| **Tokens/sec** | **17.10** 🏆 | 13.31 | 15.42 |
| **Duration** | **160s** 🏆 | 218s | 255s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.03 Gbps | **4.29 Gbps** 🏆 | 3.92 Gbps |
| **Retransmits** | 3,653 | 2,352 | **0** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $769 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 19, 2026 – Run 1)

**Timestamp:** 2026-02-19T13:59:45 CST (2026-02-19T19:59:45 UTC)  
**Backend Version:** 0.3.10  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** EKS migrated to single-AZ (us-east-1d) and gp3 storage. All providers now run in single-zone deployments.

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | **3,933 ms** 🏆 | 4,382 ms | 5,028 ms |
| **TTFT p95** | **7,175 ms** 🏆 | 8,724 ms | 11,942 ms |
| **Latency p50** | 14,779 ms | **13,882 ms** 🏆 | 20,926 ms |
| **Latency p95** | **17,866 ms** 🏆 | 19,200 ms | 28,255 ms |
| **TPOT p50** | 44.3 ms | **39.8 ms** 🏆 | 61.8 ms |
| **TPOT p95** | 50.8 ms | **44.5 ms** 🏆 | 70.2 ms |
| **Tokens/sec** | 16.92 | **18.21** 🏆 | 12.78 |
| **Duration** | 164s | **155s** 🏆 | 225s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.00 Gbps | 3.77 Gbps | **3.96 Gbps** 🏆 |
| **Retransmits** | 2,341 | 1,442 | **1** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $769 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 18, 2026)

**Timestamp:** 2026-02-17T22:26:40 CST (2026-02-18T04:26:40 UTC)  
**Backend Version:** 0.3.9  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | **3,124 ms** 🏆 | 5,669 ms | 4,617 ms |
| **TTFT p95** | **5,980 ms** 🏆 | 9,082 ms | 8,413 ms |
| **Latency p50** | **14,240 ms** 🏆 | 20,088 ms | 20,050 ms |
| **Latency p95** | **16,219 ms** 🏆 | 23,590 ms | 22,880 ms |
| **TPOT p50** | **42.6 ms** 🏆 | 57.6 ms | 61.6 ms |
| **TPOT p95** | **49.2 ms** 🏆 | 66.2 ms | 68.2 ms |
| **Tokens/sec** | **18.06** 🏆 | 13.17 | 12.87 |
| **Duration** | **151s** 🏆 | 215s | 217s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.02 Gbps | **4.65 Gbps** 🏆 | 3.82 Gbps |
| **Retransmits** | 3,949 | **2,212** 🏆 | 25,489 |

### Current Accurate Costs (from live queries):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $770 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 17, 2026)

**Timestamp:** 2026-02-17T19:35:07 CST (2026-02-18T01:35:07 UTC)  
**Backend Version:** 0.3.9  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens  
**Note:** EKS and GKE clusters were freshly re-provisioned today. EKS uses g6.xlarge (L4), GKE uses g2-standard-8 (L4), LKE uses g2-gpu-rtx4000a1-s (RTX 4000 Ada).

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 450/500 ⚠️ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | **2,324 ms** 🏆 | 6,230 ms | 8,044 ms |
| **TTFT p95** | **8,472 ms** 🏆 | 36,380 ms | 14,230 ms |
| **Latency p50** | **13,282 ms** 🏆 | 21,331 ms | 21,979 ms |
| **Latency p95** | **24,618 ms** 🏆 | 70,956 ms | 60,221 ms |
| **TPOT p50** | **30.6 ms** 🏆 | 56.4 ms | 60.7 ms |
| **TPOT p95** | **73.7 ms** 🏆 | 182.3 ms | 128.8 ms |
| **Tokens/sec** | **20.75** 🏆 | 11.42 | 10.99 |
| **Duration** | **143s** 🏆 | 296s | 286s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 0.97 Gbps | **4.65 Gbps** 🏆 | 3.92 Gbps |
| **Retransmits** | 8,751 | **1,218** | **1,218** 🏆 |

### Current Accurate Costs (from cost-config.yaml):

| Provider | Hourly | Monthly (compute only) |
|----------|--------|------------------------|
| **Akamai LKE** | $0.59 | $433 |
| **AWS EKS** | $0.99 | $722 |
| **GCP GKE** | $1.09 | $795 |

---

## Benchmark Results (February 4, 2026)

**Timestamp:** 2026-02-04T05:33:30 CST (2026-02-04T11:33:30 UTC)  
**Backend Version:** 0.3.9  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 499/500 ✅ | 500/500 ✅ | 480/500 ⚠️ |
| **TTFT p50** | **1,442 ms** 🏆 | 3,884 ms | 2,540 ms |
| **TTFT p95** | **6,010 ms** 🏆 | 6,753 ms | 7,124 ms |
| **Latency p50** | **9,009 ms** 🏆 | 18,784 ms | 15,737 ms |
| **Latency p95** | **11,841 ms** 🏆 | 19,715 ms | 21,486 ms |
| **TPOT p50** | **29.0 ms** 🏆 | 58.3 ms | 52.8 ms |
| **Tokens/sec** | **27.07** 🏆 | 13.87 | 15.55 |
| **Duration** | **107s** 🏆 | 199s | 282s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.06 Gbps | 4.92 Gbps | **6.65 Gbps** 🏆 |
| **Retransmits** | 2,416 | **194** 🏆 | 110,884 |

### Current Accurate Costs (from live queries):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $770 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 3, 2026)

**Timestamp:** 2026-02-03T09:51:20 CST (2026-02-03T15:51:20 UTC)  
**Backend Version:** 0.3.9  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | **2,902 ms** 🏆 | 3,072 ms | 3,468 ms |
| **TTFT p95** | **4,761 ms** 🏆 | 7,022 ms | 7,002 ms |
| **Latency p50** | **13,859 ms** 🏆 | 18,729 ms | 19,540 ms |
| **Latency p95** | **14,640 ms** 🏆 | 21,816 ms | 21,884 ms |
| **TPOT p50** | **43.2 ms** 🏆 | 60.8 ms | 63.3 ms |
| **Tokens/sec** | **18.38** 🏆 | 13.98 | 13.30 |
| **Duration** | **147s** 🏆 | 201s | 209s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.12 Gbps | 4.91 Gbps | **5.85 Gbps** 🏆 |
| **Retransmits** | 8,004 | **224** 🏆 | 124,699 |

### Current Accurate Costs (from live queries):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $770 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 2, 2026)

**Timestamp:** 2026-02-02T06:27:39 CST (2026-02-02T12:27:39 UTC)  
**Backend Version:** 0.3.9  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 481/500 ⚠️ | 500/500 ✅ |
| **TTFT p50** | **2,819 ms** 🏆 | 2,986 ms | 2,917 ms |
| **TTFT p95** | **4,594 ms** 🏆 | 6,733 ms | 6,453 ms |
| **Latency p50** | **13,736 ms** 🏆 | 14,775 ms | 19,166 ms |
| **Latency p95** | **14,673 ms** 🏆 | 21,181 ms | 21,395 ms |
| **TPOT p50** | **43.3 ms** 🏆 | 49.2 ms | 63.5 ms |
| **Tokens/sec** | **18.49** 🏆 | 16.56 | 13.42 |
| **Duration** | **147s** 🏆 | 254s | 205s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.06 Gbps | 4.95 Gbps | **6.65 Gbps** 🏆 |
| **Retransmits** | 1,726 | **160** 🏆 | 71,928 |

### Current Accurate Costs (from live queries):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $770 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (February 1, 2026)

**Timestamp:** 2026-02-01T14:25:58 CST (2026-02-01T20:25:58 UTC)  
**Backend Version:** 0.3.9  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | **1,994 ms** 🏆 | 3,407 ms | 2,544 ms |
| **TTFT p95** | **4,328 ms** 🏆 | 7,230 ms | 6,683 ms |
| **Latency p50** | **9,872 ms** 🏆 | 17,796 ms | 18,420 ms |
| **Latency p95** | **14,597 ms** 🏆 | 19,888 ms | 20,212 ms |
| **TPOT p50** | **31.3 ms** 🏆 | 53.4 ms | 59.9 ms |
| **Tokens/sec** | **24.05** 🏆 | 15.42 | 15.13 |
| **Duration** | **120s** 🏆 | 183s | 189s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.10 Gbps | 4.94 Gbps | **6.43 Gbps** 🏆 |
| **Retransmits** | 3,833 | **222** 🏆 | 98,988 |

### Current Accurate Costs (from live queries):

| Provider | Monthly (w/ network) | Hourly |
|----------|---------------------|--------|
| **Akamai LKE** | $433 | $0.59 |
| **AWS EKS** | $770 | $1.05 |
| **GCP GKE** | $807 | $1.11 |

---

## Benchmark Results (January 31, 2026)

**Timestamp:** 2026-01-31T19:56:31 PST (2026-02-01T01:56:31 UTC)  
**Backend Version:** 0.3.9  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 499/500 ⚠️ | 500/500 ✅ |
| **TTFT p50** | **2,260 ms** 🏆 | 2,458 ms | 4,340 ms |
| **TTFT p95** | **4,214 ms** 🏆 | 5,239 ms | 7,277 ms |
| **Latency p50** | **13,588 ms** 🏆 | 18,031 ms | 21,350 ms |
| **Latency p95** | **15,090 ms** 🏆 | 23,171 ms | 23,587 ms |
| **TPOT p50** | **45.2 ms** 🏆 | 62.1 ms | 65.2 ms |
| **Tokens/sec** | **18.82** 🏆 | 14.14 | 12.56 |
| **Duration** | **145s** 🏆 | 238s | 226s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.10 Gbps | 4.92 Gbps | **6.74 Gbps** 🏆 |
| **Retransmits** | 10,598 | **171** 🏆 | 55,829 |

---

## Benchmark Results (January 30, 2026)

**Timestamp:** 2026-01-30T16:10:00Z  
**Backend Version:** 0.3.7  
**Test Configuration:** 500 requests, 50 concurrency, 256 max output tokens

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | **2,912 ms** 🏆 | 3,490 ms | 2,933 ms |
| **TTFT p95** | **6,162 ms** 🏆 | 6,694 ms | 9,809 ms |
| **Latency p50** | **14,097 ms** 🏆 | 18,041 ms | 19,193 ms |
| **Latency p95** | **22,620 ms** 🏆 | 29,488 ms | 28,922 ms |
| **TPOT p50** | **44.6 ms** 🏆 | 57.5 ms | 63.2 ms |
| **Tokens/sec** | **17.63** 🏆 | 13.85 | 13.16 |
| **Duration** | **167s** 🏆 | 213s | 219s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.18 Gbps | 4.97 Gbps | **6.72 Gbps** 🏆 |
| **Retransmits** | 11,499 | **203** 🏆 | 46,610 |

---

## Historical Summary

| Date | LKE TTFT p50 | EKS TTFT p50 | GKE TTFT p50 | Winner |
|------|--------------|--------------|--------------|--------|
| 2026-02-18 | 3,124 ms | 5,669 ms | 4,617 ms | LKE 🏆 |
| 2026-02-17 | 2,324 ms | 6,230 ms | 8,044 ms | LKE 🏆 |
| 2026-02-04 | 1,442 ms | 3,884 ms | 2,540 ms | LKE 🏆 |
| 2026-02-03 | 2,902 ms | 3,072 ms | 3,468 ms | LKE 🏆 |
| 2026-02-02 | 2,819 ms | 2,986 ms | 2,917 ms | LKE 🏆 |
| 2026-02-01 | 1,994 ms | 3,407 ms | 2,544 ms | LKE 🏆 |
| 2026-01-31 | 2,260 ms | 2,458 ms | 4,340 ms | LKE 🏆 |
| 2026-01-30 | 2,912 ms | 3,490 ms | 2,933 ms | LKE 🏆 |

| Date | LKE Tokens/sec | EKS Tokens/sec | GKE Tokens/sec | Winner |
|------|----------------|----------------|----------------|--------|
| 2026-02-18 | 18.06 | 13.17 | 12.87 | LKE 🏆 |
| 2026-02-17 | 20.75 | 11.42 | 10.99 | LKE 🏆 |
| 2026-02-04 | 27.07 | 13.87 | 15.55 | LKE 🏆 |
| 2026-02-03 | 18.38 | 13.98 | 13.30 | LKE 🏆 |
| 2026-02-02 | 18.49 | 16.56 | 13.42 | LKE 🏆 |
| 2026-02-01 | 24.05 | 15.42 | 15.13 | LKE 🏆 |
| 2026-01-31 | 18.82 | 14.14 | 12.56 | LKE 🏆 |
| 2026-01-30 | 17.63 | 13.85 | 13.16 | LKE 🏆 |
