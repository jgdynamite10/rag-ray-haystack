import json
from dataclasses import dataclass
from typing import AsyncIterator

import httpx


@dataclass
class StreamUsage:
    """Usage info returned at the end of streaming."""
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


class VllmStreamingGenerator:
    def __init__(
        self,
        base_url: str,
        model: str,
        max_tokens: int,
        temperature: float,
        top_p: float,
        timeout_seconds: int,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.top_p = top_p
        self.timeout = httpx.Timeout(timeout_seconds)

    async def stream_chat(
        self, prompt: str, max_tokens: int | None = None
    ) -> AsyncIterator[str | StreamUsage]:
        """Stream chat completions, yielding text deltas and usage info.
        
        Yields:
            str: Text delta tokens
            StreamUsage: Final usage info (prompt_tokens, completion_tokens, total_tokens)
        """
        payload = {
            "model": self.model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens if max_tokens is not None else self.max_tokens,
            "temperature": self.temperature,
            "top_p": self.top_p,
            "stream": True,
            "stream_options": {"include_usage": True},
        }

        usage_info: StreamUsage | None = None

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/v1/chat/completions",
                json=payload,
                headers={"Content-Type": "application/json"},
            ) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    data = line.replace("data:", "", 1).strip()
                    if data == "[DONE]":
                        break
                    chunk = json.loads(data)
                    
                    # Check for usage info (sent in final chunk)
                    usage = chunk.get("usage")
                    if usage:
                        usage_info = StreamUsage(
                            prompt_tokens=usage.get("prompt_tokens", 0),
                            completion_tokens=usage.get("completion_tokens", 0),
                            total_tokens=usage.get("total_tokens", 0),
                        )
                    
                    delta = (
                        chunk.get("choices", [{}])[0]
                        .get("delta", {})
                        .get("content", "")
                    )
                    if delta:
                        yield delta
        
        # Yield usage info at the end if available
        if usage_info:
            yield usage_info

    async def complete_chat(
        self, prompt: str, max_tokens: int | None = None
    ) -> str:
        payload = {
            "model": self.model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens if max_tokens is not None else self.max_tokens,
            "temperature": self.temperature,
            "top_p": self.top_p,
            "stream": False,
        }

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/v1/chat/completions",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            response.raise_for_status()
            payload = response.json()
            return (
                payload.get("choices", [{}])[0]
                .get("message", {})
                .get("content", "")
            )
