import { useEffect, useMemo, useState } from "react";

const defaultBackend = import.meta.env.VITE_BACKEND_URL || `${window.location.origin}/api`;
const ROLLING_WINDOW = 50;

const percentile = (values, pct) => {
  if (!values.length) {
    return null;
  }
  const ordered = [...values].sort((a, b) => a - b);
  const index = Math.max(0, Math.ceil(ordered.length * pct) - 1);
  return ordered[index];
};

const formatMetric = (value, suffix = "ms") => {
  if (value === null || value === undefined) {
    return "—";
  }
  return `${value.toFixed(2)} ${suffix}`;
};

export default function App() {
  const [backendUrl, setBackendUrl] = useState(defaultBackend);
  const [query, setQuery] = useState("");
  const [messages, setMessages] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [uploadFiles, setUploadFiles] = useState([]);
  const [documentIndex, setDocumentIndex] = useState([]);
  const [status, setStatus] = useState("");
  const [sessionId, setSessionId] = useState("");
  const [timings, setTimings] = useState(null);
  const [stats, setStats] = useState(null);
  const [useStreaming, setUseStreaming] = useState(true);
  const [ttftMs, setTtftMs] = useState(null);
  const [tokensPerSecond, setTokensPerSecond] = useState(null);
  const [rollingMetrics, setRollingMetrics] = useState([]);

  useEffect(() => {
    let active = true;
    const fetchStats = async () => {
      try {
        const response = await fetch(`${backendUrl}/stats`);
        const data = await response.json();
        if (active) {
          setStats(data);
        }
      } catch (error) {
        if (active) {
          setStats({ error: error.message });
        }
      }
    };
    const fetchDocuments = async () => {
      try {
        const response = await fetch(`${backendUrl}/documents`);
        const data = await response.json();
        if (active) {
          setDocumentIndex(data.items || []);
        }
      } catch (error) {
        if (active) {
          setDocumentIndex([]);
        }
      }
    };
    fetchStats();
    fetchDocuments();
    const interval = setInterval(() => {
      fetchStats();
      fetchDocuments();
    }, 5000);
    return () => {
      active = false;
      clearInterval(interval);
    };
  }, [backendUrl]);

  const canSubmit = useMemo(() => query.trim().length > 0, [query]);
  const rollingSummary = useMemo(() => {
    const ttftValues = rollingMetrics
      .map((entry) => entry.ttft_ms)
      .filter((value) => value !== null && value !== undefined);
    const totalValues = rollingMetrics
      .map((entry) => entry.total_ms)
      .filter((value) => value !== null && value !== undefined);
    const tokenValues = rollingMetrics
      .map((entry) => entry.tokens_per_sec)
      .filter((value) => value !== null && value !== undefined);
    const successes = rollingMetrics.filter((entry) => entry.success).length;
    const errors = rollingMetrics.length - successes;
    return {
      ttft_p50: percentile(ttftValues, 0.5),
      ttft_p95: percentile(ttftValues, 0.95),
      total_p50: percentile(totalValues, 0.5),
      total_p95: percentile(totalValues, 0.95),
      avg_tokens_per_sec: tokenValues.length
        ? tokenValues.reduce((sum, value) => sum + value, 0) / tokenValues.length
        : null,
      successes,
      errors,
    };
  }, [rollingMetrics]);

  const handleQuery = async (event) => {
    event.preventDefault();
    if (!canSubmit) {
      return;
    }
    setStatus(useStreaming ? "Streaming..." : "Querying...");
    const nextMessages = [...messages, { role: "user", content: query }];
    const clientStart = performance.now();
    const assistantMetrics = {
      request_id: null,
      replica_id: null,
      model_id: null,
      k: null,
      ttft_ms: null,
      tokens_per_sec: null,
      total_ms: null,
      token_count: 0,
      _client_start_ms: clientStart,
      _first_token_ms: null,
      _last_token_ms: null,
    };
    setTtftMs(null);
    setTokensPerSecond(null);
    setQuery("");

    try {
      if (useStreaming) {
        const assistantIndex = nextMessages.length;
        setMessages([
          ...nextMessages,
          { role: "assistant", content: "", metrics: assistantMetrics },
        ]);

        const response = await fetch(`${backendUrl}/query/stream`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query, session_id: sessionId || undefined }),
        });

        if (!response.body) {
          throw new Error("Streaming not supported by the server.");
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";
        let localTokenCount = 0;
        let localRequestId = null;
        let localSessionId = sessionId || null;
        while (true) {
          const { done, value } = await reader.read();
          if (done) {
            break;
          }
          buffer += decoder.decode(value, { stream: true });
          while (buffer.includes("\n\n")) {
            const [rawEvent, rest] = buffer.split("\n\n", 2);
            buffer = rest;
            const lines = rawEvent.split("\n");
            let eventType = "message";
            let dataLine = "";
            lines.forEach((line) => {
              if (line.startsWith("event:")) {
                eventType = line.replace("event:", "").trim();
              }
              if (line.startsWith("data:")) {
                dataLine = line.replace("data:", "").trim();
              }
            });
            if (!dataLine) {
              continue;
            }
            const payload = JSON.parse(dataLine);
            if (eventType === "token") {
              if (!assistantMetrics._first_token_ms) {
                const ttftValue = performance.now() - clientStart;
                assistantMetrics._first_token_ms = performance.now();
                assistantMetrics.ttft_ms = ttftValue;
                setTtftMs(ttftValue);
              }
              assistantMetrics._last_token_ms = performance.now();
              localTokenCount += 1;
              assistantMetrics.token_count = localTokenCount;
              setMessages((current) => {
                const updated = [...current];
                const existing = updated[assistantIndex]?.content || "";
                updated[assistantIndex] = {
                  role: "assistant",
                  content: `${existing}${payload.text}`,
                  metrics: { ...(updated[assistantIndex]?.metrics || {}), ...assistantMetrics },
                };
                return updated;
              });
            }
            if (eventType === "meta") {
              setDocuments(payload.documents || []);
              localRequestId = payload.request_id || localRequestId;
              localSessionId = payload.session_id || localSessionId;
              if (payload.session_id) {
                setSessionId(payload.session_id);
              }
              assistantMetrics.request_id = payload.request_id || assistantMetrics.request_id;
              assistantMetrics.replica_id = payload.replica_id || assistantMetrics.replica_id;
              assistantMetrics.model_id = payload.model_id || assistantMetrics.model_id;
              assistantMetrics.k = payload.k ?? assistantMetrics.k;
              if (payload.timings?.retrieval_ms) {
                setTimings((current) => ({
                  ...(current || {}),
                  retrieval_ms: payload.timings.retrieval_ms,
                }));
              }
            }
            if (eventType === "ttft") {
              setTtftMs(payload.ttft_ms ?? null);
            }
            if (eventType === "done") {
              const totalMs = performance.now() - clientStart;
              assistantMetrics.total_ms = totalMs;
              assistantMetrics.request_id = payload.request_id || assistantMetrics.request_id;
              assistantMetrics.replica_id = payload.replica_id || assistantMetrics.replica_id;
              assistantMetrics.model_id = payload.model_id || assistantMetrics.model_id;
              assistantMetrics.k = payload.k ?? assistantMetrics.k;
              const streamDuration =
                assistantMetrics._first_token_ms && assistantMetrics._last_token_ms
                  ? (assistantMetrics._last_token_ms - assistantMetrics._first_token_ms) / 1000
                  : null;
              const tokensPerSec =
                payload.tokens_per_sec ??
                (streamDuration && localTokenCount
                  ? localTokenCount / streamDuration
                  : null);
              assistantMetrics.tokens_per_sec = tokensPerSec;
              setDocuments(payload.documents || []);
              setTimings({ total_ms: totalMs, retrieval_ms: timings?.retrieval_ms });
              if (payload.session_id) {
                setSessionId(payload.session_id);
              }
              setTokensPerSecond(tokensPerSec);
              setTtftMs(assistantMetrics.ttft_ms);
              setMessages((current) => {
                const updated = [...current];
                updated[assistantIndex] = {
                  role: "assistant",
                  content: updated[assistantIndex]?.content || "",
                  metrics: { ...(updated[assistantIndex]?.metrics || {}), ...assistantMetrics },
                };
                return updated;
              });
              setRollingMetrics((current) => {
                const next = [
                  ...current,
                  {
                    request_id: payload.request_id || localRequestId,
                    ttft_ms: assistantMetrics.ttft_ms,
                    total_ms: totalMs,
                    tokens_per_sec: tokensPerSec,
                    success: true,
                  },
                ];
                return next.slice(-ROLLING_WINDOW);
              });
              setStatus("Ready");
            }
            if (eventType === "error") {
              const totalMs = performance.now() - clientStart;
              setRollingMetrics((current) => {
                const next = [
                  ...current,
                  {
                    request_id: payload.request_id || localRequestId,
                    ttft_ms: assistantMetrics.ttft_ms,
                    total_ms: totalMs,
                    tokens_per_sec: assistantMetrics.tokens_per_sec,
                    success: false,
                  },
                ];
                return next.slice(-ROLLING_WINDOW);
              });
              setStatus(payload.message || "Streaming error.");
            }
          }
        }
      } else {
        const assistantIndex = nextMessages.length;
        setMessages([
          ...nextMessages,
          { role: "assistant", content: "", metrics: assistantMetrics },
        ]);
        const response = await fetch(`${backendUrl}/query`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query, session_id: sessionId || undefined }),
        });
        const data = await response.json();
        const totalMs = performance.now() - clientStart;
        setDocuments(data.documents || []);
        setTimings({ total_ms: totalMs, retrieval_ms: data.timings?.retrieval_ms });
        setTokensPerSecond(data.timings?.tokens_per_second ?? null);
        setTtftMs(data.timings?.ttft_ms ?? null);
        if (data.session_id) {
          setSessionId(data.session_id);
        }
        setMessages((current) => {
          const updated = [...current];
          updated[assistantIndex] = {
            role: "assistant",
            content: data.answers?.[0]?.answer || "No answer.",
            metrics: {
              ...assistantMetrics,
              total_ms: totalMs,
              ttft_ms: data.timings?.ttft_ms ?? null,
              tokens_per_sec: data.timings?.tokens_per_second ?? null,
              k: data.documents?.length ?? null,
            },
          };
          return updated;
        });
        setRollingMetrics((current) => {
          const next = [
            ...current,
            {
              request_id: null,
              ttft_ms: data.timings?.ttft_ms ?? null,
              total_ms: totalMs,
              tokens_per_sec: data.timings?.tokens_per_second ?? null,
              success: true,
            },
          ];
          return next.slice(-ROLLING_WINDOW);
        });
        setStatus("Ready");
      }
    } catch (error) {
      setStatus(`Query failed: ${error.message}`);
    }
  };

  const handleIngest = async () => {
    if (uploadFiles.length === 0) {
      setStatus("Select files to ingest.");
      return;
    }
    setStatus("Uploading...");
    const formData = new FormData();
    Array.from(uploadFiles).forEach((file) => {
      formData.append("files", file);
    });
    try {
      const response = await fetch(`${backendUrl}/ingest`, {
        method: "POST",
        body: formData,
      });
      const data = await response.json();
      setStatus(`Ingested ${data.ingested || 0} files.`);
      try {
        const docsResponse = await fetch(`${backendUrl}/documents`);
        const docsData = await docsResponse.json();
        setDocumentIndex(docsData.items || []);
      } catch (error) {
        setDocumentIndex([]);
      }
    } catch (error) {
      setStatus(`Ingest failed: ${error.message}`);
    }
  };

  const handleDeleteKey = async (key) => {
    setStatus(`Removing ${key}...`);
    try {
      const response = await fetch(`${backendUrl}/delete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ keys: [key] }),
      });
      const data = await response.json();
      if (data.error) {
        setStatus(`Remove failed: ${data.error}`);
        return;
      }
      setDocumentIndex((current) => current.filter((entry) => entry.key !== key));
      setStatus(`Removed ${data.deleted || 0} documents for ${key}.`);
    } catch (error) {
      setStatus(`Remove failed: ${error.message}`);
    }
  };

  const handleDeleteAll = async () => {
    setStatus("Removing all documents...");
    try {
      const response = await fetch(`${backendUrl}/delete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ all: true }),
      });
      const data = await response.json();
      if (data.error) {
        setStatus(`Remove failed: ${data.error}`);
        return;
      }
      setDocumentIndex([]);
      setDocuments([]);
      setStatus("Removed all documents.");
    } catch (error) {
      setStatus(`Remove failed: ${error.message}`);
    }
  };

  const formatDocLabel = (doc) =>
    doc?.meta?.filename || doc?.meta?.url || doc?.meta?.source || "Document";

  const formatKeyLabel = (key) => {
    if (key.startsWith("sitemap:")) {
      return key.replace("sitemap:", "Sitemap: ");
    }
    if (key.startsWith("text:")) {
      return key.replace("text:", "Text ");
    }
    return key;
  };

  const trimSnippet = (text, max = 280) => {
    if (!text) {
      return "";
    }
    if (text.length <= max) {
      return text;
    }
    return `${text.slice(0, max)}…`;
  };

  return (
    <div className="page">
      <div className="rolling-metrics">
        <h3>Rolling metrics (last {ROLLING_WINDOW})</h3>
        <div className="rolling-grid">
          <div>
            <span>TTFT p50</span>
            <strong>{formatMetric(rollingSummary.ttft_p50)}</strong>
          </div>
          <div>
            <span>TTFT p95</span>
            <strong>{formatMetric(rollingSummary.ttft_p95)}</strong>
          </div>
          <div>
            <span>Total p50</span>
            <strong>{formatMetric(rollingSummary.total_p50)}</strong>
          </div>
          <div>
            <span>Total p95</span>
            <strong>{formatMetric(rollingSummary.total_p95)}</strong>
          </div>
          <div>
            <span>Avg tokens/sec</span>
            <strong>
              {rollingSummary.avg_tokens_per_sec !== null
                ? rollingSummary.avg_tokens_per_sec.toFixed(2)
                : "—"}
            </strong>
          </div>
          <div>
            <span>Success / Errors</span>
            <strong>
              {rollingSummary.successes} / {rollingSummary.errors}
            </strong>
          </div>
        </div>
      </div>
      <header className="header">
        <h1>RAG Ray Fabric</h1>
        <p>Haystack + Ray Serve</p>
      </header>

      <section className="panel">
        <label className="label">
          Backend URL
          <input
            className="input"
            value={backendUrl}
            onChange={(event) => setBackendUrl(event.target.value)}
          />
        </label>
        <label className="label">
          <span>Streaming responses</span>
          <input
            type="checkbox"
            checked={useStreaming}
            onChange={(event) => setUseStreaming(event.target.checked)}
          />
        </label>
        <div className="meta">
          <span>Session: {sessionId || "new"}</span>
          <span>Provider: {stats?.provider || "unknown"}</span>
          {timings && (
            <span>
              Latency: {timings.total_ms} ms (retrieval {timings.retrieval_ms} ms, generation{" "}
              {timings.generation_ms} ms)
            </span>
          )}
          {ttftMs !== null && <span>TTFT: {ttftMs} ms</span>}
          {tokensPerSecond !== null && <span>Tokens/sec: {tokensPerSecond}</span>}
        </div>
      </section>

      <section className="panel">
        <h2>Upload PDFs or text</h2>
        <input
          type="file"
          accept=".pdf,.txt"
          multiple
          onChange={(event) => setUploadFiles(event.target.files)}
        />
        <button type="button" className="button" onClick={handleIngest}>
          Ingest
        </button>
        <div className="upload-list">
          <p>Uploaded files (after ingest):</p>
          {documentIndex.length === 0 && (
            <p className="muted">No files ingested in this session yet.</p>
          )}
          {documentIndex.map((entry) => (
            <div key={entry.key} className="upload-item">
              <span>
                {formatKeyLabel(entry.key)}
                <span className="upload-count">({entry.count})</span>
              </span>
              <button
                type="button"
                className="button"
                onClick={() => handleDeleteKey(entry.key)}
              >
                Remove
              </button>
            </div>
          ))}
          {documentIndex.length > 0 && (
            <button type="button" className="button" onClick={handleDeleteAll}>
              Remove all documents
            </button>
          )}
        </div>
      </section>

      <section className="panel">
        <h2>Chat</h2>
        <div className="chat">
          {messages.map((message, index) => (
            <div key={index} className={`bubble ${message.role}`}>
              <div>
                <strong>{message.role === "user" ? "You" : "Assistant"}:</strong>
                <span>{message.content}</span>
                {message.role === "assistant" && message.metrics && (
                  <div className="metrics-panel">
                    <span>TTFT: {formatMetric(message.metrics.ttft_ms)}</span>
                    <span>Total: {formatMetric(message.metrics.total_ms)}</span>
                    <span>
                      Tokens/sec:{" "}
                      {message.metrics.tokens_per_sec !== null &&
                      message.metrics.tokens_per_sec !== undefined
                        ? message.metrics.tokens_per_sec.toFixed(2)
                        : "—"}
                    </span>
                    <span>K: {message.metrics.k ?? "—"}</span>
                    <span>Model: {message.metrics.model_id || "unknown"}</span>
                    <span>Replica: {message.metrics.replica_id || "unknown"}</span>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
        <form onSubmit={handleQuery} className="chat-form">
          <input
            className="input"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Ask a question..."
          />
          <button type="submit" className="button" disabled={!canSubmit}>
            Send
          </button>
        </form>
        <div className="status">{status}</div>
      </section>

      <section className="panel">
        <h2>Top sources</h2>
        <div className="docs-list">
          {documents.length === 0 && <p>No documents returned yet.</p>}
          {documents.map((doc, index) => (
            <div key={index} className="doc">
              <div className="doc-header">
                <div>
                  <strong>{formatDocLabel(doc)}</strong>
                  <span className="doc-source">
                    {doc.meta?.source ? ` · ${doc.meta.source}` : ""}
                  </span>
                </div>
                <span className="doc-score">
                  Score: {doc.score?.toFixed?.(3) ?? doc.score}
                </span>
              </div>
              <p className="doc-snippet">{trimSnippet(doc.content)}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="panel">
        <h2>Performance snapshot</h2>
        <p className="metric-help">
          This panel uses in-memory stats from <code>/stats</code>. Avg and P95 are in ms.
        </p>
        <div className="metric-legend">
          <span>ingest: embed + store documents</span>
          <span>retrieval: fetch relevant docs</span>
          <span>generation: model response time</span>
          <span>ttft: time to first token</span>
        </div>
        {!stats && <p>Loading metrics...</p>}
        {stats?.error && <p className="error">{stats.error}</p>}
        {stats?.timings && (
          <div className="metrics-grid">
            {Object.entries(stats.timings).map(([key, value]) => (
              <div key={key} className="metric-card">
                <strong>{key}</strong>
                <div>Avg: {value.avg_ms} ms</div>
                <div>P95: {value.p95_ms} ms</div>
                <div>Count: {value.count}</div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
