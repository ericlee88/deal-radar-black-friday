// Background service worker for Deal Radar Live Price Sync
const RADAR_URL_PATTERNS = [
  'https://ericlee88.github.io/deal-radar-black-friday/*',
  'http://localhost:8080/*',
];

let batchStopRequested = false;

async function findRadarTabs() {
  const tabs = await chrome.tabs.query({ url: RADAR_URL_PATTERNS });
  return tabs || [];
}

async function deliverUpdates(updates, reload = true) {
  if (!updates || updates.length === 0) return;
  const radarTabs = await findRadarTabs();
  if (radarTabs.length > 0) {
    let delivered = false;
    for (const tab of radarTabs) {
      try {
        await chrome.tabs.sendMessage(tab.id, {
          type: 'APPLY_PRICE_UPDATES',
          updates,
          reload,
        });
        delivered = true;
      } catch (_) {}
    }
    if (delivered) return;
  }
  // No open Deal Radar tab (or not ready) -- queue until user opens Deal Radar
  const res = await chrome.storage.local.get(['pending_updates']);
  const pending = Array.isArray(res.pending_updates) ? res.pending_updates : [];
  pending.push(...updates);
  await chrome.storage.local.set({ pending_updates: pending });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function waitForTabComplete(tabId, timeoutMs = 15000) {
  return new Promise((resolve) => {
    let done = false;
    const timer = setTimeout(() => {
      if (!done) {
        done = true;
        chrome.tabs.onUpdated.removeListener(listener);
        resolve(false);
      }
    }, timeoutMs);

    function listener(updatedId, info) {
      if (updatedId === tabId && info.status === 'complete' && !done) {
        done = true;
        clearTimeout(timer);
        chrome.tabs.onUpdated.removeListener(listener);
        resolve(true);
      }
    }
    chrome.tabs.onUpdated.addListener(listener);
  });
}

async function runBatchSync() {
  batchStopRequested = false;

  // Refresh watchlist from any open Deal Radar tab first
  const radarTabs = await findRadarTabs();
  for (const tab of radarTabs) {
    try {
      await chrome.tabs.sendMessage(tab.id, { type: 'GET_WATCHLIST' });
    } catch (_) {}
  }

  const stored = await chrome.storage.local.get(['watchlist_asins']);
  const items = Array.isArray(stored.watchlist_asins) ? stored.watchlist_asins : [];
  if (items.length === 0) {
    await chrome.storage.local.set({
      batch_status: {
        running: false,
        done: 0,
        total: 0,
        updated: 0,
        message: 'Open Deal Radar first so the extension can load your watchlist ASINs.',
      },
    });
    return;
  }

  await chrome.storage.local.set({
    batch_status: {
      running: true,
      done: 0,
      total: items.length,
      updated: 0,
      message: `Starting sync for ${items.length} Amazon products...`,
    },
  });

  const collected = [];
  let workerTab = null;

  try {
    workerTab = await chrome.tabs.create({
      url: 'about:blank',
      active: false,
    });

    for (let i = 0; i < items.length; i++) {
      if (batchStopRequested) break;
      const item = items[i];
      await chrome.storage.local.set({
        batch_status: {
          running: true,
          done: i,
          total: items.length,
          updated: collected.length,
          message: `Checking ${item.asin} (${i + 1}/${items.length})...`,
        },
      });

      const url = `https://www.amazon.com/dp/${item.asin}?psc=1`;
      const loadPromise = waitForTabComplete(workerTab.id, 15000);
      await chrome.tabs.update(workerTab.id, { url });
      await loadPromise;
      await sleep(1200);

      try {
        const resp = await chrome.tabs.sendMessage(workerTab.id, {
          type: 'SCRAPE_CURRENT_PAGE',
        });
        if (resp && resp.ok && resp.data && resp.data.current_price) {
          collected.push(resp.data);
        }
      } catch (_) {}

      await sleep(700);
    }
  } finally {
    if (workerTab && workerTab.id) {
      try {
        await chrome.tabs.remove(workerTab.id);
      } catch (_) {}
    }
  }

  if (collected.length > 0) {
    await deliverUpdates(collected, true);
  }

  await chrome.storage.local.set({
    batch_status: {
      running: false,
      done: items.length,
      total: items.length,
      updated: collected.length,
      lastSyncedAt: new Date().toISOString(),
      message: batchStopRequested
        ? `Stopped early. Synced ${collected.length} prices.`
        : `Done! Synced ${collected.length}/${items.length} live Amazon prices.`,
    },
  });
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (!msg || !msg.type) return;

  if (msg.type === 'SYNC_ITEM' && msg.payload) {
    deliverUpdates([msg.payload], true).then(() => sendResponse({ ok: true }));
    return true;
  }

  if (msg.type === 'START_BATCH_SYNC') {
    runBatchSync();
    sendResponse({ ok: true });
    return true;
  }

  if (msg.type === 'STOP_BATCH_SYNC') {
    batchStopRequested = true;
    sendResponse({ ok: true });
    return true;
  }
});
