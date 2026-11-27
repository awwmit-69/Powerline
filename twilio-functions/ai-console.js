// PUBLIC function /ai-console — the PowerLine "Maya" screen.
// Auth: signed-in PowerLine agent (form field `session`, allowed Origin).
// Editing Maya's script is limited to AI_ADMINS (agent ids, comma list;
// defaults to the first agent in AGENTS).
//
// Actions (field `action`):
//   calls            { cursor? }        Maya's calls, newest first (ElevenLabs)
//   call             { id }             transcript, summary, collected data
//   call_audio       { id }             recording, base64 mp3
//   voicemails       {}                 Twilio voicemail recordings
//   voicemail_audio  { sid }            voicemail, base64 mp3
//   bookings         {}                 upcoming PowerLine bookings
//   flow_get         {}                 Maya's greeting + script + switches
//   flow_set         { first_message, prompt }   admins only; goes live on the next call

const EL = 'https://api.elevenlabs.io/v1/convai';
const MAX_AUDIO_BYTES = 4 * 1024 * 1024;

const clean = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

function admins(context, parseAgents) {
  const list = String(context.AI_ADMINS || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  if (list.length) return new Set(list);
  const first = [...parseAgents(context.AGENTS).keys()][0];
  return new Set(first ? [first] : []);
}

async function el(context, path, opts = {}, fetchImpl) {
  const doFetch = fetchImpl || fetch;
  const res = await doFetch(`${EL}${path}`, {
    ...opts,
    headers: { 'xi-api-key': context.ELEVENLABS_API_KEY, ...(opts.body ? { 'Content-Type': 'application/json' } : {}) },
  });
  if (!res.ok) throw new Error(`elevenlabs_${res.status}`);
  return res;
}

function summarizeConversation(c) {
  return {
    id: c.conversation_id,
    started: c.start_time_unix_secs ? new Date(c.start_time_unix_secs * 1000).toISOString() : null,
    seconds: c.call_duration_secs || 0,
    status: c.status || '',
    result: c.call_successful || '',
    title: c.call_summary_title || c.transcript_summary || '',
    direction: c.direction || '',
  };
}

exports.handler = async function (context, event, callback) {
  const { verify, jsonResponse, originAllowed } = require(Runtime.getFunctions()['session'].path);
  const { parseAgents } = require(Runtime.getFunctions()['dialrules'].path);
  const ai = require(Runtime.getFunctions()['ai'].path);
  const reply = (status, body) => callback(null, jsonResponse(context, event, status, body));

  if (!originAllowed(context, event)) return reply(403, { error: 'origin_not_allowed' });
  const payload = verify(event.session, context.SESSION_SECRET);
  if (!payload || !parseAgents(context.AGENTS).has(payload.sub)) return reply(401, { error: 'not_authorized' });
  const agent = payload.sub;
  const isAdmin = admins(context, parseAgents).has(agent);
  const action = clean(event.action, 20);

  try {
    if (['calls', 'call', 'call_audio', 'flow_get', 'flow_set'].includes(action) && !ai.aiConfigured(context)) {
      return reply(503, { error: 'ai_not_configured' });
    }

    if (action === 'calls') {
      const qs = new URLSearchParams({ agent_id: context.ELEVENLABS_AGENT_ID, page_size: '30' });
      const cursor = clean(event.cursor, 200);
      if (cursor) qs.set('cursor', cursor);
      const json = await (await el(context, `/conversations?${qs}`)).json();
      return reply(200, {
        calls: (json.conversations || []).map(summarizeConversation),
        next_cursor: json.has_more ? json.next_cursor : null,
      });
    }

    if (action === 'call') {
      const id = clean(event.id, 80);
      if (!/^[\w-]+$/.test(id)) return reply(422, { error: 'bad_id' });
      const c = await (await el(context, `/conversations/${id}`)).json();
      const meta = c.metadata || {};
      const phone = meta.phone_call || {};
      const analysis = c.analysis || {};
      const collected = {};
      for (const [k, v] of Object.entries(analysis.data_collection_results || {})) {
        if (v && v.value !== undefined && v.value !== null && v.value !== '') collected[k] = v.value;
      }
      return reply(200, {
        id: c.conversation_id || id,
        started: meta.start_time_unix_secs ? new Date(meta.start_time_unix_secs * 1000).toISOString() : null,
        seconds: meta.call_duration_secs || 0,
        caller: phone.external_number || '',
        line: phone.agent_number || '',
        direction: phone.direction || '',
        result: analysis.call_successful || '',
        summary: analysis.transcript_summary || '',
        collected,
        has_audio: c.has_audio !== false,
        transcript: (c.transcript || [])
          .filter((t) => t && t.message)
          .map((t) => ({ who: t.role === 'agent' ? 'Maya' : 'Caller', text: t.message, at: t.time_in_call_secs || 0 })),
      });
    }

    if (action === 'call_audio') {
      const id = clean(event.id, 80);
      if (!/^[\w-]+$/.test(id)) return reply(422, { error: 'bad_id' });
      const buf = Buffer.from(await (await el(context, `/conversations/${id}/audio`)).arrayBuffer());
      if (buf.length > MAX_AUDIO_BYTES) return reply(413, { error: 'too_large', message: 'Recording is too long to stream here. Open it in ElevenLabs → Call history.' });
      return reply(200, { mime: 'audio/mpeg', base64: buf.toString('base64') });
    }

    if (action === 'voicemails' || action === 'voicemail_audio') {
      const client = require(Runtime.getFunctions()['calendar'].path).twilioClient(context);
      if (action === 'voicemails') {
        const recs = await client.recordings.list({ limit: 30 });
        return reply(200, {
          voicemails: recs.map((r) => ({ sid: r.sid, call_sid: r.callSid, started: r.dateCreated, seconds: parseInt(r.duration || '0', 10) })),
        });
      }
      const sid = clean(event.sid, 40);
      if (!/^RE[0-9a-f]{32}$/i.test(sid)) return reply(422, { error: 'bad_sid' });
      const auth = Buffer.from(`${context.TWILIO_API_KEY_SID}:${context.TWILIO_API_KEY_SECRET}`).toString('base64');
      const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${context.TWILIO_ACCOUNT_SID}/Recordings/${sid}.mp3`, { headers: { Authorization: `Basic ${auth}` } });
      if (!res.ok) return reply(502, { error: 'recording_unavailable' });
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length > MAX_AUDIO_BYTES) return reply(413, { error: 'too_large' });
      return reply(200, { mime: 'audio/mpeg', base64: buf.toString('base64') });
    }

    if (action === 'bookings') {
      const cal = require(Runtime.getFunctions()['calendar'].path);
      if (!cal.calendarConfigured(context)) return reply(503, { error: 'booking_not_configured' });
      const { tz } = cal.config(context);
      const items = await cal.listBookings(context, {});
      return reply(200, {
        bookings: items.slice(0, 100).map((e) => {
          const p = cal.eventProps(e);
          return { id: e.id, label: cal.label(new Date(e.start.dateTime), tz), start: e.start.dateTime, name: p.pl_name, phone: p.pl_phone, service: p.pl_vertical, status: p.pl_status, address: e.location || '' };
        }),
      });
    }

    if (action === 'flow_get') {
      const a = await (await el(context, `/agents/${encodeURIComponent(context.ELEVENLABS_AGENT_ID)}`)).json();
      const cfg = ((a.conversation_config || {}).agent) || {};
      return reply(200, {
        can_edit: isAdmin,
        name: a.name || 'Maya',
        first_message: cfg.first_message || '',
        prompt: (cfg.prompt || {}).prompt || '',
        switches: {
          answers_missed_calls: ai.inboundEnabled(context),
          outbound_ai_calls: ai.outboundEnabled(context),
          transfers_to_agents: String(context.AI_TRANSFER || 'on').toLowerCase() !== 'off',
          ring_agents_seconds: parseInt(context.RING_SECONDS || '30', 10),
          calling_hours: context.AI_CALL_HOURS || '8-21',
          booking_hours: context.BOOKING_HOURS || '9-18',
          booking_days: context.BOOKING_DAYS || '1-6',
        },
      });
    }

    if (action === 'flow_set') {
      if (!isAdmin) return reply(403, { error: 'admins_only' });
      const firstMessage = clean(event.first_message, 1000);
      const prompt = clean(event.prompt, 20000);
      if (firstMessage.length < 10 || prompt.length < 50) return reply(422, { error: 'too_short' });
      // AI disclosure is required on every call; refuse a script that drops it.
      if (!/\bAI\b/.test(firstMessage) && !/\bAI\b/.test(prompt.slice(0, 2000))) {
        return reply(422, { error: 'ai_disclosure_required', message: 'Maya must say she is an AI assistant. Keep "AI" in the greeting or the top of the script.' });
      }
      // Read-modify-write: keep every other agent/prompt setting (tools, LLM, voice) as is.
      const path = `/agents/${encodeURIComponent(context.ELEVENLABS_AGENT_ID)}`;
      const current = await (await el(context, path)).json();
      const agentCfg = ((current.conversation_config || {}).agent) || {};
      const patch = {
        conversation_config: {
          agent: { ...agentCfg, first_message: firstMessage, prompt: { ...(agentCfg.prompt || {}), prompt } },
        },
      };
      await el(context, path, { method: 'PATCH', body: JSON.stringify(patch) });
      console.log(`AI_FLOW_SET by=${agent} first=${firstMessage.length} prompt=${prompt.length}`);
      return reply(200, { ok: true });
    }

    return reply(400, { error: 'unknown_action' });
  } catch (err) {
    console.log(`AI_CONSOLE_FAIL action=${action} err=${err && err.message}`);
    return reply(502, { error: 'upstream_error', message: String((err && err.message) || 'error') });
  }
};
