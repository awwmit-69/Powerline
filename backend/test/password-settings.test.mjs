import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import worker from '../worker.mjs';
import {authRoute,currentUser,passwordHash,usernameHash} from '../password-auth.mjs';
import {saveProvider,loadProvider,providerRuntime,providerSetting} from '../provider-settings.mjs';
import {base64url} from '../security.mjs';

async function fixture(){
  const db=new DatabaseSync(':memory:');
  for(const path of ['schema.sql','migrations/002_voice.sql','migrations/003_password_auth.sql'])db.exec(readFileSync(new URL('../'+path,import.meta.url),'utf8'));
  db.exec("INSERT INTO users VALUES('owner','owner@example.com','admin',1); INSERT INTO users VALUES('agent01','agent01@unassigned.invalid','agent',1)");
  const wrap=(sql,args=[])=>({bind(...values){return wrap(sql,values);},async first(){return db.prepare(sql).get(...args)||null;},async run(){const r=db.prepare(sql).run(...args);return {meta:{changes:r.changes}};},async all(){return {results:db.prepare(sql).all(...args)};}});
  const env={AUTH_MODE:'password',AUTH_PEPPER:'test-pepper',PUBLIC_ORIGIN:'https://powerline.example.com',DB:{prepare:wrap,async batch(list){db.exec('BEGIN');try{const out=[];for(const item of list)out.push(await item.run());db.exec('COMMIT');return out;}catch(e){db.exec('ROLLBACK');throw e;}}}};
  const username='pl-'+crypto.randomUUID(),salt=base64url(crypto.getRandomValues(new Uint8Array(32)));
  db.prepare('INSERT INTO credentials(user_id,username_hash,salt,password_hash) VALUES(?,?,?,?)').run('owner',await usernameHash(username,env.AUTH_PEPPER),salt,await passwordHash(username,salt,env.AUTH_PEPPER));
  return {env,db,username};
}
function req(env,path,body,cookie){return new Request(env.PUBLIC_ORIGIN+path,{method:body?'POST':'GET',headers:{Origin:env.PUBLIC_ORIGIN,'Content-Type':'application/json',...(cookie?{Cookie:cookie}:{})},...(body?{body:JSON.stringify(body)}:{})});}
test('same random username and password sign in with a hashed HttpOnly session',async()=>{
  const {env,db,username}=await fixture();
  const response=await authRoute(req(env,'/api/auth/login',{username,password:username}),env,'/api/auth/login');
  const cookie=response.headers.get('Set-Cookie');
  assert.match(cookie,/Secure; HttpOnly; SameSite=Strict/);assert.doesNotMatch(cookie,new RegExp(username));
  const sessionCookie=cookie.split(';')[0];
  assert.equal((await currentUser(req(env,'/api/session',null,sessionCookie),env)).id,'owner');
  const raw=db.prepare('SELECT * FROM credentials').get();
  assert.notEqual(raw.username_hash,username);assert.notEqual(raw.password_hash,username);
  assert.notEqual(db.prepare('SELECT token_hash FROM sessions').get().token_hash,sessionCookie.split('=')[1]);
  await authRoute(req(env,'/api/auth/logout',{},sessionCookie),env,'/api/auth/logout');
  await assert.rejects(currentUser(req(env,'/api/session',null,sessionCookie),env),e=>e.status===401);db.close();
});
test('wrong credentials, CSRF, inactive users and lockout fail closed',async()=>{
  const {env,db,username}=await fixture();
  await assert.rejects(authRoute(req(env,'/api/auth/login',{username,password:'wrong'}),env,'/api/auth/login'),e=>e.status===401);
  const bad=req(env,'/api/auth/login',{username,password:username});bad.headers.set('Origin','https://attacker.example');
  await assert.rejects(authRoute(bad,env,'/api/auth/login'),e=>e.status===403);
  db.exec('UPDATE users SET active=0');
  await assert.rejects(authRoute(req(env,'/api/auth/login',{username,password:username}),env,'/api/auth/login'),e=>e.status===401);
  for(let i=0;i<6;i++)try{await authRoute(req(env,'/api/auth/login',{username,password:'wrong'}),env,'/api/auth/login');}catch{}
  await assert.rejects(authRoute(req(env,'/api/auth/login',{username,password:username}),env,'/api/auth/login'),e=>e.status===429);db.close();
});
test('login page is public but private app and provider setup require sessions',async()=>{
  const {env,db,username}=await fixture();env.ASSETS={fetch:()=>new Response('private-app')};
  const login=await worker.fetch(req(env,'/login'),env);assert.equal(login.status,200);assert.match(await login.text(),/autocomplete="username"/);assert.match(login.headers.get('Content-Security-Policy'),/frame-ancestors 'none'/);
  assert.equal((await worker.fetch(req(env,'/'),env)).status,303);
  assert.equal((await worker.fetch(req(env,'/api/session'),env)).status,401);
  const response=await worker.fetch(req(env,'/api/auth/login',{username,password:username}),env);
  const cookie=response.headers.get('Set-Cookie').split(';')[0];
  assert.equal(await (await worker.fetch(req(env,'/',null,cookie),env)).text(),'private-app');
  assert.equal((await worker.fetch(req(env,'/setup/twilio',null,cookie),env)).status,200);
  db.exec("UPDATE users SET role='agent' WHERE id='owner'");
  assert.equal((await worker.fetch(req(env,'/setup/twilio',null,cookie),env)).status,403);db.close();
});
test('Twilio credentials are encrypted at rest and never returned to the browser',async()=>{
  const {env,db}=await fixture();
  const value={account_sid:'AC'+'a'.repeat(32),auth_token:'test-token-for-provider-fixture',enabled:false};
  await saveProvider(env,value);assert.deepEqual(await loadProvider(env),value);
  const sealed=db.prepare('SELECT sealed FROM provider_secrets').get().sealed;
  assert.ok(!sealed.includes(value.auth_token));assert.ok(!sealed.includes(value.account_sid));
  assert.equal((await providerRuntime(env)).TELECOM_ENABLED,'false');
  await assert.rejects(loadProvider({...env,AUTH_PEPPER:'wrong-key'}));db.close();
});
test('owner can configure existing trial line and only enable a verified test recipient',async()=>{
  const {env,db}=await fixture();const calls=[];
  const sid='AC'+'a'.repeat(32),numberSid='PN'+'b'.repeat(32),phone='+12025550123';
  let number={sid:numberSid,account_sid:sid,phone_number:phone,capabilities:{voice:true,sms:true}};
  const fetcher=async(url,options)=>{
    calls.push({url,method:options.method});let data;
    if(url.endsWith('/Keys.json'))data={sid:'SK'+'c'.repeat(32),secret:'private-voice-key'};
    else if(url.endsWith('/Applications.json'))data={sid:'AP'+'d'.repeat(32)};
    else if(url.includes('/IncomingPhoneNumbers/')){
      if(options.method==='POST')number={...number,voice_url:options.body.get('VoiceUrl'),sms_url:options.body.get('SmsUrl')};data=number;
    }else if(url.includes('/IncomingPhoneNumbers.json'))data={incoming_phone_numbers:[number]};
    else if(url.includes('/OutgoingCallerIds.json'))data={outgoing_caller_ids:[{phone_number:phone}]};
    else data={status:'active',type:'Trial'};
    return new Response(JSON.stringify(data));
  };
  const owner={id:'owner',role:'admin'};
  const connected=await providerSetting({method:'POST'},env,owner,'/api/provider/connect',{account_sid:sid,auth_token:'test-auth-token-32characters'},fetcher);
  assert.equal(connected.trial,true);assert.ok(!JSON.stringify(connected).includes('test-auth-token'));
  await providerSetting({method:'POST'},env,owner,'/api/provider/line',{number_sid:numberSid},fetcher);
  assert.equal(db.prepare('SELECT active FROM numbers').get().active,1);
  assert.equal(db.prepare('SELECT user_id FROM number_permissions').get().user_id,'owner');
  assert.equal((await providerRuntime(env)).TELECOM_ENABLED,'false');
  await assert.rejects(providerSetting({method:'POST'},env,owner,'/api/provider/enable',{recipient:'+12025550199',approve_usage:true},fetcher),e=>e.status===409);
  await providerSetting({method:'POST'},env,owner,'/api/provider/enable',{recipient:phone,approve_usage:true},fetcher);
  const runtime=await providerRuntime(env);assert.equal(runtime.TELECOM_ENABLED,'true');assert.equal(runtime.MAX_CALL_SECONDS,'60');
  for(const call of calls)assert.ok(!/\/Calls|\/Messages/.test(call.url));
  await assert.rejects(providerSetting({method:'POST'},env,{id:'agent01',role:'agent'},'/api/provider/connect',{},fetcher),e=>e.status===403);db.close();
});
test('known edge challenges prevent routing changes and test activation',async()=>{
  const {env,db}=await fixture();env.WEBHOOK_EDGE_READY='false';
  await saveProvider(env,{account_sid:'AC'+'a'.repeat(32),auth_token:'test-fixture-token',enabled:false});
  const denied=()=>{throw Error('must not contact provider while edge is blocked');};
  await assert.rejects(providerSetting({method:'POST'},env,{id:'owner',role:'admin'},'/api/provider/line',{number_sid:'PN'+'b'.repeat(32)},denied),/Cloudflare/);
  await assert.rejects(providerSetting({method:'POST'},env,{id:'owner',role:'admin'},'/api/provider/enable',{recipient:'+12025550123',approve_usage:true},denied),/Cloudflare/);
  assert.equal(db.prepare('SELECT count(*) AS n FROM numbers').get().n,0);db.close();
});
