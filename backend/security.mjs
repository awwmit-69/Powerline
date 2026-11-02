const encoder = new TextEncoder();
const jwksCache = new Map();
export class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
export const fail = (status, message) => { throw new HttpError(status, message); };
export const e164 = value => typeof value === 'string' && /^\+[1-9]\d{7,14}$/.test(value);
export const isStop = value => /^(stop|stopall|unsubscribe|cancel|end|quit|revoke|optout)$/i.test(String(value).trim());
export function bytes64(value) { return Uint8Array.from(atob(value.replace(/-/g,'+').replace(/_/g,'/')), c => c.charCodeAt(0)); }
export function base64url(value) { return btoa(String.fromCharCode(...value)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_'); }
export async function hmac(secret, data, hash = 'SHA-256') {
  const key = await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash},false,['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC',key,encoder.encode(data)));
}
export async function authenticate(request, env, fetcher = fetch) {
  if (!env.ACCESS_ISSUER || !env.ACCESS_AUD) fail(503,'Authentication is not configured');
  const issuer = new URL(env.ACCESS_ISSUER);
  if (issuer.protocol !== 'https:' || !issuer.hostname.endsWith('.cloudflareaccess.com') || issuer.pathname !== '/') fail(503,'Invalid authentication configuration');
  const token = request.headers.get('Cf-Access-Jwt-Assertion');
  if (!token || token.length > 16384) fail(401,'Sign in required');
  try {
    const parts = token.split('.');
    if (parts.length !== 3) fail(401,'Invalid session');
    const header = JSON.parse(new TextDecoder().decode(bytes64(parts[0])));
    const claims = JSON.parse(new TextDecoder().decode(bytes64(parts[1])));
    const now = Math.floor(Date.now()/1000);
    if (header.alg !== 'RS256' || typeof header.kid !== 'string' || claims.iss !== env.ACCESS_ISSUER || !Number.isFinite(claims.exp) || claims.exp <= now || (claims.nbf && claims.nbf > now) || !(Array.isArray(claims.aud) ? claims.aud : [claims.aud]).includes(env.ACCESS_AUD) || typeof claims.email !== 'string' || !claims.sub) fail(401,'Invalid session');
    let cached = jwksCache.get(env.ACCESS_ISSUER);
    if (!cached || cached.until < Date.now()) {
      const response = await fetcher(new URL('/cdn-cgi/access/certs',issuer));
      if (!response.ok) fail(503,'Identity service unavailable');
      cached = {keys:(await response.json()).keys,until:Date.now()+300000};
      jwksCache.set(env.ACCESS_ISSUER,cached);
    }
    const jwk = cached.keys.find(k => k.kid === header.kid && k.kty === 'RSA');
    if (!jwk) fail(401,'Invalid session');
    const key = await crypto.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
    if (!await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,bytes64(parts[2]),encoder.encode(parts[0]+'.'+parts[1]))) fail(401,'Invalid session');
    return claims;
  } catch(error) { if (error instanceof HttpError) throw error; fail(401,'Invalid session'); }
}
export async function validateWebhook(request, env) {
  if (!env.TWILIO_AUTH_TOKEN || !env.PUBLIC_ORIGIN) fail(503,'Provider not configured');
  if (request.method !== 'POST') fail(405,'POST required');
  if (!(request.headers.get('Content-Type') || '').startsWith('application/x-www-form-urlencoded')) fail(415,'Form body required');
  const url = new URL(request.url);
  if (url.origin !== env.PUBLIC_ORIGIN) fail(403,'Invalid webhook origin');
  const raw = await request.text();
  if (raw.length > 16384) fail(413,'Payload too large');
  const params = new URLSearchParams(raw);
  let signed = url.href;
  for (const key of [...new Set(params.keys())].sort()) {
    for (const value of [...new Set(params.getAll(key))].sort()) signed += key+value;
  }
  const expected = await hmac(env.TWILIO_AUTH_TOKEN,signed,'SHA-1');
  let actual;
  try {actual = bytes64(request.headers.get('X-Twilio-Signature') || '');} catch {fail(403,'Invalid webhook signature');}
  let difference = expected.length ^ actual.length;
  for (let i=0;i<expected.length;i++) difference |= expected[i] ^ (actual[i] || 0);
  if (difference) fail(403,'Invalid webhook signature');
  if (params.get('AccountSid') !== env.TWILIO_ACCOUNT_SID) fail(403,'Wrong provider account');
  return params;
}
