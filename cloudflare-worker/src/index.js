/**
 * Deal Radar Public Cloudflare Worker Proxy (Zero-Setup for New Users)
 *
 * Endpoints:
 *   POST /api/trigger-refresh   -> Triggers GitHub Actions deploy-pages.yml (15-min global cooldown)
 *   POST /api/translate-intent  -> Optional Gemini Fuzzy Mode (per-IP rate limit)
 *   GET  /api/health            -> Status check
 *
 * Required Cloudflare Secrets (`npx wrangler secret put <NAME>`):
 *   GITHUB_PAT       - Fine-grained PAT with ONLY Actions: Read & Write on your repo
 *   GEMINI_API_KEY   - (Optional) Google AI Studio key for zero-setup Fuzzy Mode
 */

const ALLOWED_ORIGINS = new Set([
  'https://ericlee88.github.io',
  'http://localhost:8080',
  'http://127.0.0.1:8080',
]);

const COOLDOWN_SECONDS = 15 * 60; // 15 minutes global cooldown for workflow_dispatch
const FUZZY_IP_LIMIT_PER_HOUR = 10;

function corsHeaders(origin) {
  const allowed = ALLOWED_ORIGINS.has(origin) ? origin : 'https://ericlee88.github.io';
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Vary': 'Origin',
  };
}

function jsonResp(data, status, origin) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders(origin),
    },
  });
}

async function handleTriggerRefresh(request, env, origin) {
  if (!env.GITHUB_PAT) {
    return jsonResp(
      { ok: false, message: 'Worker missing GITHUB_PAT secret.' },
      503,
      origin
    );
  }

  const repo = env.GITHUB_REPO || 'ericlee88/deal-radar-black-friday';
  const branch = env.GITHUB_BRANCH || 'main';
  const workflow = env.GITHUB_WORKFLOW || 'deploy-pages.yml';

  // 1. Check global 15-min cooldown in Cloudflare Edge Cache
  const cache = caches.default;
  const cooldownKey = new Request('https://deal-radar-internal.local/cooldown/refresh');
  const cached = await cache.match(cooldownKey);
  if (cached) {
    const body = await cached.json().catch(() => ({}));
    const elapsedSec = Math.floor((Date.now() - (body.ts || 0)) / 1000);
    const remainMin = Math.max(1, Math.ceil((COOLDOWN_SECONDS - elapsedSec) / 60));
    return jsonResp(
      {
        ok: true,
        already_running: true,
        message: `Price refresh was triggered recently. Reload in ~${remainMin} min (15-min global cooldown).`,
      },
      202,
      origin
    );
  }

  const ghHeaders = {
    'Authorization': `Bearer ${env.GITHUB_PAT}`,
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'deal-radar-cloudflare-worker',
    'Content-Type': 'application/json',
  };

  // 2. Check if a workflow run is already in progress
  const runsResp = await fetch(
    `https://api.github.com/repos/${repo}/actions/workflows/${workflow}/runs?branch=${branch}&status=in_progress&per_page=1`,
    { headers: ghHeaders }
  );
  if (runsResp.ok) {
    const runsData = await runsResp.json();
    if ((runsData.total_count || 0) > 0) {
      return jsonResp(
        {
          ok: true,
          already_running: true,
          message: 'A live Gemini price check is already running on GitHub Actions! Reload in ~2-3 min.',
        },
        202,
        origin
      );
    }
  }

  // 3. Dispatch the workflow
  const dispatchResp = await fetch(
    `https://api.github.com/repos/${repo}/actions/workflows/${workflow}/dispatches`,
    {
      method: 'POST',
      headers: ghHeaders,
      body: JSON.stringify({ ref: branch }),
    }
  );

  if (dispatchResp.status === 204 || dispatchResp.status === 200) {
    // Store cooldown marker
    await cache.put(
      cooldownKey,
      new Response(JSON.stringify({ ts: Date.now() }), {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': `public, max-age=${COOLDOWN_SECONDS}`,
        },
      })
    );
    return jsonResp(
      {
        ok: true,
        message: 'Live Gemini price refresh triggered! New prices will publish in ~3-4 min.',
      },
      200,
      origin
    );
  }

  const errText = await dispatchResp.text();
  return jsonResp(
    {
      ok: false,
      message: `GitHub dispatch failed (HTTP ${dispatchResp.status}): ${errText.slice(0, 140)}`,
    },
    502,
    origin
  );
}

async function handleTranslateIntent(request, env, origin) {
  if (!env.GEMINI_API_KEY) {
    return jsonResp(
      { ok: false, message: 'Fuzzy Gemini mode is not configured on this worker.' },
      501,
      origin
    );
  }

  // Simple per-IP hourly rate limit via Edge Cache
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const cache = caches.default;
  const rateKey = new Request(`https://deal-radar-internal.local/rate/${encodeURIComponent(ip)}`);
  let count = 0;
  const cachedRate = await cache.match(rateKey);
  if (cachedRate) {
    const data = await cachedRate.json().catch(() => ({ count: 0 }));
    count = data.count || 0;
  }
  if (count >= FUZZY_IP_LIMIT_PER_HOUR) {
    return jsonResp(
      { ok: false, message: 'Hourly fuzzy search limit reached. Try again later or paste an Amazon URL.' },
      429,
      origin
    );
  }

  const body = await request.json().catch(() => ({}));
  const rawIntent = String(body.raw_intent || '').trim();
  if (!rawIntent) {
    return jsonResp({ ok: false, message: 'raw_intent is required.' }, 400, origin);
  }

  const model = env.GEMINI_MODEL || 'gemini-3.8-flash';
  const prompt = `You are a Black Friday Amazon shopping analyst.
User intent: "${rawIntent}"
Return ONLY a raw JSON object (no markdown) with 2 concrete candidate products to compare:
{
  "title": "Short mission title",
  "decision_framing": "1-sentence buying trade-off summary",
  "options": [
    {
      "branch_label": "Pick #1 | Best Overall",
      "is_recommended_branch": true,
      "title": "Exact Product Name",
      "asin_or_sku": "10-char B0... ASIN if certain, else empty string",
      "strike_price": 0,
      "scout_notes": "1-sentence why this is a strong pick"
    }
  ]
}`;

  const gemResp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2, responseMimeType: 'application/json' },
      }),
    }
  );

  if (!gemResp.ok) {
    return jsonResp({ ok: false, message: `Gemini HTTP ${gemResp.status}` }, 502, origin);
  }

  await cache.put(
    rateKey,
    new Response(JSON.stringify({ count: count + 1 }), {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'public, max-age=3600',
      },
    })
  );

  const gemJson = await gemResp.json();
  const text = gemJson?.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
  try {
    const spec = JSON.parse(text);
    return jsonResp({ ok: true, spec }, 200, origin);
  } catch (_) {
    return jsonResp({ ok: false, message: 'Failed to parse Gemini JSON.' }, 502, origin);
  }
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    const url = new URL(request.url);
    if (url.pathname === '/api/health') {
      return jsonResp(
        {
          ok: true,
          refresh_enabled: Boolean(env.GITHUB_PAT),
          fuzzy_gemini_enabled: Boolean(env.GEMINI_API_KEY),
        },
        200,
        origin
      );
    }
    if (url.pathname === '/api/trigger-refresh' && request.method === 'POST') {
      return handleTriggerRefresh(request, env, origin);
    }
    if (url.pathname === '/api/translate-intent' && request.method === 'POST') {
      return handleTranslateIntent(request, env, origin);
    }

    return jsonResp({ ok: false, message: 'Not found' }, 404, origin);
  },
};
