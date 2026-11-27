// Live transfer to agents + the PowerLine "Maya" console.
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
  calendar: { path: path.join(__dirname, '..', 'calendar.private.js') },
}) };

const session = require('../session.private.js');
const ORIGIN = 'https://awwmit-69.github.io';
const SID = 'CA' + 'a'.repeat(32);

function fakeTwilio(live = []) {
  const updates = [];
  const client = (sid) => ({ update: async (o) => { updates.push({ sid, ...o }); return {}; } });
  const fn = (sid) => client(sid);
  fn.list = async (q) => live.filter((c) => (q.from && c.from === q.from) || (q.to && c.to === q.to));
  return {
    calls: Object.assign(fn, { list: fn.list, create: async () => ({ sid: 'CAnew' }) }),
    recordings: { list: async () => [{ sid: 'RE' + 'b'.repeat(32), callSid: SID, dateCreated: '2026-11-26T15:00:00Z', duration: '42' }] },
    updates,
  };
}

const base = (tw) => ({
  CALLER_ID: '+16073337825', SIP_DOMAIN: 'azdpowerline.sip.twilio.com', SIP_USERS: 'azd1001',
  AGENTS: 'shahedul:+16893036969,rep2:+16057909582', ALLOWED_ORIGINS: ORIGIN, SESSION_SECRET: 'x'.repeat(48),
  AI_TOOLS_TOKEN: 'k'.repeat(32), ELEVENLABS_API_KEY: 'e'.repeat(20), ELEVENLABS_AGENT_ID: 'agent_x',
  GOOGLE_SA_EMAIL: 'a@b.iam.gserviceaccount.com', GOOGLE_SA_KEY: 'unused', BOOKING_CALENDAR_ID: 'o@gmail.com',
  __TEST_TWILIO: tw,
});
const run = (file, event, c) => new Promise((res, rej) =>
  require(`../${file}`).handler(c, event, (e, r) => (e ? rej(e) : res(r))));
const tool = (c, body) => run('ai-tools.js', { request: { headers: { authorization: 'Bearer ' + 'k'.repeat(32) } }, action: 'transfer', ...body }, c);

// ---------- transfer ----------
test('transfer rings all agents and softphones, voicemail on no answer', async () => {
  const tw = fakeTwilio();
  const r = await tool(base(tw), { call_sid: SID, reason: 'wants a person' });
  assert.equal(r.status, 200);
  assert.equal(tw.updates[0].sid, SID);
  const x = tw.updates[0].twiml;
  assert.match(x, /<Sip>sip:azd1001@azdpowerline\.sip\.twilio\.com<\/Sip>/);
  assert.match(x, /<Client><Identity>shahedul<\/Identity><Parameter name="transfer_reason" value="wants a person"\/><\/Client>/);
  assert.match(x, /<Client><Identity>rep2<\/Identity>/);
  assert.match(x, /action="\/sip-inbound\?step=transfer-done"/);

  const vm = (await run('sip-inbound.js', { step: 'transfer-done', DialCallStatus: 'no-answer', CallSid: SID }, base(tw))).toString();
  assert.match(vm, /<Record /); assert.doesNotMatch(vm, /Stream/);
  const done = (await run('sip-inbound.js', { step: 'transfer-done', DialCallStatus: 'completed', CallSid: SID }, base(tw))).toString();
  assert.match(done, /<Hangup\/>/);
});

test('transfer finds the live call by phone when call_sid is missing; guards', async () => {
  const tw = fakeTwilio([{ sid: SID, from: '+16076639669', to: '+16073337825' }]);
  assert.equal((await tool(base(tw), { callback_number: '607-663-9669' })).status, 200);
  assert.equal(tw.updates[0].sid, SID);
  assert.equal((await tool(base(fakeTwilio()), { callback_number: '6076639669' })).body.error, 'call_not_found');
  assert.equal((await tool({ ...base(fakeTwilio()), AI_TRANSFER: 'off' }, { call_sid: SID })).status, 503);
  assert.equal((await tool({ ...base(fakeTwilio()), SIP_USERS: '', AGENTS: '' }, { call_sid: SID })).body.error, 'no_agents');
});

// ---------- console ----------
const sess = (sub) => session.sign({ sub }, 'x'.repeat(48), 600);
const con = (c, action, extra = {}, who = 'shahedul', origin = ORIGIN) =>
  run('ai-console.js', { request: { headers: origin ? { origin } : {} }, session: sess(who), action, ...extra }, c);

function fakeEleven() {
  const agent = {
    name: 'Maya',
    conversation_config: { agent: { first_message: 'Hi, this is Maya, an AI assistant.', language: 'en', prompt: { prompt: 'old', tool_ids: ['t1', 't2'], llm: 'gpt' } }, tts: { voice_id: 'v' } },
  };
  const patches = [];
  const fetchImpl = async (url, opts = {}) => {
    const u = new URL(url);
    assert.equal(opts.headers['xi-api-key'], 'e'.repeat(20));
    const ok = (body, bin) => ({ ok: true, status: 200, json: async () => body, arrayBuffer: async () => bin });
    if (u.pathname === '/v1/convai/conversations') {
      assert.equal(u.searchParams.get('agent_id'), 'agent_x');
      return ok({ conversations: [{ conversation_id: 'conv1', start_time_unix_secs: 1795000000, call_duration_secs: 95, status: 'done', call_successful: 'success', call_summary_title: 'Roof leak booking', direction: 'inbound' }], has_more: true, next_cursor: 'c2' });
    }
    if (u.pathname === '/v1/convai/conversations/conv1') {
      return ok({ conversation_id: 'conv1', metadata: { start_time_unix_secs: 1795000000, call_duration_secs: 95, phone_call: { external_number: '+16076639669', agent_number: '+16073337825', direction: 'inbound' } },
        analysis: { call_successful: 'success', transcript_summary: 'Booked roofing visit.', data_collection_results: { caller_name: { value: 'Jane' }, owns_home: { value: true }, message: { value: null } } },
        transcript: [{ role: 'agent', message: 'Hi', time_in_call_secs: 0 }, { role: 'user', message: 'My roof leaks', time_in_call_secs: 3 }, { role: 'agent', message: null }] });
    }
    if (u.pathname === '/v1/convai/conversations/conv1/audio') return ok(null, Buffer.from('ID3fakeaudio'));
    if (u.pathname === '/v1/convai/conversations/huge/audio') return ok(null, Buffer.alloc(5 * 1024 * 1024));
    if (u.pathname === '/v1/convai/agents/agent_x') {
      if (opts.method === 'PATCH') { patches.push(JSON.parse(opts.body)); return ok({}); }
      return ok(agent);
    }
    return { ok: false, status: 404, json: async () => ({}) };
  };
  return { fetchImpl, patches };
}

async function withFetch(f, fn) { const real = global.fetch; global.fetch = f; try { return await fn(); } finally { global.fetch = real; } }

test('console auth', async () => {
  const c = base(fakeTwilio());
  assert.equal((await con(c, 'calls', {}, 'shahedul', 'https://evil.example')).status, 403);
  assert.equal((await con(c, 'calls', {}, 'stranger')).status, 401);
  assert.equal((await run('ai-console.js', { request: { headers: { origin: ORIGIN } }, session: 'junk', action: 'calls' }, c)).status, 401);
});

test('console: calls, transcript, recording, voicemails', async () => {
  const c = base(fakeTwilio());
  const el = fakeEleven();
  await withFetch(el.fetchImpl, async () => {
    const list = await con(c, 'calls');
    assert.equal(list.status, 200);
    assert.deepEqual(list.body.calls[0], { id: 'conv1', started: new Date(1795000000 * 1000).toISOString(), seconds: 95, status: 'done', result: 'success', title: 'Roof leak booking', direction: 'inbound' });
    assert.equal(list.body.next_cursor, 'c2');

    const d = await con(c, 'call', { id: 'conv1' }, 'rep2');
    assert.equal(d.body.caller, '+16076639669');
    assert.deepEqual(d.body.collected, { caller_name: 'Jane', owns_home: true });
    assert.deepEqual(d.body.transcript.map((t) => t.who), ['Maya', 'Caller']);
    assert.equal((await con(c, 'call', { id: '../x' })).status, 422);

    const a = await con(c, 'call_audio', { id: 'conv1' });
    assert.equal(Buffer.from(a.body.base64, 'base64').toString(), 'ID3fakeaudio');
    assert.equal((await con(c, 'call_audio', { id: 'huge' })).status, 413);

    const vms = await con(c, 'voicemails');
    assert.equal(vms.body.voicemails[0].seconds, 42);
    assert.equal((await con(c, 'voicemail_audio', { sid: 'nope' })).status, 422);
  });
});

test('console: call flow read + admin-only save keeps tools/voice', async () => {
  const c = base(fakeTwilio());
  const el = fakeEleven();
  await withFetch(el.fetchImpl, async () => {
    const g = await con(c, 'flow_get');
    assert.equal(g.body.can_edit, true); assert.equal(g.body.prompt, 'old');
    assert.equal(g.body.switches.transfers_to_agents, true);
    assert.equal((await con(c, 'flow_get', {}, 'rep2')).body.can_edit, false);

    const script = 'You are Maya, an AI assistant for Acme Roofing. ' + 'Be brief. '.repeat(10);
    assert.equal((await con(c, 'flow_set', { first_message: 'Hi, this is Maya, an AI assistant.', prompt: script }, 'rep2')).status, 403);
    assert.equal((await con(c, 'flow_set', { first_message: 'Hi there, Maya here!', prompt: 'You are Maya. '.repeat(10) })).body.error, 'ai_disclosure_required');
    assert.equal((await con(c, 'flow_set', { first_message: 'Hi', prompt: 'x' })).body.error, 'too_short');

    const ok = await con(c, 'flow_set', { first_message: 'Hi, this is Maya, an AI assistant with Acme.', prompt: script });
    assert.equal(ok.status, 200);
    const p = el.patches[0].conversation_config.agent;
    assert.equal(p.first_message, 'Hi, this is Maya, an AI assistant with Acme.');
    assert.equal(p.prompt.prompt, script.trim());
    assert.deepEqual(p.prompt.tool_ids, ['t1', 't2'], 'tools preserved');
    assert.equal(p.prompt.llm, 'gpt'); assert.equal(p.language, 'en');
  });
  assert.equal((await con({ ...c, AI_ADMINS: 'rep2' }, 'flow_set', {}, 'shahedul')).status, 403);
});
