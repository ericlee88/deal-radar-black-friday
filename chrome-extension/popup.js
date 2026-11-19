// Popup controller for Deal Radar Live Price Sync
const RADAR_URL = 'https://ericlee88.github.io/deal-radar-black-friday/';

const pageContent = document.getElementById('pageContent');
const syncCurrentBtn = document.getElementById('syncCurrentBtn');
const pageStatus = document.getElementById('pageStatus');
const watchlistInfo = document.getElementById('watchlistInfo');
const progressWrap = document.getElementById('progressWrap');
const progressBar = document.getElementById('progressBar');
const batchStatus = document.getElementById('batchStatus');
const syncAllBtn = document.getElementById('syncAllBtn');
const stopBtn = document.getElementById('stopBtn');
const openRadarBtn = document.getElementById('openRadarBtn');

let currentScraped = null;

async function inspectActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url) return;

  const isAmazon = /^https:\/\/www\.amazon\.com\//.test(tab.url);
  const isCamel = /^https:\/\/camelcamelcamel\.com\/product\//.test(tab.url);

  if (!isAmazon && !isCamel) {
    pageContent.textContent =
      'Navigate to any Amazon product page or CamelCamelCamel page to sync its live price.';
    syncCurrentBtn.classList.add('hidden');
    return;
  }

  try {
    const resp = await chrome.tabs.sendMessage(tab.id, { type: 'SCRAPE_CURRENT_PAGE' });
    if (resp && resp.ok && resp.data) {
      currentScraped = resp.data;
      const d = resp.data;
      const priceText = d.current_price ? `$${d.current_price.toFixed(2)}` : 'Price N/A';
      const extra = [];
      if (d.clip_coupon_amount > 0) extra.push(`Coupon -$${d.clip_coupon_amount.toFixed(2)}`);
      if (d.all_time_low) extra.push(`ATL $${d.all_time_low.toFixed(2)}`);
      if (d.avg_90d_price) extra.push(`Avg $${d.avg_90d_price.toFixed(2)}`);

      pageContent.innerHTML = `
        <div class="title">${escapeHtml(d.title || d.asin)}</div>
        <div class="price">${priceText}</div>
        <div class="muted">ASIN: ${escapeHtml(d.asin)}${extra.length ? ' | ' + extra.join(' | ') : ''}</div>
      `;
      syncCurrentBtn.classList.remove('hidden');
    } else {
      pageContent.textContent = 'No product ASIN detected on this page.';
    }
  } catch (_) {
    pageContent.textContent = 'Reload this Amazon/CCC tab once after installing the extension.';
  }
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function renderStorageState(res) {
  const list = Array.isArray(res.watchlist_asins) ? res.watchlist_asins : [];
  if (list.length === 0) {
    watchlistInfo.textContent =
      'No watchlist synced yet. Open Deal Radar once to load your tracked ASINs.';
  } else {
    watchlistInfo.textContent = `${list.length} tracked Amazon ASINs ready for live browser price checks.`;
  }

  const status = res.batch_status;
  if (status) {
    batchStatus.classList.remove('hidden');
    batchStatus.textContent = status.message || '';
    if (status.running) {
      syncAllBtn.classList.add('hidden');
      stopBtn.classList.remove('hidden');
      progressWrap.classList.remove('hidden');
      const pct = status.total > 0 ? Math.round((status.done / status.total) * 100) : 0;
      progressBar.style.width = `${pct}%`;
    } else {
      syncAllBtn.classList.remove('hidden');
      stopBtn.classList.add('hidden');
      if (status.total > 0) {
        progressWrap.classList.remove('hidden');
        progressBar.style.width = '100%';
      }
    }
  }
}

syncCurrentBtn.addEventListener('click', () => {
  if (!currentScraped) return;
  syncCurrentBtn.disabled = true;
  chrome.runtime.sendMessage({ type: 'SYNC_ITEM', payload: currentScraped }, (resp) => {
    syncCurrentBtn.disabled = false;
    pageStatus.classList.remove('hidden');
    pageStatus.textContent =
      resp && resp.ok
        ? 'Saved to Deal Radar! (Will auto-apply if tab is open or next time you open it.)'
        : 'Sync failed.';
  });
});

syncAllBtn.addEventListener('click', () => {
  chrome.runtime.sendMessage({ type: 'START_BATCH_SYNC' });
});

stopBtn.addEventListener('click', () => {
  chrome.runtime.sendMessage({ type: 'STOP_BATCH_SYNC' });
});

openRadarBtn.addEventListener('click', () => {
  chrome.tabs.create({ url: RADAR_URL });
});

chrome.storage.onChanged.addListener(() => {
  chrome.storage.local.get(['watchlist_asins', 'batch_status'], renderStorageState);
});

chrome.storage.local.get(['watchlist_asins', 'batch_status'], renderStorageState);
inspectActiveTab();
