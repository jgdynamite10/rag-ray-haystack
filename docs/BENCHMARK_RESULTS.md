# Benchmark Results

This document tracks benchmark results across all three cloud providers over time.

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
| **Akamai LKE** | $435.16 | $0.60 |
| **AWS EKS** | $845.51 | $1.16 |
| **GCP GKE** | $905.47 | $1.24 |

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
| 2026-02-01 | 1,994 ms | 3,407 ms | 2,544 ms | LKE 🏆 |
| 2026-01-31 | 2,260 ms | 2,458 ms | 4,340 ms | LKE 🏆 |
| 2026-01-30 | 2,912 ms | 3,490 ms | 2,933 ms | LKE 🏆 |

| Date | LKE Tokens/sec | EKS Tokens/sec | GKE Tokens/sec | Winner |
|------|----------------|----------------|----------------|--------|
| 2026-02-01 | 24.05 | 15.42 | 15.13 | LKE 🏆 |
| 2026-01-31 | 18.82 | 14.14 | 12.56 | LKE 🏆 |
| 2026-01-30 | 17.63 | 13.85 | 13.16 | LKE 🏆 |
