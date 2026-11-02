import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {EventEmitter} from 'node:events';

function bridge(){
  const events=[],requests=[];let device;
  class Call extends EventEmitter {
    parameters={CallSid:'CA'+'a'.repeat(32),From:'+12025550123'};
    status(){return 'pending';}
    accept(){this.emit('accept');}
    reject(){this.emit('reject');}
    disconnect(){this.emit('disconnect');}
    mute(value){this.muted=value;}
    sendDigits(value){this.digits=value;}
  }
  class Device extends EventEmitter {
    constructor(){super();device=this;}
    async register(){this.emit('registered');}
    async connect(options){this.lastParams=options.params;this.call=new Call();return this.call;}
    updateToken(value){this.token=value;}
    destroy(){this.destroyed=true;}
  }
  const window={};
  const fetch=async(url,options)=>{
    requests.push({path:new URL(url).pathname,...options});
    const path=new URL(url).pathname;
    const payload=path.endsWith('/token')?{token:'test-token'}:path.endsWith('/intent')?{grant:'approved-grant'}:{sid:'SM'+'b'.repeat(32),status:'queued'};
    return {ok:true,json:async()=>payload};
  };
  runInNewContext(readFileSync(new URL('../../flutter_app/web/powerline_live.js',import.meta.url),'utf8'),{window,location:{origin:'https://powerline.example.com'},URL,crypto,fetch,Twilio:{Device},setTimeout,clearTimeout});
  return {window,events,requests,Call,get device(){return device;}};
}
test('browser registers, obtains authorized intent and controls a real SDK call object',async()=>{
  const b=bridge();
  await b.window.powerlineLiveInitialize(value=>b.events.push(JSON.parse(value)));
  assert.equal(b.events[0].state,'ready');
  await b.window.powerlineLiveCall('line','+12025550123');
  assert.deepEqual(JSON.parse(JSON.stringify(b.device.lastParams)),{To:'+12025550123',CallGrant:'approved-grant'});
  b.device.call.emit('accept');
  assert.equal(b.events.at(-1).state,'connected');
  b.window.powerlineLiveMute(true);assert.equal(b.device.call.muted,true);
  b.window.powerlineLiveDigits('12#');assert.equal(b.device.call.digits,'12#');
  assert.throws(()=>b.window.powerlineLiveDigits('<bad>'));
  await assert.rejects(b.window.powerlineLiveCall('line','+12025550123'));
  b.window.powerlineLiveHangup();assert.equal(b.events.at(-1).state,'completed');
  b.window.powerlineLiveDispose();assert.equal(b.device.destroyed,true);
});
test('inbound browser invite can be answered and rejected, without simulated calls',async()=>{
  const b=bridge();await b.window.powerlineLiveInitialize(value=>b.events.push(JSON.parse(value)));
  const first=new b.Call();b.device.emit('incoming',first);
  assert.equal(b.events.at(-1).state,'incoming');
  b.window.powerlineLiveAnswer();assert.equal(b.events.at(-1).state,'connected');
  b.window.powerlineLiveHangup();
  const second=new b.Call();b.device.emit('incoming',second);b.window.powerlineLiveReject();
  assert.equal(b.events.at(-1).state,'rejected');
  b.window.powerlineLiveDispose();
});
test('browser API refuses cross-origin paths and never equates SMS acceptance to delivery',async()=>{
  const b=bridge();
  await assert.rejects(b.window.powerlineLiveRequest('GET','https://attacker.example/api/messages'));
  const result=JSON.parse(await b.window.powerlineLiveRequest('POST','/api/messages',JSON.stringify({number_id:'line',to:'+12025550123',body:'hello'})));
  assert.equal(result.status,'queued');
  assert.equal(b.requests[0].credentials,'same-origin');
  assert.ok(b.requests[0].headers['Idempotency-Key']);
});
