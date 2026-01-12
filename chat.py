import json
import logging
import os
from typing import Generator, Optional

import requests

# Default API endpoints and models (overridable via environment variables)
DEFAULT_VLLM_API_URL = os.environ.get("VLLM_API_URL", "http://localhost:8000/v1/chat/completions")
DEFAULT_VLLM_MODEL = os.environ.get("VLLM_MODEL", "meta-llama/Meta-Llama-3-8B-Instruct")

DEFAULT_OLLAMA_API_URL = os.environ.get("OLLAMA_API_URL", "http://localhost:11434")
DEFAULT_OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3:8b-instruct-q4_K_M")

DEFAULT_LLM_PROVIDER = os.environ.get("LLM_PROVIDER", "ollama").lower()

SYSTEM_PROMPT = """You are a helpful AI assistant.

Your goal is to answer the user's question using the provided CONTEXT.

Rules:
1. Use Context: Base your answer on the information provided below.
2. Reasoning: You may synthesize and infer benefits when reasonable.
3. Honesty: If the context has no relevant info, say so clearly.
4. Tone: Be helpful, professional, and concise.
"""

LOGGER = logging.getLogger(__name__)


class ChatEngine:
    def __init__(
        self,
        vector_store,
        embedding_model,
        llm_provider: Optional[str] = None,
        ollama_api_url: Optional[str] = None,
        ollama_model: Optional[str] = None,
        vllm_api_url: Optional[str] = None,
        vllm_model: Optional[str] = None,
    ):
        self.vector_store = vector_store
        self.embedding_model = embedding_model

        self.llm_provider = (llm_provider or DEFAULT_LLM_PROVIDER).lower()
        self.ollama_api_url = ollama_api_url or DEFAULT_OLLAMA_API_URL
        self.ollama_model = self._validate_ollama_model(ollama_model or DEFAULT_OLLAMA_MODEL)
        self.vllm_api_url = vllm_api_url or DEFAULT_VLLM_API_URL
        self.vllm_model = vllm_model or DEFAULT_VLLM_MODEL

        if self.llm_provider not in ["ollama", "vllm"]:
            raise ValueError(f"Unsupported LLM_PROVIDER '{self.llm_provider}'. Use 'ollama' or 'vllm'.")

        LOGGER.info(
            "ChatEngine initialized with provider=%s, ollama_model=%s, vllm_model=%s",
            self.llm_provider,
            self.ollama_model,
            self.vllm_model,
        )

    def _validate_ollama_model(self, model_name: str) -> str:
        """Block unquantized llama3:latest and enforce quantized suffix."""
        if not model_name:
            raise ValueError("OLLAMA_MODEL is required for Ollama provider.")

        disallowed = ["llama3:latest", "llama3", "llama-3", "llama-3:latest"]
        if model_name.lower() in disallowed:
            raise ValueError(
                "OLLAMA_MODEL cannot be 'llama3:latest' (unquantized). "
                "Use a quantized model, e.g., 'llama3:8b-instruct-q4_K_M'."
            )

        allowed_tags = ("q4", "q5", "q6", "q8")
        if not any(tag in model_name for tag in allowed_tags):
            raise ValueError(
                f"OLLAMA_MODEL '{model_name}' appears unquantized. "
                "Use a quantized variant like 'llama3:8b-instruct-q4_K_M'."
            )

        return model_name

    def _get_sources(self, results):
        sources = set()
        if results and results.get("metadatas"):
            for meta in results["metadatas"][0]:
                if meta and "source" in meta:
                    sources.add(meta["source"])
        return sorted(sources)

    def _build_messages(self, context, question):
        return [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": f"Context:\n{context}\n\nQuestion:\n{question}",
            },
        ]

    def _build_prompt(self, context: str, question: str) -> str:
        return f"{SYSTEM_PROMPT}\n\nContext:\n{context}\n\nQuestion:\n{question}\n\nAnswer:"

    def _query_vllm(self, messages):
        payload = {
            "model": self.vllm_model,
            "messages": messages,
            "temperature": 0.3,
            "top_p": 0.9,
            "max_tokens": 512,
        }
        res = requests.post(
            self.vllm_api_url,
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=120,
        )
        res.raise_for_status()
        return res.json()["choices"][0]["message"]["content"]

    def _query_ollama(self, prompt: str) -> str:
        payload = {
            "model": self.ollama_model,
            "prompt": prompt,
            "stream": False,
        }
        res = requests.post(
            f"{self.ollama_api_url}/api/generate",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=120,
        )
        res.raise_for_status()
        data = res.json()
        return data.get("response", "")

    def query(self, user_question):
        results = self.vector_store.search(
            user_question, self.embedding_model, n_results=5
        )

        context_text = ""
        if results and results.get("documents"):
            context_text = "\n\n".join(results["documents"][0])

        if not context_text:
            context_text = "No context available."

        messages = self._build_messages(context_text, user_question)

        try:
            if self.llm_provider == "ollama":
                prompt = self._build_prompt(context_text, user_question)
                response_text = self._query_ollama(prompt)
            else:
                response_text = self._query_vllm(messages)

            sources = self._get_sources(results)
            if sources:
                response_text += "\n\n**Sources:**\n" + "\n".join(f"- {s}" for s in sources)

            return response_text

        except Exception as e:
            LOGGER.exception("Error during query with provider=%s", self.llm_provider)
            provider_label = "Ollama" if self.llm_provider == "ollama" else "vLLM"
            return f"Error communicating with {provider_label}: {str(e)}"

    def _stream_vllm(self, messages) -> Generator[str, None, None]:
        payload = {
            "model": self.vllm_model,
            "messages": messages,
            "temperature": 0.3,
            "top_p": 0.9,
            "max_tokens": 512,
            "stream": True,
        }

        with requests.post(
            self.vllm_api_url,
            headers={"Content-Type": "application/json"},
            data=json.dumps(payload),
            stream=True,
            timeout=120,
        ) as r:
            for line in r.iter_lines():
                if not line:
                    continue

                decoded = line.decode("utf-8").replace("data: ", "")
                if decoded == "[DONE]":
                    break

                chunk = json.loads(decoded)
                delta = chunk["choices"][0]["delta"]

                if "content" in delta:
                    yield delta["content"]

    def _stream_ollama(self, prompt: str) -> Generator[str, None, None]:
        payload = {
            "model": self.ollama_model,
            "prompt": prompt,
            "stream": True,
        }

        with requests.post(
            f"{self.ollama_api_url}/api/generate",
            headers={"Content-Type": "application/json"},
            json=payload,
            stream=True,
            timeout=120,
        ) as r:
            for line in r.iter_lines():
                if not line:
                    continue

                decoded = line.decode("utf-8")
                if decoded.startswith("data:"):
                    decoded = decoded.replace("data: ", "")
                try:
                    data = json.loads(decoded)
                except json.JSONDecodeError:
                    LOGGER.warning("Failed to decode SSE chunk: %s", decoded)
                    continue

                if data.get("done"):
                    break

                chunk = data.get("response")
                if chunk:
                    yield chunk

    def query_stream(self, user_question):
        results = self.vector_store.search(
            user_question, self.embedding_model, n_results=5
        )

        context_text = ""
        if results and results.get("documents"):
            context_text = "\n\n".join(results["documents"][0])

        if not context_text:
            context_text = "No context available."

        messages = self._build_messages(context_text, user_question)

        try:
            if self.llm_provider == "ollama":
                prompt = self._build_prompt(context_text, user_question)
                for chunk in self._stream_ollama(prompt):
                    yield chunk
            else:
                for chunk in self._stream_vllm(messages):
                    yield chunk

            sources = self._get_sources(results)
            if sources:
                yield "\n\n**Sources:**\n" + "\n".join(f"- {s}" for s in sources)

        except Exception as e:
            LOGGER.exception("Error during streaming query with provider=%s", self.llm_provider)
            yield f"\nError communicating with {self.llm_provider}: {str(e)}"
