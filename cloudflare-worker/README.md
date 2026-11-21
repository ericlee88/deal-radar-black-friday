# Deal Radar Public Proxy — Cloudflare Worker (Free Tier)

Lets **any visitor** click **Refresh Prices** (and optionally use **Gemini Fuzzy Mode**) on https://ericlee88.github.io/deal-radar-black-friday/ without needing a GitHub token or Gemini API key.

## 60-Second Deploy
1. Create a fine-grained GitHub PAT (`github.com/settings/personal-access-tokens/new`) scoped **only** to `ericlee88/deal-radar-black-friday` with permission **Actions: Read and write**.
2. Deploy the Worker:
   ```bash
   cd cloudflare-worker
   npx wrangler login
   npx wrangler secret put GITHUB_PAT
   # Optional: enable zero-key Gemini Fuzzy Mode for new users too
   npx wrangler secret put GEMINI_API_KEY
   npx wrangler deploy
   ```
3. Copy the deployed Worker URL (e.g. `https://deal-radar-proxy.<your-subdomain>.workers.dev`).
4. In GitHub (`Settings → Secrets and variables → Actions → Variables`), add a **Repository Variable**:
   - Name: `PUBLIC_WORKER_URL`
   - Value: `https://deal-radar-proxy.<your-subdomain>.workers.dev`
5. Re-run the **Deploy Deal Radar to GitHub Pages** workflow once — the live site will automatically use your Worker for all visitors!
