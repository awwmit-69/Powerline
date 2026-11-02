import {base64url,hmac,validateWebhook,e164,fail} from './security.mjs';
const q=(env,sql,...values)=>env.DB.prepare(sql).bind(...values);
const twiml=body=>new Response(`<?xml version="1.0" encoding="UTF-8"?><Response>${body}</Response>`,{headers:{'Content-Type':'text/xml','Cache-Control':'no-store'}});
const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const terminal=['completed','busy','failed','no-answer','canceled'];
export function enabled(env) {
  if(env.TELECOM_ENABLED!=='true')fail(503,'Telecom traffic is disabled pending configuration and usage approval');
  for(const key of ['TWILIO_ACCOUNT_SID','TWILIO_AUTH_TOKEN','PUBLIC_ORIGIN'])if(!env[key])fail(503,'Twilio configuration is incomplete');
}
export async function authorizedNumber(env,user,id,capability) {
  if(typeof id!=='string')fail(400,'Choose an assigned number');
  const row=await q(env,"SELECT n.* FROM numbers n WHERE n.id=? AND n.active=1 AND (?='admin' OR EXISTS(SELECT 1 FROM number_permissions p WHERE p.number_id=n.id AND p.user_id=?))",id,user.role,user.id).first();
  if(!row||!row[capability]||row.provider!=='twilio')fail(403,'Number is not authorized for this operation');
  return row;
}
export async function limit(env,key,max=10) {
  const minute=Math.floor(Date.now()/60000);
  const result=await q(env,'INSERT INTO rate_limits(user_id,window,count) VALUES(?,?,1) ON CONFLICT(user_id,window) DO UPDATE SET count=count+1 RETURNING count',key,minute).first();
  if(result.count>max)fail(429,'Rate limit exceeded');
}
export async function createVoiceToken(env,user) {
  enabled(env);
  if(!env.TWILIO_API_KEY_SID||!env.TWILIO_API_KEY_SECRET||!env.TWIML_APP_SID)fail(503,'Twilio voice key and TwiML application are not configured');
  if(!/^[A-Za-z0-9_-]{1,80}$/.test(user.id))fail(503,'Invalid voice identity');
  await limit(env,'token:'+user.id,6);
  const now=Math.floor(Date.now()/1000);
  const encode=x=>base64url(new TextEncoder().encode(JSON.stringify(x)));
  const identity='pl_'+user.id;
  const header=encode({typ:'JWT',alg:'HS256',cty:'twilio-fpa;v=1'});
  const body=encode({jti:env.TWILIO_API_KEY_SID+'-'+now+'-'+crypto.randomUUID(),iss:env.TWILIO_API_KEY_SID,sub:env.TWILIO_ACCOUNT_SID,iat:now,nbf:now,exp:now+300,grants:{identity,voice:{incoming:{allow:true},outgoing:{application_sid:env.TWIML_APP_SID}}}});
  return {token:header+'.'+body+'.'+base64url(await hmac(env.TWILIO_API_KEY_SECRET,header+'.'+body)),identity,expires_at:now+300};
}
export async function createIntent(env,user,input) {
  enabled(env);
  if(!e164(input.to))fail(400,'Use a telephone number in international +country format');
  const number=await authorizedNumber(env,user,input.number_id,'voice');
  const allowed=String(env.TEST_DESTINATIONS||'').split(',').map(x=>x.trim()).filter(Boolean);
  if(env.UNRESTRICTED_CALLING!=='true'&&!allowed.includes(input.to))fail(403,'Destination is not approved for calling');
  if(await q(env,'SELECT 1 FROM voice_dnc WHERE remote=?',input.to).first())fail(409,'This destination is on the do-not-call list');
  await limit(env,'dial:'+user.id,5);
  const grant=base64url(crypto.getRandomValues(new Uint8Array(32)));
  const hash=base64url(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(grant))));
  await env.DB.batch([
    q(env,'INSERT INTO call_intents(token_hash,user_id,number_id,remote,expires_at) VALUES(?,?,?,?,unixepoch()+60)',hash,user.id,number.id,input.to),
    q(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'voice.intent',?)",user.id,number.id)
  ]);
  return {grant,to:input.to,number_id:number.id};
}
export async function voiceWebhook(request,env,path) {
  const p=await validateWebhook(request,env);
  enabled(env);
  const sid=p.get('CallSid');
  if(!/^CA[0-9a-f]{32}$/i.test(sid||''))fail(400,'Invalid call identifier');
  const callback=escape(env.PUBLIC_ORIGIN+'/webhooks/twilio/call-status');
  if(path==='/webhooks/twilio/voice') {
    const grant=p.get('CallGrant')||'';
    if(!/^[\w-]{43}$/.test(grant))fail(403,'Missing authorized call intent');
    const hash=base64url(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(grant))));
    const old=await q(env,'SELECT * FROM calls WHERE sid=?',sid).first();
    if(old){
      // A signed Twilio retry of the same authorized parent call is idempotent.
      if(old.intent_hash!==hash||p.get('From')!=='client:pl_'+old.user_id||old.remote!==p.get('To'))fail(403,'Call identity mismatch');
      const user=await q(env,'SELECT * FROM users WHERE id=? AND active=1',old.user_id).first();
      if(!user)fail(403,'Inactive user');
      const number=await authorizedNumber(env,user,old.number_id,'voice');
      if(terminal.includes(old.status))return twiml('<Hangup/>');
      return twiml(`<Dial callerId="${escape(number.e164)}" answerOnBridge="true" timeLimit="600" timeout="30"><Number statusCallback="${callback}" statusCallbackMethod="POST" statusCallbackEvent="initiated ringing answered completed">${escape(old.remote)}</Number></Dial>`);
    }
    const intent=await q(env,'SELECT * FROM call_intents WHERE token_hash=? AND used=0 AND expires_at>=unixepoch()',hash).first();
    if(!intent||p.get('From')!=='client:pl_'+intent.user_id||p.get('To')!==intent.remote)fail(403,'Invalid or expired call intent');
    const user=await q(env,'SELECT * FROM users WHERE id=? AND active=1',intent.user_id).first();
    if(!user)fail(403,'Inactive user');
    const number=await authorizedNumber(env,user,intent.number_id,'voice');
    if(await q(env,'SELECT 1 FROM voice_dnc WHERE remote=?',intent.remote).first())fail(409,'Destination is blocked');
    const claim=await q(env,'UPDATE call_intents SET used=1 WHERE token_hash=? AND used=0 RETURNING token_hash',hash).first();
    if(!claim)fail(409,'Call intent has already been used');
    await q(env,"INSERT INTO calls(sid,number_id,user_id,remote,direction,status,intent_hash) VALUES(?,?,?,?,'outbound','initiated',?)",sid,number.id,user.id,intent.remote,hash).run();
    return twiml(`<Dial callerId="${escape(number.e164)}" answerOnBridge="true" timeLimit="600" timeout="30"><Number statusCallback="${callback}" statusCallbackMethod="POST" statusCallbackEvent="initiated ringing answered completed">${escape(intent.remote)}</Number></Dial>`);
  }
  if(path==='/webhooks/twilio/incoming') {
    const number=await q(env,'SELECT * FROM numbers WHERE e164=? AND active=1 AND voice=1',p.get('To')).first();
    if(!number||!e164(p.get('From')))return twiml('<Reject reason="rejected"/>');
    const users=await q(env,"SELECT u.id FROM users u JOIN number_permissions np ON np.user_id=u.id WHERE np.number_id=? AND u.active=1 ORDER BY u.id LIMIT 5",number.id).all();
    await q(env,"INSERT OR IGNORE INTO calls(sid,number_id,remote,direction,status,ring_targets) VALUES(?,?,?,'inbound','ringing',?)",sid,number.id,p.get('From'),Math.max(1,users.results.length)).run();
    if(!users.results.length)return twiml('<Reject reason="busy"/>');
    const clients=users.results.map(u=>`<Client statusCallback="${callback}" statusCallbackMethod="POST" statusCallbackEvent="initiated ringing answered completed">pl_${escape(u.id)}</Client>`).join('');
    return twiml(`<Dial answerOnBridge="true" timeLimit="600" timeout="25">${clients}</Dial>`);
  }
  const status=p.get('CallStatus');
  if(!['initiated','queued','ringing','in-progress',...terminal].includes(status))fail(400,'Invalid call status');
  const parent=p.get('ParentCallSid')||sid;
  const sequence=Number(p.get('SequenceNumber')||0);
  const duration=Number(p.get('CallDuration')||0);
  if(!Number.isSafeInteger(sequence)||sequence<0||!Number.isSafeInteger(duration)||duration<0||duration>86400)fail(400,'Invalid call metrics');
  // Child events are ordered per child, then aggregated for multi-agent inbound calls.
  await q(env,"INSERT INTO call_events(sid,parent_sid,status,sequence,duration) VALUES(?,?,?,?,?) ON CONFLICT(sid) DO UPDATE SET status=excluded.status,sequence=excluded.sequence,duration=excluded.duration WHERE excluded.sequence>=call_events.sequence AND call_events.status NOT IN ('completed','busy','failed','no-answer','canceled')",sid,parent,status,sequence,duration).run();
  const events=(await q(env,'SELECT status,duration FROM call_events WHERE parent_sid=?',parent).all()).results;
  const call=await q(env,'SELECT ring_targets FROM calls WHERE sid=?',parent).first();
  let aggregate;
  if(events.some(e=>e.status==='completed'))aggregate='completed';
  else if(events.some(e=>e.status==='in-progress'))aggregate='in-progress';
  else if(events.some(e=>!terminal.includes(e.status))||events.length<(call?.ring_targets||1))aggregate='ringing';
  else aggregate=status;
  await q(env,"UPDATE calls SET status=?,duration=?,updated_at=unixepoch() WHERE sid=? AND status NOT IN ('completed','busy','failed','no-answer','canceled')",aggregate,Math.max(0,...events.map(e=>e.duration)),parent).run();
  return twiml('');
}
