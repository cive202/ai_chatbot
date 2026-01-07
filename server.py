from fastapi import FastAPI, HTTPException, BackgroundTasks, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
import asyncio
import os
import uvicorn
from contextlib import asynccontextmanager

# Import our existing modules
from chat import ChatEngine
from vector_store import VectorStore
from embeddings import EmbeddingModel
from crawler import crawl
from chunker import chunk_documents
from config import OUTPUT_FILE

# Global instances
chat_engine = None
vector_store = None
embedding_model = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global chat_engine, vector_store, embedding_model
    print("Initializing models...")
    embedding_model = EmbeddingModel()
    vector_store = VectorStore()
    chat_engine = ChatEngine(vector_store, embedding_model)
    print("Models initialized.")
    yield
    # Shutdown (if needed)

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for dev
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    messages: List[dict]

class IngestUrlRequest(BaseModel):
    url: str

@app.post("/api/chat")
async def chat(request: ChatRequest):
    global chat_engine
    if not chat_engine:
        raise HTTPException(status_code=503, detail="Chat engine not initialized")
    
    # Get the last user message
    print(f"DEBUG: Received messages: {request.messages}")
    if not request.messages:
         raise HTTPException(status_code=400, detail="No messages provided")
         
    last_msg = request.messages[-1]
    user_message = last_msg.get('content')
    
    if not user_message:
        print(f"DEBUG: Message content missing. Keys found: {last_msg.keys()}")
        # Fallback for Vercel AI SDK 'parts' if present (multimodal)
        if 'parts' in last_msg:
             # parts is a list of {type: 'text', text: '...'}
             texts = [p.get('text', '') for p in last_msg['parts'] if p.get('type') == 'text']
             user_message = "\n".join(texts)
             
    if not user_message:
         raise HTTPException(status_code=400, detail="Last message has no content")

    # Stream the response
    return StreamingResponse(chat_engine.query_stream(user_message), media_type="text/plain")

@app.websocket("/ws/chat")
async def websocket_chat(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            # Basic handling: query engine and send back response
            # Note: This expects raw text. If client sends JSON, we might need to parse.
            # But let's just try to support it.
            if chat_engine:
                 response_stream = chat_engine.query_stream(data)
                 for chunk in response_stream:
                     await websocket.send_text(chunk)
            else:
                 await websocket.send_text("Error: Chat engine not initialized")
    except Exception as e:
        print(f"WebSocket disconnected: {e}")

@app.post("/api/ingest/url")
async def ingest_url(request: IngestUrlRequest):
    url = request.url
    print(f"Received ingest request for: {url}")
    
    try:
        # 1. Crawl
        # We need to run the async crawl function
        # Since we are in an async route, we can await it directly
        print("Starting crawl...")
        crawled_data = await crawl(url)
        print(f"Crawl complete. Found {len(crawled_data)} pages.")
        
        # 2. Chunk
        print("Chunking data...")
        documents = []
        for page_url, content in crawled_data.items():
            documents.append({
                "text": content.get("text", ""),
                "metadata": {"source": page_url}
            })
        
        chunks = chunk_documents(documents)
        print(f"Created {len(chunks)} chunks.")
        
        # 3. Ingest
        global vector_store, embedding_model
        if not vector_store or not embedding_model:
             # Just in case
             embedding_model = EmbeddingModel()
             vector_store = VectorStore()
        
        print("Ingesting into Vector Store...")
        vector_store.add_documents(chunks, embedding_model)
        print("Ingestion complete.")
        
        return {"status": "success", "message": f"Successfully ingested {len(chunks)} chunks from {url}", "chunks": len(chunks)}
        
    except Exception as e:
        print(f"Error during ingestion: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
