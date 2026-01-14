FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir uv==0.4.18

COPY pyproject.toml /app/pyproject.toml
COPY README.md /app/README.md

RUN uv pip install --system .

COPY app /app/app

EXPOSE 8000

CMD ["serve", "run", "app.main:deployment"]
