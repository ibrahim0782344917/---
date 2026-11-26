import test from 'node:test';
import assert from 'node:assert/strict';
import {validateEvent} from './alani-fcm-validation-worker.mjs';
const now=Date.parse('2026-11-26T20:00:00Z');
const event={id:'00000000-0000-4000-8000-000000000001',recipient_id:'00000000-0000-4000-8000-000000000002',event_kind:'return_update',app_kind:'customer',expires_at:new Date(now+120000).toISOString(),private_note:'DO NOT SEND'};
const device={user_id:event.recipient_id,app_kind:event.app_kind,session_active:true,consent:true,verified:true,event_authorized:true,revoked:false,token:'synthetic_test_token_123456789'};
const opts={event,projectRef:'tgvdwotbrnhcoykuxdpr',now,authorizeDevice:async()=>device,getAccessToken:async()=> 'synthetic-access',fetchImpl:async()=>{throw Error('unexpected network')}};
test('validates only, correct endpoint, generic payload, never includes private note',async()=>{
 let calls=0;
 const r=await validateEvent({...opts,fetchImpl:async(url,req)=>{
  calls++;assert.equal(url,'https://fcm.googleapis.com/v1/projects/alani-store-e3dc9/messages:send');
  const body=JSON.parse(req.body);assert.equal(body.validate_only,true);assert.equal(body.message.token,device.token);
  assert.equal(body.message.android.ttl,'120s');assert.deepEqual(body.message.data,{kind:'return_update'});
  assert.ok(!req.body.includes('DO NOT SEND'));return {ok:true,status:200};
 }});
 assert.equal(calls,1);assert.equal(r.state,'validated');assert.ok(!JSON.stringify(r).includes(device.token));
});
test('wrong environment and expired event fail closed',async()=>{
 assert.equal((await validateEvent({...opts,projectRef:'ltwncrewggdrjevakwpb'})).code,'WRONG_ENVIRONMENT');
 assert.equal((await validateEvent({...opts,event:{...event,expires_at:new Date(now).toISOString()}})).state,'expired');
});
test('reject invalid event kind and missing adapter',async()=>{
 assert.equal((await validateEvent({...opts,event:{...event,event_kind:'anything'}})).code,'INVALID_EVENT');
 assert.equal((await validateEvent({...opts,authorizeDevice:null})).code,'ADAPTER_MISSING');
});
test('never sends for unverified, revoked, wrong user, inactive, or wrong role',async()=>{
 for(const patch of [{verified:false},{revoked:true},{user_id:'other'},{session_active:false},{app_kind:'admin'},{consent:false},{event_authorized:false}]){
  const r=await validateEvent({...opts,authorizeDevice:async()=>({...device,...patch})});assert.equal(r.code,'DEVICE_NOT_AUTHORIZED');
 }
});
test('retry bounded by known status, no error body leakage',async()=>{
 const r=await validateEvent({...opts,fetchImpl:async()=>({ok:false,status:429,headers:{get:()=> '120'}})});
 assert.deepEqual(r,{state:'retry',code:'FCM_TEMPORARY',delaySeconds:120});
 assert.equal((await validateEvent({...opts,fetchImpl:async()=>({ok:false,status:503})})).state,'retry');
 assert.equal((await validateEvent(opts)).code,'NETWORK_OR_TIMEOUT');
});
test('auth and not-found errors block rather than retry blindly',async()=>{
 for(const status of [401,403,404]) assert.equal((await validateEvent({...opts,fetchImpl:async()=>({ok:false,status})})).state,'blocked');
});
