// Content script for amazon.com product pages
(function () {
  function extractAsin() {
    const urlMatch = window.location.href.match(/\/(?:dp|gp\/product)\/(B0[A-Z0-9]{8})/i);
    if (urlMatch) return urlMatch[1].toUpperCase();
    const input = document.querySelector('input#ASIN');
    if (input && input.value && /^B0[A-Z0-9]{8}$/i.test(input.value)) {
      return input.value.toUpperCase();
    }
    return null;
  }

  function parseDollar(text) {
    if (!text) return null;
    const m = text.replace(/,/g, '').match(/\$([0-9]+(?:\.[0-9]{1,2})?)/);
    if (!m) return null;
    const val = parseFloat(m[1]);
    return Number.isFinite(val) && val > 0 ? Math.round(val * 100) / 100 : null;
  }

  function scrapeAmazonProduct() {
    const asin = extractAsin();
    if (!asin) return null;

    const titleEl = document.querySelector('#productTitle');
    const title = titleEl ? titleEl.textContent.trim() : document.title.replace(/^Amazon\.com\s*:\s*/i, '').trim();

    // Primary live Buy Box price selectors (in priority order)
    const priceSelectors = [
      '#corePriceDisplay_desktop_feature_div .priceToPay .a-offscreen',
      '#corePriceDisplay_desktop_feature_div .apexPriceToPay .a-offscreen',
      '#corePrice_feature_div .a-price .a-offscreen',
      '#price_inside_buybox',
      '#priceblock_ourprice',
      '#priceblock_dealprice',
      '.a-price.aok-align-center .a-offscreen',
    ];
    let currentPrice = null;
    for (const sel of priceSelectors) {
      const el = document.querySelector(sel);
      if (el) {
        const val = parseDollar(el.textContent);
        if (val !== null) {
          currentPrice = val;
          break;
        }
      }
    }

    // Fallback: assemble whole + fraction spans if a-offscreen was empty
    if (currentPrice === null) {
      const whole = document.querySelector('#corePriceDisplay_desktop_feature_div .priceToPay .a-price-whole');
      const frac = document.querySelector('#corePriceDisplay_desktop_feature_div .priceToPay .a-price-fraction');
      if (whole) {
        const w = whole.textContent.replace(/[^0-9]/g, '');
        const f = frac ? frac.textContent.replace(/[^0-9]/g, '') : '00';
        const parsed = parseFloat(`${w}.${f}`);
        if (Number.isFinite(parsed) && parsed > 0) {
          currentPrice = Math.round(parsed * 100) / 100;
        }
      }
    }

    // List Price / MSRP
    let msrp = null;
    const msrpSelectors = [
      '#corePriceDisplay_desktop_feature_div .basisPrice .a-offscreen',
      '.a-text-price[data-a-strike="true"] .a-offscreen',
      '#listPrice',
    ];
    for (const sel of msrpSelectors) {
      const el = document.querySelector(sel);
      if (el) {
        const val = parseDollar(el.textContent);
        if (val !== null && (currentPrice === null || val >= currentPrice)) {
          msrp = val;
          break;
        }
      }
    }

    // On-page clip coupon ("Apply $5 coupon" / "Save $4.00 with coupon" / "Save 10% with coupon")
    let couponAmount = 0.0;
    const couponArea = document.querySelector('#promoPriceBlockMessage_feature_div, #couponFeature_feature_div, #vpcButton');
    const couponText = couponArea ? couponArea.textContent : '';
    const dollarCoupon = couponText.match(/(?:Apply|Save)\s+\$([0-9]+(?:\.[0-9]{1,2})?)/i);
    if (dollarCoupon) {
      couponAmount = Math.round(parseFloat(dollarCoupon[1]) * 100) / 100;
    } else if (currentPrice !== null) {
      const pctCoupon = couponText.match(/(?:Apply|Save)\s+([0-9]{1,2})%\s+coupon/i);
      if (pctCoupon) {
        couponAmount = Math.round(currentPrice * (parseFloat(pctCoupon[1]) / 100) * 100) / 100;
      }
    }

    return {
      asin,
      title: title.slice(0, 120),
      current_price: currentPrice,
      msrp: msrp || currentPrice || 0,
      clip_coupon_amount: couponAmount,
      price_source: 'live',
      note: 'Synced live from Amazon via Chrome Extension',
      url: `https://www.amazon.com/dp/${asin}?psc=1`,
    };
  }

  // Listen for requests from background.js / popup.js
  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg && msg.type === 'SCRAPE_CURRENT_PAGE') {
      sendResponse({ ok: true, data: scrapeAmazonProduct() });
      return true;
    }
  });

  // Inject floating "Sync to Deal Radar" pill on Amazon product pages
  function injectFloatingButton() {
    const asin = extractAsin();
    if (!asin || document.getElementById('deal-radar-sync-pill')) return;

    const btn = document.createElement('button');
    btn.id = 'deal-radar-sync-pill';
    btn.textContent = 'Sync to Deal Radar';
    Object.assign(btn.style, {
      position: 'fixed',
      bottom: '20px',
      right: '20px',
      zIndex: '2147483647',
      background: '#0F172A',
      color: '#4ADE80',
      border: '1.5px solid #22C55E',
      borderRadius: '999px',
      padding: '10px 16px',
      fontSize: '13px',
      fontWeight: '700',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      cursor: 'pointer',
      boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
    });

    btn.addEventListener('click', () => {
      const data = scrapeAmazonProduct();
      if (!data || !data.current_price) {
        btn.textContent = 'Price not found on page';
        btn.style.color = '#FBBF24';
        setTimeout(() => {
          btn.textContent = 'Sync to Deal Radar';
          btn.style.color = '#4ADE80';
        }, 2500);
        return;
      }
      btn.textContent = `Syncing $${data.current_price.toFixed(2)}...`;
      chrome.runtime.sendMessage({ type: 'SYNC_ITEM', payload: data }, (resp) => {
        if (resp && resp.ok) {
          btn.textContent = `Saved $${data.current_price.toFixed(2)} to Deal Radar!`;
          setTimeout(() => {
            btn.textContent = 'Sync to Deal Radar';
          }, 3000);
        } else {
          btn.textContent = 'Sync failed -- try again';
        }
      });
    });

    document.body.appendChild(btn);
  }

  injectFloatingButton();
})();
