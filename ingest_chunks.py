import json
from vector_store import VectorStore
from embeddings import EmbeddingModel

def ingest_existing_chunks(chunks_file="chunks.json"):
    print(f"Loading chunks from {chunks_file}...")
    try:
        with open(chunks_file, "r", encoding="utf-8") as f:
            chunks = json.load(f)
    except FileNotFoundError:
        print(f"{chunks_file} not found.")
        return

    print(f"Found {len(chunks)} chunks. Ingesting into Vector Store...")
    
    embedding_model = EmbeddingModel()
    vector_store = VectorStore()
    
    # Add documents
    vector_store.add_documents(chunks, embedding_model)
    print("Ingestion complete.")

if __name__ == "__main__":
    ingest_existing_chunks()