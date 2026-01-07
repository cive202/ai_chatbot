import json
import uuid

def chunk_text(text, chunk_size=1000, overlap=200):
    """
    Splits text into chunks of approximately `chunk_size` characters,
    respecting sentence boundaries where possible.
    """
    chunks = []
    start = 0
    text_len = len(text)

    while start < text_len:
        end = min(start + chunk_size, text_len)
        
        # If we are not at the end, try to find the last period or newline to break cleanly
        if end < text_len:
            # Look for the last newline in the chunk
            last_newline = text.rfind('\n', start, end)
            if last_newline != -1:
                end = last_newline + 1
            else:
                # If no newline, look for a period
                last_period = text.rfind('. ', start, end)
                if last_period != -1:
                    end = last_period + 1
        
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        
        # If we reached the end, break
        if end == text_len:
            break
            
        # Move start forward, minus overlap
        # But ensure we don't get stuck if the chunk was extremely small or overlap is too big
        next_start = end - overlap
        if next_start <= start:
            next_start = end  # Force forward movement if overlap causes stagnation
        
        start = next_start
            
    return chunks

def chunk_documents(documents):
    """
    Takes a list of documents (dicts with 'text' and 'metadata')
    and returns a list of chunked records.
    """
    all_chunks = []
    
    for doc in documents:
        text = doc.get("text", "")
        metadata = doc.get("metadata", {})
        
        if not text:
            continue
            
        chunks = chunk_text(text)
        
        for chunk in chunks:
            chunk_record = {
                "id": str(uuid.uuid4()),
                "text": chunk,
                "metadata": metadata
            }
            all_chunks.append(chunk_record)
            
    return all_chunks

def process_output_file(input_file="output.json", output_file="chunks.json"):
    try:
        with open(input_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: {input_file} not found.")
        return

    # Convert crawler format to generic document format
    documents = []
    for url, content in data.items():
        documents.append({
            "text": content.get("text", ""),
            "metadata": {"source": url}
        })

    print(f"Processing {len(documents)} documents...")
    all_chunks = chunk_documents(documents)

    # Save to chunks.json
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(all_chunks, f, indent=4, ensure_ascii=False)

    print(f"Successfully created {len(all_chunks)} chunks in {output_file}")

if __name__ == "__main__":
    process_output_file()
