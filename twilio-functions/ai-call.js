// PUBLIC function /ai-call — starts an outbound AI-agent call to ONE consented lead.
// Callers: the PowerLine app (form field `session`, allowed Origin) or a server
// such as n8n (header `Authorization: Bearer <AI_OUTBOUND_TOKEN>`).
//
// POST fields:
//   to                 lead phone (US/Canada; same dial rules as agents)
//   consent_timestamp  ISO date/time the lead gave prior express written consent (required)
//   consent_source     where consent was captured, e.g. "roofquote.com form" (required)
//   first_name         optional, used in the greeting
//   vertical           optional: roofing | solar | insurance | hvac | general
//   tz                 optional IANA zone of the lead (calling-hours check), e.g. America/Chicago
//
// Refuses: AI outbound off, no consent, DNC_NUMBERS match, outside AI_CALL_HOURS,
// blocked destinations. The call itself is answered by /ai-connect.

const crypto = require('crypto');

const VERTICALS = new Set(['roofing', 'solar', 'insurance', 'hvac', 'general']);

function safeEqual(a, b) {
  const x = Buffer.from(String(a || ''));
  const y = Buffer.from(String(b || ''));
  return x.length > 0 && x.length === y.length && crypto.timingSafeEqual(x, y);
}

exports.handler = async function (context, event, callback) {
  const { checkDestination, parseAgents } = require(Runtime.getFunctions()['dialrules'].path);
  const { verify, jsonResponse, originAllowed } = require(Runtime.getFunctions()['session'].path);
  const ai = require(Runtime.getFunctions()['ai'].path);
  const reply = (status, body) => callback(null, jsonResponse(context, event, status, body));

  // --- auth: PowerLine agent session, or server bearer token ---
  const headers = (event.request && event.request.headers) || {};
  const auth = String(headers.authorization || '');
  let actor = null;
  if (auth.startsWith('Bearer ') && context.AI_OUTBOUND_TOKEN && safeEqual(auth.slice(7).trim(), context.AI_OUTBOUND_TOKEN)) {
    actor = 'server';
  } else if (event.session) {
    if (!originAllowed(context, event)) return reply(403, { error: 'origin_not_allowed' });
    const payload = verify(event.session, context.SESSION_SECRET);
    if (payload && parseAgents(context.AGENTS).has(payload.sub)) actor = payload.sub;
  }
  if (!actor) return reply(401, { error: 'not_authorized' });

  if (!ai.outboundEnabled(context)) return reply(503, { error: 'ai_outbound_disabled' });

  // --- destination ---
  const dest = checkDestination(event.to, context.CALLER_ID);
  if (!dest.ok) return reply(422, { error: 'bad_destination', reason: dest.reason, message: dest.message });
  if (ai.dncSet(context).has(dest.e164)) return reply(422, { error: 'do_not_call' });

  // --- consent (FCC: AI-voice calls need prior express written consent) ---
  const consentAt = Date.parse(String(event.consent_timestamp || ''));
  const consentSource = String(event.consent_source || '').trim();
  if (!consentAt || consentAt > Date.now() + 5 * 60 * 1000 || consentSource.length < 3) {
    return reply(422, { error: 'consent_required', message: 'consent_timestamp and consent_source are required' });
  }

  // --- calling hours in the lead's time zone ---
  const tz = String(event.tz || '').trim() || undefined;
  if (!ai.withinCallingHours(context, tz)) {
    return reply(422, { error: 'outside_calling_hours', hours: context.AI_CALL_HOURS || '8-21' });
  }

  const vertical = VERTICALS.has(String(event.vertical || '').toLowerCase()) ? String(event.vertical).toLowerCase() : 'general';
  const firstName = String(event.first_name || '').replace(/[^A-Za-z' -]/g, '').trim().slice(0, 40);

  const qs = new URLSearchParams({ vertical });
  if (firstName) qs.set('first_name', firstName);

  try {
    const client = require('twilio')(context.TWILIO_API_KEY_SID, context.TWILIO_API_KEY_SECRET, {
      accountSid: context.TWILIO_ACCOUNT_SID,
    });
    const call = await client.calls.create({
      to: dest.e164,
      from: context.CALLER_ID,
      url: `https://${context.DOMAIN_NAME}/ai-connect?${qs.toString()}`,
      method: 'POST',
      machineDetection: 'Enable',
      timeout: 30,
      timeLimit: parseInt(context.AI_MAX_CALL_SECONDS || '900', 10),
    });
    console.log(`AI_CALL actor=${actor} npa=${dest.e164.slice(2, 5)} vertical=${vertical} consent_source=${consentSource.slice(0, 60)} sid=${call.sid}`);
    return reply(200, { ok: true, callSid: call.sid });
  } catch (err) {
    console.log(`AI_CALL_FAIL actor=${actor} code=${err && err.code}`);
    return reply(502, { error: 'call_failed', code: err && err.code });
  }
};
