import {test} from 'node:test';
import assert from 'node:assert/strict';
import {configureTwilio} from '../configure-twilio.mjs';
const env={TWILIO_ACCOUNT_SID:'AC'+'a'.repeat(32),TWILIO_AUTH_TOKEN:'test',TWILIO_API_KEY_SID:'SK'+'b'.repeat(32),TWILIO_API_KEY_SECRET:'test',TWIML_APP_SID:'AP'+'c'.repeat(32),POWERLINE_FROM_NUMBER:'+12025550123',PUBLIC_ORIGIN:'https://powerline.example.com'};
const number={sid:'PN'+'d'.repeat(32),phone_number:env.POWERLINE_FROM_NUMBER,capabilities:{voice:true,sms:true},voice_url:'https://demo.twilio.com/welcome/voice/',sms_url:''};
test('provider configuration never runs without protected credentials',async()=>{
  await assert.rejects(configureTwilio({},()=>{throw Error('must not make network requests');}),/Missing protected/);
});
test('configuration updates only owned line and application, without billable calls',async()=>{
  const writes=[];let current={...number};
  const fetcher=async(url,options)=>{
    if(url.startsWith(env.PUBLIC_ORIGIN))return new Response(JSON.stringify({error:'Invalid webhook signature'}),{status:403});
    if(options.method==='POST'){
      writes.push({url,body:Object.fromEntries(options.body)});
      if(url.includes('/IncomingPhoneNumbers/'))current={...current,voice_url:options.body.get('VoiceUrl'),sms_url:options.body.get('SmsUrl')};
    }
    const payload=url.includes('IncomingPhoneNumbers.json?')?{incoming_phone_numbers:[current]}:url.includes('/IncomingPhoneNumbers/')?current:{voice_url:'',sms_url:''};
    return new Response(JSON.stringify(payload));
  };
  assert.equal((await configureTwilio(env,fetcher)).configured,true);
  assert.equal(writes.length,2);
  for(const write of writes)assert.match(write.url,/\/(Applications|IncomingPhoneNumbers)\//);
  assert.equal(writes[1].body.VoiceUrl,env.PUBLIC_ORIGIN+'/webhooks/twilio/incoming');
});
test('unrelated routing is preserved and no provider writes occur',async()=>{
  const fetcher=async(url,options)=>{
    assert.equal(options.method,'GET');
    return new Response(JSON.stringify(url.includes('IncomingPhoneNumbers.json?')?{incoming_phone_numbers:[{...number,voice_url:'https://other-service.example/voice'}]}:{voice_url:'',sms_url:''}));
  };
  await assert.rejects(configureTwilio(env,fetcher),/outside PowerLine/);
});
