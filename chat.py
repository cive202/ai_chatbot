import ollama
import json

SYSTEM_PROMPT = """You are a helpful AI assistant for Khalti.

Your goal is to answer the user's question using the provided CONTEXT.

Rules:
1.  **Use Context**: Base your answer on the information provided below.
2.  **Reasoning**: You ARE allowed to synthesize and infer benefits. For example, if the context lists "instant cashback" and "easy payments", and the user asks "Why is it better?", you can explain that it offers instant rewards and convenience.
3.  **Honesty**: If the context contains NO relevant information, admit it politely, but do not make up facts.
4.  **Tone**: Be helpful, professional, and concise.

Context:
{context}

Question:
{question}
"""

class ChatEngine:
    def __init__(self, vector_store, embedding_model, llm_model="llama3:latest"):
        self.vector_store = vector_store
        self.embedding_model = embedding_model
        self.llm_model = llm_model
        
        # Load examples
        try:
            with open("example.txt", "r", encoding="utf-8") as f:
                self.examples = f.read()
        except FileNotFoundError:
            self.examples = ""

    def _get_sources(self, results):
        sources = set()
        if results and results.get('metadatas'):
            # results['metadatas'] is a list of lists
            for meta in results['metadatas'][0]:
                if meta and 'source' in meta:
                    sources.add(meta['source'])
        return sorted(list(sources))

    def query_stream(self, user_question):
        # Retrieve relevant chunks
        results = self.vector_store.search(user_question, self.embedding_model, n_results=5)
        
        # Format context
        context_text = ""
        if results and results['documents']:
            documents = results['documents'][0]
            context_text = "\n\n".join(documents)
        
        if not context_text:
            context_text = "No context available."

        # Construct prompt
        full_prompt = SYSTEM_PROMPT.format(
            # examples=self.examples, # Removed from prompt
            context=context_text,
            question=user_question
        )

        # Call Ollama with stream=True
        try:
            stream = ollama.chat(model=self.llm_model, messages=[
                {'role': 'user', 'content': full_prompt},
            ], stream=True, options={
                'temperature': 0.3,
                'top_p': 0.9,
                'repeat_penalty': 1.1,
                'num_ctx': 4096
            })
            
            for chunk in stream:
                yield chunk['message']['content']
            
            # Append sources
            sources = self._get_sources(results)
            if sources:
                yield "\n\n**Sources:**\n" + "\n".join([f"- {s}" for s in sources])
                
        except Exception as e:
            yield f"Error communicating with Ollama: {str(e)}"

    def query(self, user_question):
        # Retrieve relevant chunks
        results = self.vector_store.search(user_question, self.embedding_model, n_results=5)
        
        # Format context
        context_text = ""
        if results and results['documents']:
            # Flatten list of lists if necessary (chromadb query returns list of lists)
            documents = results['documents'][0]
            context_text = "\n\n".join(documents)
        
        if not context_text:
            context_text = "No context available."

        # Construct prompt
        full_prompt = SYSTEM_PROMPT.format(
            # examples=self.examples, # Removed from prompt
            context=context_text,
            question=user_question
        )

        # Call Ollama
        try:
            response = ollama.chat(model=self.llm_model, messages=[
                {'role': 'user', 'content': full_prompt},
            ], options={
                'temperature': 0.3,
                'top_p': 0.9,
                'repeat_penalty': 1.1,
                'num_ctx': 4096
            })
            
            response_text = response['message']['content']
            
            # Append sources
            sources = self._get_sources(results)
            if sources:
                response_text += "\n\n**Sources:**\n" + "\n".join([f"- {s}" for s in sources])
            return response_text
        except Exception as e:
            return f"Error communicating with Ollama: {str(e)}"
