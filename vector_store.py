import chromadb
from chromadb.config import Settings
import os

class VectorStore:
    def __init__(self, path="chroma_db"):
        self.client = chromadb.PersistentClient(path=path)
        self.collection = self.client.get_or_create_collection("chatbot_knowledge")

    def add_documents(self, documents, embedding_model):
        if not documents:
            return
            
        ids = [doc.get('id', str(i)) for i, doc in enumerate(documents)]
        texts = [doc.get('text', '') for doc in documents]
        metadatas = [doc.get('metadata', {'source': 'unknown'}) for doc in documents]
        embeddings = [embedding_model.embed(text) for text in texts]
        
        self.collection.add(
            ids=ids,
            documents=texts,
            metadatas=metadatas,
            embeddings=embeddings
        )

    def search(self, query, embedding_model, n_results=3):
        query_embedding = embedding_model.embed(query)
        results = self.collection.query(
            query_embeddings=[query_embedding],
            n_results=n_results
        )
        return results
