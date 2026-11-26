// Server-only FCM HTTP v1 transport. Not a public endpoint or queue worker.
// The caller must reauthorize the recipient/device/session and respect consent.
// No token, key, response body, order details or message contents are logged.
import {createSign} from 'node:crypto';
const project='alani-store-e3dc9';
const oauth='https://oauth2.googleapis.com/token';
const endpoint='https://fcm.googleapis.com/v1/projects/'+project+'/messages:send';
const scope='https://www.googleapis.com/auth/firebase.messaging';
const labels={order_update:'لديك تحديث جديد. افتح التطبيق للاطلاع.',support_update:'لديك رسالة جديدة. افتح التطبيق للاطلاع.'};
const b64=x=>Buffer.from(x).toString('base64url');
function assertion(account, now){
  if(account?.project_id!==project||account.type!=='service_account'||typeof account.client_email!=='string'||typeof account.private_key!=='string')throw new Error('FCM_CREDENTIAL_CONFIGURATION');
  const head=b64(JSON.stringify({alg:'RS256',typ:'JWT'}));
  const body=b64(JSON.stringify({iss:account.client_email,scope,aud:oauth,iat:now,exp:now+3600}));
  const signer=createSign('RSA-SHA256');
  signer.update(head+'.'+body);signer.end();
  return head+'.'+body+'.'+signer.sign(account.private_key).toString('base64url');
}
export function createFcmTransport({account,fetchImpl=fetch,clock=Date.now}){
  let cached=null;
  async function access(){
    const now=Math.floor(clock()/1000);
    if(cached&&cached.expires>now+60)return cached.token;
    const body=new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:assertion(account,now)});
    const response=await fetchImpl(oauth,{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body,signal:AbortSignal.timeout(12000)});
    if(!response.ok)throw new Error('FCM_OAUTH_FAILED');
    const value=await response.json();
    if(typeof value.access_token!=='string'||!Number.isFinite(value.expires_in)||value.expires_in<=60)throw new Error('FCM_OAUTH_INVALID_RESPONSE');
    cached={token:value.access_token,expires:now+value.expires_in};
    return cached.token;
  }
  return async function send({token,kind,expiresAt,authorized}){
    // Internal call only. This boolean is not a substitute for database authorization.
    if(authorized!==true||!Object.hasOwn(labels,kind)||typeof token!=='string'||token.length<20||token.length>4096)return {state:'suppressed'};
    const remaining=Math.floor((Date.parse(expiresAt)-clock())/1000);
    if(!Number.isFinite(remaining)||remaining<=0)return {state:'expired'};
    const payload={message:{token,notification:{title:'السيد إبراهيم العاني',body:labels[kind]},android:{ttl:Math.min(remaining,300)+'s',priority:'normal',notification:{visibility:'PRIVATE'}}}};
    let bearer;
    try{bearer=await access();}catch{return {state:'retry',code:'FCM_AUTH_UNAVAILABLE'};}
    try{
      const r=await fetchImpl(endpoint,{method:'POST',headers:{authorization:'Bearer '+bearer,'content-type':'application/json'},body:JSON.stringify(payload),signal:AbortSignal.timeout(12000)});
      if(r.ok)return {state:'accepted'};
      let error;
      try{error=await r.json();}catch{}
      const codes=Array.isArray(error?.error?.details)?error.error.details.map(x=>x?.errorCode):[];
      if(codes.includes('UNREGISTERED'))return {state:'invalid_token',code:'UNREGISTERED'};
      if(r.status===401){cached=null;return {state:'retry',code:'FCM_AUTH_EXPIRED'};}
      if(r.status===429||r.status>=500)return {state:'retry',code:'FCM_TEMPORARY'};
      return {state:'failed',code:'FCM_REJECTED'};
    }catch{return {state:'retry',code:'FCM_NETWORK'};}
  };
}
