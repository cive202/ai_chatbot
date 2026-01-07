import pypdf

def load_pdf(file_path):
    """
    Extracts text from a PDF file.
    """
    text = ""
    try:
        reader = pypdf.PdfReader(file_path)
        for page in reader.pages:
            text += page.extract_text() + "\n"
    except Exception as e:
        print(f"Error reading PDF {file_path}: {e}")
        return None
        
    return text
