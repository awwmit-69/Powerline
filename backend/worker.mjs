import {authenticate,validateWebhook,e164,isStop,fail,HttpError} from './security.mjs';
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
      if (path === '/webhooks/twilio/sms' || path === '/webhooks/twilio/status') return await webhook(request,env,path);
      if (!path.startsWith('/api/')) fail(404,'Not found');
      const claims = await authenticate(request,env);
      if (!env.DB) fail(503,'Storage not configured');
      const user = await run(env,'SELECT * FROM users WHERE email=? AND active=1',claims.email.toLowerCase()).first();
      if (!user) fail(403,'User has not been invited');
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
      if (request.headers.get('Origin') !== env.PUBLIC_ORIGIN || url.origin !== env.PUBLIC_ORIGIN) fail(403,'Same-origin requests required');
      if (!(request.headers.get('Content-Type') || '').startsWith('application/json')) fail(415,'JSON required');
      const raw = await request.text();
      if (raw.length > 8192) fail(413,'Payload too large');
      let input; try {input=JSON.parse(raw);} catch {fail(400,'Invalid JSON');}
      if (!input || typeof input !== 'object' || !e164(input.to) || typeof input.body !== 'string' || !input.body.trim() || input.body.length>1600) fail(400,'Valid destination and body required');
      // Match the existing Flutter client's from field, but authorize it server-side.
      const id = input.number_id || (await run(env,'SELECT id FROM numbers WHERE e164=?',input.from || '').first())?.id;
      if (typeof id !== 'string' || !id) fail(400,'An authorized source number is required');
      const number = await permitted(env,user,id,'sms');
      if (number.provider !== 'twilio') fail(409,'Provider adapter is not enabled');
      if (await run(env,'SELECT 1 FROM suppressions WHERE number_id=? AND remote=?',number.id,input.to).first()) fail(409,'Recipient has opted out');
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
