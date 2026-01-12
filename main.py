import argparse
import sys
import os
import asyncio
import json
from dotenv import load_dotenv
from config import START_URL, OUTPUT_FILE
from chat import ChatEngine
from vector_store import VectorStore
from embeddings import EmbeddingModel

# Load environment variables
load_dotenv()

def run_crawler():
    try:
        from crawler import crawl
        print(f"Starting crawl of {START_URL}...")
        data = asyncio.run(crawl(START_URL))
        
        print(f"Crawling complete. Saving to {OUTPUT_FILE}...")
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
        print(f"Data saved to {OUTPUT_FILE}")
        
    except ImportError:
        print("crawler module not found.")
    except Exception as e:  
        print(f"Crawling failed: {e}")

def chat_loop(model_name=None):
    # Get LLM provider from environment or default to ollama
    llm_provider = os.getenv("LLM_PROVIDER", "ollama").lower()
    
    # If model_name is provided, use it (for backward compatibility)
    # Otherwise, use environment variables
    if model_name:
        print(f"Initializing Chat Engine with model: {model_name}...")
        # For Ollama, validate the model name
        if llm_provider == "ollama" and model_name:
            ollama_model = model_name
        else:
            ollama_model = None
    else:
        ollama_model = os.getenv("OLLAMA_MODEL")
        print(f"Initializing Chat Engine with provider: {llm_provider}...")
    
    try:
        embedding_model = EmbeddingModel()
        vector_store = VectorStore()
        chat_engine = ChatEngine(
            vector_store, 
            embedding_model, 
            llm_provider=llm_provider,
            ollama_model=ollama_model
        )
    except Exception as e:
        print(f"Initialization failed: {e}")
        return

    print("Chat initialized. Type 'exit' or 'quit' to stop.")
    while True:
        try:
            user_input = input("\nYou: ")
            if user_input.lower() in ['exit', 'quit']:
                break
            
            print("Assistant: ", end="", flush=True)
            for chunk in chat_engine.query_stream(user_input):
                print(chunk, end="", flush=True)
            print()
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"An error occurred: {e}")

def main():
    parser = argparse.ArgumentParser(description="AI Chatbot CLI")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Chat command
    chat_parser = subparsers.add_parser("chat", help="Start the chat interface")
    chat_parser.add_argument("--model", default=None, help="Ollama LLM model to use (default: from OLLAMA_MODEL env var). WARNING: Use quantized models like llama3:8b-instruct-q4_K_M for RTX 3060")

    # Ingest command
    ingest_parser = subparsers.add_parser("ingest", help="Ingest chunks from chunks.json")

    # Crawl command
    crawl_parser = subparsers.add_parser("crawl", help="Crawl the website defined in config.py")

    # Chunk command
    chunk_parser = subparsers.add_parser("chunk", help="Chunk the crawled data into chunks.json")

    args = parser.parse_args()

    if args.command == "chat":
        chat_loop(args.model)
    elif args.command == "crawl":
        run_crawler()
    elif args.command == "chunk":
        try:
            from chunker import process_output_file
            process_output_file()
        except ImportError:
            print("chunker module not found.")
    elif args.command == "ingest":
        try:
            from ingest_chunks import ingest_existing_chunks
            ingest_existing_chunks()
        except ImportError:
            print("ingest_chunks module not found.")
            print("Please ensure ingest_chunks.py exists.")
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
