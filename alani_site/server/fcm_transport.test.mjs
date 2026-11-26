import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {createFcmTransport} from './fcm_transport.mjs';
const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}});
const account={project_id:'alani-store-e3dc9',type:'service_account',client_email:'synthetic@example.invalid',private_key:privateKey};
const now=Date.now();
const request={token:'synthetic-device-token-0001',kind:'order_update',expiresAt:new Date(now+600000).toISOString(),authorized:true};
function mock(status=200,details=[],overrideAccount=account){let calls=[];const send=createFcmTransport({account:overrideAccount,clock:()=>now,fetchImpl:async(url,options)=>{calls.push([url,options]);if(url.includes('oauth2'))return Response.json({access_token:'synthetic',expires_in:3600});return Response.json({error:{details}},{status});}});return {send,calls};}
test('unauthorized and expired events do not reach network',async()=>{const {send,calls}=mock();assert.equal((await send({...request,authorized:false})).state,'suppressed');assert.equal((await send({...request,expiresAt:new Date(now-1000).toISOString()})).state,'expired');assert.equal(calls.length,0);});
test('accepted, generic private payload and OAuth cache',async()=>{const {send,calls}=mock();assert.equal((await send(request)).state,'accepted');assert.equal((await send({...request,kind:'support_update'})).state,'accepted');assert.equal(calls.length,3);const p=JSON.parse(calls[1][1].body).message;assert.equal(p.android.ttl,'300s');assert.equal(p.android.notification.visibility,'PRIVATE');assert.equal(p.data,undefined);assert.equal(p.token,request.token);});
test('unregistered token classified',async()=>{const {send}=mock(404,[{errorCode:'UNREGISTERED'}]);assert.equal((await send(request)).state,'invalid_token');});
test('temporary errors classified',async()=>{for(const s of [429,503])assert.equal((await mock(s).send(request)).code,'FCM_TEMPORARY');});
test('401 refreshes credentials',async()=>{const {send,calls}=mock(401);assert.equal((await send(request)).code,'FCM_AUTH_EXPIRED');await send(request);assert.equal(calls.filter(c=>c[0].includes('oauth2')).length,2);});
test('wrong Firebase project refuses OAuth',async()=>{const {send,calls}=mock(200,[],{...account,project_id:'other'});assert.equal((await send(request)).code,'FCM_AUTH_UNAVAILABLE');assert.equal(calls.length,0);});
