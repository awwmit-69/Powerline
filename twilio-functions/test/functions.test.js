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
