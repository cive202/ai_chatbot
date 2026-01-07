from urllib.parse import urlparse


def normalize_url(url: str) -> str:
    return url.split("#")[0].rstrip("/")


def is_internal(url: str, base_domain: str) -> bool:
    return urlparse(url).netloc.endswith(base_domain)
