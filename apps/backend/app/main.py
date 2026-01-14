import io
import logging
import os
import time
from collections import defaultdict, deque
from typing import Any
from uuid import uuid4

import requests
from bs4 import BeautifulSoup
from pypdf import PdfReader
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse, Response
from haystack import Document
from haystack.components.embedders import (
    SentenceTransformersDocumentEmbedder,
    SentenceTransformersTextEmbedder,
)
from haystack.components.generators import HuggingFaceLocalGenerator
from haystack.components.retrievers.in_memory import (
    InMemoryBM25Retriever,
    InMemoryEmbeddingRetriever,
)
from haystack.document_stores.in_memory import InMemoryDocumentStore
from haystack_integrations.document_stores.qdrant import QdrantDocumentStore
from haystack_integrations.components.retrievers.qdrant import QdrantEmbeddingRetriever
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pythonjsonlogger import jsonlogger
from ray import serve


def configure_logging() -> None:
    handler = logging.StreamHandler()
    formatter = jsonlogger.JsonFormatter()
    handler.setFormatter(formatter)
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.handlers = [handler]


def env_flag(name: str, default: str = "false") -> bool:
    return os.getenv(name, default).lower() in {"1", "true", "yes", "on"}


def chunk_text(text: str, chunk_size: int = 800, overlap: int = 120) -> list[str]:
    if len(text) <= chunk_size:
        return [text]
    chunks = []
    start = 0
    while start < len(text):
        end = min(len(text), start + chunk_size)
        chunks.append(text[start:end])
        if end == len(text):
            break
        start = max(end - overlap, 0)
    return chunks


def extract_text_from_pdf(data: bytes) -> str:
    try:
        reader = PdfReader(io.BytesIO(data))
        pages = []
        for page in reader.pages:
            pages.append(page.extract_text() or "")
        return "\n".join(pages)
    except Exception:  # noqa: BLE001
        return data.decode("utf-8", errors="ignore")


def load_text_from_upload(upload: Any) -> str:
    data = upload.file.read()
    if upload.filename and upload.filename.lower().endswith(".pdf"):
        return extract_text_from_pdf(data)
    return data.decode("utf-8", errors="ignore")


def load_text_from_url(url: str, timeout: int = 10) -> str:
    response = requests.get(url, timeout=timeout)
    response.raise_for_status()
    content_type = response.headers.get("content-type", "")
    if "text/html" in content_type:
        soup = BeautifulSoup(response.text, "html.parser")
        return soup.get_text(separator=" ", strip=True)
    return response.text


class TimingTracker:
    def __init__(self, maxlen: int = 200) -> None:
        self.samples: dict[str, deque[float]] = defaultdict(lambda: deque(maxlen=maxlen))

    def record(self, name: str, value: float) -> None:
        self.samples[name].append(value)

    def summarize(self) -> dict[str, dict[str, float]]:
        summary: dict[str, dict[str, float]] = {}
        for key, values in self.samples.items():
            if not values:
                continue
            ordered = sorted(values)
            avg = sum(values) / len(values)
            p95 = ordered[int(len(ordered) * 0.95) - 1] if len(ordered) > 1 else ordered[0]
            summary[key] = {
                "avg_ms": round(avg * 1000, 2),
                "p95_ms": round(p95 * 1000, 2),
                "count": len(values),
            }
        return summary


@serve.deployment(ray_actor_options={"num_cpus": 1})
class RagApp:
    def __init__(self) -> None:
        configure_logging()
        self.logger = logging.getLogger("rag-app")
        self.request_counter = Counter(
            "rag_requests_total",
            "Total requests",
            ["endpoint"],
        )
        self.error_counter = Counter(
            "rag_errors_total",
            "Total errors",
            ["endpoint"],
        )
        self.latency_histogram = Histogram(
            "rag_latency_seconds",
            "Latency in seconds",
            ["stage"],
        )
        self.timings = TimingTracker()
        self.use_embeddings = env_flag("RAG_USE_EMBEDDINGS", "true")
        self.qdrant_url = os.getenv("QDRANT_URL", "")
        self.qdrant_collection = os.getenv("QDRANT_COLLECTION", "rag-documents")
        self.embedding_model = os.getenv(
            "EMBEDDING_MODEL_ID",
            "sentence-transformers/all-MiniLM-L6-v2",
        )
        self.generator_model = os.getenv(
            "GENERATOR_MODEL_ID",
            "sshleifer/tiny-gpt2",
        )
        self.generator_enabled = env_flag("GENERATOR_ENABLED", "true")
        self.max_history = int(os.getenv("RAG_MAX_HISTORY", "6"))
        self.top_k = int(os.getenv("RAG_TOP_K", "4"))
        self.sessions: dict[str, list[dict[str, str]]] = {}

        self.document_store = self._build_document_store()
        if self.qdrant_url:
            self.use_embeddings = True
        self.retriever = self._build_retriever()
        self.document_embedder = self._build_document_embedder()
        self.query_embedder = self._build_query_embedder()
        self.generator = self._build_generator()

    def _build_document_store(self) -> Any:
        if self.qdrant_url:
            return QdrantDocumentStore(
                url=self.qdrant_url,
                index=self.qdrant_collection,
            )
        return InMemoryDocumentStore()

    def _build_retriever(self) -> Any:
        if self.use_embeddings:
            if self.qdrant_url:
                return QdrantEmbeddingRetriever(document_store=self.document_store)
            return InMemoryEmbeddingRetriever(document_store=self.document_store)
        if isinstance(self.document_store, InMemoryDocumentStore):
            return InMemoryBM25Retriever(document_store=self.document_store)
        raise ValueError("BM25 retriever is only supported with in-memory store.")

    def _build_document_embedder(self) -> Any | None:
        if not self.use_embeddings:
            return None
        return SentenceTransformersDocumentEmbedder(model=self.embedding_model)

    def _build_query_embedder(self) -> Any | None:
        if not self.use_embeddings:
            return None
        return SentenceTransformersTextEmbedder(model=self.embedding_model)

    def _build_generator(self) -> Any | None:
        if not self.generator_enabled:
            self.logger.info("generator_disabled")
            return None
        return HuggingFaceLocalGenerator(
            model=self.generator_model,
            generation_kwargs={
                "max_new_tokens": int(os.getenv("GENERATOR_MAX_NEW_TOKENS", "256")),
                "temperature": float(os.getenv("GENERATOR_TEMPERATURE", "0.2")),
            },
        )

    def _get_session_history(self, session_id: str | None) -> tuple[str, list[dict[str, str]]]:
        if not session_id:
            session_id = str(uuid4())
        history = self.sessions.get(session_id, [])
        return session_id, history

    def _update_session(self, session_id: str, role: str, content: str) -> None:
        history = self.sessions.setdefault(session_id, [])
        history.append({"role": role, "content": content})
        if len(history) > self.max_history:
            self.sessions[session_id] = history[-self.max_history :]

    async def healthz(self) -> dict[str, str]:
        self.request_counter.labels("healthz").inc()
        return {"status": "ok"}

    async def metrics(self) -> PlainTextResponse:
        self.request_counter.labels("metrics").inc()
        return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    async def stats(self) -> dict[str, Any]:
        self.request_counter.labels("stats").inc()
        return {
            "sessions": len(self.sessions),
            "timings": self.timings.summarize(),
        }

    async def ingest(
        self,
        files: list[Any] | None,
        payload: dict[str, Any] | None,
    ) -> dict[str, Any]:
        self.request_counter.labels("ingest").inc()
        payload = payload or {}
        documents: list[Document] = []
        errors: list[str] = []

        start_time = time.perf_counter()

        if files:
            for upload in files:
                try:
                    content = load_text_from_upload(upload)
                    for chunk in chunk_text(content):
                        documents.append(
                            Document(content=chunk, meta={"filename": upload.filename})
                        )
                except Exception as exc:  # noqa: BLE001
                    errors.append(str(exc))

        for item in payload.get("documents", []):
            documents.append(
                Document(content=item.get("content", ""), meta=item.get("meta", {}))
            )

        for text in payload.get("texts", []):
            for chunk in chunk_text(text):
                documents.append(Document(content=chunk, meta={"source": "text"}))

        for url in payload.get("urls", []):
            try:
                content = load_text_from_url(url)
                for chunk in chunk_text(content):
                    documents.append(
                        Document(content=chunk, meta={"source": "url", "url": url})
                    )
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{url}: {exc}")

        if not documents:
            return {"ingested": 0, "errors": errors}

        if self.use_embeddings and self.document_embedder:
            documents = self.document_embedder.run(documents=documents)["documents"]

        self.document_store.write_documents(documents)
        duration = time.perf_counter() - start_time
        self.latency_histogram.labels("ingest").observe(duration)
        self.timings.record("ingest", duration)
        self.logger.info(
            "ingested_documents",
            extra={"count": len(documents), "errors": len(errors)},
        )
        return {"ingested": len(documents), "errors": errors}

    async def query(self, payload: dict[str, Any]) -> dict[str, Any]:
        self.request_counter.labels("query").inc()
        query = payload.get("query", "")
        if not query:
            return {"answers": [], "documents": []}

        session_id, history = self._get_session_history(payload.get("session_id"))
        if payload.get("history"):
            history = payload["history"]

        self._update_session(session_id, "user", query)

        retrieval_start = time.perf_counter()
        if self.use_embeddings and self.query_embedder:
            embedding = self.query_embedder.run(text=query)["embedding"]
            result = self.retriever.run(query_embedding=embedding, top_k=self.top_k)
        else:
            result = self.retriever.run(query=query, top_k=self.top_k)
        documents = result.get("documents", [])
        retrieval_time = time.perf_counter() - retrieval_start

        prompt_context = "\n\n".join(
            f"[{index + 1}] {doc.content}" for index, doc in enumerate(documents)
        )
        history_text = "\n".join(
            f"{message['role']}: {message['content']}" for message in history[-self.max_history :]
        )
        prompt = (
            "You are a helpful RAG assistant. Use the context to answer.\n\n"
            f"Context:\n{prompt_context}\n\n"
            f"Conversation:\n{history_text}\n\n"
            f"Question: {query}\nAnswer:"
        )

        generation_start = time.perf_counter()
        answer = "Generator disabled."
        if self.generator:
            try:
                reply = self.generator.run(prompt=prompt)
                replies = reply.get("replies") or reply.get("results") or []
                answer = replies[0] if replies else "No response."
            except Exception as exc:  # noqa: BLE001
                self.error_counter.labels("query").inc()
                answer = f"Generation failed: {exc}"
        generation_time = time.perf_counter() - generation_start

        self._update_session(session_id, "assistant", answer)
        self.timings.record("retrieval", retrieval_time)
        self.timings.record("generation", generation_time)
        self.latency_histogram.labels("retrieval").observe(retrieval_time)
        self.latency_histogram.labels("generation").observe(generation_time)

        total_time = retrieval_time + generation_time
        self.latency_histogram.labels("total").observe(total_time)

        self.logger.info(
            "query",
            extra={
                "query": query,
                "documents": len(documents),
                "session_id": session_id,
                "retrieval_ms": round(retrieval_time * 1000, 2),
                "generation_ms": round(generation_time * 1000, 2),
            },
        )
        return {
            "session_id": session_id,
            "answers": [{"answer": answer}],
            "documents": [
                {
                    "content": doc.content,
                    "meta": doc.meta,
                    "score": doc.score,
                }
                for doc in documents
            ],
            "timings": {
                "retrieval_ms": round(retrieval_time * 1000, 2),
                "generation_ms": round(generation_time * 1000, 2),
                "total_ms": round(total_time * 1000, 2),
            },
            "history": self.sessions.get(session_id, []),
        }

    async def __call__(self, request: Request) -> Response:
        path = request.url.path
        method = request.method.upper()

        if path == "/healthz" and method == "GET":
            return JSONResponse(await self.healthz())

        if path == "/metrics" and method == "GET":
            return await self.metrics()

        if path == "/stats" and method == "GET":
            return JSONResponse(await self.stats())

        if path == "/ingest" and method == "POST":
            content_type = request.headers.get("content-type", "")
            files = None
            payload = None
            if "multipart/form-data" in content_type:
                form = await request.form()
                files = form.getlist("files")
            else:
                try:
                    payload = await request.json()
                except ValueError:
                    payload = None
            return JSONResponse(await self.ingest(files=files, payload=payload))

        if path == "/query" and method == "POST":
            payload = await request.json()
            return JSONResponse(await self.query(payload))

        return JSONResponse({"error": "not_found"}, status_code=404)


deployment = RagApp.bind()
