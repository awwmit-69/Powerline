import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {authenticate,base64url,validateWebhook,e164,isStop} from '../security.mjs';
import worker from '../worker.mjs';
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
