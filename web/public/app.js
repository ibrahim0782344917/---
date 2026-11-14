const storeList=document.getElementById('store-list');
const productList=document.getElementById('product-list');
const search=document.getElementById('search');
let catalog={stores:[],products:[],configured:false};
function create(tag,klass,text){
 const el=document.createElement(tag); if(klass)el.className=klass; if(text!==undefined)el.textContent=String(text);return el;
}
function safeImage(parent,url,alt){
 if(!url)return false;
 try{
  const u=new URL(url); if(u.protocol!=='https:' || !u.hostname.endsWith('.supabase.co'))return false;
  const img=create('img');img.src=u.href;img.alt=alt;img.loading='lazy';img.referrerPolicy='no-referrer';parent.append(img);return true;
 }catch{return false;}
}
function showEmpty(container,msg){container.replaceChildren(create('div','empty-state',msg));}
function storeCard(s){
 const a=create('article','catalog-card');
 const art=create('div','catalog-art');
 if(!safeImage(art,s.logo_url,'شعار '+s.name))art.textContent='🏪';
 const body=create('div','catalog-body');
 body.append(create('h3','',s.name),create('p','',((s.category||'متجر')+' • '+(s.area||'بغداد'))));
 if(s.opening_hours)body.append(create('p','',s.opening_hours));
 const verified=create('p','','✓ متجر معتمد من شتريد');verified.style.color='#0b7255';body.append(verified);
 a.append(art,body);return a;
}
function productCard(p){
 const a=create('article','catalog-card'), art=create('div','catalog-art');
 if(!safeImage(art,p.image_url,'صورة منتج '+p.name))art.textContent='🛍️';
 const body=create('div','catalog-body');
 const store=catalog.stores.find(s=>s.id===p.store_id);
 body.append(create('h3','',p.name),create('p','',store?.name||'متجر شتريد'));
 if(p.stock_quantity!=null)body.append(create('p','',Number(p.stock_quantity)>0?'متوفر':'غير متوفر حالياً'));
 const price=Number(p.price_iqd);if(Number.isFinite(price)&&price>=0)body.append(create('div','price',price.toLocaleString('en-US')+' د.ع'));
 a.append(art,body);return a;
}
function render(q=''){
 const term=q.trim().toLocaleLowerCase('ar');
 const matches=(txt)=>String(txt||'').toLocaleLowerCase('ar').includes(term);
 const stores=catalog.stores.filter(s=>!term||[s.name,s.area,s.category,s.description].some(matches));
 const products=catalog.products.filter(p=>!term||[p.name,p.description,catalog.stores.find(s=>s.id===p.store_id)?.name].some(matches));
 if(!catalog.configured){showEmpty(storeList,'ربط عرض المتاجر بالموقع قيد الإعداد. تطبيق شتريد وقاعدة البيانات يعملان بشكل منفصل.');showEmpty(productList,'ستظهر المنتجات المعتمدة بعد إكمال إعداد الاتصال.');return;}
 storeList.replaceChildren(...stores.map(storeCard));
 productList.replaceChildren(...products.map(productCard));
 if(!stores.length)showEmpty(storeList,term?'لا يوجد متجر مطابق لبحثك حالياً.':'لا توجد متاجر معتمدة منشورة حالياً.');
 if(!products.length)showEmpty(productList,term?'لا توجد منتجات مطابقة لبحثك حالياً.':'لا توجد منتجات متاحة للبيع حالياً.');
}
async function boot(){
 try{
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),8000);
  try{
   const response=await fetch('/api/catalog',{signal:controller.signal});
   if(!response.ok)throw Error('catalog unavailable');
   const data=await response.json();
   catalog={configured:!!data.configured,stores:Array.isArray(data.stores)?data.stores:[],products:Array.isArray(data.products)?data.products:[]};
   render();
  }finally{clearTimeout(timer);}
 }catch{showEmpty(storeList,'تعذر تحميل المتاجر مؤقتاً. حاول مرة أخرى لاحقاً.');showEmpty(productList,'تعذر تحميل المنتجات مؤقتاً.');}
}
const form=document.getElementById('search-form');
if(form)form.addEventListener('submit',e=>{e.preventDefault();render(search?.value||'');document.getElementById('stores').scrollIntoView({behavior:'smooth'});});
for(const btn of document.querySelectorAll('[data-query]'))btn.addEventListener('click',()=>{if(search)search.value=btn.dataset.query;render(btn.dataset.query);document.getElementById('stores').scrollIntoView({behavior:'smooth'});});
const year=document.getElementById('year');if(year)year.textContent=String(new Date().getFullYear());
if(storeList && productList)boot();