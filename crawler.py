from playwright.async_api import async_playwright
from urllib.parse import urlparse
import json
import time
import asyncio
from extractor import extract_text_and_links
from utils import normalize_url, is_internal
from config import START_URL, MAX_PAGES, DELAY, OUTPUT_FILE, MAX_DEPTH, BASE_DOMAIN


async def crawl(start_url: str):
    # Use BASE_DOMAIN from config if available, else derive from start_url
    try:
        base_domain = BASE_DOMAIN
    except NameError:
        base_domain = urlparse(start_url).netloc
        
    visited = set()
    # Queue stores tuples of (url, depth)
    queue = [(normalize_url(start_url), 0)]
    data = {}

    async with async_playwright() as p:
        try:
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()

            while queue and len(visited) < MAX_PAGES:
                url, depth = queue.pop(0)

                if url in visited:
                    continue

                print(f"Visiting (Depth {depth}): {url}")
                visited.add(url)

                try:
                    await page.goto(url, wait_until="networkidle")
                    await page.wait_for_timeout(2000)

                    html = await page.content()
                    
                    text, content_links, all_links = extract_text_and_links(html, url)
                    
                    # Always use all_links for crawling to ensure we don't miss pages accessible via nav/footer
                    links = all_links

                    data[url] = {
                        "text": text,
                        "links": sorted(links)
                    }

                    # Only add new links if we haven't reached max depth
                    if depth < MAX_DEPTH:
                        for link in links:
                            if is_internal(link, base_domain) and link not in visited:
                                # Check if link is already in queue to avoid duplicates in queue (optional optimization)
                                # But simple visited check is usually enough. 
                                # We add it with depth + 1
                                queue.append((link, depth + 1))

                except Exception as e:
                    print(f"Error processing {url}: {e}")

                await asyncio.sleep(DELAY)

            await browser.close()
        except Exception as e:
            print(f"Browser Launch Error: {e}")

    return data

if __name__ == "__main__":
    print(f"Starting crawl of {START_URL}...")
    data = asyncio.run(crawl(START_URL))
    
    print(f"Crawling complete. Saving to {OUTPUT_FILE}...")
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
    print(f"Data saved to {OUTPUT_FILE}")
