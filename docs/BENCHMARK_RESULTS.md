# Benchmark Results

This document tracks benchmark results across all three cloud providers over time.

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
