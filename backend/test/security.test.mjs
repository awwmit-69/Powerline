import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {authenticate,base64url,validateWebhook,e164,isStop,readLimited} from '../security.mjs';
import worker from '../worker.mjs';
import {createVoiceToken,createIntent,voiceWebhook} from '../voice.mjs';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';

const encode = data => base64url(new TextEncoder().encode(JSON.stringify(data)));
const pair = await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk = {...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'test-key'};
const env = {ACCESS_ISSUER:'https://powerline-test.cloudflareaccess.com',ACCESS_AUD:'powerline',TWILIO_AUTH_TOKEN:'test-secret',TWILIO_ACCOUNT_SID:'AC'+'a'.repeat(32),PUBLIC_ORIGIN:'https://powerline.example.com'};
const claims = () => ({iss:env.ACCESS_ISSUER,aud:['powerline'],sub:'user',email:'owner@example.com',exp:Math.floor(Date.now()/1000)+300});
async function token(payload=claims(),header={alg:'RS256',kid:'test-key'}) {
  const data=encode(header)+'.'+encode(payload);
  return data+'.'+base64url(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(data))));
}
const request = jwt => new Request(env.PUBLIC_ORIGIN+'/api/session',{headers:jwt?{'Cf-Access-Jwt-Assertion':jwt}:{}});
const certs = async () => new Response(JSON.stringify({keys:[jwk]}));
test('unconfigured identity and missing session fail closed',async()=>{
  await assert.rejects(authenticate(request(),{}),e=>e.status===503);
  await assert.rejects(authenticate(request(),env),e=>e.status===401);
});
test('correct RS256 session verifies',async()=>assert.equal((await authenticate(request(await token()),env,certs)).email,'owner@example.com'));
for (const [name,change] of Object.entries({expired:{exp:0},audience:{aud:['other']},issuer:{iss:'https://attacker.example'},future:{nbf:9999999999},email:{email:null}})) {
  test('rejects '+name,async()=>assert.rejects(authenticate(request(await token({...claims(),...change})),env,certs),e=>e.status===401));
}
test('rejects algorithm confusion and tampered signatures',async()=>{
  await assert.rejects(authenticate(request(await token(claims(),{alg:'HS256',kid:'test-key'})),env,certs),e=>e.status===401);
  const jwt=await token();
  await assert.rejects(authenticate(request(jwt.slice(0,-8)+'AAAAAAAA'),env,certs),e=>e.status===401);
});
function webhook(body,override={}) {
  const url=env.PUBLIC_ORIGIN+'/webhooks/twilio/sms';
  const params=new URLSearchParams({AccountSid:env.TWILIO_ACCOUNT_SID,From:'+12025550123',To:'+12025550124',Body:body});
  let data=url;
  for (const key of [...params.keys()].sort()) data+=key+params.get(key);
  const signature=createHmac('sha1',env.TWILIO_AUTH_TOKEN).update(data).digest('base64');
  return new Request(url,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','X-Twilio-Signature':signature,...override},body:params});
}
test('validates provider signature against independent node HMAC',async()=>assert.equal((await validateWebhook(webhook('hello'),env)).get('Body'),'hello'));
test('rejects forged webhook, changed body, and wrong account',async()=>{
  await assert.rejects(validateWebhook(webhook('hello',{'X-Twilio-Signature':'forged'}),env),e=>e.status===403);
  const signed=webhook('hello');
  const changed=new Request(signed.url,{method:'POST',headers:signed.headers,body:(await signed.text()).replace('hello','changed')});
  await assert.rejects(validateWebhook(changed,env),e=>e.status===403);
  await assert.rejects(validateWebhook(webhook('hello'),{...env,TWILIO_ACCOUNT_SID:'wrong'}),e=>e.status===403);
});
test('validates numbers and exact opt-out keywords',()=>{
  assert.equal(e164('+12025550123'),true);
  for(const value of ['911','+012345678','+1<script>','2025550123',null]) assert.equal(e164(value),false);
  for(const value of ['STOP',' unsubscribe ','REVOKE','optout']) assert.equal(isStop(value),true);
  assert.equal(isStop('please do not stop by'),false);
});
test('API without authentication never reaches database',async()=>{
  const response=await worker.fetch(new Request(env.PUBLIC_ORIGIN+'/api/messages'),{...env,DB:{prepare(){throw Error('must not query');}}});
  assert.equal(response.status,401);
  assert.equal(response.headers.get('Cache-Control'),'no-store');
});
test('webhooks cannot bypass signature verification',async()=>assert.equal((await worker.fetch(new Request(env.PUBLIC_ORIGIN+'/webhooks/twilio/sms',{method:'POST'}),env)).status,415));

function database() {
  const sql=new DatabaseSync(':memory:');
  sql.exec(readFileSync(new URL('../schema.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/002_voice.sql',import.meta.url),'utf8'));
  sql.exec("INSERT INTO users VALUES('owner','owner@example.com','agent',1); INSERT INTO numbers VALUES('line','+12025550124','twilio',0,1,1); INSERT INTO numbers VALUES('private','+12025550125','twilio',0,1,1); INSERT INTO number_permissions VALUES('owner','line');");
  const wrap=(query,args=[])=>({bind(...values){return wrap(query,values);},async first(){return sql.prepare(query).get(...args)||null;},async all(){return {results:sql.prepare(query).all(...args)};},async run(){const r=sql.prepare(query).run(...args);return {meta:{changes:r.changes}};}});
  return {sql,DB:{prepare:wrap,async batch(statements){sql.exec('BEGIN');try{const out=[];for(const s of statements)out.push(await s.run());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}}};
}
async function api(path,body,key='request_unique_12345',jwt) {
  return new Request(env.PUBLIC_ORIGIN+path,{method:body?'POST':'GET',headers:{'Cf-Access-Jwt-Assertion':jwt||await token(),'Origin':env.PUBLIC_ORIGIN,'Content-Type':'application/json','Idempotency-Key':key},...(body?{body:JSON.stringify(body)}:{})});
}
test('database ACL isolates personal numbers and conversation history',async()=>{
  const {sql,DB}=database();
  const lines=await worker.fetch(await api('/api/numbers'),{...env,DB});
  assert.deepEqual((await lines.json()).numbers.map(n=>n.id),['line']);
  assert.equal((await worker.fetch(await api('/api/messages?number_id=private'),{...env,DB})).status,403);
  assert.equal((await worker.fetch(await api('/api/messages',{number_id:'private',to:'+12025550123',body:'hello'}),{...env,DB,TELECOM_ENABLED:'true'})).status,403);
  sql.close();
});
test('disabled traffic, uninvited users and opt-outs block sends',async()=>{
  const {sql,DB}=database();
  const input={number_id:'line',to:'+12025550123',body:'hello'};
  assert.equal((await worker.fetch(await api('/api/messages',input),{...env,DB})).status,503);
  sql.exec("INSERT INTO suppressions(number_id,remote) VALUES('line','+12025550123')");
  assert.equal((await worker.fetch(await api('/api/messages',input),{...env,DB,TELECOM_ENABLED:'true'})).status,409);
  const jwt=await token({...claims(),email:'stranger@example.com'});
  assert.equal((await worker.fetch(await api('/api/numbers',null,null,jwt),{...env,DB})).status,403);
  sql.close();
});
test('accepted SMS persists and retries cannot duplicate provider sends',async()=>{
  const {sql,DB}=database();
  const previous=globalThis.fetch;let calls=0;
  globalThis.fetch=async(url,options)=>{calls++;assert.equal(new URL(url).hostname,'api.twilio.com');assert.equal(new URLSearchParams(options.body).get('From'),'+12025550124');return new Response(JSON.stringify({sid:'SM'+'b'.repeat(32),status:'queued'}));};
  try {
    const input={number_id:'line',to:'+12025550123',body:'hello'};
    const first=await worker.fetch(await api('/api/messages',input),{...env,DB,TELECOM_ENABLED:'true'});
    assert.equal(first.status,202);
    assert.equal(sql.prepare('SELECT status FROM messages').get().status,'queued');
    assert.equal((await worker.fetch(await api('/api/messages',input),{...env,DB,TELECOM_ENABLED:'true'})).status,409);
    assert.equal(calls,1);
    assert.equal(sql.prepare('SELECT count(*) AS n FROM audit_logs').get().n,2);
  } finally {globalThis.fetch=previous;sql.close();}
});
test('signed STOP webhook persists suppression and deduplicates retries',async()=>{
  const {sql,DB}=database();
  const incoming=async()=>{
    const r=webhook('STOP');
    const p=new URLSearchParams(await r.text());p.set('MessageSid','SM'+'c'.repeat(32));
    let data=r.url;for(const key of [...p.keys()].sort())data+=key+p.get(key);
    return new Request(r.url,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','X-Twilio-Signature':createHmac('sha1',env.TWILIO_AUTH_TOKEN).update(data).digest('base64')},body:p});
  };
  assert.equal((await worker.fetch(await incoming(),{...env,DB})).status,200);
  assert.equal((await worker.fetch(await incoming(),{...env,DB})).status,200);
  assert.equal(sql.prepare('SELECT count(*) AS n FROM messages').get().n,1);
  assert.equal(sql.prepare('SELECT count(*) AS n FROM suppressions').get().n,1);
  sql.close();
});

async function receipt(status,sid='SM'+'b'.repeat(32)) {
  const url=env.PUBLIC_ORIGIN+'/webhooks/twilio/status';
  const p=new URLSearchParams({AccountSid:env.TWILIO_ACCOUNT_SID,MessageSid:sid,MessageStatus:status});
  let data=url;for(const key of [...p.keys()].sort())data+=key+p.get(key);
  return new Request(url,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','X-Twilio-Signature':createHmac('sha1',env.TWILIO_AUTH_TOKEN).update(data).digest('base64')},body:p});
}
test('early delivery receipts survive outbound insert and delayed sent receipts',async()=>{
  const {sql,DB}=database();
  const previous=globalThis.fetch;
  globalThis.fetch=async()=>{
    assert.equal((await worker.fetch(await receipt('delivered'),{...env,DB})).status,200);
    return new Response(JSON.stringify({sid:'SM'+'b'.repeat(32),status:'queued'}));
  };
  try {
    assert.equal((await worker.fetch(await api('/api/messages',{number_id:'line',to:'+12025550123',body:'hello'}),{...env,DB,TELECOM_ENABLED:'true'})).status,202);
    assert.equal(sql.prepare('SELECT status FROM messages').get().status,'delivered');
    assert.equal((await worker.fetch(await receipt('sent'),{...env,DB})).status,200);
    assert.equal(sql.prepare('SELECT status FROM messages').get().status,'delivered');
  }finally{globalThis.fetch=previous;sql.close();}
});
test('rate limits and cross-origin requests block before provider access',async()=>{
  const {sql,DB}=database();
  const input={number_id:'line',to:'+12025550123',body:'hello'};
  sql.prepare('INSERT INTO rate_limits VALUES(?,?,10)').run('owner',Math.floor(Date.now()/60000));
  assert.equal((await worker.fetch(await api('/api/messages',input),{...env,DB,TELECOM_ENABLED:'true'})).status,429);
  const r=await api('/api/messages',input);r.headers.set('Origin','https://attacker.example');
  assert.equal((await worker.fetch(r,{...env,DB,TELECOM_ENABLED:'true'})).status,403);
  sql.close();
});
test('ambiguous provider failure cannot be blindly retried',async()=>{
  const {sql,DB}=database();const previous=globalThis.fetch;let calls=0;
  globalThis.fetch=async()=>{calls++;throw Error('timeout');};
  try {
    const input={number_id:'line',to:'+12025550123',body:'hello'};
    assert.equal((await worker.fetch(await api('/api/messages',input),{...env,DB,TELECOM_ENABLED:'true'})).status,502);
    assert.equal((await worker.fetch(await api('/api/messages',input),{...env,DB,TELECOM_ENABLED:'true'})).status,409);
    assert.equal(calls,1);
  }finally{globalThis.fetch=previous;sql.close();}
});

const voiceEnv={...env,TELECOM_ENABLED:'true',TWILIO_API_KEY_SID:'SK'+'d'.repeat(32),TWILIO_API_KEY_SECRET:'test-voice-secret',TWIML_APP_SID:'AP'+'e'.repeat(32),TEST_DESTINATIONS:'+12025550123'};
function voiceDatabase(){const db=database();db.sql.exec("UPDATE numbers SET voice=1");return db;}
async function signedVoice(path,fields){
  const url=env.PUBLIC_ORIGIN+path;
  const p=new URLSearchParams({AccountSid:env.TWILIO_ACCOUNT_SID,CallSid:'CA'+'f'.repeat(32),...fields});
  let data=url;for(const key of [...p.keys()].sort())data+=key+p.get(key);
  return new Request(url,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','X-Twilio-Signature':createHmac('sha1',env.TWILIO_AUTH_TOKEN).update(data).digest('base64')},body:p});
}
test('voice tokens are short-lived, server-signed and bound to a user',async()=>{
  const {sql,DB}=voiceDatabase();
  const result=await createVoiceToken({...voiceEnv,DB},{id:'owner'});
  const [header,body,signature]=result.token.split('.');
  const payload=JSON.parse(Buffer.from(body,'base64url').toString());
  assert.equal(signature,createHmac('sha256',voiceEnv.TWILIO_API_KEY_SECRET).update(header+'.'+body).digest('base64url'));
  assert.equal(payload.grants.identity,'pl_owner');
  assert.equal(payload.exp-payload.iat,300);
  assert.equal(payload.grants.voice.outgoing.application_sid,voiceEnv.TWIML_APP_SID);
  assert.equal(JSON.parse(Buffer.from(header,'base64url').toString()).cty,'twilio-fpa;v=1');
  await assert.rejects(createVoiceToken({...voiceEnv,DB,TELECOM_ENABLED:'false'},{id:'owner'}),e=>e.status===503);
  sql.close();
});
test('outgoing voice requires authorized line, destination and single-use grant',async()=>{
  const {sql,DB}=voiceDatabase();const user={id:'owner',role:'agent'};
  await assert.rejects(createIntent({...voiceEnv,DB},user,{number_id:'private',to:'+12025550123'}),e=>e.status===403);
  await assert.rejects(createIntent({...voiceEnv,DB},user,{number_id:'line',to:'+12025550129'}),e=>e.status===403);
  const intent=await createIntent({...voiceEnv,DB},user,{number_id:'line',to:'+12025550123'});
  const fields={From:'client:pl_owner',To:intent.to,CallGrant:intent.grant,CallerId:'+12025550199'};
  const response=await voiceWebhook(await signedVoice('/webhooks/twilio/voice',fields),{...voiceEnv,DB},'/webhooks/twilio/voice');
  const xml=await response.text();
  assert.match(xml,/callerId="\+12025550124"/);assert.doesNotMatch(xml,/50199/);
  assert.equal(sql.prepare('SELECT used FROM call_intents').get().used,1);
  assert.equal(sql.prepare('SELECT count(*) AS n FROM calls').get().n,1);
  await voiceWebhook(await signedVoice('/webhooks/twilio/voice',fields),{...voiceEnv,DB},'/webhooks/twilio/voice');
  await assert.rejects(voiceWebhook(await signedVoice('/webhooks/twilio/voice',{...fields,CallSid:'CA'+'a'.repeat(32)}),{...voiceEnv,DB},'/webhooks/twilio/voice'),e=>e.status===403);
  sql.close();
});
test('voice grants reject spoofed identities, expired grants and DNC destinations',async()=>{
  const {sql,DB}=voiceDatabase();const user={id:'owner',role:'agent'};
  const intent=await createIntent({...voiceEnv,DB},user,{number_id:'line',to:'+12025550123'});
  await assert.rejects(voiceWebhook(await signedVoice('/webhooks/twilio/voice',{From:'client:pl_attacker',To:intent.to,CallGrant:intent.grant}),{...voiceEnv,DB},'/webhooks/twilio/voice'),e=>e.status===403);
  sql.exec('UPDATE call_intents SET expires_at=0');
  await assert.rejects(voiceWebhook(await signedVoice('/webhooks/twilio/voice',{From:'client:pl_owner',To:intent.to,CallGrant:intent.grant}),{...voiceEnv,DB},'/webhooks/twilio/voice'),e=>e.status===403);
  sql.exec("INSERT INTO voice_dnc VALUES('+12025550123')");
  await assert.rejects(createIntent({...voiceEnv,DB},user,{number_id:'line',to:intent.to}),e=>e.status===409);
  sql.close();
});
test('inbound voice rings only active users assigned to that number',async()=>{
  const {sql,DB}=voiceDatabase();
  sql.exec("INSERT INTO users VALUES('unassigned','nobody@example.com','agent',1)");
  const response=await voiceWebhook(await signedVoice('/webhooks/twilio/incoming',{To:'+12025550124',From:'+12025550123'}),{...voiceEnv,DB},'/webhooks/twilio/incoming');
  const xml=await response.text();assert.match(xml,/pl_owner/);assert.doesNotMatch(xml,/pl_unassigned/);
  sql.exec("UPDATE users SET active=0 WHERE id='owner'");
  assert.match(await (await voiceWebhook(await signedVoice('/webhooks/twilio/incoming',{To:'+12025550124',From:'+12025550123'}),{...voiceEnv,DB},'/webhooks/twilio/incoming')).text(),/Reject/);
  sql.close();
});
test('agents cannot manage accounts and owner cannot disable self',async()=>{
  const {sql,DB}=database();
  assert.equal((await worker.fetch(await api('/api/users'),{...env,DB})).status,403);
  sql.exec("UPDATE users SET role='admin' WHERE id='owner'");
  const req=await api('/api/users',{id:'owner',email:'owner@example.com',role:'agent',active:false});
  const patch=new Request(req,{method:'PATCH'});
  assert.equal((await worker.fetch(patch,{...env,DB})).status,409);
  sql.close();
});
test('an early rejected agent leg cannot mark another ringing agent as a missed call',async()=>{
  const {sql,DB}=voiceDatabase();
  sql.exec("INSERT INTO users VALUES('second','second@example.com','agent',1); INSERT INTO number_permissions VALUES('second','line')");
  await voiceWebhook(await signedVoice('/webhooks/twilio/incoming',{To:'+12025550124',From:'+12025550123'}),{...voiceEnv,DB},'/webhooks/twilio/incoming');
  const parent='CA'+'f'.repeat(32);
  await voiceWebhook(await signedVoice('/webhooks/twilio/call-status',{CallSid:'CA'+'a'.repeat(32),ParentCallSid:parent,CallStatus:'busy',SequenceNumber:'1'}),{...voiceEnv,DB},'/webhooks/twilio/call-status');
  assert.equal(sql.prepare('SELECT status FROM calls').get().status,'ringing');
  await voiceWebhook(await signedVoice('/webhooks/twilio/call-status',{CallSid:'CA'+'b'.repeat(32),ParentCallSid:parent,CallStatus:'in-progress',SequenceNumber:'1'}),{...voiceEnv,DB},'/webhooks/twilio/call-status');
  assert.equal(sql.prepare('SELECT status FROM calls').get().status,'in-progress');
  await voiceWebhook(await signedVoice('/webhooks/twilio/call-status',{CallSid:'CA'+'b'.repeat(32),ParentCallSid:parent,CallStatus:'completed',SequenceNumber:'2',CallDuration:'34'}),{...voiceEnv,DB},'/webhooks/twilio/call-status');
  assert.equal(sql.prepare('SELECT status,duration FROM calls').get().duration,34);
  sql.close();
});
test('large streams are rejected before the complete body is buffered',async()=>{
  let canceled=false;
  const stream=new ReadableStream({start(c){c.enqueue(new Uint8Array(5000));c.enqueue(new Uint8Array(5000));},cancel(){canceled=true;}});
  const req=new Request('https://example.com',{method:'POST',body:stream,duplex:'half'});
  await assert.rejects(readLimited(req,8192),e=>e.status===413);
  assert.equal(canceled,true);
});
test('private frontend assets require an invited active identity',async()=>{
  const {sql,DB}=database();let reads=0;
  const config={...env,DB,ASSETS:{fetch(){reads++;return new Response('app');}}};
  assert.equal((await worker.fetch(new Request(env.PUBLIC_ORIGIN+'/'),config)).status,401);
  assert.equal(reads,0);
  assert.equal((await worker.fetch(await api('/'),config)).status,200);
  assert.equal(reads,1);
  sql.exec("UPDATE users SET active=0");
  assert.equal((await worker.fetch(await api('/'),config)).status,403);
  assert.equal(reads,1);sql.close();
});
