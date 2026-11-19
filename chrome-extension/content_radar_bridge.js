// Bridge content script running on Deal Radar (GitHub Pages / localhost)
// Syncs tracked ASINs from localStorage -> extension and applies scraped updates -> localStorage.
(function () {
  const STORAGE_KEY = 'deal_radar_state_v1';

  function extractAsin(str) {
    if (!str) return null;
    const m = String(str).toUpperCase().match(/\b(B0[A-Z0-9]{8})\b/);
    return m ? m[1] : null;
  }

  function readState() {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (_) {
      return null;
    }
  }

  function writeState(state) {
    state.updated_at = new Date().toISOString();
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  function publishWatchlistToExtension() {
    const state = readState();
    if (!state || !Array.isArray(state.missions)) return [];
    const items = [];
    const seen = new Set();
    for (const m of state.missions) {
      for (const o of m.options || []) {
        if (o.is_trap_warning) continue;
        const asin = extractAsin(o.asin_or_sku);
        if (asin && !seen.has(asin)) {
          seen.add(asin);
          items.push({
            asin,
            title: o.title || m.title || asin,
            optionId: o.id,
            currentPrice: o.current_price || 0,
          });
        }
      }
    }
    chrome.storage.local.set({ watchlist_asins: items });
    return items;
  }

  function applyUpdatesToLocalStorage(updates) {
    if (!Array.isArray(updates) || updates.length === 0) return false;
    const state = readState();
    if (!state || !Array.isArray(state.missions)) return false;

    let changed = false;
    const today = new Date().toISOString().slice(0, 10);

    for (const upd of updates) {
      if (!upd || !upd.asin) continue;
      const targetAsin = upd.asin.toUpperCase();
      let matched = false;

      for (const m of state.missions) {
        for (const o of m.options || []) {
          if (extractAsin(o.asin_or_sku) === targetAsin) {
            matched = true;
            if (typeof upd.current_price === 'number' && upd.current_price > 0) {
              o.current_price = upd.current_price;
              const hist = Array.isArray(o.price_history)
                ? o.price_history.filter((v) => typeof v === 'number' && v > 0)
                : [];
              hist.push(upd.current_price);
              o.price_history = hist.slice(-24);

              const log = Array.isArray(o.price_log) ? o.price_log : [];
              log.unshift({
                date: today,
                price: upd.current_price,
                source: upd.price_source || 'live',
                note: upd.note || 'Synced via Chrome Extension',
              });
              o.price_log = log.slice(0, 30);
            }
            if (typeof upd.msrp === 'number' && upd.msrp > 0) {
              o.msrp = Math.max(o.msrp || 0, upd.msrp);
            }
            if (typeof upd.avg_90d_price === 'number' && upd.avg_90d_price > 0) {
              o.avg_90d_price = upd.avg_90d_price;
            }
            if (typeof upd.all_time_low === 'number' && upd.all_time_low > 0) {
              o.all_time_low = upd.all_time_low;
            }
            if (typeof upd.clip_coupon_amount === 'number' && upd.clip_coupon_amount >= 0) {
              o.clip_coupon_amount = upd.clip_coupon_amount;
            }
            if (upd.price_source) {
              o.price_source = upd.price_source;
            }
            changed = true;
          }
        }
      }

      // If ASIN wasn't in the watchlist yet, create a new custom mission for it
      if (!matched && typeof upd.current_price === 'number' && upd.current_price > 0) {
        let nextMId = 1;
        let nextOId = 1;
        for (const m of state.missions) {
          nextMId = Math.max(nextMId, (m.id || 0) + 1);
          for (const o of m.options || []) {
            nextOId = Math.max(nextOId, (o.id || 0) + 1);
          }
        }
        const price = upd.current_price;
        const strike = Math.round(price * 0.9 * 100) / 100;
        state.missions.unshift({
          id: nextMId,
          slug: `ext-${targetAsin.toLowerCase()}-${Date.now()}`,
          title: upd.title || `Amazon Item (${targetAsin})`,
          raw_intent: upd.title || targetAsin,
          node_type: 'EXACT_SKU',
          category_tag: 'custom',
          icon: '',
          decision_framing: 'Added via Deal Radar Chrome Extension.',
          options: [
            {
              id: nextOId,
              mission_id: nextMId,
              branch_key: `ext_${targetAsin.toLowerCase()}`,
              branch_label: 'Chrome Extension Sync',
              is_recommended_branch: true,
              is_trap_warning: false,
              title: upd.title || `Amazon Item (${targetAsin})`,
              asin_or_sku: targetAsin,
              amazon_query: encodeURIComponent(upd.title || targetAsin),
              msrp: upd.msrp || price,
              avg_90d_price: upd.avg_90d_price || 0,
              current_price: price,
              clip_coupon_amount: upd.clip_coupon_amount || 0,
              strike_price: strike,
              all_time_low: upd.all_time_low || 0,
              sns_eligible: false,
              pg_stockup_eligible: false,
              b2g1_eligible: false,
              selected_in_stack: true,
              snagged: false,
              unit_name: 'item',
              unit_quantity: 1.0,
              price_history: [price],
              price_log: [
                {
                  date: today,
                  price,
                  source: upd.price_source || 'live',
                  note: upd.note || 'Added via Chrome Extension',
                },
              ],
              price_source: upd.price_source || 'live',
              scout_notes: 'Synced live from Amazon via Chrome Extension.',
            },
          ],
        });
        changed = true;
      }
    }

    if (changed) {
      writeState(state);
      publishWatchlistToExtension();
    }
    return changed;
  }

  // Drain any queued updates that arrived while Deal Radar was closed
  function drainPendingUpdates() {
    chrome.storage.local.get(['pending_updates'], (res) => {
      const pending = res.pending_updates || [];
      if (pending.length > 0 && readState()) {
        const applied = applyUpdatesToLocalStorage(pending);
        chrome.storage.local.set({ pending_updates: [] });
        if (applied) {
          window.location.reload();
        }
      }
    });
  }

  // Wait briefly for Flutter to initialize localStorage on first visit, then sync
  setTimeout(() => {
    publishWatchlistToExtension();
    drainPendingUpdates();
  }, 1500);

  // Listen for live updates pushed from background.js
  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg && msg.type === 'APPLY_PRICE_UPDATES') {
      const applied = applyUpdatesToLocalStorage(msg.updates || []);
      sendResponse({ ok: true, applied });
      if (applied && msg.reload !== false) {
        window.location.reload();
      }
      return true;
    }
    if (msg && msg.type === 'GET_WATCHLIST') {
      const items = publishWatchlistToExtension();
      sendResponse({ ok: true, items });
      return true;
    }
  });
})();
