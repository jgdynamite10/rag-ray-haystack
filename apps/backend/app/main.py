import logging
from typing import Any

from fastapi import FastAPI, File, UploadFile
from fastapi.responses import PlainTextResponse
from haystack import Document
from haystack.components.retrievers.in_memory import InMemoryBM25Retriever
from haystack.document_stores.in_memory import InMemoryDocumentStore
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
from pythonjsonlogger import jsonlogger
from ray import serve

api = FastAPI()

REQUEST_COUNTER = Counter(
    "rag_requests_total",
    "Total requests",
    ["endpoint"],
)


def configure_logging() -> None:
    handler = logging.StreamHandler()
    formatter = jsonlogger.JsonFormatter()
    handler.setFormatter(formatter)
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.handlers = [handler]


def build_retriever(document_store: InMemoryDocumentStore) -> InMemoryBM25Retriever:
    return InMemoryBM25Retriever(document_store=document_store)


def load_text_from_pdf(data: bytes) -> str:
    # TODO: replace with proper PDF extraction (pypdf) when enabled.
    return data.decode("utf-8", errors="ignore")


def load_text_from_file(upload: UploadFile) -> str:
    data = upload.file.read()
    if upload.filename and upload.filename.lower().endswith(".pdf"):
        return load_text_from_pdf(data)
    return data.decode("utf-8", errors="ignore")


@serve.deployment(ray_actor_options={"num_cpus": 1})
@serve.ingress(api)
class RagApp:
    def __init__(self) -> None:
        configure_logging()
        self.logger = logging.getLogger("rag-app")
        self.document_store = InMemoryDocumentStore()
        self.retriever = build_retriever(self.document_store)

    @api.get("/healthz")
    async def healthz(self) -> dict[str, str]:
        REQUEST_COUNTER.labels("healthz").inc()
        return {"status": "ok"}

    @api.get("/metrics")
    async def metrics(self) -> PlainTextResponse:
        REQUEST_COUNTER.labels("metrics").inc()
        return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @api.post("/ingest")
    async def ingest(
        self,
        files: list[UploadFile] | None = File(default=None),
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        REQUEST_COUNTER.labels("ingest").inc()
        documents: list[Document] = []

        if files:
            for upload in files:
                content = load_text_from_file(upload)
                documents.append(Document(content=content, meta={"filename": upload.filename}))

        if payload and "documents" in payload:
            for item in payload["documents"]:
                documents.append(Document(content=item.get("content", ""), meta=item.get("meta", {})))

        if not documents:
            return {"ingested": 0}

        self.document_store.write_documents(documents)
        self.logger.info("ingested_documents", extra={"count": len(documents)})
        return {"ingested": len(documents)}

    @api.post("/query")
    async def query(self, payload: dict[str, Any]) -> dict[str, Any]:
        REQUEST_COUNTER.labels("query").inc()
        query = payload.get("query", "")
        if not query:
            return {"answers": [], "documents": []}

        result = self.retriever.run(query=query)
        documents = result.get("documents", [])
        self.logger.info(
            "query",
            extra={"query": query, "documents": len(documents)},
        )
        return {
            "answers": [
                {
                    "answer": "Top documents returned. Add a generator to synthesize answers.",
                }
            ],
            "documents": [
                {
                    "content": doc.content,
                    "meta": doc.meta,
                    "score": doc.score,
                }
                for doc in documents
            ],
        }


deployment = RagApp.bind()
