// Run: node --test twilio-functions/test  (needs `npm i twilio` in twilio-functions/)
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');

global.Twilio = require('twilio');
class FakeResponse { constructor(){this.headers={};this.status=200;this.body=null;}
  setStatusCode(s){this.status=s;} appendHeader(k,v){this.headers[k]=v;} setBody(b){this.body=b;} }
global.Twilio.Response = FakeResponse;
global.Runtime = { getFunctions: () => ({
  dialrules: { path: path.join(__dirname, '..', 'dialrules.private.js') },
  session: { path: path.join(__dirname, '..', 'session.private.js') },
  ai: { path: path.join(__dirname, '..', 'ai.private.js') },
  appt: { path: path.join(__dirname, '..', 'appt.private.js') },
}) };

const ORIGIN = 'https://awwmit-69.github.io';
const ctx = {
  SIP_DOMAIN: 'azdpowerline.sip.twilio.com', CALLER_ID: '+16073337825', SIP_USERS: 'azd1001',
  AGENTS: 'shahedul:+16893036969', ALLOWED_ORIGINS: ORIGIN,
  SESSION_SECRET: 'x'.repeat(48), TWILIO_ACCOUNT_SID: 'AC' + '0'.repeat(32),
  TWILIO_API_KEY_SID: 'SK' + '0'.repeat(32), TWILIO_API_KEY_SECRET: 's'.repeat(32),
  TWIML_APP_SID: 'AP' + '0'.repeat(32),
};
const req = (o = ORIGIN) => ({ request: { headers: o ? { origin: o } : {} } });
const run = (file, event, c = ctx) => new Promise((res, rej) =>
  require(`../${file}`).handler(c, event, (e, r) => (e ? rej(e) : res(r))));
const xml = async (file, ev) => (await run(file, ev)).toString();

const rules = require('../dialrules.private.js');
const session = require('../session.private.js');

test('dial rules', () => {
  assert.equal(rules.checkDestination('6076639669').e164, '+16076639669');
  assert.equal(rules.checkDestination('+1 (607) 663-9669').e164, '+16076639669');
  for (const bad of ['911', '933', '411', '+18765551234', '9005551234', '+442071234567', '12345', '2125550']) {
    assert.equal(rules.checkDestination(bad).ok, false, bad);
  }
  assert.equal(rules.checkDestination('6073337825', '+16073337825').reason, 'self_dial');
  assert.deepEqual([...rules.parseAgents('Ab:+16893036969, bad, xy:123').entries()], [['ab', '+16893036969']]);
});

test('session sign/verify', () => {
  const t = session.sign({ sub: 'shahedul' }, ctx.SESSION_SECRET, 60);
  assert.equal(session.verify(t, ctx.SESSION_SECRET).sub, 'shahedul');
  assert.equal(session.verify(t, 'y'.repeat(48)), null);
  assert.equal(session.verify(t.slice(0, -2) + 'aa', ctx.SESSION_SECRET), null);
  assert.equal(session.verify(session.sign({ sub: 'a' }, ctx.SESSION_SECRET, -10), ctx.SESSION_SECRET), null);
  assert.throws(() => session.sign({ sub: 'a' }, 'short', 60));
});

test('voice-token requires session + allowed origin', async () => {
  const good = session.sign({ sub: 'shahedul' }, ctx.SESSION_SECRET, 60);
  let r = await run('voice-token.js', { ...req(), session: good });
  assert.equal(r.status, 200); assert.ok(r.body.token); assert.equal(r.body.identity, 'shahedul');
  assert.equal(r.headers['Access-Control-Allow-Origin'], ORIGIN);
  const decoded = JSON.parse(Buffer.from(r.body.token.split('.')[1], 'base64url'));
  assert.equal(decoded.grants.identity, 'shahedul');
  assert.equal(decoded.grants.voice.outgoing.application_sid, ctx.TWIML_APP_SID);
  assert.equal(decoded.grants.voice.incoming.allow, true);
  assert.ok(decoded.exp - decoded.iat <= 3600);
  r = await run('voice-token.js', { ...req(), session: 'garbage' }); assert.equal(r.status, 401);
  r = await run('voice-token.js', { ...req('https://evil.example'), session: good }); assert.equal(r.status, 403);
  r = await run('voice-token.js', { ...req(null), session: good }); assert.equal(r.status, 403);
  const stranger = session.sign({ sub: 'removed-agent' }, ctx.SESSION_SECRET, 60);
  r = await run('voice-token.js', { ...req(), session: stranger }); assert.equal(r.status, 401);
});

test('auth endpoints reject bad input without calling Twilio', async () => {
  let r = await run('auth-verify.js', { ...req(), agent: 'nobody', code: '123456' }); assert.equal(r.status, 401);
  r = await run('auth-verify.js', { ...req(), agent: 'shahedul', code: 'abc' }); assert.equal(r.status, 401);
  r = await run('auth-start.js', { ...req(), agent: 'nobody' }); assert.equal(r.status, 200);
  r = await run('auth-start.js', { ...req('https://evil.example'), agent: 'shahedul' }); assert.equal(r.status, 403);
});

test('voice-outbound: agent + dial rules', async () => {
  assert.match(await xml('voice-outbound.js', { From: 'client:shahedul', To: '6076639669' }),
    /<Dial callerId="\+16073337825"[^>]*><Number>\+16076639669<\/Number>/);
  assert.match(await xml('voice-outbound.js', { From: 'client:intruder', To: '6076639669' }), /not authorized/);
  assert.match(await xml('voice-outbound.js', { From: '+15551234567', To: '6076639669' }), /not authorized/);
  assert.match(await xml('voice-outbound.js', { From: 'client:shahedul', To: '911' }), /Emergency/);
});

test('sip-outbound', async () => {
  const F = 'sip:azd1001@azdpowerline.sip.singapore.twilio.com';
  assert.match(await xml('sip-outbound.js', { From: F, To: 'sip:6076639669@azdpowerline.sip.twilio.com' }), /<Number>\+16076639669/);
  assert.match(await xml('sip-outbound.js', { From: F, To: 'sip:911@x' }), /Emergency/);
  assert.match(await xml('sip-outbound.js', { From: 'sip:azd1001@evil.sip.twilio.com', To: 'sip:6076639669@x' }), /not authorized/);
  assert.match(await xml('sip-outbound.js', { From: 'sip:other@azdpowerline.sip.twilio.com', To: 'sip:6076639669@x' }), /not authorized/);
});

test('sip-inbound rings softphones + browser agents, then voicemail', async () => {
  const first = await xml('sip-inbound.js', { CallSid: 'CA1' });
  assert.match(first, /<Sip>sip:azd1001@azdpowerline\.sip\.twilio\.com<\/Sip><Client>shahedul<\/Client>/);
  assert.match(await xml('sip-inbound.js', { CallSid: 'CA1', DialCallStatus: 'no-answer' }), /<Record /);
  assert.match(await xml('sip-inbound.js', { CallSid: 'CA1', DialCallStatus: 'completed' }), /^<\?xml[^>]*><Response><Hangup\/><\/Response>$/);
  assert.match(await xml('sip-inbound.js', { step: 'vm-done' }), /recorded/);
});

test('PIN backup sign-in', async () => {
  const c = { ...ctx, AGENT_PINS: 'shahedul:Ab3dE6gH9k' };
  let r = await run('auth-verify.js', { ...req(), agent: 'shahedul', code: 'Ab3dE6gH9k' }, c);
  assert.equal(r.status, 200); assert.ok(r.body.session);
  assert.equal(session.verify(r.body.session, ctx.SESSION_SECRET).sub, 'shahedul');
  r = await run('auth-verify.js', { ...req(), agent: 'shahedul', code: 'Ab3dE6gH9X' }, c);
  assert.equal(r.status, 401);
  r = await run('auth-verify.js', { ...req('https://evil.example'), agent: 'shahedul', code: 'Ab3dE6gH9k' }, c);
  assert.equal(r.status, 403);
  // Agents with a PIN skip SMS entirely; without one, SMS failure (no network here) -> 429.
  r = await run('auth-start.js', { ...req(), agent: 'shahedul' }, c);
  assert.equal(r.status, 200); assert.equal(r.body.fallback, 'pin');
  r = await run('auth-start.js', { ...req(), agent: 'shahedul' });
  assert.equal(r.status, 429);
  r = await run('auth-start.js', { ...req(), agent: 'shahedul' }, { ...ctx, AGENT_PINS: 'shahedul:has space!' });
  assert.equal(r.status, 429); assert.equal(r.body.pinFormatInvalid, true);
  assert.equal(rules.parsePins('a:x,bb:Ab3dE6gH9k,cc:bad pin!').size, 1);
  // Bare PIN, quotes and spaces tolerated; maps to the only agent.
  assert.equal(rules.parsePins(' "Dhaka2026" ', 'shahedul:+16893036969').get('shahedul'), 'Dhaka2026');
  assert.equal(rules.parsePins('Shahedul : 1234', 'shahedul:+16893036969').get('shahedul'), '1234');
  r = await run('auth-verify.js', { ...req(), agent: 'shahedul', code: 'Dhaka2026' }, { ...ctx, AGENT_PINS: 'Dhaka2026' });
  assert.equal(r.status, 200);
});

// ---------------- AI agent ----------------
const ai = require('../ai.private.js');
const aiCtx = { ...ctx, ELEVENLABS_API_KEY: 'k'.repeat(20), ELEVENLABS_AGENT_ID: 'agent_x', AI_OUTBOUND: 'on', AI_OUTBOUND_TOKEN: 't'.repeat(32), DOMAIN_NAME: 'x.twil.io' };
const TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="wss://x"/></Connect></Response>';

test('ai flags and helpers', () => {
  assert.equal(ai.inboundEnabled(ctx), false);
  assert.equal(ai.inboundEnabled(aiCtx), true);
  assert.equal(ai.inboundEnabled({ ...aiCtx, AI_INBOUND: 'off' }), false);
  assert.equal(ai.outboundEnabled({ ...aiCtx, AI_OUTBOUND: '' }), false);
  assert.deepEqual(ai.cleanVars({ a: ' x ', 'bad key': 1, e: '' }), { a: 'x' });
  const noon = new Date('2026-11-21T17:00:00Z'); // 12:00 New York
  const night = new Date('2026-11-22T04:00:00Z'); // 23:00 New York
  assert.equal(ai.withinCallingHours({}, 'America/New_York', noon), true);
  assert.equal(ai.withinCallingHours({}, 'America/New_York', night), false);
  assert.equal(ai.withinCallingHours({}, 'Not/AZone', noon), false);
  assert.ok(ai.dncSet({ DNC_NUMBERS: '+1 (607) 663-9669' }).has('+16076639669'));
});

test('ai registerCall', async () => {
  let sent;
  const ok = async (url, opts) => { sent = { url, opts }; return { ok: true, status: 200, text: async () => JSON.stringify(TWIML) }; };
  const xmlOut = await ai.registerCall(aiCtx, { from: '+15551234567', to: '+16073337825', direction: 'inbound', vars: { call_direction: 'inbound' } }, ok);
  assert.equal(xmlOut, TWIML);
  const body = JSON.parse(sent.opts.body);
  assert.equal(body.agent_id, 'agent_x');
  assert.equal(body.direction, 'inbound');
  assert.equal(body.conversation_initiation_client_data.dynamic_variables.call_direction, 'inbound');
  assert.equal(sent.opts.headers['xi-api-key'], aiCtx.ELEVENLABS_API_KEY);
  const bad = async () => ({ ok: false, status: 401, text: async () => 'nope' });
  assert.equal(await ai.registerCall(aiCtx, { from: 'a', to: 'b' }, bad), null);
  const boom = async () => { throw new Error('x'); };
  assert.equal(await ai.registerCall(aiCtx, { from: 'a', to: 'b' }, boom), null);
  assert.equal(await ai.registerCall(ctx, { from: 'a', to: 'b' }, ok), null);
});

test('sip-inbound falls back to voicemail without AI, uses AI when configured', async () => {
  const vm = (await run('sip-inbound.js', { DialCallStatus: 'no-answer', CallSid: 'CA1' })).toString();
  assert.match(vm, /<Record/);
  const realFetch = global.fetch;
  global.fetch = async () => ({ ok: true, status: 200, text: async () => TWIML });
  try {
    const r = await run('sip-inbound.js', { DialCallStatus: 'no-answer', From: '+15551234567', To: '+16073337825', CallSid: 'CA2' }, aiCtx);
    assert.equal(r.body, TWIML);
    global.fetch = async () => ({ ok: false, status: 500, text: async () => 'err' });
    const r2 = (await run('sip-inbound.js', { DialCallStatus: 'no-answer', CallSid: 'CA3' }, aiCtx)).toString();
    assert.match(r2, /<Record/);
  } finally { global.fetch = realFetch; }
});

test('ai-call guards', async () => {
  const bearer = (extra = {}) => ({ request: { headers: { authorization: 'Bearer ' + 't'.repeat(32) } }, to: '6076639669',
    consent_timestamp: '2026-11-01T10:00:00Z', consent_source: 'roofquote form', tz: 'UTC', ...extra });
  assert.equal((await run('ai-call.js', { ...bearer(), request: { headers: { authorization: 'Bearer wrong' } } }, aiCtx)).status, 401);
  assert.equal((await run('ai-call.js', bearer(), { ...aiCtx, AI_OUTBOUND: 'off' })).status, 503);
  assert.equal((await run('ai-call.js', bearer({ to: '911' }), aiCtx)).body.error, 'bad_destination');
  assert.equal((await run('ai-call.js', bearer({ consent_timestamp: '' }), aiCtx)).body.error, 'consent_required');
  assert.equal((await run('ai-call.js', bearer({ consent_source: '' }), aiCtx)).body.error, 'consent_required');
  assert.equal((await run('ai-call.js', bearer(), { ...aiCtx, DNC_NUMBERS: '+16076639669' })).body.error, 'do_not_call');
  assert.equal((await run('ai-call.js', bearer(), { ...aiCtx, AI_CALL_HOURS: '0-0' })).body.error, 'outside_calling_hours');
});

test('ai-connect hangs up on machines', async () => {
  const x = (await run('ai-connect.js', { AnsweredBy: 'machine_end_beep', CallSid: 'CA9' }, aiCtx)).toString();
  assert.match(x, /<Hangup\/>/);
});

// ---------------- Appointments ----------------
const appt = require('../appt.private.js');
const apptCtx = { ...aiCtx, ELEVENLABS_AGENT_ID: 'agent_x' };

test('appointment slots: Mon-Sat 9-18 local, DST-safe, lead time', () => {
  const cfg = appt.config({});
  const now = Date.parse('2026-11-23T12:00:00Z'); // Mon 7:00 New York
  const slots = appt.allSlots(cfg, 'America/New_York', now);
  // first slot Monday 9:00 ET = 14:00Z (lead time 2h from 07:00 -> 09:00 ok)
  assert.equal(new Date(slots[0]).toISOString(), '2026-11-23T14:00:00.000Z');
  for (const ts of slots) {
    const p = appt.zoneParts(ts, 'America/New_York');
    assert.ok(p.wd >= 1 && p.wd <= 6, 'no Sundays');
    assert.ok(p.h >= 9 && p.h <= 17, 'within hours');
  }
  assert.equal(slots.filter((ts) => appt.zoneParts(ts, 'America/New_York').d === 23).length, 9);
  // Chicago is an hour behind -> 9:00 CT = 15:00Z
  assert.equal(new Date(appt.allSlots(cfg, 'America/Chicago', now)[0]).toISOString(), '2026-11-23T15:00:00.000Z');
  // DST: 9:00 ET on 2026-03-09 (after spring forward) = 13:00Z
  const spring = appt.allSlots(cfg, 'America/New_York', Date.parse('2026-03-09T09:00:00Z'));
  assert.equal(new Date(spring[0]).toISOString(), '2026-03-09T13:00:00.000Z');
  assert.equal(appt.slotKey(Date.parse('2026-11-23T14:00:00Z')), 'slot-2026-11-23T14:00');
  assert.equal(appt.validTz('Nope/Zone'), false);
});

test('verifyConversation', async () => {
  const live = async () => ({ ok: true, json: async () => ({ agent_id: 'agent_x', status: 'in-progress' }) });
  const other = async () => ({ ok: true, json: async () => ({ agent_id: 'agent_y', status: 'in-progress' }) });
  const done = async () => ({ ok: true, json: async () => ({ agent_id: 'agent_x', status: 'done' }) });
  assert.equal(await appt.verifyConversation(apptCtx, 'conv_abcdefghijkl', live), true);
  assert.equal(await appt.verifyConversation(apptCtx, 'conv_abcdefghijkl', other), false);
  assert.equal(await appt.verifyConversation(apptCtx, 'conv_abcdefghijkl', done), false);
  assert.equal(await appt.verifyConversation(apptCtx, 'bad id', live), false);
});

test('appt-book: validates, books once, offers alternatives when taken', async () => {
  const store = new Map();
  const orig = { list: appt.listBookings, create: appt.createBooking, verify: appt.verifyConversation };
  appt.listBookings = async () => [...store.entries()].map(([key, d]) => ({ key, ...d }));
  appt.createBooking = async (_c, data) => {
    const key = appt.slotKey(Date.parse(data.start));
    if (store.has(key)) return { ok: false, reason: 'slot_taken' };
    store.set(key, data); return { ok: true, booking: { key, ...data } };
  };
  appt.verifyConversation = async (_c, id) => id === 'conv_okokokokokok';
  try {
    const slot = new Date(appt.allSlots(appt.config({}), 'America/New_York')[0]).toISOString();
    const ev = { conversation_id: 'conv_okokokokokok', start: slot, timezone: 'America/New_York', name: 'Jane Doe',
      phone: '(607) 663-9669', address: '1 Main St', zip: '13760', vertical: 'roofing' };
    assert.equal((await run('appt-book.js', { ...ev, conversation_id: 'conv_badbadbadbad' }, apptCtx)).status, 401);
    assert.equal((await run('appt-book.js', { ...ev, phone: '' }, apptCtx)).body.error, 'missing_fields');
    assert.equal((await run('appt-book.js', { ...ev, start: '2026-11-29T15:00:00Z' }, apptCtx)).body.error, 'invalid_time');
    const ok = await run('appt-book.js', ev, apptCtx);
    assert.equal(ok.body.booked, true);
    assert.equal([...store.values()][0].phone, '+16076639669');
    const again = await run('appt-book.js', ev, apptCtx);
    assert.equal(again.body.error, 'slot_taken');
    assert.ok(again.body.alternatives.length > 0);
    const avail = await run('appt-availability.js', { conversation_id: 'conv_okokokokokok', timezone: 'America/New_York' }, apptCtx);
    assert.ok(!avail.body.slots.some((s) => s.start === slot), 'booked slot hidden');
    assert.equal(avail.body.slots.length, 6);
  } finally {
    appt.listBookings = orig.list; appt.createBooking = orig.create; appt.verifyConversation = orig.verify;
  }
});
