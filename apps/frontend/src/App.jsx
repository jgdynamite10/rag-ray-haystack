import { useMemo, useState } from "react";

const defaultBackend = import.meta.env.VITE_BACKEND_URL || "http://rag-app-backend:8000";

export default function App() {
  const [backendUrl, setBackendUrl] = useState(defaultBackend);
  const [query, setQuery] = useState("");
  const [messages, setMessages] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [uploadFiles, setUploadFiles] = useState([]);
  const [status, setStatus] = useState("");

  const canSubmit = useMemo(() => query.trim().length > 0, [query]);

  const handleQuery = async (event) => {
    event.preventDefault();
    if (!canSubmit) {
      return;
    }
    setStatus("Querying...");
    const nextMessages = [...messages, { role: "user", content: query }];
    setMessages(nextMessages);
    setQuery("");

    try {
      const response = await fetch(`${backendUrl}/query`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query }),
      });
      const data = await response.json();
      setDocuments(data.documents || []);
      setMessages((current) => [
        ...current,
        { role: "assistant", content: (data.answers?.[0]?.answer || "No answer.") },
      ]);
      setStatus("Ready");
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
    } catch (error) {
      setStatus(`Ingest failed: ${error.message}`);
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
    </div>
  );
}
