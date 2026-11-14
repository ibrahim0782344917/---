const $ = id=>document.getElementById(id);
const fmt = v=>Number(v||0).toLocaleString('en-US')+' د.ع';
async function api(path,options={}){
 let response;
 try{response=await fetch(path,{credentials:'same-origin',headers:{'content-type':'application/json',...(options.headers||{})},...options});}
 catch{throw Error('تعذر الاتصال بالموقع. تحقق من الإنترنت ثم حاول مجدداً.');}
 let data;
 try{data=await response.json();}catch{data={error:'استجابة غير متوقعة من الخادم'};}
 if(!response.ok)throw Error(data.error||'تعذر تنفيذ العملية');
 return data;
}
function text(id,message,type=''){
 const el=$(id);
 if(!el)return;
 el.textContent=message||'';
 el.dataset.type=type;
}
function create(tag,klass,t){
 const x=document.createElement(tag);
 if(klass)x.className=klass;
 if(t!==undefined)x.textContent=String(t);
 return x;
}
function link(label,href){
 const a=create('a','text-link',label);a.href=href;return a;
}
function nextPath(){
 try{
  const p=new URLSearchParams(location.search).get('next');
  if(p&&p.startsWith('/')&&!p.startsWith('//')&&p.length<300&&!p.includes('\\'))return p;
 }catch{}
 return '/orders';
}
async function loginPage(){
 const tabLogin=$('tab-login'),tabRegister=$('tab-register'),form=$('auth-form'),submit=$('auth-submit');
 let isRegister=false;
 function toggle(x){
  isRegister=x;tabLogin.classList.toggle('active',!x);tabRegister.classList.toggle('active',x);
  submit.textContent=x?'إنشاء الحساب':'تسجيل الدخول';
  $('password').setAttribute('autocomplete',x?'new-password':'current-password');
  text('form-status','');
 }
 tabLogin.addEventListener('click',()=>toggle(false));
 tabRegister.addEventListener('click',()=>toggle(true));
 form.addEventListener('submit',async event=>{
  event.preventDefault();submit.disabled=true;text('form-status','جاري التحقق من البيانات...');
  try{
   const body={email:$('email').value.trim(),password:$('password').value};
   const result=await api(isRegister?'/api/auth/register':'/api/auth/login',{method:'POST',body:JSON.stringify(body)});
   if(result.checkEmail)text('form-status','تم استلام طلب التسجيل. افتح بريدك الإلكتروني وأكد الحساب ثم سجّل الدخول.','success');
   else location.assign(nextPath());
  }catch(e){text('form-status',e.message,'error');}
  finally{submit.disabled=false;}
 });
 try{
  const s=await api('/api/auth/session');
  if(s.authenticated){
   form.parentElement.hidden=true;
   const panel=$('signed-in');panel.hidden=false;
   panel.append(create('h2','','حسابك متصل'),create('p','',s.email));
   panel.append(link('عرض طلباتي','/orders'),create('span','','  •  '),link('التسوق','/checkout'));
   const b=create('button','button button-outline','تسجيل الخروج');
   b.type='button';b.style.marginInlineStart='16px';
   b.addEventListener('click',async()=>{b.disabled=true;try{await api('/api/auth/logout',{method:'POST',body:'{}'});location.reload();}catch(e){b.disabled=false;alert(e.message);}});
   panel.append(create('p'),b);
  }
 }catch{}
}
async function checkoutPage(){
 const select=$('item'),quantity=$('quantity'),summary=$('order-summary'),button=$('place-order');
 let catalog,logged=false;
 let requestKey=null;
 try{
  const session=await api('/api/auth/session');
  logged=!!session.authenticated;
  const hint=$('session-hint');
  hint.replaceChildren();
  if(logged)hint.append(create('span','', 'تم تسجيل الدخول: '+session.email));
  else hint.append(create('span','','سجّل الدخول أولاً لإتمام الطلب. '),link('تسجيل الدخول','/login?next='+encodeURIComponent(location.pathname+location.search)));
 }catch{ text('session-hint','تعذر التحقق من الحساب.'); }
 try{
  catalog=await api('/api/catalog');
  if(!catalog.configured||!catalog.products?.length){select.replaceChildren(create('option','','لا توجد منتجات متاحة حالياً'));button.disabled=true;text('checkout-status','لا يمكن إنشاء طلب بدون منتج متوفر.');return;}
  const stores=new Map((catalog.stores||[]).map(s=>[s.id,s]));
  select.replaceChildren(create('option','','اختر المنتج من المتاجر المعتمدة'));
  select.firstElementChild.value='';
  for(const product of catalog.products){
   if(!stores.has(product.store_id)||Number(product.stock_quantity)<1)continue;
   const option=create('option','',(product.name||'منتج')+' — '+(stores.get(product.store_id)?.name||'متجر')+' — '+fmt(product.price_iqd));
   option.value=product.id; select.append(option);
  }
  const fromURL=new URLSearchParams(location.search).get('product');
  if(fromURL&&catalog.products.some(p=>p.id===fromURL))select.value=fromURL;
  function update(){
   const p=catalog.products.find(p=>p.id===select.value);
   if(!p){summary.textContent='اختر منتجاً لمعرفة السعر.';return;}
   const qty=Math.max(1,Math.min(20,Number(quantity.value)||1));
   summary.replaceChildren(create('strong','',p.name),create('p','',(stores.get(p.store_id)?.name||'المتجر')+' • '+qty+' قطعة'),create('h2','',fmt(qty*Number(p.price_iqd))),create('small','','الدفع نقداً عند الاستلام'));
  }
  select.addEventListener('change',()=>{requestKey=null;update();});
  quantity.addEventListener('change',()=>{requestKey=null;update();});
  update();
 }catch(e){select.replaceChildren(create('option','','تعذر تحميل المنتجات'));button.disabled=true;text('checkout-status',e.message,'error');return;}
 $('checkout-form').addEventListener('submit',async e=>{
  e.preventDefault();
  if(!logged){text('checkout-status','يجب تسجيل الدخول أولاً.','error');return;}
  const product=catalog.products.find(x=>x.id===select.value);
  if(!product){text('checkout-status','اختر منتجاً صالحاً','error');return;}
  const q=Number(quantity.value);
  if(!Number.isInteger(q)||q<1||q>20){text('checkout-status','الكمية يجب أن تكون بين 1 و20','error');return;}
  button.disabled=true;
  text('checkout-status','جاري إرسال الطلب، لا تغلق الصفحة...');
  requestKey??=crypto.randomUUID();
  const request={
   store_id:product.store_id,
   items:[{product_id:product.id,quantity:q}],
   delivery_address:$('address').value,
   phone:$('phone').value,
   notes:$('notes').value,
   request_key:requestKey,
   confirmed:$('confirm-order').checked
  };
  try{
   const answer=await api('/api/orders',{method:'POST',body:JSON.stringify(request)});
   $('checkout-form').hidden=true;
   summary.replaceChildren(create('h2','','تم استلام الطلب ✓'),create('p','','رقم الطلب: '+answer.order_id),create('p','','طريقة الدفع: عند الاستلام'));
   summary.append(link('عرض طلباتي','/orders'));
  }catch(err){text('checkout-status',err.message,'error');button.disabled=false;}
 });
}
async function ordersPage(){
 const list=$('orders-list');
 try{
  const payload=await api('/api/orders');
  const rows=Array.isArray(payload.orders)?payload.orders:[];
  if(!rows.length){text('orders-status','لا توجد طلبات في حسابك حالياً.');return;}
  text('orders-status','آخر '+rows.length+' طلباً من حسابك');
  const status={placed:'تم إنشاء الطلب',accepted:'مقبول',preparing:'قيد التحضير',ready:'جاهز',cancelled:'ملغى',rejected:'مرفوض'};
  for(const order of rows){
   const card=create('article','purchase-card');
   const h=create('div','purchase-row');
   h.append(create('strong','','الطلب '+String(order.id).slice(0,8)),create('span','soft-chip',status[order.status]||order.status));
   card.append(h,create('p','',fmt(order.total_iqd)),create('small','',new Date(order.created_at).toLocaleString('ar-IQ')));
   list.append(card);
  }
 }catch(e){
  text('orders-status',e.message,'error');
  if(String(e.message).includes('سجّل'))list.append(link('اضغط هنا لتسجيل الدخول','/login?next=/orders'));
 }
}
const page=document.body.dataset.shopPage;
if(page==='login')loginPage();
if(page==='checkout')checkoutPage();
if(page==='orders')ordersPage();
