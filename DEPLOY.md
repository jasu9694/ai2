# 🚀 LearnCraft — Production Deployment Guide

**Stack:** Clerk Auth · Supabase (Postgres) · Vercel · Pyodide (in-browser Python)  
**Estimated time:** 30–45 minutes for a full production deploy  
**Cost at 10,000 users:** ~$0/month (all free tiers comfortably cover this)

---

## Architecture Overview

```
User browser
    │
    ├─ Clerk JS SDK ──────────── Authentication (login, signup, sessions)
    │
    ├─ Supabase JS Client ──────── Postgres DB (XP, progress, bookmarks)
    │
    ├─ Pyodide (WebAssembly) ──── Runs Python CODE in the user's browser
    │                              Zero server cost. 10,000 users = 0 compute on our side.
    │
    └─ Anthropic API ──────────── AI Interview Practice (Claude)
           └─ Proxied via Vercel Edge Function (keeps API key server-side)

Vercel CDN ──────────────────── Serves the HTML globally from nearest edge
```

---

## Step 1 — Clerk (Authentication)

1. Go to **[clerk.com](https://clerk.com)** → Create account → Create application
2. Name it `LearnCraft`
3. Enable: **Email/Password** + **Google** + **GitHub** sign-in methods
4. In your Clerk dashboard → **API Keys** → copy your **Publishable Key** (starts with `pk_live_` or `pk_test_`)
5. Open `learncraft-full.html`, find line:
   ```js
   const CLERK_PUBLISHABLE_KEY = 'YOUR_CLERK_PUBLISHABLE_KEY';
   ```
   Replace with your actual key:
   ```js
   const CLERK_PUBLISHABLE_KEY = 'pk_live_xxxxxxxxxxxx';
   ```
6. Also update the `<script>` tag in the HTML head:
   ```html
   data-clerk-publishable-key="pk_live_xxxxxxxxxxxx"
   ```

**Free tier:** Up to **10,000 Monthly Active Users** — free forever.

---

## Step 2 — Supabase (Database)

1. Go to **[supabase.com](https://supabase.com)** → Create account → New project
2. Name: `learncraft` | Region: pick closest to your users | Set a strong DB password
3. Wait ~2 minutes for the project to provision

### Run the schema

4. In Supabase dashboard → **SQL Editor** → New query
5. Paste the entire contents of **`supabase-schema.sql`** → Run
6. You should see all 6 tables created with RLS policies ✓

### Get your keys

7. Go to **Settings → API**
8. Copy:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon / public** key (safe to use in the browser)

9. Update `learncraft-full.html`:
   ```js
   const SUPABASE_URL      = 'https://abcdefgh.supabase.co';
   const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6...';
   ```

**Free tier:** 500MB database, 5GB bandwidth, 50,000 monthly active users — free forever.

---

## Step 3 — Vercel (Hosting)

### Option A: Deploy via Vercel CLI (fastest)

```bash
# Install Vercel CLI
npm install -g vercel

# Navigate to your project folder
cd your-learncraft-folder

# Deploy
vercel

# Follow prompts:
# - Link to existing project? No
# - Project name: learncraft
# - Directory: ./
# - Override settings? No
```

Your site is live at `https://learncraft.vercel.app` in ~30 seconds.

### Option B: Deploy via GitHub (recommended for teams)

1. Push your files to a GitHub repo:
   ```bash
   git init
   git add learncraft-full.html vercel.json
   git commit -m "Initial deployment"
   git remote add origin https://github.com/yourusername/learncraft
   git push -u origin main
   ```
2. Go to **[vercel.com](https://vercel.com)** → Import Git Repository
3. Select your repo → Deploy
4. Every `git push` auto-deploys. Zero downtime.

### Custom domain (optional)

1. Vercel dashboard → your project → Settings → Domains
2. Add `learncraft.io` (or whatever you own)
3. Update your domain's DNS records as shown by Vercel
4. SSL certificate is auto-generated ✓

**Free tier:** 100GB bandwidth/month, unlimited deployments — free forever.

---

## Step 4 — Secure the Anthropic API Key

Right now the Anthropic API key lives in the browser (visible to users). For production, proxy it through a Vercel Edge Function:

### Create `/api/chat.js` in your project:

```js
// api/chat.js — Vercel Edge Function
export const config = { runtime: 'edge' };

export default async function handler(req) {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  
  const body = await req.json();
  
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,    // ← server-side only
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify(body),
  });
  
  const data = await response.json();
  return new Response(JSON.stringify(data), {
    headers: { 'Content-Type': 'application/json' },
  });
}
```

### Add to Vercel:
1. Vercel Dashboard → your project → Settings → Environment Variables
2. Add: `ANTHROPIC_API_KEY` = `sk-ant-xxxxxxxxxxxx`

### Update the fetch in `learncraft-full.html`:
```js
// Change:
const response = await fetch("https://api.anthropic.com/v1/messages", {
// To:
const response = await fetch("/api/chat", {
// (remove the x-api-key header — the edge function adds it server-side)
```

---

## Step 5 — Pyodide (Python Execution)

Pyodide is already integrated — no setup needed. It runs Python in the user's browser via WebAssembly. The first click on "Run Code" downloads Pyodide (~10MB, cached by the browser forever after).

**For Java/C++/other languages (future):** Use the [Piston API](https://github.com/engineer-man/piston):
```js
const response = await fetch('https://emkc.org/api/v2/piston/execute', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    language: 'java', version: '*',
    files: [{ content: userCode }],
  }),
});
```

---

## Environment Variables Summary

| Variable | Where to get it | Where to put it |
|---|---|---|
| `CLERK_PUBLISHABLE_KEY` | Clerk Dashboard → API Keys | `learncraft-full.html` (line ~300) |
| `SUPABASE_URL` | Supabase → Settings → API | `learncraft-full.html` (line ~301) |
| `SUPABASE_ANON_KEY` | Supabase → Settings → API | `learncraft-full.html` (line ~302) |
| `ANTHROPIC_API_KEY` | console.anthropic.com | Vercel Environment Variables (never in HTML!) |

---

## Scaling Estimates

| Users | Clerk | Supabase | Vercel | Monthly Cost |
|---|---|---|---|---|
| 100 | Free | Free | Free | **$0** |
| 1,000 | Free | Free | Free | **$0** |
| 10,000 | Free | Free | Free | **$0** |
| 50,000 | ~$25/mo | ~$25/mo | Free | **~$50** |
| 100,000 | ~$100/mo | ~$100/mo | ~$20/mo | **~$220** |

Python execution (Pyodide) costs $0 at any scale — it runs on users' machines.

---

## Checklist Before Going Live

- [ ] Replace `YOUR_CLERK_PUBLISHABLE_KEY` with real key in HTML
- [ ] Replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` in HTML
- [ ] Run `supabase-schema.sql` in Supabase SQL Editor
- [ ] Move `ANTHROPIC_API_KEY` to Vercel env vars + create `/api/chat.js` proxy
- [ ] Deploy to Vercel
- [ ] Add custom domain (optional)
- [ ] Test signup → lesson → assessment → interview flow end-to-end
- [ ] Check Supabase Table Editor to confirm data is being saved

---

## Support

- **Clerk docs:** https://clerk.com/docs
- **Supabase docs:** https://supabase.com/docs
- **Vercel docs:** https://vercel.com/docs
- **Pyodide docs:** https://pyodide.org/en/stable/
