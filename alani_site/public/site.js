const $ = (id) => document.getElementById(id);
const safe = (value) => String(value ?? '');
const formatPrice = (number) => new Intl.NumberFormat('ar-IQ').format(Number(number || 0)) + ' د.ع';
const uuidRegex = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
let catalog = [], publications = [], checkoutEnabled = false, searchTerm = '', categoryTerm = '';
let pendingCheckout = null; // Keep request key across network retries in this page only.

function node(tag, text = '', className = '') {
  const el = document.createElement(tag);
  if (className) el.className = className;
  if (text !== null && text !== undefined) el.textContent = safe(text);
  return el;
}
function empty(container, message) {
  container.replaceChildren(node('p', message, 'empty'));
}
async function api(path, options = {}) {
  const response = await fetch(path, options);
  let data = {};
  try { data = await response.json(); } catch {}
  if (!response.ok) throw Error(data.error || 'تعذر الاتصال بالخدمة');
  return data;
}
function readCart() {
  try {
    const v = JSON.parse(localStorage.getItem('alani_cart_v1') || '{}');
    if (!v || Array.isArray(v) || typeof v !== 'object') return {};
    return Object.fromEntries(Object.entries(v).filter(([key,qty]) =>
      uuidRegex.test(key) && Number.isInteger(qty) && qty > 0 && qty <= 20));
  } catch { return {}; }
}
let cart = readCart();
function saveCart() {
  localStorage.setItem('alani_cart_v1',JSON.stringify(cart));
  renderBasket();
}
function add(id) {
  const product = catalog.find(x=>x.id === id);
  if (!product || product.stock_quantity < 1) return;
  cart[id] = Math.min((cart[id]||0)+1, product.stock_quantity, 20);
  saveCart();
  flash('تمت إضافة المنتج للسلة');
}
function step(id, amount) {
  const product = catalog.find(x=>x.id === id);
  if (!product) return;
  const next = (cart[id]||0)+amount;
  if (next<=0) delete cart[id];
  else cart[id] = Math.min(next,product.stock_quantity,20);
  saveCart();
}
function flash(message) {
  const toast = node('div',message,'toast');
  toast.setAttribute('role','status');
  document.body.append(toast);
  setTimeout(()=>toast.remove(),2600);
}
function renderBasket() {
  const count = $('cart-count'), list = $('basket-items');
  count.textContent = String(Object.values(cart).reduce((sum,v)=>sum+v,0));
  let total = 0;
  list.replaceChildren();
  const items = catalog.filter(x=>Number.isInteger(cart[x.id]) && cart[x.id]>0);
  if (!items.length) empty(list,'السلة فارغة. أضف منتجاً من متجرنا.');
  for (const p of items) {
    const qty = Math.min(cart[p.id],p.stock_quantity,20);
    if (qty<=0) continue;
    total += p.price_iqd*qty;
    const row = node('div',null,'basket-row');
    const descr=node('div');descr.append(node('strong',p.name),
      node('br'),node('small',formatPrice(p.price_iqd)));
    const controls=node('div',null,'qty-controls');
    const minus=node('button','−');minus.type='button';minus.setAttribute('aria-label','نقصان كمية '+p.name);
    minus.addEventListener('click',()=>step(p.id,-1));
    const plus=node('button','+');plus.type='button';plus.setAttribute('aria-label','زيادة كمية '+p.name);
    plus.disabled=qty >= p.stock_quantity || qty>=20;
    plus.addEventListener('click',()=>step(p.id,1));
    controls.append(minus,node('strong',qty),plus);row.append(descr,controls);list.append(row);
  }
  $('basket-total').textContent=formatPrice(total);
  $('basket-estimate').textContent=formatPrice(items.length ? total+5000 : 0);
  const btn=$('checkout-button');
  btn.disabled=!checkoutEnabled || !items.length;
  btn.textContent=checkoutEnabled?'تأكيد الطلب — الدفع عند الاستلام':'الشراء غير مفعّل بعد';
}
function productCard(p) {
  const card=node('article',null,'product-card');
  const media=node('div',null,'product-media');
  if (p.image_url && p.image_url.startsWith('https://')) {
    const img=node('img');img.src=p.image_url;img.loading='lazy';img.alt='صورة '+p.name;
    img.onerror=()=>media.replaceChildren(node('span','🌿','placeholder'));
    media.append(img);
  } else media.append(node('span','🌿','placeholder'));
  const info=node('div',null,'product-info');
  info.append(node('h3',p.name),node('div',formatPrice(p.price_iqd),'price'),
    node('div',p.stock_quantity>0?'المتوفر: '+p.stock_quantity:'نفد المخزون','stock'));
  const actions=node('div',null,'product-actions');
  const detail=node('button','تفاصيل','details-button');detail.type='button';
  detail.addEventListener('click',()=>showDetails({
    title:p.name,body:p.description||'لم يُنشر وصف لهذا المنتج بعد.',
    price:p.price_iqd,kind:'product'
  }));
  const buy=node('button',p.stock_quantity>0?'أضف للسلة':'غير متوفر','button primary');buy.type='button';
  buy.disabled=p.stock_quantity<=0;
  buy.addEventListener('click',()=>add(p.id));
  actions.append(detail,buy);info.append(actions);card.append(media,info);
  return card;
}
function renderProducts() {
  const grid=$('product-grid');grid.replaceChildren();
  const match=catalog.filter(p=>{
    const combined=(p.name+' '+(p.description||'')).toLowerCase();
    const inCategory=!categoryTerm || (categoryTerm==='الزيوت'? /زيت|زيوت/.test(combined)
      :categoryTerm==='الأعشاب'?/عشب|أعشاب/.test(combined)
      :categoryTerm==='العسل'?/عسل/.test(combined)
      :/صابون|عناية/.test(combined));
    return inCategory && combined.includes(searchTerm);
  });
  if (!match.length) return empty(grid,'لا توجد منتجات منشورة مطابقة للبحث حالياً.');
  match.forEach(p=>grid.append(productCard(p)));
}
function showDetails(item) {
  const d=$('details'), content=$('details-content');content.replaceChildren();
  content.append(node('span',item.kind==='product'?'منتج طبيعي':item.kind==='video'?'فيديو':'محتوى تثقيفي','overline'));
  content.append(node('h2',item.title));
  if (Number.isInteger(item.price)) content.append(node('strong',formatPrice(item.price),'price'));
  if (item.ingredients) {
    content.append(node('h3','المكونات'),node('p',item.ingredients));
  }
  content.append(node('p',item.body||'لا يوجد وصف مرفق.'));
  if (item.safety_note) content.append(node('h3','تنبيه'),node('p',item.safety_note));
  if (item.video_url) {
    try {const u=new URL(item.video_url);
      if (u.protocol==='https:') {const a=node('a','مشاهدة الفيديو ↗','button primary');
        a.href=u.toString();a.rel='noopener noreferrer';a.target='_blank';content.append(a);}
    } catch {}
  }
  d.showModal();
}
function makePostCard(p) {
  const article=node('article',null,'content-card');
  const names={video:'فيديو',recipe:'وصفة',article:'مقال',post:'منشور'};
  article.append(node('span',names[p.kind]||'مقال','content-kind'),
    node('h3',p.title),node('p',p.body||'اضغط لعرض المزيد'));
  const view=node('button','اقرأ المزيد ←');view.type='button';
  view.addEventListener('click',()=>showDetails(p));
  article.append(view);return article;
}
function renderPosts() {
  const sections=[
    [$('video-grid'),new Set(['video']),'لم تُنشر فيديوهات بعد.'],
    [$('recipe-grid'),new Set(['recipe']),'لم تُنشر وصفات بعد.'],
    [$('article-grid'),new Set(['article','post']),'لم تُنشر مقالات أو منشورات بعد.']
  ];
  for (const [element,kinds,msg] of sections) {
    const items=publications.filter(p=>kinds.has(p.kind));
    element.replaceChildren();
    if (!items.length) empty(element,msg);
    else items.forEach(p=>element.append(makePostCard(p)));
  }
}

/* StoreKing home-slider behavior adapted for the independent Al-Ani website.
 * Does not create fictitious promotions or claim unverified discounts. */
function setupPromoCarousel() {
  const slides=[...document.querySelectorAll('[data-promo-slide]')];
  const target=$('promo-dots');
  if (!slides.length || !target) return;
  let selected=0;
  const dots=[];
  function select(index) {
    selected=(index+slides.length)%slides.length;
    slides.forEach((slide,i)=>{
      slide.hidden=i!==selected;
      slide.classList.toggle('is-active',i===selected);
    });
    dots.forEach((button,i)=>button.setAttribute('aria-current',String(i===selected)));
  }
  slides.forEach((_,i)=>{
    const button=node('button',null);
    button.type='button';
    button.setAttribute('aria-label','اذهب إلى العرض '+(i+1));
    button.addEventListener('click',()=>select(i));
    target.append(button);dots.push(button);
  });
  $('promo-next')?.addEventListener('click',()=>select(selected+1));
  $('promo-prev')?.addEventListener('click',()=>select(selected-1));
  select(0);
  const carousel=$('promo-carousel');
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;
  let interval=setInterval(()=>select(selected+1),6200);
  const pause=()=>{clearInterval(interval);interval=null;};
  const resume=()=>{
    if(interval===null && !document.hidden) {
      interval=setInterval(()=>select(selected+1),6200);
    }
  };
  carousel.addEventListener('mouseenter',pause);
  carousel.addEventListener('mouseleave',resume);
  carousel.addEventListener('focusin',pause);
  carousel.addEventListener('focusout',resume);
  document.addEventListener('visibilitychange',()=>document.hidden?pause():resume());
}

async function init() {
  $('year').textContent=String(new Date().getFullYear());
  setupPromoCarousel();
  $('search').addEventListener('input',e=>{
    searchTerm=e.target.value.trim().toLowerCase();renderProducts();
  });
  document.querySelectorAll('[data-category]').forEach(link=>
    link.addEventListener('click',()=>{
      categoryTerm=link.dataset.category;
      $('search').value='';searchTerm='';renderProducts();
    }));
  try {
    const [storeData,postsData]=await Promise.all([
      api('/api/catalog'),api('/api/publications')
    ]);
    catalog=Array.isArray(storeData.products)?storeData.products:[];
    publications=Array.isArray(postsData.items)?postsData.items:[];
    checkoutEnabled=storeData.checkoutEnabled===true;
    $('store-status').textContent=storeData.store
      ? 'عرض منتجات متجر السيد إبراهيم العاني المعتمد — الأسعار تتحدث مع بيانات المتجر.'
      : 'المتجر غير متاح للبيع حالياً.';
    if (!postsData.available) $('store-status').textContent+=
      ' قسم الفيديوهات والمدونة بانتظار تفعيل قاعدة المحتوى.';
  } catch (e) {
    $('store-status').textContent='تعذّر تحميل بيانات المتجر حالياً. حاول تحديث الصفحة.';
  }
  renderProducts();renderPosts();renderBasket();
  // A copied share URL opens only the real published post.
  const shared = /^#post=([a-f0-9-]{36})$/i.exec(window.location.hash);
  if (shared) {
    const post = publications.find(item => item.id === shared[1]);
    if (post) showDetails(post);
  }

  $('checkout-form').addEventListener('submit',async e=>{
    e.preventDefault();
    const msg=$('checkout-message');msg.textContent='';
    if (!checkoutEnabled) return;
    const selected=catalog.filter(p=>cart[p.id]>0);
    if (selected.length!==Object.keys(cart).length ||
        selected.some(p=>!Number.isInteger(p.price_iqd) ||
          cart[p.id]>p.stock_quantity)) {
      msg.textContent='أحد المنتجات غير متوفر أو سعره غير واضح؛ حدّث الصفحة.';
      return;
    }
    const items=selected.map(p=>({product_id:p.id,quantity:cart[p.id]}));
    if (!items.length) return;
    const expectedTotalIqd=selected.reduce((n,p)=>n+
      p.price_iqd*cart[p.id],5000);
    const details={
      items,address:$('checkout-address').value,
      phone:$('checkout-phone').value,notes:$('checkout-notes').value,
      expectedTotalIqd
    };
    // A retry after a lost network response reuses exactly the same key,
    // preventing a second COD order and a second stock decrement.
    const fingerprint=JSON.stringify(details);
    if (!pendingCheckout || pendingCheckout.fingerprint!==fingerprint) {
      pendingCheckout={fingerprint,requestKey:crypto.randomUUID()};
    }
    const btn=$('checkout-button');btn.disabled=true;btn.textContent='جارٍ إرسال الطلب…';
    try {
      const login=await api('/api/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({
        email:$('checkout-email').value,password:$('checkout-password').value,
      })});
      const order=await api('/api/order',{
        method:'POST',headers:{'content-type':'application/json',
          'authorization':'Bearer '+login.access_token},
        body:JSON.stringify({...details,requestKey:pendingCheckout.requestKey}),
      });
      if (Number(order.totalIqd)!==expectedTotalIqd ||
          Number(order.deliveryFeeIqd)!==5000) {
        throw Error('المبلغ غير مؤكد؛ راجع طلباتك قبل إعادة الإرسال.');
      }
      pendingCheckout=null;
      cart={};saveCart();
      msg.textContent='تم تسجيل الطلب بنجاح، رقم الطلب: '+
        safe(order.orderId).slice(0,8)+'، الإجمالي مع التوصيل: '+
        formatPrice(order.totalIqd);
    } catch(err) {
      msg.textContent=err.message||'تعذر إرسال الطلب';
    } finally{renderBasket();}
  });
}
init();