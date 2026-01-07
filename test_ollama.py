import ollama
try:
    print("Testing Ollama connection...")
    response = ollama.chat(model='llama3:latest', messages=[{'role': 'user', 'content': 'hi'}])
    print("Response:", response['message']['content'])
except Exception as e:
    print("Error:", e)
