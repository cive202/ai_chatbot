from sentence_transformers import SentenceTransformer

class EmbeddingModel:
    def __init__(self, model_name="all-MiniLM-L6-v2", model_type="sentence-transformers"):
        # We ignore model_type for now as we default to sentence-transformers
        self.model = SentenceTransformer(model_name)

    def embed(self, text):
        return self.model.encode(text).tolist()
