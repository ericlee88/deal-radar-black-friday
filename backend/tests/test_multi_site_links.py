import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from app.models import DealOptionNode
from app.providers.price_provider import PriceDataProvider
from app.url_parser import (
    extract_price_from_html,
    extract_site_name,
    is_amazon_url,
    parse_product_link,
)


def test_parse_product_links_across_retailers():
    wm = parse_product_link(
        "https://www.walmart.com/ip/DEWALT-20V-MAX-5-0Ah-Battery-Kit/5254478164 $119"
    )
    assert wm is not None
    assert wm["site_name"] == "Walmart"
    assert wm["is_amazon"] is False
    assert wm["sku"] == "WALMART-5254478164"
    assert "DEWALT 20V MAX" in wm["title"]
    assert wm["inline_price"] == 119.0

    bb = parse_product_link(
        "https://www.bestbuy.com/site/sony-wh-1000xm5-wireless-headphones/6505727.p?skuId=6505727"
    )
    assert bb is not None
    assert bb["site_name"] == "Best Buy"
    assert bb["sku"] == "BB-6505727"
    assert "Sony Wh 1000Xm5" in bb["title"]

    tgt = parse_product_link(
        "https://www.target.com/p/dyson-v8-origin-cordless-stick-vacuum/-/A-89123456"
    )
    assert tgt is not None
    assert tgt["site_name"] == "Target"
    assert tgt["sku"] == "A-89123456"

    hd = parse_product_link(
        "https://www.homedepot.com/p/DEWALT-20V-MAX-Hammer-Drill/319876543"
    )
    assert hd is not None
    assert hd["site_name"] == "Home Depot"
    assert hd["sku"] == "HOMEDEPO-319876543"

    amz = parse_product_link(
        "https://www.amazon.com/Work-Sharp-Precision-Adjust-Upgrade/dp/B09FXD3ZCF"
    )
    assert amz is not None
    assert amz["site_name"] == "Amazon"
    assert amz["is_amazon"] is True
    assert amz["sku"] == "B09FXD3ZCF"

    custom = parse_product_link("Custom Espresso Grinder https://www.fellowproducts.com/products/ode-gen-2 $299")
    assert custom is not None
    assert custom["site_name"] == "Fellowproducts"
    assert custom["title"] == "Custom Espresso Grinder"
    assert custom["inline_price"] == 299.0


def test_extract_price_from_html_jsonld_and_og():
    jsonld_html = """
    <html><head>
      <script type="application/ld+json">
        {"@context": "https://schema.org", "@type": "Product", "name": "Sony XM5",
         "offers": {"@type": "Offer", "priceCurrency": "USD", "price": "279.99"}}
      </script>
    </head><body></body></html>
    """
    assert extract_price_from_html(jsonld_html) == 279.99

    og_html = '<html><head><meta property="product:price:amount" content="149.50"></head></html>'
    assert extract_price_from_html(og_html) == 149.50

    microdata_html = '<span itemprop="price" content="89.00">$89.00</span>'
    assert extract_price_from_html(microdata_html) == 89.00


def test_price_provider_polls_non_amazon_product_url():
    provider = PriceDataProvider()
    node = DealOptionNode(
        mission_id=1,
        branch_key="link_sony_xm5",
        branch_label="Best Buy Link",
        title="Sony WH-1000XM5 Headphones",
        asin_or_sku="BB-6505727",
        amazon_query="Sony+WH-1000XM5",
        product_url="https://www.bestbuy.com/site/sony-wh-1000xm5/6505727.p",
        msrp=399.99,
        avg_90d_price=329.99,
        current_price=329.99,
        clip_coupon_amount=0.0,
        strike_price=280.0,
        all_time_low=249.0,
    )

    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.text = '<meta property="og:price:amount" content="279.99">'

    mock_client = AsyncMock()
    mock_client.get = AsyncMock(return_value=mock_resp)
    mock_cm = MagicMock()
    mock_cm.__aenter__ = AsyncMock(return_value=mock_client)
    mock_cm.__aexit__ = AsyncMock(return_value=False)

    with patch("app.providers.price_provider.httpx.AsyncClient", return_value=mock_cm):
        tick = asyncio.run(provider.refresh_node_price(node, simulate_drop=False))
        assert tick["current_price"] == 279.99
        assert tick["provider"] == "direct_best_buy"


def test_api_from_link_and_from_intent_with_other_site():
    with TestClient(app) as client:
        # 1. Add via dedicated POST /api/missions/from-link
        resp = client.post(
            "/api/missions/from-link",
            json={
                "product_url": "https://www.target.com/p/ninja-creami-ice-cream-maker/-/A-87654321",
                "title": "Ninja CREAMi Ice Cream Maker",
                "strike_price": 149.99,
                "current_price": 169.99,
                "category_tag": "kitchen",
            },
        )
        assert resp.status_code == 200
        mission = resp.json()
        assert mission["title"] == "Ninja CREAMi Ice Cream Maker"
        assert len(mission["options"]) == 1
        opt = mission["options"][0]
        assert opt["site_name"] == "Target"
        assert opt["product_url"] == "https://www.target.com/p/ninja-creami-ice-cream-maker/-/A-87654321"
        assert opt["amazon_url"] == opt["product_url"]
        assert opt["asin_or_sku"] == "A-87654321"

        # 2. Patch product_url on existing option to another site (Walmart)
        patch_resp = client.patch(
            f"/api/options/{opt['id']}",
            json={
                "product_url": "https://www.walmart.com/ip/Ninja-CREAMi/123456789",
                "current_price": 139.99,
            },
        )
        assert patch_resp.status_code == 200
        patched = patch_resp.json()
        assert patched["site_name"] == "Walmart"
        assert patched["product_url"] == "https://www.walmart.com/ip/Ninja-CREAMi/123456789"
        assert patched["is_below_strike"] is True

        # Clean up created mission
        del_resp = client.delete(f"/api/missions/{mission['id']}")
        assert del_resp.status_code == 200

        # 3. Paste a Best Buy URL directly into /api/missions/from-intent
        intent_resp = client.post(
            "/api/missions/from-intent",
            json={
                "raw_intent": "https://www.bestbuy.com/site/apple-airpods-pro-2/6447382.p?skuId=6447382 $189",
            },
        )
        assert intent_resp.status_code == 200
        m2 = intent_resp.json()
        opt2 = m2["options"][0]
        assert opt2["site_name"] == "Best Buy"
        assert opt2["product_url"].startswith("https://www.bestbuy.com/site/apple-airpods-pro-2/")
        assert opt2["current_price"] == 189.0

        client.delete(f"/api/missions/{m2['id']}")
