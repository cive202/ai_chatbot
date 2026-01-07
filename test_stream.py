import requests
import json

url = "http://localhost:8000/api/chat"
payload = {
    "messages": [{"role": "user", "content": "Tell me a story about a cat."}]
}

print("Sending request...")
with requests.post(url, json=payload, stream=True) as r:
    print(f"Status: {r.status_code}")
    print("Headers:", r.headers)
    print("Body:")
    for chunk in r.iter_content(chunk_size=None):
        if chunk:
            print(chunk.decode(), end='', flush=True)
print("\nDone.")
