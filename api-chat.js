/**
 * LearnCraft — Anthropic API Proxy
 * Vercel Edge Function: /api/chat.js
 *
 * This keeps your ANTHROPIC_API_KEY server-side and never exposed to the browser.
 * Add ANTHROPIC_API_KEY to Vercel → Settings → Environment Variables.
 *
 * Usage in learncraft-full.html:
 *   Change: fetch("https://api.anthropic.com/v1/messages", ...)
 *   To:     fetch("/api/chat", ...)
 *   And remove the x-api-key header from the browser request.
 */

export const config = { runtime: 'edge' };

const ALLOWED_MODELS = [
  'claude-opus-4-6',
  'claude-sonnet-4-6',
  'claude-haiku-4-5-20251001',
];

const RATE_LIMIT_REQUESTS = 20;    // requests per window
const RATE_LIMIT_WINDOW   = 60000; // 1 minute in ms
const rateLimitMap = new Map();    // In-memory (resets on cold start; use KV for production)

export default async function handler(req) {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
    });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
  }

  // Basic rate limiting by IP
  const ip = req.headers.get('x-forwarded-for') || 'unknown';
  const now = Date.now();
  const windowData = rateLimitMap.get(ip) || { count: 0, windowStart: now };

  if (now - windowData.windowStart > RATE_LIMIT_WINDOW) {
    windowData.count = 0;
    windowData.windowStart = now;
  }

  if (windowData.count >= RATE_LIMIT_REQUESTS) {
    return new Response(JSON.stringify({ error: 'Rate limit exceeded. Please wait a minute.' }), {
      status: 429,
      headers: { 'Retry-After': '60' },
    });
  }

  windowData.count++;
  rateLimitMap.set(ip, windowData);

  // Parse and validate request body
  let body;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), { status: 400 });
  }

  // Validate model
  if (!ALLOWED_MODELS.includes(body.model)) {
    body.model = 'claude-haiku-4-5-20251001'; // Fallback to cheapest
  }

  // Cap max_tokens for cost control
  body.max_tokens = Math.min(body.max_tokens || 1000, 2000);

  // Forward to Anthropic
  try {
    const anthropicResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
    });

    const data = await anthropicResponse.json();

    return new Response(JSON.stringify(data), {
      status: anthropicResponse.status,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: 'Failed to reach AI service', details: String(error) }), {
      status: 502,
    });
  }
}
