// Customer-only authentication and cash-on-delivery checkout.
// No service_role credentials, no direct database writes from public clients.
// Prices and inventory are always determined by public.place_cash_order in PostgreSQL.
const COOKIE_AT='__Host-shitreed-at';
const COOKIE_RT='__Host-shitreed-rt';
const actions=new Map();
const state=new Map();
function send(res,status,data){
  res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store','pragma':'no-cache','x-content-type-options':'nosniff'});
  res.end(JSON.stringify(data));
}
function parseCookies(req){
 const result={};
 for(const part of (req.headers.cookie||'').split(';')){
  const i=part.indexOf('='); if(i<0)continue;
  const key=part.slice(0,i).trim();
  if(key===COOKIE_AT||key===COOKIE_RT)result[key]=part.slice(i+1).trim();
 }
 return result;
}
function setCookie(res,name,value,maxAge){
 const v=encodeURIComponent(value);
 res.setHeader('Set-Cookie',[...(res.getHeader('Set-Cookie')||[]),name+'='+v+'; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age='+maxAge]);
}
function clearCookies(res){setCookie(res,COOKIE_AT,'',0);setCookie(res,COOKIE_RT,'',0);}
function saveSession(res,tokens){
 if(typeof tokens.access_token!=='string'||typeof tokens.refresh_token!=='string')return false;
 setCookie(res,COOKIE_AT,tokens.access_token,Math.min(Number(tokens.expires_in)||3600,3600));
 setCookie(res,COOKIE_RT,tokens.refresh_token,60*60*24*21);
 return true;
}
function rateLimit(req,name,max,periodMs){
 const key=(req.socket.remoteAddress||'unknown')+'|'+name;
 const now=Date.now();
 const rec=actions.get(key);
 if(!rec||now>rec.until){actions.set(key,{count:1,until:now+periodMs});return true;}
 rec.count++;
 return rec.count<=max;
}
function sameOrigin(req){
 const origin=req.headers.origin;
 if(typeof origin!=='string')return false;
 try{
  const src=new URL(origin);
  const hostname=(req.headers.host||'').toLowerCase();
  return src.protocol==='https:'&&src.host.toLowerCase()===hostname;
 }catch{return false;}
}
async function bodyJson(req,max=12000){
 if(!String(req.headers['content-type']||'').toLowerCase().startsWith('application/json'))throw new Error('BAD_CONTENT_TYPE');
 let size=0,chunks=[];
 for await(const chunk of req){
  size+=chunk.length;
  if(size>max)throw new Error('TOO_LARGE');
  chunks.push(chunk);
 }
 try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw new Error('BAD_JSON');}
}
async function supa(conf,path,opts={}){
 const controller=new AbortController();
 const timeout=setTimeout(()=>controller.abort(),9000);
 try{
  return await fetch(conf.url+path,{...opts,signal:controller.signal,redirect:'manual',
   headers:{'apikey':conf.key,'content-type':'application/json',...(opts.headers||{})}});
 }finally{clearTimeout(timeout);}
}
async function auth(conf,req,res){
 const c=parseCookies(req);
 let token;
 try{token=c[COOKIE_AT]?decodeURIComponent(c[COOKIE_AT]):null;}catch{token=null;}
 if(token){
  try{
   const u=await supa(conf,'/auth/v1/user',{headers:{Authorization:'Bearer '+token}});
   if(u.ok){const user=await u.json();if(user?.id)return{token,user};}
  }catch{}
 }
 let refresh;
 try{refresh=c[COOKIE_RT]?decodeURIComponent(c[COOKIE_RT]):null;}catch{}
 if(!refresh)return null;
 try{
  const r=await supa(conf,'/auth/v1/token?grant_type=refresh_token',{method:'POST',body:JSON.stringify({refresh_token:refresh})});
  if(!r.ok){clearCookies(res);return null;}
  const tokens=await r.json();if(!saveSession(res,tokens))return null;
  const u=await supa(conf,'/auth/v1/user',{headers:{Authorization:'Bearer '+tokens.access_token}});
  if(!u.ok)return null;
  const user=await u.json();return user?.id?{token:tokens.access_token,user}:null;
 }catch{return null;}
}
function validEmail(x){return typeof x==='string'&&x.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(x);}
function validUuid(x){return typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);}
async function proxyStripe(req,res){
 if(req.method!=='POST'){res.writeHead(405,{'allow':'POST'});res.end();return;}
 const signature=req.headers['stripe-signature'];
 const headers={'content-type':req.headers['content-type']||'application/json'};
 if(typeof signature==='string')headers['stripe-signature']=signature;
 const ac=new AbortController();
 const timer=setTimeout(()=>ac.abort(),12000);
 try{
  const stream=[];
  let total=0;
  for await(const part of req){total+=part.length;if(total>1024*1024){res.writeHead(413);return res.end();}stream.push(part);}
  const response=await fetch('https://api.pixer-laravel.com/webhooks/stripe',{method:'POST',body:Buffer.concat(stream),headers,redirect:'manual',signal:ac.signal});
  // Never leak upstream cookies or authentication headers to the requester.
  res.writeHead(response.status,{'content-type':response.headers.get('content-type')||'text/plain','cache-control':'no-store'});
  res.end(Buffer.from(await response.arrayBuffer()));
 }catch{send(res,502,{error:'تعذر تمرير إشعار الدفع القديم'});}
 finally{clearTimeout(timer);}
}
export async function handleShop(req,res,path,conf){
 if(path==='/webhooks/stripe'){await proxyStripe(req,res);return true;}
 if(!path.startsWith('/api/auth/')&&path!=='/api/orders')return false;
 if(!conf.url||!conf.key){send(res,503,{error:'إعداد اتصال الحسابات غير مكتمل'});return true;}
 const method=req.method||'GET';
 if(method!=='GET'&&method!=='POST'){res.writeHead(405,{'allow':'GET, POST'});res.end();return true;}
 if(method==='POST'&&!sameOrigin(req)){send(res,403,{error:'طلب غير مسموح من مصدر آخر'});return true;}
 if(method==='POST'&&!rateLimit(req,path,path==='/api/auth/login'?10:20,15*60*1000)){send(res,429,{error:'طلبات كثيرة. حاول لاحقاً'});return true;}
 try{
  if(path==='/api/auth/login'&&method==='POST'){
   const input=await bodyJson(req);
   if(!validEmail(input?.email)||typeof input?.password!=='string'||input.password.length<8||input.password.length>128)return send(res,400,{error:'راجع البريد الإلكتروني وكلمة المرور'});
   const r=await supa(conf,'/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email:input.email.trim(),password:input.password})});
   if(!r.ok)return send(res,401,{error:'تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور وتأكيد الحساب'});
   const tokens=await r.json();if(!saveSession(res,tokens))return send(res,502,{error:'تعذر إنشاء جلسة آمنة'});
   return send(res,200,{ok:true});
  }
  if(path==='/api/auth/register'&&method==='POST'){
   const input=await bodyJson(req);
   if(!validEmail(input?.email)||typeof input?.password!=='string'||input.password.length<8||input.password.length>128)return send(res,400,{error:'استخدم بريداً صحيحاً وكلمة مرور من 8 أحرف على الأقل'});
   const r=await supa(conf,'/auth/v1/signup',{method:'POST',body:JSON.stringify({email:input.email.trim(),password:input.password})});
   if(!r.ok)return send(res,400,{error:'تعذر إنشاء الحساب. تحقق من البيانات أو حاول لاحقاً'});
   const reply=await r.json();
   const signedIn=saveSession(res,reply);
   return send(res,200,{ok:true,signedIn,checkEmail:!signedIn});
  }
  if(path==='/api/auth/logout'&&method==='POST'){
   const c=parseCookies(req);
   const token=c[COOKIE_AT];
   clearCookies(res);
   if(token)try{await supa(conf,'/auth/v1/logout',{method:'POST',headers:{Authorization:'Bearer '+decodeURIComponent(token)}});}catch{}
   return send(res,200,{ok:true});
  }
  if(path==='/api/auth/session'&&method==='GET'){
   const session=await auth(conf,req,res);
   return send(res,200,session?{authenticated:true,email:session.user.email||'',user_id:session.user.id}:{authenticated:false});
  }
  if(path==='/api/orders'&&method==='GET'){
   const session=await auth(conf,req,res);
   if(!session)return send(res,401,{error:'سجّل الدخول لعرض طلباتك'});
   const url='/rest/v1/orders?select=id,store_id,status,total_iqd,payment_method,created_at&buyer_id=eq.'+encodeURIComponent(session.user.id)+'&order=created_at.desc&limit=25';
   const r=await supa(conf,url,{headers:{Authorization:'Bearer '+session.token}});
   if(!r.ok)return send(res,502,{error:'تعذر تحميل الطلبات'});
   return send(res,200,{orders:await r.json()});
  }
  if(path==='/api/orders'&&method==='POST'){
   if(process.env.ENABLE_COD_CHECKOUT!=='true')return send(res,503,{error:'إنشاء الطلبات غير مفعّل بعد'});
   const session=await auth(conf,req,res);
   if(!session)return send(res,401,{error:'سجّل الدخول قبل إتمام الطلب'});
   const input=await bodyJson(req);
   if(!validUuid(input?.store_id)||!Array.isArray(input.items)||input.items.length<1||input.items.length>20
      ||input.items.some(x=>!validUuid(x?.product_id)||!Number.isInteger(x?.quantity)||x.quantity<1||x.quantity>20)
      ||new Set(input.items.map(x=>x.product_id)).size!==input.items.length
      ||typeof input.delivery_address!=='string'||input.delivery_address.trim().length<8||input.delivery_address.length>300
      ||typeof input.phone!=='string'||input.phone.trim().length<8||input.phone.length>25
      ||typeof input.notes!=='string'||input.notes.length>400
      ||input.confirmed!==true)return send(res,400,{error:'راجع بيانات السلة والعنوان ورقم الهاتف'});
   const idempotency=String(input.request_key||'');
   if(!validUuid(idempotency))return send(res,400,{error:'معرّف الطلب غير صالح'});
   // Prevent same-process accidental double submission. Durable database idempotency is a pre-production follow-up.
   const attemptKey=session.user.id+'|'+idempotency;
   const attempt=state.get(attemptKey);
   if(attempt&&Date.now()<attempt.expires)return send(res,attempt.orderId?200:409,attempt.orderId?{order_id:attempt.orderId,repeated:true}:{error:'الطلب قيد المعالجة'});
   state.set(attemptKey,{expires:Date.now()+60*60*1000});
   const payload={p_store_id:input.store_id,p_items:input.items,p_delivery_address:input.delivery_address.trim(),p_phone:input.phone.trim(),p_notes:input.notes};
   const r=await supa(conf,'/rest/v1/rpc/place_cash_order',{method:'POST',headers:{Authorization:'Bearer '+session.token},body:JSON.stringify(payload)});
   if(!r.ok){state.delete(attemptKey);return send(res,409,{error:'تعذر إتمام الطلب. راجع توفر المنتجات والعنوان'});}
   const id=await r.json();
   if(!validUuid(id)){state.delete(attemptKey);return send(res,502,{error:'استجابة الطلب غير صالحة'});}
   state.set(attemptKey,{expires:Date.now()+60*60*1000,orderId:id});
   return send(res,201,{order_id:id,payment_method:'cash_on_delivery'});
  }
  return send(res,404,{error:'مسار غير موجود'});
 }catch(err){
  // Never log credentials, tokens, cookies, personal data or request bodies.
  const code=err?.message==='TOO_LARGE'?413:err?.message==='BAD_CONTENT_TYPE'?415:err?.message==='BAD_JSON'?400:502;
  return send(res,code,{error:code===413?'بيانات الطلب كبيرة':code===415?'صيغة الطلب غير مدعومة':code===400?'بيانات غير صالحة':'الخدمة غير متاحة مؤقتاً'});
 }
}
