import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';

const PORT = Number(process.env.PORT || 3000);
const SB_URL = (process.env.SUPABASE_URL || '').replace(/\/+$/, '');
const SB_KEY = process.env.SUPABASE_PUBLISHABLE_KEY || '';
const STORE_ID = process.env.ALANI_STORE_ID || '25091ca2-c0da-416c-b634-81b188ee66be';
const CHECKOUT_ENABLED = process.env.ALANI_CHECKOUT_ENABLED === 'true';
const RETURNS_ENABLED = process.env.ALANI_RETURNS_ENABLED === 'true';
const root = join(dirname(fileURLToPath(import.meta.url)), 'public');
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const staticRoutes = {
  '/':'index.html', '/index.html':'index.html', '/admin':'admin.html',
  '/admin/':'admin.html', '/privacy':'privacy.html', '/terms':'terms.html',
  '/site.css':'site.css', '/site.js':'site.js', '/admin.js':'admin.js',
  '/info.js':'info.js','/menu.js':'menu.js',
  '/welcome':'info.html','/about-us':'info.html',
  '/payment-policy':'info.html','/return-policy':'info.html',
  '/return-request':'info.html','/broken-product':'info.html',
  '/help':'info.html','/settings':'info.html',
};
const mime = {
  '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8',
  '.js':'text/javascript; charset=utf-8',
};
const limits = new Map();

const headers = {
  'x-content-type-options':'nosniff',
  'x-frame-options':'DENY',
  'referrer-policy':'strict-origin-when-cross-origin',
  'permissions-policy':'camera=(),microphone=(),geolocation=()',
  'content-security-policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: https://*.supabase.co; connect-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
function respond(res, status, obj) {
  res.writeHead(status, {
    'content-type':'application/json; charset=utf-8',
    'cache-control':'no-store'
  });
  res.end(JSON.stringify(obj));
}
function healthy() { return Boolean(SB_URL && SB_KEY && /^https:\/\//.test(SB_URL)); }
function needConfig() { if (!healthy()) throw new HttpError(503,'الموقع لم يكتمل ربطه بقاعدة البيانات.'); }
async function readBody(req) {
  let total = 0, input = '';
  for await (const chunk of req) {
    total += chunk.length;
    if (total > 64 * 1024) throw new HttpError(413, 'حجم البيانات كبير.');
    input += chunk.toString('utf8');
  }
  try { return JSON.parse(input || '{}'); }
  catch { throw new HttpError(400, 'صيغة البيانات غير صحيحة.'); }
}
function tokenFrom(req) {
  const match = /^Bearer ([A-Za-z0-9._~-]+)$/.exec(String(req.headers.authorization || ''));
  return match?.[1] || null;
}
async function supabase(path, options = {}, token = null) {
  needConfig();
  const requestHeaders = {
    'apikey': SB_KEY, 'accept':'application/json',
    ...options.body ? { 'content-type':'application/json', 'prefer':'return=representation' } : {},
  };
  if (token) requestHeaders.authorization = 'Bearer ' + token;
  const response = await fetch(SB_URL + path, {
    ...options,
    headers: requestHeaders,
    signal: AbortSignal.timeout(10000),
  });
  const body = await response.text();
  let data;
  try { data = body ? JSON.parse(body) : null; }
  catch { data = null; }
  if (!response.ok) {
    if (response.status === 404 || data?.code === 'PGRST205') {
      throw new HttpError(503,'هذه الوحدة لم تُفعّل في قاعدة البيانات بعد.');
    }
    if (response.status === 401 || response.status === 403) {
      throw new HttpError(403,'لا تمتلك صلاحية تنفيذ هذه العملية.');
    }
    throw new HttpError(response.status >= 500 ? 503 : 400,
      'تعذّر تنفيذ العملية؛ راجع المعلومات أو حاول مجدداً.');
  }
  return data;
}
function selectUrl(table, query) {
  return '/rest/v1/' + table + '?' + query;
}
async function publicShop() {
  needConfig();
  const id = encodeURIComponent(STORE_ID);
  const [stores, products] = await Promise.all([
    supabase(selectUrl('stores', 'select=id,name,area,description,opening_hours,phone,address,logo_url&status=eq.approved&id=eq.'+id+'&limit=1')),
    supabase(selectUrl('products', 'select=id,name,description,price_iqd,stock_quantity,image_url&is_active=eq.true&store_id=eq.'+id+'&order=created_at.desc&limit=100')),
  ]);
  const store = stores?.[0] || null;
  return {store, products: store ? products : [], checkoutEnabled: CHECKOUT_ENABLED};
}
async function publications(token = null, owner = false) {
  const path = selectUrl('alani_publications',
    'select=id,kind,title,body,ingredients,safety_note,image_url,video_url,status,published_at,created_at&store_id=eq.'
    + encodeURIComponent(STORE_ID)
    + (owner ? '' : '&status=eq.published')
    + '&order=created_at.desc&limit=100');
  try { return { available:true, items: await supabase(path, {}, token) }; }
  catch (error) {
    if (error.status === 503) return {available:false,items:[]};
    throw error;
  }
}
async function authOwner(req) {
  const token = tokenFrom(req);
  if (!token) throw new HttpError(401,'سجل الدخول أولاً.');
  const user = await supabase('/auth/v1/user', {}, token);
  const rows = await supabase(selectUrl('stores',
    'select=id,owner_id&limit=1&id=eq.'+encodeURIComponent(STORE_ID)), {}, token);
  if (!user?.id || !rows.length || user.id !== rows[0].owner_id) {
    throw new HttpError(403,'الإدارة متاحة لمالك هذا المتجر فقط.');
  }
  return token;
}
function validText(value, min, max) {
  return typeof value === 'string' && value.trim().length >= min && value.trim().length <= max;
}
function validUrl(value) {
  if (value === '' || value === null || value === undefined) return true;
  try { let u = new URL(value); return u.protocol === 'https:' && u.hostname.length > 3; }
  catch { return false; }
}
function str(v) { return typeof v === 'string' ? v.trim() : ''; }
async function handleApi(req, res, path) {
  if (req.method === 'GET' && path === '/api/health') {
    return respond(res,200,{ok:true,service:'alani-natural-store',configured:healthy()});
  }
  if (req.method === 'GET' && path === '/api/catalog') {
    return respond(res,200,await publicShop());
  }
  if (req.method === 'GET' && path === '/api/publications') {
    return respond(res,200,await publications());
  }
  if (req.method === 'GET' && path === '/api/config') {
    return respond(res,200,{checkoutEnabled:CHECKOUT_ENABLED,
      returnsEnabled:RETURNS_ENABLED,
      deliveryFeeIqd:5000,optionalReturnFeeIqd:5000,
      paymentMethod:'cash_on_delivery',storeId:STORE_ID});
  }
  if (req.method === 'GET' && path === '/api/returns/config') {
    return respond(res,200,{enabled:RETURNS_ENABLED,
      feeForVoluntaryReturnIqd:5000,
      initialDeliveryFeeIqd:5000,
      merchantFaultCasesNoDeduction:true});
  }
  if (req.method === 'POST' && path === '/api/login') {
    const ip = req.socket.remoteAddress || 'unknown';
    const now = Date.now(), state = limits.get(ip) || {count:0,time:now};
    if (now - state.time > 5*60*1000) {state.count=0;state.time=now;}
    if (++state.count > 15) throw new HttpError(429,'محاولات كثيرة؛ حاول لاحقاً.');
    limits.set(ip,state);
    if (limits.size > 4000) limits.clear();
    const body = await readBody(req);
    if (!validText(body.email,5,254) || !validText(body.password,8,300)) {
      throw new HttpError(400,'أدخل البريد الإلكتروني وكلمة المرور بشكل صحيح.');
    }
    const login = await supabase('/auth/v1/token?grant_type=password', {
      method:'POST',
      body:JSON.stringify({email:body.email.trim(),password:body.password}),
    });
    return respond(res,200,{access_token:login.access_token,
      expires_in:login.expires_in, user_id:login.user?.id});
  }
  if (req.method === 'POST' && path === '/api/return-requests') {
    if (!RETURNS_ENABLED) throw new HttpError(503,
      'استقبال طلبات الاسترجاع الإلكترونية لم يُفعّل بعد. يُرجى مراجعة سياسة المتجر.');
    const token = tokenFrom(req);
    if (!token) throw new HttpError(401,'يجب تسجيل الدخول بحساب صاحب الطلب.');
    const body = await readBody(req);
    const reasons = ['change_mind','damaged','wrong_item','defective'];
    if (!uuid.test(String(body.orderId || '')) ||
        !reasons.includes(body.reason) ||
        !validText(body.details,15,2000) ||
        str(body.photoUrl).length > 1000 ||
        !validUrl(body.photoUrl)) {
      throw new HttpError(400,'تحقق من رقم الطلب والسبب والتفاصيل ورابط الصورة.');
    }
    const user = await supabase('/auth/v1/user',{},token);
    const order = await supabase(selectUrl('orders',
      'select=id,buyer_id,store_id&limit=1&id=eq.'+encodeURIComponent(body.orderId)
      +'&store_id=eq.'+encodeURIComponent(STORE_ID)),{},token);
    if (!user?.id || order.length!==1 || order[0].buyer_id!==user.id ||
        order[0].store_id!==STORE_ID) {
      throw new HttpError(403,'لا يمكن تقديم طلب استرجاع إلا لطلب اشتريته من هذا المتجر.');
    }
    const inserted=await supabase('/rest/v1/alani_return_requests',{
      method:'POST',
      body:JSON.stringify({
        store_id:STORE_ID,order_id:body.orderId,
        customer_id:user.id,reason:body.reason,
        details:body.details.trim(),
        photo_url:str(body.photoUrl)||null,
      }),
    },token);
    if (!inserted?.[0]?.id) throw new HttpError(503,'تعذر تسجيل الطلب حالياً.');
    return respond(res,201,{id:inserted[0].id,status:'submitted'});
  }
  if (req.method === 'POST' && path === '/api/order') {
    if (!CHECKOUT_ENABLED) throw new HttpError(503,'الشراء الإلكتروني لم يُفعّل بعد.');
    const token = tokenFrom(req);
    if (!token) throw new HttpError(401,'يجب تسجيل الدخول قبل الطلب.');
    const payload = await readBody(req);
    const items = payload.items;
    if (!Array.isArray(items) || !items.length || items.length>20 ||
      items.some(x=>!uuid.test(String(x.product_id)) || !Number.isInteger(x.quantity) ||
          x.quantity<1 || x.quantity>20) ||
      !validText(payload.address,8,300) || !validText(payload.phone,8,25) ||
      str(payload.notes).length>400) {
      throw new HttpError(400,'تحقق من المنتجات والعنوان ورقم الهاتف.');
    }
    const requestKey = uuid.test(String(payload.requestKey))
      ? payload.requestKey : randomUUID();
    const rows = await supabase('/rest/v1/rpc/place_cash_order_web', {
      method:'POST',
      body:JSON.stringify({
        p_store_id:STORE_ID,
        p_items:items.map(x=>({product_id:x.product_id,quantity:x.quantity})),
        p_delivery_address:payload.address.trim(),
        p_phone:payload.phone.trim(),
        p_notes:str(payload.notes),
        p_request_key:requestKey,
      }),
    },token);
    return respond(res,200,{orderId:rows, requestKey});
  }

  if (!path.startsWith('/api/admin/')) throw new HttpError(404,'المسار غير موجود.');
  if (req.method === 'POST' && path === '/api/admin/login') {
    throw new HttpError(404,'استخدم واجهة الدخول.');
  }
  const token = await authOwner(req);
  if (req.method === 'GET' && path === '/api/admin/overview') {
    const id=encodeURIComponent(STORE_ID);
    const [products, orders, posts, returnsResult] = await Promise.all([
      supabase(selectUrl('products',
        'select=id,name,description,price_iqd,stock_quantity,image_url,is_active,created_at&store_id=eq.'+id+'&order=created_at.desc&limit=200'),{},token),
      supabase(selectUrl('orders',
        'select=id,status,total_iqd,payment_method,delivery_address,phone,created_at&store_id=eq.'+id+'&order=created_at.desc&limit=100'),{},token),
      publications(token,true),
      RETURNS_ENABLED
        ? supabase(selectUrl('alani_return_requests',
          'select=id,order_id,reason,details,photo_url,status,created_at'
          +'&store_id=eq.'+id+'&order=created_at.desc&limit=100'),{},token)
          .then(items=>({available:true,items}))
          .catch(()=>({available:false,items:[]}))
        : Promise.resolve({available:false,items:[]}),
    ]);
    return respond(res,200,{products,orders,posts,returns:returnsResult});
  }
  if (req.method === 'POST' && path === '/api/admin/product') {
    const input = await readBody(req);
    if (!validText(input.name,2,160) || str(input.description).length > 3000 ||
      !Number.isInteger(input.price_iqd) || input.price_iqd < 0 ||
      input.price_iqd > 100000000 || !Number.isInteger(input.stock_quantity) ||
      input.stock_quantity < 0 || input.stock_quantity > 1000000 ||
      !validUrl(input.image_url) || typeof input.is_active !== 'boolean') {
      throw new HttpError(400,'اسم المنتج أو السعر أو المخزون أو الرابط غير صالح.');
    }
    const item = {
      name:input.name.trim(), description:str(input.description),
      price_iqd:input.price_iqd, stock_quantity:input.stock_quantity,
      image_url:str(input.image_url) || null, is_active:input.is_active,
    };
    if (input.id) {
      if (!uuid.test(String(input.id))) throw new HttpError(400,'معرف المنتج غير صالح.');
      const out = await supabase(selectUrl('products',
        'id=eq.'+encodeURIComponent(input.id)+'&store_id=eq.'+encodeURIComponent(STORE_ID)),
        {method:'PATCH',body:JSON.stringify(item)},token);
      if (!out.length) throw new HttpError(404,'المنتج غير موجود أو غير مصرح لك.');
      return respond(res,200,{ok:true, product:out[0]});
    }
    const out=await supabase('/rest/v1/products',{
      method:'POST',body:JSON.stringify({...item,store_id:STORE_ID})
    },token);
    return respond(res,201,{ok:true,product:out[0]});
  }
  if (req.method === 'POST' && path === '/api/admin/order') {
    const input=await readBody(req);
    if (!uuid.test(String(input.id)) ||
      !['accepted','rejected','preparing','ready'].includes(input.status)) {
      throw new HttpError(400,'انتقال حالة الطلب غير صالح.');
    }
    const orders=await supabase(selectUrl('orders',
      'select=id&store_id=eq.'+encodeURIComponent(STORE_ID)+'&id=eq.'+encodeURIComponent(input.id)),{},token);
    if (!orders.length) throw new HttpError(404,'الطلب غير موجود لهذا المتجر.');
    const status=await supabase('/rest/v1/rpc/change_cash_order_status',{
      method:'POST',
      body:JSON.stringify({p_order_id:input.id,p_new_status:input.status}),
    },token);
    return respond(res,200,{ok:true,status});
  }
  if (req.method === 'POST' && path === '/api/admin/post') {
    const input=await readBody(req);
    if (!['video','recipe','article','post'].includes(input.kind) ||
      !validText(input.title,3,180) || str(input.body).length>30000 ||
      str(input.ingredients).length>8000 || str(input.safety_note).length>4000 ||
      !validUrl(input.image_url) || !validUrl(input.video_url) ||
      !['draft','published'].includes(input.status) ||
      (input.kind==='video' && !validUrl(input.video_url)) ||
      (input.kind==='video' && !str(input.video_url))) {
      throw new HttpError(400,'تحقق من بيانات الفيديو أو المقال أو الوصفة.');
    }
    const row={
      store_id:STORE_ID,kind:input.kind,title:input.title.trim(),
      body:str(input.body), ingredients:str(input.ingredients),
      safety_note:str(input.safety_note),
      image_url:str(input.image_url)||null, video_url:str(input.video_url)||null,
      status:input.status, updated_at:new Date().toISOString(),
      published_at:input.status==='published'?new Date().toISOString():null,
    };
    let out;
    if (input.id) {
      if (!uuid.test(String(input.id))) throw new HttpError(400,'معرف المنشور غير صالح.');
      out=await supabase(selectUrl('alani_publications',
        'id=eq.'+encodeURIComponent(input.id)+'&store_id=eq.'+encodeURIComponent(STORE_ID)),
        {method:'PATCH',body:JSON.stringify(row)},token);
    } else {
      out=await supabase('/rest/v1/alani_publications',{
        method:'POST',body:JSON.stringify(row)},token);
    }
    if (!out?.length) throw new HttpError(404,'المنشور غير موجود أو غير مصرح.');
    return respond(res,200,{ok:true,post:out[0]});
  }
  throw new HttpError(404,'المسار غير موجود.');
}
export const server = createServer(async (req,res) => {
  for (const [key,value] of Object.entries(headers)) res.setHeader(key,value);
  try {
    const pathname = new URL(req.url || '/', 'http://localhost').pathname;
    if (pathname.startsWith('/api/')) {
      return await handleApi(req,res,pathname);
    }
    if (!['GET','HEAD'].includes(req.method)) {
      res.setHeader('allow','GET, HEAD');
      throw new HttpError(405,'الطلب غير مسموح.');
    }
    if (pathname === '/health') return respond(res,200,{ok:true,service:'alani-natural-store'});
    const file = staticRoutes[pathname];
    if (!file) throw new HttpError(404,'الصفحة غير موجودة.');
    const bytes = await readFile(join(root,file));
    const ext = '.'+file.split('.').pop();
    res.writeHead(200,{
      'content-type':mime[ext] || 'application/octet-stream',
      'cache-control':ext==='.html'?'no-store':'public, max-age=600',
    });
    return req.method === 'HEAD' ? res.end() : res.end(bytes);
  } catch (e) {
    const code=e instanceof HttpError?e.status:500;
    if (code===500) console.error('Al-Ani site error:',String(e?.message||'Unknown'));
    if (res.writableEnded) return;
    return respond(res,code,{error:code===500?'تعذر إكمال الطلب مؤقتاً.':e.message});
  }
});
if (process.env.NODE_ENV !== 'test') {
  server.listen(PORT, '0.0.0.0', () => {
    console.log('Al-Ani independent store listening on '+PORT);
    publicShop().then(data => {
      console.log('Al-Ani catalog probe: approved='+Boolean(data.store)+
        ', published products='+data.products.length);
    }).catch(error => console.error('Al-Ani catalog probe failed:',error.message));
  });
}
