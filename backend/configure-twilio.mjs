// Operator-side configuration only. Never included in the Worker/frontend bundle.
import {pathToFileURL} from 'node:url';

export async function configureTwilio(env,fetcher=fetch) {
  for(const name of ['TWILIO_ACCOUNT_SID','TWILIO_AUTH_TOKEN','TWILIO_API_KEY_SID','TWILIO_API_KEY_SECRET','TWIML_APP_SID','POWERLINE_FROM_NUMBER','PUBLIC_ORIGIN']) {
    if(!env[name])throw Error('Missing protected configuration: '+name);
  }
  if(!/^AC[0-9a-f]{32}$/i.test(env.TWILIO_ACCOUNT_SID)||!/^AP[0-9a-f]{32}$/i.test(env.TWIML_APP_SID)||!/^SK[0-9a-f]{32}$/i.test(env.TWILIO_API_KEY_SID)||!/^\+[1-9]\d{7,14}$/.test(env.POWERLINE_FROM_NUMBER))throw Error('Invalid provider configuration');
  const origin=new URL(env.PUBLIC_ORIGIN);
  if(origin.protocol!=='https:'||origin.origin!==env.PUBLIC_ORIGIN)throw Error('PUBLIC_ORIGIN must be an HTTPS origin');
  const root=`https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}`;
  const authorization='Basic '+Buffer.from(env.TWILIO_ACCOUNT_SID+':'+env.TWILIO_AUTH_TOKEN).toString('base64');
  async function api(path,body){
    const response=await fetcher(root+path,{method:body?'POST':'GET',headers:{Authorization:authorization,...(body?{'Content-Type':'application/x-www-form-urlencoded'}:{})},...(body?{body:new URLSearchParams(body)}:{}),signal:AbortSignal.timeout(20000)});
    if(!response.ok)throw Error('Twilio configuration request failed (HTTP '+response.status+')');
    return response.json();
  }
  const list=await api('/IncomingPhoneNumbers.json?'+new URLSearchParams({PhoneNumber:env.POWERLINE_FROM_NUMBER}));
  const matches=(list.incoming_phone_numbers||[]).filter(n=>n.phone_number===env.POWERLINE_FROM_NUMBER);
  if(matches.length!==1)throw Error('Configured number is not uniquely owned by this Twilio account');
  const number=matches[0];
  if(!number.capabilities?.voice||!number.capabilities?.sms)throw Error('Selected number must support voice and SMS');
  if(number.trunk_sid)throw Error('Selected number is attached to a SIP trunk; routing was not changed');
  if([number.voice_application_sid,number.sms_application_sid].some(s=>s&&s!==env.TWIML_APP_SID))throw Error('Selected number belongs to another application; routing was not changed');
  const app=await api(`/Applications/${env.TWIML_APP_SID}.json`);
  function existingRouteAllowed(url){
    if(!url)return true;
    try{const u=new URL(url);return u.origin===origin.origin||u.hostname==='powerline-voice-2020.twil.io'||u.hostname==='demo.twilio.com';}catch{return false;}
  }
  if(![number.voice_url,number.sms_url,app.voice_url,app.sms_url].every(existingRouteAllowed))throw Error('Existing routing is outside PowerLine; no configuration changed');
  // Confirm provider webhooks reach our signature validator rather than a login page.
  const probe=await fetcher(origin.origin+'/webhooks/twilio/incoming',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:''});
  let detail;try{detail=await probe.json();}catch{throw Error('Webhook routing is not ready');}
  if(probe.status!==403||detail.error!=='Invalid webhook signature')throw Error('Webhook signature boundary is not ready; no configuration changed');
  const status=origin.origin+'/webhooks/twilio/call-status';
  await api(`/Applications/${env.TWIML_APP_SID}.json`,{VoiceUrl:origin.origin+'/webhooks/twilio/voice',VoiceMethod:'POST',SmsUrl:origin.origin+'/webhooks/twilio/sms',SmsMethod:'POST',StatusCallback:status,StatusCallbackMethod:'POST'});
  await api(`/IncomingPhoneNumbers/${number.sid}.json`,{VoiceApplicationSid:'',SmsApplicationSid:'',VoiceUrl:origin.origin+'/webhooks/twilio/incoming',VoiceMethod:'POST',SmsUrl:origin.origin+'/webhooks/twilio/sms',SmsMethod:'POST',StatusCallback:status,StatusCallbackMethod:'POST'});
  const verified=await api(`/IncomingPhoneNumbers/${number.sid}.json`);
  if(verified.voice_url!==origin.origin+'/webhooks/twilio/incoming'||verified.sms_url!==origin.origin+'/webhooks/twilio/sms')throw Error('Provider update requires verification; inspect routing before retrying');
  return {configured:true,number_id:number.sid,voice:!!verified.capabilities.voice,sms:!!verified.capabilities.sms};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{await configureTwilio(process.env);console.log('Twilio routing configured and read back. No call, SMS or number purchase was initiated.');}
  catch(error){console.error(error.message);process.exitCode=1;}
}
