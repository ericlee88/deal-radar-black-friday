# Deal Radar Live Price Sync — Chrome Extension

Zero-cost, zero-API-key live Amazon & CamelCamelCamel price syncing for [Deal Radar](https://ericlee88.github.io/deal-radar-black-friday/).

## What It Does
1. **1-Click Sync on Amazon Product Pages**: Shows a floating **"Sync to Deal Radar"** button on any `amazon.com/dp/<ASIN>` page. Captures the real Buy Box price, MSRP, and on-page clip coupon and saves it straight into Deal Radar's `localStorage`.
2. **1-Click Sync on CamelCamelCamel**: Shows a floating **"Sync CCC History to Deal Radar"** button on `camelcamelcamel.com/product/<ASIN>` pages to import real Current, Average, and All-Time Low prices.
3. **Batch Sync All Watchlist Prices**: Click the extension icon → **"Sync All Live Amazon Prices"** to quietly check every tracked ASIN in your Deal Radar watchlist using a single background tab in your browser (no cloud IP blocks, no paid API keys).

## How to Install (30 Seconds)
1. Clone or download this repository (`feat/github-pages-static-sync` branch).
2. Open Chrome and go to `chrome://extensions`.
3. Turn on **Developer mode** (top right).
4. Click **Load unpacked** and select the `chrome-extension` folder.
5. Open https://ericlee88.github.io/deal-radar-black-friday/ once so the extension loads your watchlist ASINs, then click the **Deal Radar Sync** icon in your Chrome toolbar!
