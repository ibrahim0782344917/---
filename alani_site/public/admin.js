const $=id=>document.getElementById(id);
let accessToken=null;
let sessionExpires=0;
let adminData={products:[],orders:[],posts:{available:false,items:[]},returns:{available:false,items:[]}};
let productQuery='', inventoryFilter='all', orderQuery='', orderFilter='all', postFilter='all';
const lowStock=p=>Number(p.stock_quantity||0)<=5;
function filteredProducts() {
  return adminData.products.filter(p=>{
    const haystack=(String(p.name||'')+' '+String(p.description||'')).toLowerCase();
    if(productQuery&&!haystack.includes(productQuery))return false;
    if(inventoryFilter==='low'&&!lowStock(p))return false;
    if(inventoryFilter==='out'&&Number(p.stock_quantity)!==0)return false;
    if(inventoryFilter==='hidden'&&p.is_active===true)return false;
    return true;
  });
}
function filteredOrders() {
  return adminData.orders.filter(o=>{
    if(orderFilter!=='all'&&o.status!==orderFilter)return false;
    const haystack=(String(o.id||'')+' '+String(o.delivery_address||'')).toLowerCase();
    return !orderQuery||haystack.includes(orderQuery);
  });
}
function filteredPosts() {
  return (adminData.posts.items||[]).filter(p=>
    postFilter==='all'||p.kind===postFilter);
}
const money=n=>new Intl.NumberFormat('ar-IQ').format(Number(n||0))+' د.ع';
const text=(tag,value,klass)=>{const e=document.createElement(tag);e.textContent=String(value??'');if(klass)e.className=klass;return e;};
function message(value,error=false) {
  const box=$('admin-message');box.hidden=false;box.textContent=value;
  box.style.background=error?'#fff0e7':'#e5eee7';
  box.style.color=error?'#a23f2b':'#27553b';
}
async function api(path,options={}) {
  const headers={'content-type':'application/json',...(accessToken?{authorization:'Bearer '+accessToken}:{}),...options.headers};
  const res=await fetch(path,{...options,headers});
  let data;try{data=await res.json();}catch{data={};}
  if(!res.ok)throw Error(data.error||'تعذرت العملية');
  return data;
}
function active(){
  if(!accessToken || sessionExpires < Date.now()+5000){
    resetSession();throw Error('انتهت الجلسة، سجل الدخول مرة أخرى.');
  }
  return true;
}
function resetSession() {
  accessToken=null;sessionExpires=0;adminData={products:[],orders:[],posts:{available:false,items:[]},returns:{available:false,items:[]}};
  $('admin-section').hidden=true;$('login-section').hidden=false;$('logout').hidden=true;
  $('password').value='';
}
function showAdmin(){
  $('admin-section').hidden=false;$('login-section').hidden=true;$('logout').hidden=false;
}
function editProduct(p) {
  $('product-heading').textContent='تعديل المنتج: '+p.name;
  $('product-id').value=p.id;
  $('product-name').value=p.name;
  $('product-description').value=p.description||'';
  $('product-price').value=p.price_iqd;
  $('product-stock').value=p.stock_quantity;
  $('product-image').value=p.image_url||'';
  $('product-active').value=String(p.is_active);
  document.querySelector('#product-form').scrollIntoView({behavior:'smooth',block:'start'});
}
function resetProduct(){
  $('product-form').reset();$('product-id').value='';
  $('product-heading').textContent='إضافة منتج جديد';
}
function renderProducts(){
  const t=$('products-table');t.replaceChildren();
  for(const p of filteredProducts()){
    const row=document.createElement('tr');
    const edit=text('button','تعديل');edit.addEventListener('click',()=>editProduct(p));
    for(const v of [p.name,money(p.price_iqd),p.stock_quantity,p.is_active?'منشور':'مخفي']){
      row.append(text('td',v));
    }
    const cell=document.createElement('td');cell.append(edit);row.append(cell);t.append(row);
  }
  if(!filteredProducts().length){
    const row=text('tr');const col=text('td','لا توجد منتجات مسجلة');col.colSpan=5;
    row.append(col);t.append(row);
  }
}
function statusOptions(status) {
  if(status==='placed')return ['accepted','rejected'];
  if(status==='accepted')return ['preparing'];
  if(status==='preparing')return ['ready'];
  return [];
}
const statuses={placed:'جديد',accepted:'مقبول',preparing:'قيد التجهيز',ready:'جاهز',rejected:'مرفوض',cancelled:'ملغي'};
function renderOrders(){
  const table=$('orders-table');table.replaceChildren();
  for(const o of filteredOrders()){
    const row=document.createElement('tr');
    [o.id?.slice(0,8),money(o.total_iqd)+(Number(o.delivery_fee_iqd)>0?' (يشمل توصيل '+money(o.delivery_fee_iqd)+')':''),statuses[o.status]||o.status,o.delivery_address||''].forEach(v=>row.append(text('td',v)));
    const cell=document.createElement('td');
    for(const status of statusOptions(o.status)){
      const b=text('button',statuses[status]);
      b.addEventListener('click',()=>changeOrder(o,status));cell.append(b);
    }
    row.append(cell);table.append(row);
  }
  if(!filteredOrders().length){
    const row=document.createElement('tr'),col=text('td','لا توجد طلبات مسجلة');
    col.colSpan=5;row.append(col);table.append(row);
  }
}
async function changeOrder(o,status){
  if(!confirm('هل تريد تغيير حالة الطلب '+o.id.slice(0,8)+' إلى '+statuses[status]+'؟'))return;
  try {
    active();
    await api('/api/admin/order',{method:'POST',body:JSON.stringify({id:o.id,status})});
    await refresh();message('تم تحديث الطلب.');
  } catch(e){message(e.message,true);}
}
function editPost(p) {
  $('post-heading').textContent='تعديل المنشور: '+p.title;
  $('post-id').value=p.id;$('post-kind').value=p.kind;$('post-status').value=p.status;
  $('post-title').value=p.title;$('post-body').value=p.body||'';
  $('post-ingredients').value=p.ingredients||'';$('post-warning').value=p.safety_note||'';
  $('post-image').value=p.image_url||'';$('post-video').value=p.video_url||'';
  $('post-form').scrollIntoView({behavior:'smooth'});
}
function resetPost(){
  $('post-form').reset();$('post-id').value='';
  $('post-heading').textContent='إضافة محتوى جديد';
}
function renderPosts() {
  const t=$('posts-table');t.replaceChildren();
  const enabled=adminData.posts.available===true;
  $('posts-availability').textContent=enabled
    ? 'نظام المحتوى متصل بقاعدة البيانات.'
    : 'قاعدة الفيديوهات والمدونة لم تُفعّل بعد؛ لا يمكن حفظ المحتوى حالياً.';
  for(const p of filteredPosts()){
    const row=document.createElement('tr');
    [p.title,p.kind,p.status==='published'?'منشور':'مسودة'].forEach(value=>row.append(text('td',value)));
    const cell=document.createElement('td');const edit=text('button','تعديل');
    edit.addEventListener('click',()=>editPost(p));cell.append(edit);row.append(cell);t.append(row);
  }
  $('post-submit').disabled=!enabled;
}
const returnReasons={change_mind:'منتج سليم',damaged:'مكسور/متضرر',
  wrong_item:'منتج مختلف',defective:'عيب'};
const returnStatuses={submitted:'مُقدّم',reviewing:'قيد المراجعة',
  approved:'مقبول',declined:'مرفوض',resolved:'تمت المعالجة'};
function returnNext(current){
  if(current==='submitted')return ['reviewing'];
  if(current==='reviewing')return ['approved','declined'];
  if(current==='approved')return ['resolved'];
  return [];
}
async function changeReturn(entry,status){
  const note=prompt('اكتب ملاحظة للمراجعة (10 حروف على الأقل):');
  if(!note||note.trim().length<10)return;
  try{
    active();
    await api('/api/admin/return',{
      method:'POST',body:JSON.stringify({id:entry.id,status,note:note.trim()})
    });
    await refresh();message('تم تحديث حالة مراجعة الاسترجاع فقط، دون دفع مبالغ.');
  }catch(e){message(e.message,true);}
}
function renderReturns(){
  const section=adminData.returns||{available:false,items:[]};
  $('returns-availability').textContent=section.available
    ? 'طلبات الاسترجاع المسجلة (تُراجع من مالك المتجر).'
    : 'نظام استقبال الاسترجاع غير مفعل بعد؛ لا توجد عمليات استرداد مالي.';
  const table=$('returns-table');table.replaceChildren();
  for(const entry of section.items||[]){
    const row=document.createElement('tr');
    [
      String(entry.order_id||'').slice(0,8),
      returnReasons[entry.reason]||entry.reason,
      String(entry.details||'').slice(0,150),
      returnStatuses[entry.status]||entry.status
    ].forEach(v=>row.append(text('td',v)));
    const actions=document.createElement('td');
    for(const next of returnNext(entry.status)){
      const btn=text('button',returnStatuses[next]||next);
      btn.addEventListener('click',()=>changeReturn(entry,next));
      actions.append(btn);
    }
    row.append(actions);table.append(row);
  }
  if(!(section.items||[]).length){
    const row=document.createElement('tr'),cell=text('td','لا توجد طلبات استرجاع مسجلة حالياً.');
    cell.colSpan=5;row.append(cell);table.append(row);
  }
}
function reports(){
  const total=adminData.orders.reduce((sum,o)=>sum+(Number(o.total_iqd)||0),0);
  const pending=adminData.orders.filter(o=>o.status==='placed').length;
  $('reports').textContent='إجمالي قيمة الطلبات المسجلة (لا يمثل المبالغ المحصّلة): '+money(total)+
    ' | طلبات جديدة: '+pending+
    ' | المنتجات النشطة: '+adminData.products.filter(p=>p.is_active).length;
}
async function refresh(){
  active();
  const response=await api('/api/admin/overview');
  adminData=response;
  $('m-products').textContent=String(response.products.length);
  $('m-orders').textContent=String(response.orders.length);
  $('m-posts').textContent=String((response.posts.items||[]).filter(p=>p.status==='published').length);
  $('m-low').textContent=String(response.products.filter(lowStock).length);
  $('m-returns').textContent=String((response.returns?.items||[]).filter(x=>
    !['resolved','declined'].includes(x.status)).length);
  renderProducts();renderOrders();renderPosts();renderReturns();reports();
  message('تم تحديث البيانات. جميع العمليات تقتصر على المتجر الذي تملكه.');
}
function showTab(tab){
  for(const element of document.querySelectorAll('[data-tab]')){
    element.classList.toggle('active',element.dataset.tab===tab);
  }
  for(const name of ['products','orders','returns','posts','settings']){
    $('tab-'+name).hidden=name!==tab;
  }
}
$('login-form').addEventListener('submit',async e=>{
  e.preventDefault();const button=$('login-button'),msg=$('login-message');
  button.disabled=true;msg.textContent='جارٍ التحقق من الحساب…';
  try{
    const response=await api('/api/login',{method:'POST',body:JSON.stringify({
      email:$('email').value,password:$('password').value,
    })});
    accessToken=response.access_token;
    sessionExpires=Date.now()+Math.min(Number(response.expires_in||3600),3600)*1000;
    await refresh();
    showAdmin();msg.textContent='';
  }catch(err){resetSession();msg.textContent='تعذر الدخول إلى إدارة المتجر: '+err.message;}
  finally{button.disabled=false;}
});
$('logout').addEventListener('click',resetSession);
$('refresh').addEventListener('click',async()=>{try{await refresh();}catch(e){message(e.message,true);}});
document.querySelectorAll('[data-tab]').forEach(btn=>
  btn.addEventListener('click',()=>showTab(btn.dataset.tab)));
$('admin-product-search').addEventListener('input',event=>{
  productQuery=event.target.value.trim().toLowerCase();renderProducts();
});
$('admin-inventory-filter').addEventListener('change',event=>{
  inventoryFilter=event.target.value;renderProducts();
});
$('admin-order-search').addEventListener('input',event=>{
  orderQuery=event.target.value.trim().toLowerCase();renderOrders();
});
$('admin-order-filter').addEventListener('change',event=>{
  orderFilter=event.target.value;renderOrders();
});
$('admin-post-filter').addEventListener('change',event=>{
  postFilter=event.target.value;renderPosts();
});
$('reset-product').addEventListener('click',resetProduct);
$('product-form').addEventListener('submit',async e=>{
  e.preventDefault();
  try{
    active();
    const p={
      id:$('product-id').value||undefined,
      name:$('product-name').value,
      description:$('product-description').value,
      price_iqd:Number($('product-price').value),
      stock_quantity:Number($('product-stock').value),
      image_url:$('product-image').value,
      is_active:$('product-active').value==='true',
    };
    await api('/api/admin/product',{method:'POST',body:JSON.stringify(p)});
    resetProduct();await refresh();message('تم حفظ المنتج.');
  }catch(err){message(err.message,true);}
});
$('reset-post').addEventListener('click',resetPost);
$('post-form').addEventListener('submit',async e=>{
  e.preventDefault();
  try{
    active();
    const p={
      id:$('post-id').value||undefined,
      kind:$('post-kind').value, status:$('post-status').value,
      title:$('post-title').value,body:$('post-body').value,
      ingredients:$('post-ingredients').value,
      safety_note:$('post-warning').value,
      image_url:$('post-image').value,
      video_url:$('post-video').value,
    };
    await api('/api/admin/post',{method:'POST',body:JSON.stringify(p)});
    resetPost();await refresh();message('تم حفظ المحتوى.');
  }catch(err){message(err.message,true);}
});
showTab('products');