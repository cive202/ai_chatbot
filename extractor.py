from bs4 import BeautifulSoup
from urllib.parse import urljoin
import re

from utils import normalize_url


def extract_text_and_links(html: str, current_url: str):
    soup = BeautifulSoup(html, "html.parser")

    # ------------------------
    # REMOVE NOISE (Scripts, etc)
    # ------------------------
    for tag in soup(["script", "style", "noscript"]):
        tag.decompose()

    # ------------------------
    # 1. EXTRACT ALL LINKS (For Crawling)
    # ------------------------
    # We extract links BEFORE removing nav/header/footer so the crawler can find them.
    all_links = set()
    _extract_links_from_soup(soup, current_url, all_links)

    # ------------------------
    # REMOVE NAV/HEADER/FOOTER
    # ------------------------
    # Now remove these to clean up the text and find "content-only" links
    for tag in soup(["nav", "footer", "header"]):
        tag.decompose()

    # Remove Elementor/Theme specific header/footers and roles
    for class_name in ["finaxio-builder-header", "finaxio-builder-footer"]:
        for tag in soup.find_all(class_=class_name):
            tag.decompose()

    for role in ["navigation", "banner", "contentinfo"]:
        for tag in soup.find_all(attrs={"role": role}):
            tag.decompose()

    # ------------------------
    # 2. EXTRACT CONTENT LINKS (For Saving)
    # ------------------------
    # These are links that remain in the body after removing navigation
    content_links = set()
    _extract_links_from_soup(soup, current_url, content_links)

    # ------------------------
    # TEXT EXTRACTION
    # ------------------------
    text = "\n".join(soup.stripped_strings)

    return text, sorted(list(content_links)), sorted(list(all_links))


def _extract_links_from_soup(soup, current_url, links_set):
    """Helper to extract links from a soup object into a set."""
    # <a href="">
    for a in soup.find_all("a", href=True):
        href = a["href"].strip().strip("`").strip()
        if href.startswith(("mailto:", "tel:", "javascript:")):
            continue
        links_set.add(normalize_url(urljoin(current_url, href)))

    # onclick="location.href='...'"
    for tag in soup.find_all(onclick=True):
        match = re.search(
            r"(?:location\.href|window\.location)\s*=\s*['\"](.*?)['\"]",
            tag["onclick"]
        )
        if match:
            links_set.add(normalize_url(urljoin(current_url, match.group(1))))

    # data-href / data-url
    for attr in ("data-href", "data-url"):
        for tag in soup.find_all(attrs={attr: True}):
            links_set.add(normalize_url(urljoin(current_url, tag[attr])))
