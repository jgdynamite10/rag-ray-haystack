import { useEffect, useMemo, useState } from "react";

const defaultBackend = import.meta.env.VITE_BACKEND_URL || `${window.location.origin}/api`;

export default function App() {
  const [backendUrl, setBackendUrl] = useState(defaultBackend);
  const [query, setQuery] = useState("");
  const [messages, setMessages] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [uploadFiles, setUploadFiles] = useState([]);
  const [uploadedFileNames, setUploadedFileNames] = useState([]);
  const [status, setStatus] = useState("");
  const [sessionId, setSessionId] = useState("");
  const [timings, setTimings] = useState(null);
  const [stats, setStats] = useState(null);
  const [useStreaming, setUseStreaming] = useState(true);
  const [ttftMs, setTtftMs] = useState(null);
  const [tokensPerSecond, setTokensPerSecond] = useState(null);

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
    fetchStats();
    const interval = setInterval(fetchStats, 5000);
    return () => {
      active = false;
      clearInterval(interval);
    };
  }, [backendUrl]);

  const canSubmit = useMemo(() => query.trim().length > 0, [query]);

  const handleQuery = async (event) => {
    event.preventDefault();
    if (!canSubmit) {
      return;
    }
    setStatus(useStreaming ? "Streaming..." : "Querying...");
    const nextMessages = [...messages, { role: "user", content: query }];
    setTtftMs(null);
    setTokensPerSecond(null);
    setQuery("");

    try {
      if (useStreaming) {
        const assistantIndex = nextMessages.length;
        setMessages([...nextMessages, { role: "assistant", content: "" }]);

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
              setMessages((current) => {
                const updated = [...current];
                const existing = updated[assistantIndex]?.content || "";
                updated[assistantIndex] = {
                  role: "assistant",
                  content: `${existing}${payload.text}`,
                };
                return updated;
              });
            }
            if (eventType === "meta") {
              setDocuments(payload.documents || []);
              if (payload.session_id) {
                setSessionId(payload.session_id);
              }
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
              setDocuments(payload.documents || []);
              setTimings(payload.timings || null);
              if (payload.session_id) {
                setSessionId(payload.session_id);
              }
              if (payload.timings?.tokens_per_second) {
                setTokensPerSecond(payload.timings.tokens_per_second);
              }
              if (payload.timings?.ttft_ms) {
                setTtftMs(payload.timings.ttft_ms);
              }
              setStatus("Ready");
            }
            if (eventType === "error") {
              setStatus(payload.message || "Streaming error.");
            }
          }
        }
      } else {
        setMessages(nextMessages);
        const response = await fetch(`${backendUrl}/query`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query, session_id: sessionId || undefined }),
        });
        const data = await response.json();
        setDocuments(data.documents || []);
        setTimings(data.timings || null);
        setTokensPerSecond(data.timings?.tokens_per_second ?? null);
        setTtftMs(data.timings?.ttft_ms ?? null);
        if (data.session_id) {
          setSessionId(data.session_id);
        }
        setMessages((current) => [
          ...current,
          { role: "assistant", content: data.answers?.[0]?.answer || "No answer." },
        ]);
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
      const names = Array.from(uploadFiles).map((file) => file.name);
      setUploadedFileNames((current) => Array.from(new Set([...current, ...names])));
      setStatus(`Ingested ${data.ingested || 0} files.`);
    } catch (error) {
      setStatus(`Ingest failed: ${error.message}`);
    }
  };

  const handleDeleteFile = async (filename) => {
    setStatus(`Removing ${filename}...`);
    try {
      const response = await fetch(`${backendUrl}/delete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filenames: [filename] }),
      });
      const data = await response.json();
      if (data.error) {
        setStatus(`Remove failed: ${data.error}`);
        return;
      }
      setUploadedFileNames((current) => current.filter((name) => name !== filename));
      setStatus(`Removed ${data.deleted || 0} documents for ${filename}.`);
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
      setUploadedFileNames([]);
      setDocuments([]);
      setStatus("Removed all documents.");
    } catch (error) {
      setStatus(`Remove failed: ${error.message}`);
    }
  };

  return (
    <div className="page">
      <header className="header">
        <h1>RAG Ray Chat</h1>
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
        {uploadedFileNames.length > 0 && (
          <div className="upload-list">
            <p>Uploaded files:</p>
            {uploadedFileNames.map((name) => (
              <div key={name} className="upload-item">
                <span>{name}</span>
                <button
                  type="button"
                  className="button"
                  onClick={() => handleDeleteFile(name)}
                >
                  Remove
                </button>
              </div>
            ))}
            <button type="button" className="button" onClick={handleDeleteAll}>
              Remove all documents
            </button>
          </div>
        )}
      </section>

      <section className="panel">
        <h2>Chat</h2>
        <div className="chat">
          {messages.map((message, index) => (
            <div key={index} className={`bubble ${message.role}`}>
              <strong>{message.role === "user" ? "You" : "Assistant"}:</strong>
              <span>{message.content}</span>
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
        <h2>Top documents</h2>
        <div className="docs">
          {documents.length === 0 && <p>No documents returned yet.</p>}
          {documents.map((doc, index) => (
            <div key={index} className="doc">
              <div className="doc-meta">
                <span>{doc.meta?.filename || "Document"}</span>
                <span>Score: {doc.score?.toFixed?.(3) ?? doc.score}</span>
              </div>
              <pre>{doc.content}</pre>
            </div>
          ))}
        </div>
      </section>

      <section className="panel">
        <h2>Performance snapshot</h2>
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
