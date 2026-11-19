// Content script for camelcamelcamel.com/product/<ASIN> pages
(function () {
  function extractAsin() {
    const m = window.location.pathname.match(/\/product\/(B0[A-Z0-9]{8})/i);
    return m ? m[1].toUpperCase() : null;
  }

  function parseDollar(text) {
    if (!text) return null;
    const m = text.replace(/,/g, '').match(/\$([0-9]+(?:\.[0-9]{1,2})?)/);
    if (!m) return null;
    const val = parseFloat(m[1]);
    return Number.isFinite(val) && val > 0 ? Math.round(val * 100) / 100 : null;
  }

  function scrapeCamelProduct() {
    const asin = extractAsin();
    if (!asin) return null;

    const h2 = document.querySelector('h2 a, h1, .product_title');
    const title = h2 ? h2.textContent.trim() : document.title.split('|')[0].trim();

    let currentPrice = null;
    let lowestPrice = null;
    let averagePrice = null;
    let highestPrice = null;

    // Parse CamelCamelCamel summary tables (Amazon price section preferred)
    const rows = Array.from(document.querySelectorAll('table.product_pane tr, table tr'));
    for (const row of rows) {
      const cells = Array.from(row.querySelectorAll('td, th')).map((c) => c.textContent.trim());
      if (cells.length < 2) continue;
      const label = cells[0].toLowerCase();
      const val = parseDollar(cells[1]);
      if (val === null) continue;
      if (label.includes('current') && currentPrice === null) currentPrice = val;
      else if (label.includes('lowest') && lowestPrice === null) lowestPrice = val;
      else if (label.includes('average') && averagePrice === null) averagePrice = val;
      else if (label.includes('highest') && highestPrice === null) highestPrice = val;
    }

    return {
      asin,
      title: title.slice(0, 120),
      current_price: currentPrice,
      avg_90d_price: averagePrice,
      all_time_low: lowestPrice,
      msrp: highestPrice || averagePrice || currentPrice || 0,
      price_source: 'camelcamelcamel',
      note: 'Synced from CamelCamelCamel via Chrome Extension',
      url: `https://www.amazon.com/dp/${asin}?psc=1`,
    };
  }

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg && msg.type === 'SCRAPE_CURRENT_PAGE') {
      sendResponse({ ok: true, data: scrapeCamelProduct() });
      return true;
    }
  });

  function injectFloatingButton() {
    const asin = extractAsin();
    if (!asin || document.getElementById('deal-radar-ccc-pill')) return;

    const btn = document.createElement('button');
    btn.id = 'deal-radar-ccc-pill';
    btn.textContent = 'Sync CCC History to Deal Radar';
    Object.assign(btn.style, {
      position: 'fixed',
      bottom: '20px',
      right: '20px',
      zIndex: '2147483647',
      background: '#0F172A',
      color: '#38BDF8',
      border: '1.5px solid #0EA5E9',
      borderRadius: '999px',
      padding: '10px 16px',
      fontSize: '13px',
      fontWeight: '700',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      cursor: 'pointer',
      boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
    });

    btn.addEventListener('click', () => {
      const data = scrapeCamelProduct();
      if (!data || (!data.current_price && !data.all_time_low && !data.avg_90d_price)) {
        btn.textContent = 'No price table found on page';
        return;
      }
      btn.textContent = 'Syncing CCC history...';
      chrome.runtime.sendMessage({ type: 'SYNC_ITEM', payload: data }, (resp) => {
        if (resp && resp.ok) {
          btn.textContent = 'Saved CCC History to Deal Radar!';
          setTimeout(() => {
            btn.textContent = 'Sync CCC History to Deal Radar';
          }, 3000);
        }
      });
    });

    document.body.appendChild(btn);
  }

  injectFloatingButton();
})();
