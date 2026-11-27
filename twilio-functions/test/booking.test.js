// Booking, confirm/rebook and owner notification. Google Calendar is faked in memory.
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const crypto = require('crypto');

global.Twilio = require('twilio');
class FakeResponse { constructor(){this.headers={};this.status=200;this.body=null;}
  setStatusCode(s){this.status=s;} appendHeader(k,v){this.headers[k]=v;} setBody(b){this.body=b;} }
global.Twilio.Response = FakeResponse;
global.Runtime = { getFunctions: () => ({
  dialrules: { path: path.join(__dirname, '..', 'dialrules.private.js') },
  session: { path: path.join(__dirname, '..', 'session.private.js') },
  ai: { path: path.join(__dirname, '..', 'ai.private.js') },
  calendar: { path: path.join(__dirname, '..', 'calendar.private.js') },
}) };

const cal = require('../calendar.private.js');
const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

// ---------- fakes ----------
function fakeGoogle() {
  const events = new Map();
  let n = 0;
  const json = (status, body) => ({ ok: status < 400, status, json: async () => body, text: async () => JSON.stringify(body) });
  const fetchImpl = async (url, opts = {}) => {
    const u = new URL(url);
    const method = opts.method || 'GET';
    if (u.href.startsWith('https://oauth2.googleapis.com/token')) {
      const assertion = new URLSearchParams(opts.body).get('assertion');
      assert.equal(assertion.split('.').length, 3);
      return json(200, { access_token: 'tok', expires_in: 3600 });
    }
    assert.equal(opts.headers.Authorization, 'Bearer tok');
    const body = opts.body ? JSON.parse(opts.body) : null;
    if (u.pathname.endsWith('/freeBusy')) {
      const min = Date.parse(body.timeMin); const max = Date.parse(body.timeMax);
      const busy = [...events.values()]
        .filter((e) => e.transparency !== 'transparent')
        .filter((e) => Date.parse(e.end.dateTime) > min && Date.parse(e.start.dateTime) < max)
        .map((e) => ({ start: e.start.dateTime, end: e.end.dateTime }));
      return json(200, { calendars: { [body.items[0].id]: { busy } } });
    }
    const m = u.pathname.match(/\/events(?:\/([^/]+))?$/);
    if (!m) return json(404, {});
    const id = m[1] && decodeURIComponent(m[1]);
    if (method === 'POST') { const e = { ...body, id: `ev${++n}`, status: 'confirmed' }; events.set(e.id, e); return json(200, e); }
    if (method === 'GET' && id) return events.has(id) ? json(200, events.get(id)) : json(404, {});
    if (method === 'PATCH') { const e = { ...events.get(id), ...body }; events.set(id, e); return json(200, e); }
    if (method === 'GET') {
      const props = u.searchParams.getAll('privateExtendedProperty').map((s) => s.split('='));
      const min = Date.parse(u.searchParams.get('timeMin')); const max = u.searchParams.get('timeMax') ? Date.parse(u.searchParams.get('timeMax')) : Infinity;
      const items = [...events.values()].filter((e) => {
        const p = (e.extendedProperties || {}).private || {};
        const t = Date.parse(e.start.dateTime);
        return t >= min && t < max && props.every(([k, v]) => p[k] === v);
      }).sort((a, b) => Date.parse(a.start.dateTime) - Date.parse(b.start.dateTime));
      return json(200, { items });
    }
    return json(400, {});
  };
  return { events, fetchImpl };
}

function fakeTwilio() {
  const calls = []; const messages = [];
  return { calls: { create: async (o) => { calls.push(o); return { sid: 'CA' + calls.length }; } },
    messages: { create: async (o) => { messages.push(o); return { sid: 'SM' + messages.length }; } }, log: { calls, messages } };
}

const TOKEN = 'k'.repeat(32);
function makeCtx(extra = {}) {
  const tw = fakeTwilio();
  return {
    ctx: {
      CALLER_ID: '+16073337825', DOMAIN_NAME: 'x.twil.io', BUSINESS_NAME: 'Acme Roofing',
      GOOGLE_SA_EMAIL: 'pl@proj.iam.gserviceaccount.com', GOOGLE_SA_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }).replace(/\n/g, '\\n'),
      BOOKING_CALENDAR_ID: 'owner@gmail.com', BOOKING_TZ: 'America/New_York', BOOKING_DAYS: '0-6',
      AI_TOOLS_TOKEN: TOKEN, CONFIRM_TOKEN: 'c'.repeat(32), OWNER_NOTIFY_PHONE: '+16893036969',
      ELEVENLABS_API_KEY: 'e'.repeat(20), ELEVENLABS_AGENT_ID: 'agent_x', AI_CALL_HOURS: '0-24',
      __TEST_TWILIO: tw, ...extra,
    },
    tw,
  };
}

const run = (file, event, c) => new Promise((res, rej) =>
  require(`../${file}`).handler(c, event, (e, r) => (e ? rej(e) : res(r))));
const tool = (c, action, body = {}, token = TOKEN) =>
  run('ai-tools.js', { request: { headers: { authorization: `Bearer ${token}` } }, action, ...body }, c);

async function withFetch(fetchImpl, fn) {
  const real = global.fetch; global.fetch = fetchImpl; cal._resetTokenCache();
  try { return await fn(); } finally { global.fetch = real; }
}

// ---------- pure time math ----------
test('zonedToUtc handles DST', () => {
  assert.equal(cal.zonedToUtc(2026, 11, 26, 9, 0, 'America/New_York').toISOString(), '2026-11-26T14:00:00.000Z');
  assert.equal(cal.zonedToUtc(2026, 7, 1, 9, 0, 'America/New_York').toISOString(), '2026-07-01T13:00:00.000Z');
  assert.equal(cal.zonedToUtc(2026, 3, 8, 9, 0, 'America/New_York').toISOString(), '2026-03-08T13:00:00.000Z');
  assert.equal(cal.zonedToUtc(2026, 11, 26, 9, 0, 'America/Los_Angeles').toISOString(), '2026-11-26T17:00:00.000Z');
  assert.deepEqual([...cal.parseDays('1-6')].sort(), [1, 2, 3, 4, 5, 6]);
  assert.deepEqual([...cal.parseDays('1-5,0')].sort(), [0, 1, 2, 3, 4, 5]);
});

test('openSlots: hours, lead time, busy, days off, one per slot', () => {
  const ctx = { BOOKING_TZ: 'America/New_York', BOOKING_DAYS: '1-6', BOOKING_HOURS: '9-18' };
  const now = new Date('2026-11-26T14:00:00Z'); // Thu 9:00 ET
  const busy = [{ start: '2026-11-26T17:00:00Z', end: '2026-11-26T18:00:00Z' }]; // 12:00 ET
  const slots = cal.openSlots(ctx, { now, busy, limit: 6 });
  assert.deepEqual(slots.map((s) => s.start.slice(11, 16)), ['16:00', '18:00', '19:00', '20:00', '21:00', '22:00']); // 11,13..17 ET
  assert.match(slots[0].label, /Thursday, November 26.*11:00/);
  const many = cal.openSlots(ctx, { now, limit: 200 });
  assert.ok(many.every((s) => new Date(s.start).getUTCDay() !== 0), 'no Sundays');
  assert.ok(many.every((s) => { const h = cal.wallParts(new Date(s.start), 'America/New_York').h; return h >= 9 && h <= 17; }));
  const fromSat = cal.openSlots(ctx, { now, limit: 1, fromDate: '2026-11-28' });
  assert.match(fromSat[0].label, /Saturday, November 28.*9:00/);
});

// ---------- /ai-tools ----------
test('ai-tools: auth + not configured', async () => {
  const { ctx } = makeCtx();
  assert.equal((await tool(ctx, 'availability', {}, 'wrong')).status, 401);
  assert.equal((await tool({ ...ctx, AI_TOOLS_TOKEN: '' }, 'availability')).status, 401);
  assert.equal((await tool({ ...ctx, GOOGLE_SA_KEY: '' }, 'availability')).status, 503);
});

test('ai-tools: book, double-book blocked, lookup, confirm, reschedule, cancel frees slot', async () => {
  const g = fakeGoogle();
  const { ctx, tw } = makeCtx();
  await withFetch(g.fetchImpl, async () => {
    const av = await tool(ctx, 'availability');
    assert.equal(av.status, 200); assert.equal(av.body.slots.length, 6);
    const slot = av.body.slots[0];

    const lead = { start: slot.start, caller_name: 'Jane Doe', callback_number: '(607) 663-9669', address_or_zip: '12 Oak St 12590', vertical: 'roofing', notes: 'leak', confirm_ok: 'yes' };
    const b = await tool(ctx, 'book', lead);
    assert.equal(b.status, 200); assert.ok(b.body.event_id);
    const ev = g.events.get(b.body.event_id);
    assert.equal(ev.extendedProperties.private.pl_phone, '+16076639669');
    assert.equal(ev.extendedProperties.private.pl_confirm_ok, '1');
    assert.match(ev.summary, /Roofing: Jane Doe/);
    assert.equal(tw.log.calls.length, 1); assert.equal(tw.log.calls[0].to, '+16893036969');
    assert.match(tw.log.calls[0].twiml, /New appointment\. Jane Doe/);
    assert.equal(tw.log.messages.length, 0, 'no SMS unless OWNER_NOTIFY_SMS=on');

    const dup = await tool(ctx, 'book', { ...lead, caller_name: 'Second Caller' });
    assert.equal(dup.status, 409); assert.equal(dup.body.error, 'slot_taken');
    assert.ok(dup.body.slots.every((s) => s.start !== slot.start));
    assert.equal((await tool(ctx, 'book', { ...lead, start: '2026-01-01T03:00:00Z' })).status, 409, 'past/out-of-hours rejected');
    assert.equal((await tool(ctx, 'book', { ...lead, start: av.body.slots[1].start, callback_number: '911' })).body.error, 'bad_phone');

    const look = await tool(ctx, 'lookup', { callback_number: '6076639669' });
    assert.equal(look.body.bookings.length, 1); assert.equal(look.body.bookings[0].event_id, b.body.event_id);

    assert.equal((await tool(ctx, 'confirm', { event_id: b.body.event_id })).status, 200);
    assert.equal(g.events.get(b.body.event_id).extendedProperties.private.pl_status, 'confirmed');
    assert.match(g.events.get(b.body.event_id).summary, /^CONFIRMED /);

    const to = av.body.slots[2];
    const rs = await tool(ctx, 'reschedule', { event_id: b.body.event_id, start: to.start });
    assert.equal(rs.status, 200);
    assert.equal(g.events.get(b.body.event_id).start.dateTime, to.start);
    assert.equal(g.events.get(b.body.event_id).extendedProperties.private.pl_status, 'booked');
    assert.doesNotMatch(g.events.get(b.body.event_id).summary, /CONFIRMED/);

    assert.equal((await tool(ctx, 'cancel', { event_id: b.body.event_id, reason: 'went elsewhere' })).status, 200);
    assert.equal(g.events.get(b.body.event_id).extendedProperties.private.pl_status, 'cancelled');
    const again = await tool(ctx, 'book', { ...lead, start: to.start });
    assert.equal(again.status, 200, 'cancelled slot is bookable again');
    assert.equal((await tool(ctx, 'confirm', { event_id: b.body.event_id })).status, 404, 'cannot touch cancelled');
    assert.equal((await tool(ctx, 'confirm', { event_id: 'nope' })).status, 502);
    assert.equal((await tool(ctx, 'lookup', { callback_number: '6076639669' })).body.bookings.length, 1);
  });
});

test('ai-tools: message notifies owner by call and SMS when enabled', async () => {
  const { ctx, tw } = makeCtx({ OWNER_NOTIFY_SMS: 'on' });
  await withFetch(fakeGoogle().fetchImpl, async () => {
    const r = await tool(ctx, 'message', { caller_name: 'Bob <Builder>', callback_number: '6076639669', message: 'call me about solar' });
    assert.equal(r.status, 200);
  });
  assert.equal(tw.log.calls.length, 1); assert.match(tw.log.calls[0].twiml, /Bob &lt;Builder&gt;/);
  assert.equal(tw.log.messages.length, 1); assert.match(tw.log.messages[0].body, /call me about solar/);
});

test('ai-tools: calendar outage returns a safe fallback line', async () => {
  const { ctx } = makeCtx();
  await withFetch(async () => ({ ok: false, status: 500, json: async () => ({}) }), async () => {
    const r = await tool(ctx, 'availability');
    assert.equal(r.status, 502); assert.match(r.body.say, /Take their details/);
  });
});

// ---------- /confirm-run + ai-connect confirm mode ----------
test('confirm-run calls only tomorrow, consented, still-booked, non-DNC', async () => {
  const g = fakeGoogle();
  const { ctx, tw } = makeCtx({ DNC_NUMBERS: '+16075550123' });
  const { timeMin } = cal.tomorrowRange(ctx);
  const tomorrow = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(new Date(Date.parse(timeMin) + 3600e3));
  await withFetch(g.fetchImpl, async () => {
    const av = await tool(ctx, 'availability', { from_date: tomorrow });
    const s = av.body.slots.filter((x) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(new Date(x.start)) === tomorrow);
    assert.ok(s.length >= 4);
    const base = { address_or_zip: '12590', vertical: 'hvac' };
    await tool(ctx, 'book', { ...base, start: s[0].start, caller_name: 'Yes Call', callback_number: '6076639669', confirm_ok: 'true' });
    await tool(ctx, 'book', { ...base, start: s[1].start, caller_name: 'No Consent', callback_number: '6076639668', confirm_ok: 'no' });
    await tool(ctx, 'book', { ...base, start: s[2].start, caller_name: 'On DNC', callback_number: '6075550123', confirm_ok: 'yes' });
    const done = await tool(ctx, 'book', { ...base, start: s[3].start, caller_name: 'Already', callback_number: '6076639667', confirm_ok: 'yes' });
    await tool(ctx, 'confirm', { event_id: done.body.event_id });
    tw.log.calls.length = 0;

    const auth = { request: { headers: { authorization: 'Bearer ' + 'c'.repeat(32) } } };
    assert.equal((await run('confirm-run.js', { request: { headers: { authorization: 'Bearer x' } } }, ctx)).status, 401);
    const dry = await run('confirm-run.js', { ...auth, dry_run: 'true' }, ctx);
    assert.deepEqual(dry.body, { checked: 4, called: 1, skipped: 3, failed: 0, dry_run: true });
    assert.equal(tw.log.calls.length, 0);
    const r = await run('confirm-run.js', auth, ctx);
    assert.equal(r.body.called, 1);
    assert.equal(tw.log.calls.length, 1);
    assert.equal(tw.log.calls[0].to, '+16076639669');
    const url = new URL(tw.log.calls[0].url);
    assert.equal(url.pathname, '/ai-connect');
    assert.equal(url.searchParams.get('mode'), 'confirm');
    assert.equal(url.searchParams.get('first_name'), 'Yes');
    assert.ok(url.searchParams.get('event_id'));
    assert.equal((await run('confirm-run.js', auth, { ...ctx, AI_CALL_HOURS: '0-0' })).body.error, 'outside_calling_hours');
  });
});

test('ai-connect passes confirm-mode variables to Maya', async () => {
  const { ctx } = makeCtx();
  let sent;
  const TWIML = '<Response><Connect><Stream url="wss://x"/></Connect></Response>';
  await withFetch(async (url, opts) => { sent = JSON.parse(opts.body); return { ok: true, status: 200, text: async () => TWIML }; }, async () => {
    const r = await run('ai-connect.js', { AnsweredBy: 'human', mode: 'confirm', event_id: 'ev9', appointment_time: 'Friday 10:00 AM', first_name: 'Jane', To: '+16076639669' }, ctx);
    assert.equal(r.body, TWIML);
  });
  const v = sent.conversation_initiation_client_data.dynamic_variables;
  assert.equal(v.call_direction, 'confirm'); assert.equal(v.event_id, 'ev9');
  assert.equal(v.appointment_time, 'Friday 10:00 AM'); assert.equal(v.business_name, 'Acme Roofing');
});

test('every call type sends every prompt variable', async () => {
  const { ctx } = makeCtx();
  const keys = ['call_direction', 'business_name', 'business_number', 'caller_number', 'lead_first_name', 'vertical', 'event_id', 'appointment_time'];
  const TWIML = '<Response><Connect><Stream url="wss://x"/></Connect></Response>';
  const seen = [];
  await withFetch(async (url, opts) => { seen.push(JSON.parse(opts.body).conversation_initiation_client_data.dynamic_variables); return { ok: true, status: 200, text: async () => TWIML }; }, async () => {
    await run('ai-connect.js', { AnsweredBy: 'human', To: '+16076639669' }, ctx);
    await run('sip-inbound.js', { DialCallStatus: 'no-answer', From: '+15551234567', To: '+16073337825', CallSid: 'CA2' }, ctx);
  });
  assert.equal(seen.length, 2);
  for (const v of seen) for (const k of keys) assert.ok(v[k], `${v.call_direction} missing ${k}`);
});
