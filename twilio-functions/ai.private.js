// Shared AI-agent helpers (deploy as PRIVATE function at path /ai).
// Bridges Twilio calls to an ElevenLabs Conversational AI agent using the
// "register call" API: ElevenLabs returns TwiML that streams the call audio to
// the agent. The agent must use μ-law 8000 Hz input and output.
//
// Env: ELEVENLABS_API_KEY (secret), ELEVENLABS_AGENT_ID,
//      AI_INBOUND=on|off (default on), AI_OUTBOUND=on|off (default off),
//      AI_CALL_HOURS=8-21 (recipient local hours), AI_DEFAULT_TZ, DNC_NUMBERS.

const REGISTER_URL = 'https://api.elevenlabs.io/v1/convai/twilio/register-call';

function aiConfigured(context) {
  return Boolean(context.ELEVENLABS_API_KEY && context.ELEVENLABS_AGENT_ID);
}

function flag(value, fallback) {
  const v = String(value || '').trim().toLowerCase();
  if (!v) return fallback;
  return ['on', 'true', '1', 'yes'].includes(v);
}

function inboundEnabled(context) {
  return aiConfigured(context) && flag(context.AI_INBOUND, true);
}

function outboundEnabled(context) {
  return aiConfigured(context) && flag(context.AI_OUTBOUND, false);
}

// Only string/number/boolean values, trimmed and length-capped.
function cleanVars(vars) {
  const out = {};
  for (const [k, v] of Object.entries(vars || {})) {
    if (v === undefined || v === null || v === '') continue;
    if (!/^[a-z_][a-z0-9_]{0,40}$/i.test(k)) continue;
    out[k] = typeof v === 'string' ? v.trim().slice(0, 200) : v;
  }
  return out;
}

// Returns TwiML (string) from ElevenLabs, or null on any failure so callers can
// fall back to voicemail / hang up gracefully. Never logs the API key.
async function registerCall(context, { from, to, direction, vars }, fetchImpl) {
  if (!aiConfigured(context)) return null;
  const doFetch = fetchImpl || fetch;
  const body = {
    agent_id: context.ELEVENLABS_AGENT_ID,
    from_number: String(from || ''),
    to_number: String(to || ''),
    direction: direction === 'outbound' ? 'outbound' : 'inbound',
  };
  const dynamic = cleanVars(vars);
  if (Object.keys(dynamic).length) {
    body.conversation_initiation_client_data = { dynamic_variables: dynamic };
  }
  const controller = typeof AbortController === 'function' ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), 8000) : null;
  try {
    const res = await doFetch(REGISTER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'xi-api-key': context.ELEVENLABS_API_KEY },
      body: JSON.stringify(body),
      signal: controller ? controller.signal : undefined,
    });
    const text = await res.text();
    if (!res.ok) {
      console.log(`AI_REGISTER_FAIL status=${res.status} dir=${body.direction} detail=${text.slice(0, 200)}`);
      return null;
    }
    // Endpoint returns TwiML; some SDKs JSON-encode it as a string.
    let twiml = text.trim();
    if (twiml.startsWith('"')) {
      try { twiml = JSON.parse(twiml); } catch (_) { /* keep raw */ }
    }
    if (!/<Response[\s>]/.test(twiml)) {
      console.log(`AI_REGISTER_FAIL unexpected_body dir=${body.direction}`);
      return null;
    }
    return twiml;
  } catch (err) {
    console.log(`AI_REGISTER_FAIL error=${err && err.name} dir=${body.direction}`);
    return null;
  } finally {
    if (timer) clearTimeout(timer);
  }
}

// Wraps raw TwiML so it can be returned from a Function callback.
function rawTwimlResponse(xml) {
  const response = new Twilio.Response();
  response.setStatusCode(200);
  response.appendHeader('Content-Type', 'text/xml');
  response.setBody(xml);
  return response;
}

function dncSet(context) {
  return new Set(
    String(context.DNC_NUMBERS || '')
      .split(',')
      .map((s) => s.replace(/[^\d+]/g, ''))
      .filter(Boolean),
  );
}

// True when the recipient's local hour is inside AI_CALL_HOURS (default 8-21,
// i.e. 8:00 to 20:59). Unknown/invalid tz falls back to AI_DEFAULT_TZ.
function withinCallingHours(context, tz, now) {
  const [startH, endH] = String(context.AI_CALL_HOURS || '8-21').split('-').map((n) => parseInt(n, 10));
  const zone = tz || context.AI_DEFAULT_TZ || 'America/New_York';
  let hour;
  try {
    hour = parseInt(
      new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone: zone }).format(now || new Date()),
      10,
    );
  } catch (_) {
    return false;
  }
  return hour >= startH && hour < endH;
}

module.exports = {
  aiConfigured,
  inboundEnabled,
  outboundEnabled,
  registerCall,
  rawTwimlResponse,
  dncSet,
  withinCallingHours,
  cleanVars,
};
