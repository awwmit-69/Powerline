import {base64url,bytes64,fail,e164} from './security.mjs';
const q=(env,sql,...args)=>env.DB.prepare(sql).bind(...args);
const encode=value=>new TextEncoder().encode(value);
async function cipherKey(env){
  if(!env.AUTH_PEPPER)fail(503,'Server secret storage is not configured');
  const raw=await crypto.subtle.digest('SHA-256',encode('provider-storage:'+env.AUTH_PEPPER));
  return crypto.subtle.importKey('raw',raw,'AES-GCM',false,['encrypt','decrypt']);
}
export async function loadProvider(env){
  const row=await q(env,'SELECT sealed FROM provider_secrets WHERE id=1').first();if(!row)return null;
  const [iv,data]=row.sealed.split('.');
  const raw=await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes64(iv),additionalData:encode('powerline-provider-v1')},await cipherKey(env),bytes64(data));
  return JSON.parse(new TextDecoder().decode(raw));
}
export async function saveProvider(env,value){
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const data=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encode('powerline-provider-v1')},await cipherKey(env),encode(JSON.stringify(value)));
  await q(env,'INSERT INTO provider_secrets(id,sealed) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET sealed=excluded.sealed,updated_at=unixepoch()',base64url(iv)+'.'+base64url(new Uint8Array(data))).run();
}
export async function providerRuntime(env){
  if(env.AUTH_MODE!=='password'||!env.DB)return env;
  const p=await loadProvider(env);if(!p)return env;
  return {...env,TWILIO_ACCOUNT_SID:p.account_sid,TWILIO_AUTH_TOKEN:p.auth_token,TWILIO_API_KEY_SID:p.key_sid,TWILIO_API_KEY_SECRET:p.key_secret,TWIML_APP_SID:p.app_sid,TWILIO_IS_TRIAL:p.trial,TELECOM_ENABLED:p.enabled?'true':'false',TEST_DESTINATIONS:p.recipient||'',MAX_CALL_SECONDS:'60',SMS_TEST_DESTINATIONS:p.recipient||''};
}
async function twilio(p,path,body,fetcher=fetch){
  const response=await fetcher(`https://api.twilio.com/2010-04-01/Accounts/${p.account_sid}${path}`,{method:body?'POST':'GET',headers:{Authorization:'Basic '+btoa(p.account_sid+':'+p.auth_token),...(body?{'Content-Type':'application/x-www-form-urlencoded'}:{})},...(body?{body:new URLSearchParams(body)}:{}),signal:AbortSignal.timeout(20000)});
  if(!response.ok)fail(502,'Twilio rejected the configuration request (HTTP '+response.status+'). Check account access and trial restrictions.');
  return response.json();
}
const summaries=numbers=>numbers.map(n=>({id:n.sid,e164:n.phone_number,voice:!!n.capabilities?.voice,sms:!!n.capabilities?.sms}));
async function setting(request,env,user,path,input,fetcher){
  if(user.role!=='admin')fail(403,'Administrator required');
  if(path==='/api/provider/connect'){
    if(!/^AC[0-9a-f]{32}$/i.test(input.account_sid||'')||typeof input.auth_token!=='string'||input.auth_token.length<16||input.auth_token.length>128)fail(400,'Enter the Twilio Account SID and Auth Token');
    const p={account_sid:input.account_sid,auth_token:input.auth_token,enabled:false};
    const account=await twilio(p,'.json',null,fetcher);
    const numbers=await twilio(p,'/IncomingPhoneNumbers.json?PageSize=100',null,fetcher);
    if(account.status!=='active')fail(409,'Twilio account is not active');
    const old=await loadProvider(env);
    if(old?.account_sid===p.account_sid){p.key_sid=old.key_sid;p.key_secret=old.key_secret;p.app_sid=old.app_sid;p.number_sid=old.number_sid;}
    p.trial=String(account.type).toLowerCase()==='trial';
    await saveProvider(env,p);
    await q(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'provider.connect','twilio')",user.id).run();
    return {connected:true,trial:p.trial,numbers:summaries(numbers.incoming_phone_numbers||[])};
  }
  const p=await loadProvider(env);if(!p)fail(409,'Connect the Twilio account first');
  if(path==='/api/provider/numbers'){
    const rows=await twilio(p,'/IncomingPhoneNumbers.json?PageSize=100',null,fetcher);
    return {trial:p.trial,numbers:summaries(rows.incoming_phone_numbers||[])};
  }
  if(path==='/api/provider/line'){
    if(!/^PN[0-9a-f]{32}$/i.test(input.number_sid||''))fail(400,'Select an existing Twilio number');
    const number=await twilio(p,`/IncomingPhoneNumbers/${input.number_sid}.json`,null,fetcher);
    if(number.account_sid!==p.account_sid||!number.capabilities?.voice)fail(403,'Choose a voice-capable number owned by this account');
    if(number.trunk_sid)fail(409,'This number is assigned to a SIP trunk. Its routing was not changed.');
    for(const sid of [number.voice_application_sid,number.sms_application_sid])if(sid&&sid!==p.app_sid)fail(409,'This number is assigned to another application. Its routing was not changed.');
    const origin=env.PUBLIC_ORIGIN;
    const appParams={FriendlyName:'PowerLine',VoiceUrl:origin+'/webhooks/twilio/voice',VoiceMethod:'POST',SmsUrl:origin+'/webhooks/twilio/sms',SmsMethod:'POST',StatusCallback:origin+'/webhooks/twilio/call-status',StatusCallbackMethod:'POST'};
    if(!p.key_sid){const key=await twilio(p,'/Keys.json',{FriendlyName:'PowerLine browser'},fetcher);p.key_sid=key.sid;p.key_secret=key.secret;await saveProvider(env,p);}
    if(!p.app_sid){const app=await twilio(p,'/Applications.json',appParams,fetcher);p.app_sid=app.sid;await saveProvider(env,p);}
    else await twilio(p,`/Applications/${p.app_sid}.json`,appParams,fetcher);
    await twilio(p,`/IncomingPhoneNumbers/${number.sid}.json`,{VoiceApplicationSid:'',SmsApplicationSid:'',VoiceUrl:origin+'/webhooks/twilio/incoming',VoiceMethod:'POST',SmsUrl:origin+'/webhooks/twilio/sms',SmsMethod:'POST',StatusCallback:origin+'/webhooks/twilio/call-status',StatusCallbackMethod:'POST'},fetcher);
    const verified=await twilio(p,`/IncomingPhoneNumbers/${number.sid}.json`,null,fetcher);
    if(verified.voice_url!==origin+'/webhooks/twilio/incoming'||verified.sms_url!==origin+'/webhooks/twilio/sms')fail(502,'Webhook configuration could not be verified');
    await env.DB.batch([
      q(env,"INSERT INTO numbers(id,e164,provider,voice,sms,active) VALUES(?,?,'twilio',1,?,1) ON CONFLICT(id) DO UPDATE SET e164=excluded.e164,voice=1,sms=excluded.sms,active=1",number.sid,number.phone_number,number.capabilities.sms?1:0),
      q(env,'INSERT OR IGNORE INTO number_permissions(user_id,number_id) VALUES(?,?)',user.id,number.sid),
      q(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'provider.line',?)",user.id,number.sid)
    ]);
    p.number_sid=number.sid;p.enabled=false;await saveProvider(env,p);
    return {configured:true,number:{id:number.sid,e164:number.phone_number},trial:p.trial};
  }
  if(path==='/api/provider/enable'){
    if(!p.number_sid||!p.key_sid||!p.app_sid)fail(409,'Configure the existing number first');
    if(input.approve_usage!==true||!e164(input.recipient))fail(400,'Enter an authorized test recipient and approve Twilio usage charges');
    const account=await twilio(p,'.json',null,fetcher);
    if(account.status!=='active')fail(409,'Twilio account is not active');
    p.trial=String(account.type).toLowerCase()==='trial';
    if(p.trial){
      const verified=await twilio(p,'/OutgoingCallerIds.json?PageSize=100',null,fetcher);
      if(!(verified.outgoing_caller_ids||[]).some(n=>n.phone_number===input.recipient))fail(409,'Trial calling requires this recipient to be verified in Twilio first');
    }
    p.recipient=input.recipient;p.enabled=true;await saveProvider(env,p);
    await q(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'provider.test-usage-approved',?)",user.id,p.number_sid).run();
    return {enabled:true,recipient:p.recipient,max_call_seconds:60,trial:p.trial};
  }
  if(path==='/api/provider/disable'){
    p.enabled=false;await saveProvider(env,p);return {enabled:false};
  }
  fail(404,'Not found');
}
export async function providerSetting(request,env,user,path,input,fetcher=fetch){
  if(user.role!=='admin')fail(403,'Administrator required');
  if(request.method==='GET')return setting(request,env,user,path,input,fetcher);
  const token=crypto.randomUUID();
  const lock=await q(env,"INSERT INTO provider_locks(key,token,expires_at) VALUES('configuration',?,unixepoch()+180) ON CONFLICT(key) DO UPDATE SET token=excluded.token,expires_at=excluded.expires_at WHERE provider_locks.expires_at<unixepoch() RETURNING token",token).first();
  if(!lock)fail(409,'Another provider configuration change is in progress');
  try{return await setting(request,env,user,path,input,fetcher);}finally{await q(env,"DELETE FROM provider_locks WHERE key='configuration' AND token=?",token).run();}
}
