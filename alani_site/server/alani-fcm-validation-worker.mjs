// TEST-only FCM transport. No production sending, no public endpoint, no scheduler.
const ENDPOINT = 'https://fcm.googleapis.com/v1/projects/alani-store-e3dc9/messages:send';
const TEST_PROJECT = 'tgvdwotbrnhcoykuxdpr';
const EVENTS = new Set(['order_created','order_update','support_update','delivery_update','return_update']);
const ROLES = new Set(['customer','merchant','admin']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const result=(state,code,delaySeconds=0)=>({state,code,delaySeconds});
export async function validateEvent({event, projectRef, authorizeDevice, getAccessToken, fetchImpl=fetch, now=Date.now()}) {
  // Caller must implement a trusted private database adapter. Never accept a client-supplied authorization result.
  if (projectRef!==TEST_PROJECT) return result('suppressed','WRONG_ENVIRONMENT');
  if (!event || !EVENTS.has(event.event_kind) || !ROLES.has(event.app_kind) || !UUID.test(event.id??'') || !UUID.test(event.recipient_id??'')) return result('suppressed','INVALID_EVENT');
  const expiry=Date.parse(event.expires_at);
  if (!Number.isFinite(expiry) || expiry<=now) return result('expired','EVENT_EXPIRED');
  if (typeof authorizeDevice!=='function' || typeof getAccessToken!=='function') return result('suppressed','ADAPTER_MISSING');
  let device, access;
  try { device=await authorizeDevice(event); } catch { return result('retry','AUTH_CHECK_FAILED',60); }
  if (!device || device.user_id!==event.recipient_id || device.app_kind!==event.app_kind || device.session_active!==true || device.consent!==true || device.verified!==true || device.event_authorized!==true || device.revoked!==false || typeof device.token!=='string' || device.token.length<20 || device.token.length>4096 || /\s/.test(device.token)) return result('suppressed','DEVICE_NOT_AUTHORIZED');
  try { access=await getAccessToken(); } catch { return result('retry','TOKEN_UNAVAILABLE',60); }
  if (typeof access!=='string' || !access || /[\r\n]/.test(access)) return result('retry','TOKEN_UNAVAILABLE',60);
  const ttl=Math.min(300,Math.floor((expiry-now)/1000));
  if (ttl<1) return result('expired','EVENT_EXPIRED');
  let response;
  try {
    response=await fetchImpl(ENDPOINT,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{Authorization:'Bearer '+access,'Content-Type':'application/json'},body:JSON.stringify({
      validate_only:true,
      message:{token:device.token,notification:{title:'السيد إبراهيم العاني',body:'لديك تحديث جديد. افتح التطبيق للاطلاع عليه.'},data:{kind:event.event_kind},android:{ttl:ttl+'s'}}
    })});
  } catch { return result('retry','NETWORK_OR_TIMEOUT',60); }
  if(response.ok) return result('validated','FCM_VALIDATION_ACCEPTED');
  // Never log or return response bodies or device tokens; only known error codes.
  if(response.status===429 || response.status>=500) {
    const raw=response.headers?.get('retry-after');
    const seconds=raw && /^\d+$/.test(raw) ? Number(raw) : 60;
    const wait=Math.max(60,Math.min(3600,seconds));
    return result('retry','FCM_TEMPORARY',wait);
  }
  if(response.status===401 || response.status===403) return result('blocked','FCM_AUTHORIZATION_FAILED');
  if(response.status===404) return result('blocked','FCM_NOT_FOUND_REVIEW');
  return result('failed','FCM_REQUEST_REJECTED');
}
