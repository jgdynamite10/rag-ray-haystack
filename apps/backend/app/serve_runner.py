import os
import signal

import ray
from ray import serve

from app.main import deployment


def _parse_int(name: str) -> int | None:
    value = os.getenv(name)
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def main() -> None:
    object_store_memory = _parse_int("RAY_OBJECT_STORE_MEMORY")
    ray_kwargs: dict[str, int] = {}
    if object_store_memory:
        ray_kwargs["object_store_memory"] = object_store_memory

    ray.init(**ray_kwargs)

    port = _parse_int("PORT") or 8000
    serve.start(http_options={"host": "0.0.0.0", "port": port})
    serve.run(deployment)
    # Keep the process alive for Kubernetes.
    signal.pause()


if __name__ == "__main__":
    main()
