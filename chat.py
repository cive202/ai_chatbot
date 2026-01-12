import requests
import json

VLLM_API_URL = "http://localhost:8000/v1/chat/completions"
MODEL_NAME = "meta-llama/Meta-Llama-3-8B-Instruct"

SYSTEM_PROMPT = """You are a helpful AI assistant for Khalti.

Your goal is to answer the user's question using the provided CONTEXT.

Rules:
1. Use Context: Base your answer on the information provided below.
2. Reasoning: You may synthesize and infer benefits when reasonable.
3. Honesty: If the context has no relevant info, say so clearly.
4. Tone: Be helpful, professional, and concise.
"""

class ChatEngine:
    def __init__(self, vector_store, embedding_model):
        self.vector_store = vector_store
        self.embedding_model = embedding_model

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
                "content": f"Context:\n{context}\n\nQuestion:\n{question}"
            }
        ]

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
            res = requests.post(
                VLLM_API_URL,
                headers={"Content-Type": "application/json"},
                json={
                    "model": MODEL_NAME,
                    "messages": messages,
                    "temperature": 0.3,
                    "top_p": 0.9,
                    "max_tokens": 512
                },
                timeout=120
            )

            res.raise_for_status()
            response_text = res.json()["choices"][0]["message"]["content"]

            sources = self._get_sources(results)
            if sources:
                response_text += "\n\n**Sources:**\n" + "\n".join(f"- {s}" for s in sources)

            return response_text

        except Exception as e:
            return f"Error communicating with vLLM: {str(e)}"

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

        payload = {
            "model": MODEL_NAME,
            "messages": messages,
            "temperature": 0.3,
            "top_p": 0.9,
            "max_tokens": 512,
            "stream": True
        }

        try:
            with requests.post(
                VLLM_API_URL,
                headers={"Content-Type": "application/json"},
                data=json.dumps(payload),
                stream=True,
                timeout=120
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

                sources = self._get_sources(results)
                if sources:
                    yield "\n\n**Sources:**\n" + "\n".join(f"- {s}" for s in sources)

        except Exception as e:
            yield f"\nError communicating with vLLM: {str(e)}"
