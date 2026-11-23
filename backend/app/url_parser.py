"""Multi-site product URL parsing, retailer detection, and generic HTML price extraction."""

from __future__ import annotations

import json
import re
from typing import Any, Dict, Optional
from urllib.parse import parse_qs, unquote, urlparse

_ASIN_RX = re.compile(r"\b(B0[A-Z0-9]{8})\b", re.IGNORECASE)
_URL_RX = re.compile(r"(https?://[^\s<>\"']+)", re.IGNORECASE)
_INLINE_PRICE_RX = re.compile(r"\$([0-9]+(?:\.[0-9]{1,2})?)")

_KNOWN_SITES: Dict[str, str] = {
    "amazon.com": "Amazon",
    "amzn.to": "Amazon",
    "a.co": "Amazon",
    "walmart.com": "Walmart",
    "target.com": "Target",
    "bestbuy.com": "Best Buy",
    "homedepot.com": "Home Depot",
    "lowes.com": "Lowe's",
    "costco.com": "Costco",
    "newegg.com": "Newegg",
    "bhphotovideo.com": "B&H",
    "rei.com": "REI",
    "dyson.com": "Dyson",
    "apple.com": "Apple",
    "iherb.com": "iHerb",
    "ebay.com": "eBay",
    "microcenter.com": "Micro Center",
    "samsclub.com": "Sam's Club",
    "williams-sonoma.com": "Williams-Sonoma",
    "chewy.com": "Chewy",
    "wayfair.com": "Wayfair",
    "sephora.com": "Sephora",
    "ulta.com": "Ulta",
    "nike.com": "Nike",
    "adidas.com": "Adidas",
    "acmetools.com": "Acme Tools",
    "knifecenter.com": "KnifeCenter",
    "knivesshipfree.com": "KnivesShipFree",
}

_NOISE_PATH_SEGMENTS = {
    "ip",
    "dp",
    "gp",
    "product",
    "products",
    "p",
    "pd",
    "site",
    "shop",
    "c",
    "item",
    "itm",
    "store",
    "en-us",
    "us",
    "en",
    "pr",
    "s",
    "-",
}


def _root_domain(host: str) -> str:
    clean = (host or "").lower().strip()
    if clean.startswith("www."):
        clean = clean[4:]
    if clean.startswith("m."):
        clean = clean[2:]
    return clean


def extract_site_name(url: str) -> str:
    """Return a friendly retailer name for a product URL (e.g. 'Walmart', 'Best Buy', 'Amazon')."""
    if not url or not url.strip():
        return "Amazon"
    try:
        parsed = urlparse(url.strip())
        host = _root_domain(parsed.netloc)
    except Exception:
        return "Amazon"
    if not host:
        return "Amazon"

    for domain, label in _KNOWN_SITES.items():
        if host == domain or host.endswith("." + domain):
            return label

    # Fallback: take primary domain label and title-case it
    parts = host.split(".")
    label = parts[-2] if len(parts) >= 2 else parts[0]
    return label.replace("-", " ").title()


def is_amazon_url(url: str) -> bool:
    if not url:
        return False
    try:
        host = _root_domain(urlparse(url.strip()).netloc)
    except Exception:
        return False
    return (
        host == "amazon.com"
        or host.endswith(".amazon.com")
        or host in ("a.co", "amzn.to")
    )


def extract_sku_from_url(url: str) -> str:
    """Extract an ASIN or retailer-specific product ID from a URL if recognizable."""
    if not url:
        return ""
    asin_m = _ASIN_RX.search(url)
    if asin_m:
        return asin_m.group(1).upper()

    try:
        parsed = urlparse(url)
        path = parsed.path or ""
        qs = parse_qs(parsed.query or "")
    except Exception:
        return ""

    # Best Buy: ?skuId=6505727 or /6505727.p
    if "skuId" in qs and qs["skuId"]:
        return f"BB-{qs['skuId'][0]}"
    bb_m = re.search(r"/(\d{6,8})\.p\b", path)
    if bb_m:
        return f"BB-{bb_m.group(1)}"

    # Target: /-/A-89123456
    tgt_m = re.search(r"/(A-\d{6,10})\b", path, re.IGNORECASE)
    if tgt_m:
        return tgt_m.group(1).upper()

    # Costco: .product.4000118614.html
    costco_m = re.search(r"\.product\.(\d{6,12})\.html", path, re.IGNORECASE)
    if costco_m:
        return f"COSTCO-{costco_m.group(1)}"

    # Walmart / Home Depot / Lowe's numeric trailing item ID
    num_m = re.search(r"/(?:ip|p|pd)/(?:[^/]+/)?(\d{6,12})(?:/|$)", path)
    if num_m:
        site = extract_site_name(url).upper().replace(" ", "")[:8]
        return f"{site}-{num_m.group(1)}"

    return ""


def _humanize_slug(raw_slug: str) -> str:
    slug = unquote(raw_slug)
    slug = re.sub(r"\.(?:html?|php|aspx?|p)$", "", slug, flags=re.IGNORECASE)
    slug = re.sub(r"\.product\.\d+$", "", slug, flags=re.IGNORECASE)
    slug = re.sub(r"[-_+]+", " ", slug)
    slug = re.sub(r"\s+", " ", slug).strip()
    if not slug:
        return ""
    # Preserve acronyms/model numbers if already mixed-case; title-case all-lowercase slugs
    if slug.islower():
        slug = slug.title()
    return slug


def extract_title_from_url(url: str) -> str:
    """Derive a clean readable product title from a product URL path slug."""
    try:
        parsed = urlparse(url.strip())
    except Exception:
        return ""

    path = parsed.path or ""
    # Amazon: /Some-Product-Slug/dp/B0...
    amz_m = re.search(r"/([^/]+)/dp/B0[A-Z0-9]{8}", path, re.IGNORECASE)
    if amz_m:
        return _humanize_slug(amz_m.group(1))

    segments = [seg for seg in path.split("/") if seg]
    best = ""
    for seg in segments:
        low = seg.lower()
        if low in _NOISE_PATH_SEGMENTS:
            continue
        if re.fullmatch(r"\d+(?:\.p)?", low):
            continue
        if re.fullmatch(r"a-\d+", low):
            continue
        if _ASIN_RX.fullmatch(seg):
            continue
        candidate = _humanize_slug(seg)
        # Prefer the longest descriptive slug containing letters
        if any(c.isalpha() for c in candidate) and len(candidate) > len(best):
            best = candidate
    return best


def parse_product_link(raw_text: str) -> Optional[Dict[str, Any]]:
    """Parse any user-pasted product link (optionally accompanied by a title or $price)."""
    cleaned = (raw_text or "").strip()
    url_m = _URL_RX.search(cleaned)
    if not url_m:
        return None

    url = url_m.group(1).rstrip(".,);]")
    site_name = extract_site_name(url)
    sku = extract_sku_from_url(url)

    # Extract inline $price from text outside the URL
    non_url_text = (cleaned[: url_m.start()] + " " + cleaned[url_m.end() :]).strip()
    inline_price: Optional[float] = None
    price_m = _INLINE_PRICE_RX.search(non_url_text)
    if price_m:
        try:
            val = float(price_m.group(1))
            if val > 0:
                inline_price = round(val, 2)
        except ValueError:
            pass

    custom_label = _INLINE_PRICE_RX.sub("", non_url_text).strip(" -|:")
    title = custom_label or extract_title_from_url(url)
    if not title:
        title = f"{site_name} Item ({sku})" if sku else f"Custom {site_name} Item"

    return {
        "url": url,
        "site_name": site_name,
        "is_amazon": is_amazon_url(url),
        "sku": sku,
        "title": title[:80],
        "inline_price": inline_price,
    }


def _extract_jsonld_price(obj: Any) -> Optional[float]:
    if isinstance(obj, list):
        for item in obj:
            found = _extract_jsonld_price(item)
            if found is not None:
                return found
        return None

    if not isinstance(obj, dict):
        return None

    if "@graph" in obj:
        found = _extract_jsonld_price(obj["@graph"])
        if found is not None:
            return found

    obj_type = obj.get("@type")
    type_names = obj_type if isinstance(obj_type, list) else [obj_type]
    type_lower = {str(t).lower() for t in type_names if t}

    if "product" in type_lower and "offers" in obj:
        found = _extract_jsonld_price(obj["offers"])
        if found is not None:
            return found

    if any(t in type_lower for t in ("offer", "aggregateoffer")) or "price" in obj or "lowPrice" in obj:
        for key in ("price", "lowPrice"):
            raw = obj.get(key)
            if isinstance(raw, (int, float)) and raw > 0:
                return round(float(raw), 2)
            if isinstance(raw, str):
                cleaned = raw.replace("$", "").replace(",", "").strip()
                try:
                    val = float(cleaned)
                    if val > 0:
                        return round(val, 2)
                except ValueError:
                    pass
        if "offers" in obj:
            return _extract_jsonld_price(obj["offers"])

    return None


def extract_price_from_html(html: str) -> Optional[float]:
    """Extract a USD product price from generic retailer HTML (JSON-LD, OpenGraph, microdata)."""
    if not html:
        return None

    # 1. JSON-LD structured product offers
    for m in re.finditer(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        html,
        re.IGNORECASE | re.DOTALL,
    ):
        raw_json = m.group(1).strip()
        if not raw_json:
            continue
        try:
            parsed = json.loads(raw_json)
            found = _extract_jsonld_price(parsed)
            if found is not None:
                return found
        except Exception:
            continue

    # 2. OpenGraph / product meta price tags
    for pattern in (
        r'<meta[^>]+property=["\'](?:og|product):price:amount["\'][^>]+content=["\']([0-9,]+(?:\.[0-9]{1,2})?)["\']',
        r'<meta[^>]+content=["\']([0-9,]+(?:\.[0-9]{1,2})?)["\'][^>]+property=["\'](?:og|product):price:amount["\']',
        r'itemprop=["\']price["\'][^>]+content=["\']([0-9,]+(?:\.[0-9]{1,2})?)["\']',
        r'content=["\']([0-9,]+(?:\.[0-9]{1,2})?)["\'][^>]+itemprop=["\']price["\']',
    ):
        m = re.search(pattern, html, re.IGNORECASE)
        if m:
            try:
                val = round(float(m.group(1).replace(",", "")), 2)
                if val > 0:
                    return val
            except ValueError:
                pass

    return None
