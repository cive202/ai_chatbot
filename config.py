START_URL = "https://khaltibyime.khalti.com/"
MAX_PAGES = 100
MAX_DEPTH = 3
DELAY = 2
OUTPUT_FILE = "output.json"
BASE_DOMAIN = "khalti.com"  # Allow crawling subdomains and parent domain
IGNORED_DOMAINS = [
    "google.com", "www.google.com", "play.google.com",
    "facebook.com", "www.facebook.com", "m.me",
    "twitter.com", "x.com", "www.x.com",
    "instagram.com", "www.instagram.com",
    "linkedin.com", "www.linkedin.com",
    "youtube.com", "www.youtube.com",
    "apple.com", "apps.apple.com",
    "viber", "viber.com"
]
