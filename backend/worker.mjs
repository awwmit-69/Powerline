import {authenticate,validateWebhook,e164,isStop,fail,HttpError,readJson} from './security.mjs';
import {createVoiceToken,createIntent,voiceWebhook,authorizedNumber} from './voice.mjs';
import {currentUser,authRoute} from './password-auth.mjs';
import {loginPage} from './login.mjs';
import {providerRuntime,providerSetting} from './provider-settings.mjs';
import {setupPage} from './setup-page.mjs';
import {serveEmbedded} from './embedded-assets.mjs';
const json = (data,status=200) => new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'}});
const xml = () => new Response('<?xml version="1.0" encoding="UTF-8"?><Response/>',{headers:{'Content-Type':'text/xml','Cache-Control':'no-store'}});
const run = (env,sql,...values) => env.DB.prepare(sql).bind(...values);
async function permitted(env,user,number,capability) {
  const row = await run(env,`SELECT n.* FROM numbers n WHERE n.id=? AND n.active=1 AND (EXISTS(SELECT 1 FROM number_permissions p WHERE p.number_id=n.id AND p.user_id=?) OR ?='admin')`,number,user.id,user.role).first();
  if (!row || (capability && !row[capability])) fail(403,'Number is not authorized');
  return row;
}
async function webhook(request,env,path) {
  const p = await validateWebhook(request,env);
  const sid = p.get('MessageSid');
  if (!/^SM[0-9a-fA-F]{32}$/.test(sid || '')) fail(400,'Invalid message identifier');
  if (path === '/webhooks/twilio/sms') {
    const number = await run(env,'SELECT * FROM numbers WHERE e164=? AND active=1 AND sms=1',p.get('To')).first();
    if (!number) fail(404,'Unknown number');
    if (!e164(p.get('From'))) fail(400,'Unsupported sender');
    const body = p.get('Body') || '';
    if (body.length > 1600) fail(400,'Message too long');
    const statements = [run(env,"INSERT OR IGNORE INTO messages(sid,number_id,remote,direction,body,status) VALUES(?,?,?,'inbound',?,'received')",sid,number.id,p.get('From'),body)];
    // Never automatically clear a suppression on START: require verified consent.
    if (isStop(body) || p.get('OptOutType') === 'STOP') statements.push(run(env,'INSERT OR IGNORE INTO suppressions(number_id,remote) VALUES(?,?)',number.id,p.get('From')));
    await env.DB.batch(statements);
    return xml();
  }
  const status = p.get('MessageStatus');
  if (!['queued','sending','sent','delivered','undelivered','failed'].includes(status)) fail(400,'Invalid status');
  // A delayed sent/queued event must never overwrite a terminal receipt.
  await env.DB.batch([
    run(env,"INSERT INTO delivery_events(sid,status) VALUES(?,?) ON CONFLICT(sid) DO UPDATE SET status=excluded.status,received_at=unixepoch() WHERE delivery_events.status NOT IN ('delivered','undelivered','failed')",sid,status),
    run(env,"UPDATE messages SET status=? WHERE sid=? AND direction='outbound' AND status NOT IN ('delivered','undelivered','failed')",status,sid)
  ]);
  return xml();
}
export default {
  async fetch(request,env) {
    try {
      const url = new URL(request.url), path = url.pathname;
      if(path==='/login'&&request.method==='GET')return loginPage();
      if(path==='/api/auth/login'||path==='/api/auth/logout')return await authRoute(request,env,path);
      if(path.startsWith('/webhooks/twilio/'))env=await providerRuntime(env);
      if(['/webhooks/twilio/voice','/webhooks/twilio/incoming','/webhooks/twilio/call-status'].includes(path))return await voiceWebhook(request,env,path);
      if (path === '/webhooks/twilio/sms' || path === '/webhooks/twilio/status') return await webhook(request,env,path);
      let user;
      try{user=await currentUser(request,env);}catch(error){
        if(env.AUTH_MODE==='password'&&!path.startsWith('/api/')&&error.status===401)return Response.redirect(url.origin+'/login',303);
        throw error;
      }
      if(path==='/setup/twilio'){
        if(user.role!=='admin')fail(403,'Administrator required');
        return setupPage(env);
      }
      if(['/api/provider/connect','/api/provider/line','/api/provider/enable','/api/provider/disable','/api/provider/numbers'].includes(path)){
        if(path==='/api/provider/numbers'&&request.method!=='GET')fail(405,'GET required');
        if(path!=='/api/provider/numbers'&&request.method!=='POST')fail(405,'POST required');
        return json(await providerSetting(request,env,user,path,request.method==='GET'?{}:await readJson(request,env)));
      }
      if(!path.startsWith('/api/')){
        if(!env.ASSETS)return serveEmbedded(request);
        return env.ASSETS.fetch(request);
      }
      env=await providerRuntime(env);
      if(path==='/api/provider/status'&&request.method==='GET')return json({enabled:env.TELECOM_ENABLED==='true',sms_configured:!!(env.TWILIO_ACCOUNT_SID&&env.TWILIO_AUTH_TOKEN),voice_configured:!!(env.TWILIO_API_KEY_SID&&env.TWILIO_API_KEY_SECRET&&env.TWIML_APP_SID),emergency_calling:false});
      if(path==='/api/voice/token'&&request.method==='GET')return json(await createVoiceToken(env,user));
      if(path==='/api/voice/intent'&&request.method==='POST')return json(await createIntent(env,user,await readJson(request,env)),201);
      if(path==='/api/calls'&&request.method==='GET'){
        const number=await authorizedNumber(env,user,url.searchParams.get('number_id'),'voice');
        return json({calls:(await run(env,'SELECT sid,number_id,remote,direction,status,duration,created_at FROM calls WHERE number_id=? ORDER BY created_at DESC,sid DESC LIMIT 100',number.id).all()).results});
      }
      if(path==='/api/users'){
        if(user.role!=='admin')fail(403,'Administrator required');
        if(request.method==='GET')return json({users:(await run(env,'SELECT id,email,role,active FROM users ORDER BY id').all()).results});
        if(request.method!=='PATCH')fail(405,'Method not allowed');
        const input=await readJson(request,env);
        if(typeof input.id!=='string'||!['admin','agent'].includes(input.role)||typeof input.email!=='string'||input.email.length>254||!/^\S+@\S+\.\S+$/.test(input.email)||![true,false].includes(input.active))fail(400,'Valid ID, email, role and active status required');
        if(input.active&&input.email.endsWith('.invalid')&&env.AUTH_MODE!=='password')fail(400,'Assign a real email before activation');
        if(input.id===user.id&&(!input.active||input.role!=='admin'||input.email.toLowerCase()!==user.email))fail(409,'You cannot remove your own owner access');
        if(!await run(env,'SELECT id FROM users WHERE id=?',input.id).first())fail(404,'Account slot does not exist');
        await env.DB.batch([run(env,'UPDATE users SET email=?,role=?,active=? WHERE id=?',input.email.toLowerCase(),input.role,input.active?1:0,input.id),run(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'user.update',?)",user.id,input.id)]);
        return json({updated:true});
      }
      if(path==='/api/permissions'&&request.method==='POST'){
        if(user.role!=='admin')fail(403,'Administrator required');
        const input=await readJson(request,env);
        if(typeof input.user_id!=='string'||typeof input.number_id!=='string'||typeof input.grant!=='boolean')fail(400,'Account, number and grant flag required');
        if(!await run(env,'SELECT id FROM users WHERE id=?',input.user_id).first()||!await run(env,'SELECT id FROM numbers WHERE id=? AND active=1',input.number_id).first())fail(404,'Unknown account or number');
        await env.DB.batch([input.grant?run(env,'INSERT OR IGNORE INTO number_permissions(user_id,number_id) VALUES(?,?)',input.user_id,input.number_id):run(env,'DELETE FROM number_permissions WHERE user_id=? AND number_id=?',input.user_id,input.number_id),run(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'number.permission',?)",user.id,input.user_id+':'+input.number_id)]);
        return json({updated:true});
      }
      if (path === '/api/session' && request.method === 'GET') return json({id:user.id,role:user.role,email:user.email});
      if (path === '/api/numbers' && request.method === 'GET') {
        const result = await run(env,"SELECT n.* FROM numbers n WHERE n.active=1 AND (?='admin' OR EXISTS(SELECT 1 FROM number_permissions p WHERE p.number_id=n.id AND p.user_id=?))",user.role,user.id).all();
        return json({numbers:result.results});
      }
      if (path !== '/api/messages') fail(404,'Not found');
      if (request.method === 'GET') {
        const number = await permitted(env,user,url.searchParams.get('number_id'),'sms');
        const result = await run(env,'SELECT * FROM messages WHERE number_id=? ORDER BY created_at DESC,sid DESC LIMIT 100',number.id).all();
        return json({messages:result.results});
      }
      if (request.method !== 'POST') fail(405,'Method not allowed');
      const input=await readJson(request,env);
      if (!input || typeof input !== 'object' || !e164(input.to) || typeof input.body !== 'string' || !input.body.trim() || input.body.length>1600) fail(400,'Valid destination and body required');
      // Match the existing Flutter client's from field, but authorize it server-side.
      const id = input.number_id || (await run(env,'SELECT id FROM numbers WHERE e164=?',input.from || '').first())?.id;
      if (typeof id !== 'string' || !id) fail(400,'An authorized source number is required');
      const number = await permitted(env,user,id,'sms');
      if (number.provider !== 'twilio') fail(409,'Provider adapter is not enabled');
      if (await run(env,'SELECT 1 FROM suppressions WHERE number_id=? AND remote=?',number.id,input.to).first()) fail(409,'Recipient has opted out');
      if(env.SMS_TEST_DESTINATIONS&&!env.SMS_TEST_DESTINATIONS.split(',').includes(input.to))fail(403,'Recipient is not approved for test messaging');
      if (env.TELECOM_ENABLED !== 'true' || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_ACCOUNT_SID) fail(503,'Paid telecom traffic is disabled');
      const requestId = request.headers.get('Idempotency-Key');
      if (!/^[a-zA-Z0-9_-]{16,100}$/.test(requestId || '')) fail(400,'Idempotency-Key required');
      const window = Math.floor(Date.now()/60000);
      const rate = await run(env,'INSERT INTO rate_limits(user_id,window,count) VALUES(?,?,1) ON CONFLICT(user_id,window) DO UPDATE SET count=count+1 RETURNING count',user.id,window).first();
      if (rate.count > 10) fail(429,'Send rate exceeded');
      const claim = await run(env,"INSERT OR IGNORE INTO send_attempts(user_id,request_id,state) VALUES(?,?,'pending')",user.id,requestId).run();
      if (!claim.meta.changes) fail(409,'Send already attempted; check message history before retrying');
      await run(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'sms.send.attempt',?)",user.id,requestId).run();
      // No automatic retries: an ambiguous provider response could already have sent.
      let response;
      try {
        response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`,{method:'POST',headers:{Authorization:'Basic '+btoa(env.TWILIO_ACCOUNT_SID+':'+env.TWILIO_AUTH_TOKEN),'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({To:input.to,From:number.e164,Body:input.body,StatusCallback:env.PUBLIC_ORIGIN+'/webhooks/twilio/status'}),signal:AbortSignal.timeout(15000)});
      } catch {fail(502,'Provider response unknown; do not resend before checking history');}
      if (!response.ok) fail(502,'Provider rejected the message');
      const message = await response.json();
      if (!/^SM[0-9a-fA-F]{32}$/.test(message.sid || '')) fail(502,'Provider returned an invalid response');
      await env.DB.batch([
        run(env,"INSERT INTO messages(sid,number_id,remote,direction,body,status) VALUES(?,?,?,'outbound',?,COALESCE((SELECT status FROM delivery_events WHERE sid=?),?))",message.sid,number.id,input.to,input.body,message.sid,message.status || 'queued'),
        run(env,"UPDATE send_attempts SET state='accepted',sid=? WHERE user_id=? AND request_id=?",message.sid,user.id,requestId),
        run(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'sms.accepted',?)",user.id,message.sid)
      ]);
      return json({sid:message.sid,status:message.status || 'queued'},202);
    } catch(error) {return json({error:error instanceof HttpError ? error.message : 'Internal service error'},error instanceof HttpError ? error.status : 500);}
  }
};
