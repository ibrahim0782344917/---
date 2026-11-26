// Private TEST worker. The adapter and isolated TEST OAuth credential must be provisioned separately.
const endpoint='https://fcm.googleapis.com/v1/projects/alani-store-e3dc9/messages:send';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export async function runChallengeWorker({projectRef,adapter,getAccessToken,fetchImpl=fetch,mode='validate',allowLiveTestSend=false,now=Date.now}) {
  if(projectRef!=='tgvdwotbrnhcoykuxdpr'||!['validate','send'].includes(mode))return {state:'blocked'};
  if(mode==='send'&&allowLiveTestSend!==true)return {state:'blocked'};
  if(!adapter||typeof adapter.claim!=='function'||typeof adapter.finish!=='function'||typeof getAccessToken!=='function')return {state:'blocked'};
  let c;
  try{c=await adapter.claim();}catch{return {state:'retry'};}
  if(!c)return {state:'empty'};
  if(!uuid.test(c.id??'')||!uuid.test(c.claim_key??''))return {state:'blocked'};
  const finish=async outcome=>{
    try{return {state:await adapter.finish(c.id,c.claim_key,outcome)===true?outcome:'lease_lost'};}
    catch{return {state:'lease_lost'};}
  };
  const expiry=Date.parse(c.expires_at);
  if(!Number.isFinite(expiry)||expiry-now()<15000||!(/^[a-f0-9]{64}$/.test(c.nonce??''))||typeof c.token!=='string'||c.token.length<20||c.token.length>4096||/\s/.test(c.token))return finish('failed');
  let access;
  try{access=await getAccessToken();}catch{return finish('retry');}
  if(typeof access!=='string'||!access||/\s/.test(access))return finish('retry');
  const ttl=Math.min(120,Math.floor((expiry-now())/1000));
  if(ttl<10)return finish('failed');
  let r;
  try{
    r=await fetchImpl(endpoint,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),
      headers:{Authorization:'Bearer '+access,'Content-Type':'application/json'},
      body:JSON.stringify({validate_only:mode!=='send',message:{token:c.token,
        data:{kind:'device_challenge',challenge_id:c.id,nonce:c.nonce},android:{ttl:ttl+'s',priority:'HIGH'}}})});
  }catch{return finish('retry');}
  if(r.ok)return finish(mode==='send'?'accepted':'validated');
  if(r.status===429||r.status>=500)return finish('retry');
  return finish('failed');
}
