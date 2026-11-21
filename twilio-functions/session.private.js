// Agent session helpers (deploy as PRIVATE function at path /session).
// Stateless HS256 session tokens signed with SESSION_SECRET (env, >= 32 chars).
// CORS helpers restrict browser access to ALLOWED_ORIGINS.

const crypto = require('crypto');

const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const fromB64url = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

function requireSecret(secret) {
  if (!secret || String(secret).length < 32) throw new Error('SESSION_SECRET missing or too short');
  return String(secret);
}

function sign(payload, secret, ttlSeconds) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify({ ...payload, typ: 'pl-session', iat: now, exp: now + ttlSeconds }));
  const sig = b64url(crypto.createHmac('sha256', requireSecret(secret)).update(`${header}.${body}`).digest());
  return `${header}.${body}.${sig}`;
}

// Returns payload or null.
function verify(token, secret) {
  try {
    const parts = String(token || '').split('.');
    if (parts.length !== 3) return null;
    const [header, body, sig] = parts;
    const expected = crypto.createHmac('sha256', requireSecret(secret)).update(`${header}.${body}`).digest();
    const given = fromB64url(sig);
    if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
    const h = JSON.parse(fromB64url(header).toString('utf8'));
    if (h.alg !== 'HS256') return null;
    const payload = JSON.parse(fromB64url(body).toString('utf8'));
    if (payload.typ !== 'pl-session' || typeof payload.sub !== 'string') return null;
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

function allowedOrigins(context) {
  return String(context.ALLOWED_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

// Builds a JSON response with CORS for allowed origins only.
function jsonResponse(context, event, status, body) {
  const response = new Twilio.Response();
  response.setStatusCode(status);
  response.appendHeader('Content-Type', 'application/json');
  response.appendHeader('Cache-Control', 'no-store');
  const origin = event && event.request && event.request.headers && event.request.headers.origin;
  if (origin && allowedOrigins(context).includes(origin)) {
    response.appendHeader('Access-Control-Allow-Origin', origin);
    response.appendHeader('Vary', 'Origin');
  }
  response.setBody(body);
  return response;
}

function originAllowed(context, event) {
  const origin = event && event.request && event.request.headers && event.request.headers.origin;
  // Non-browser callers (no Origin) are allowed only if explicitly enabled for testing.
  if (!origin) return String(context.ALLOW_NO_ORIGIN || '') === 'true';
  return allowedOrigins(context).includes(origin);
}

module.exports = { sign, verify, jsonResponse, originAllowed };
