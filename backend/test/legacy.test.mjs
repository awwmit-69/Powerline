import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const legacy=require('../../twilio-functions/sms.js');
test('legacy SMS function cannot contact Twilio or emit permissive CORS',()=>{
  globalThis.Twilio={Response:class {
    headers={}; setStatusCode(v){this.status=v;} appendHeader(k,v){this.headers[k]=v;} setBody(v){this.body=v;}
  }};
  let result;
  legacy.handler({getTwilioClient(){throw Error('must not contact provider');}},{to:'+12025550123',body:'hello'},(error,response)=>{assert.equal(error,null);result=response;});
  assert.equal(result.status,410);
  assert.equal(result.headers['Access-Control-Allow-Origin'],undefined);
});
