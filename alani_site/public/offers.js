const offersRoot=document.getElementById('offers-grid');
const offersStatus=document.getElementById('offers-status');
let offers=[];
const t=(tag,text,cls)=>{const node=document.createElement(tag);node.textContent=text??'';if(cls)node.className=cls;return node;};
const remaining=iso=>{
  const ms=new Date(iso).getTime()-Date.now();
  if(!Number.isFinite(ms)||ms<=0)return null;
  const mins=Math.floor(ms/60000),days=Math.floor(mins/1440);
  const hrs=Math.floor((mins%1440)/60);
  return days>0?`باقي ${days} يوم و${hrs} ساعة`:`باقي ${hrs} ساعة و${mins%60} دقيقة`;
};
function card(offer){
  const el=t('article',null,'limited-offer-card');
  const photo=offer.image_url;
  if(typeof photo==='string'&&photo.startsWith('https://')){
    const img=t('img');img.loading='lazy';img.alt='صورة العرض';
    img.src=photo;el.append(img);
  }
  const body=t('div',null,'limited-offer-body');
  body.append(t('span','⏳ عرض محدود','limited-offer-kicker'),
    t('h3',offer.title),t('p',offer.description||''));
  const products=Array.isArray(offer.products)?offer.products:[];
  if(products.length){
    const list=t('div',null,'limited-offer-products');
    const money=n=>new Intl.NumberFormat('ar-IQ').format(n)+' د.ع';
    for(const p of products){
      const product=t('div',null,'limited-offer-product');
      product.append(t('strong',p.name));
      const prices=t('div',null,'limited-offer-prices');
      const oldPrice=t('del',money(p.regular_price_iqd),'offer-regular-price');
      const newPrice=t('strong',money(p.sale_price_iqd),'offer-sale-price');
      const discount=t('span','خصم '+p.discount_percent+'%','offer-discount-percent');
      prices.append(oldPrice,newPrice,discount);
      product.append(prices);list.append(product);
    }
    body.append(list);
  }
  const time=t('strong',remaining(offer.ends_at),'limited-offer-time');
  body.append(time);
  const link=t('a',offer.product_id?'تصفح المنتج في المتجر':'تصفح المنتجات','button primary');
  link.href='/#products';body.append(link);
  el.append(body);return el;
}
function render(){
  const now=Date.now();
  const active=offers.filter(o=>o&&o.is_published!==false&&
    new Date(o.starts_at).getTime()<=now&&new Date(o.ends_at).getTime()>now);
  offersRoot.replaceChildren();
  if(active.length===0){
    offersStatus.textContent='لا توجد عروض محدودة الوقت منشورة حالياً.';
    return;
  }
  offersStatus.textContent=`هناك ${active.length} عرض نشط الآن.`;
  active.forEach(o=>offersRoot.append(card(o)));
}
async function load(){
  offersStatus.textContent='جارٍ تحديث العروض…';
  try{
    const res=await fetch('/api/offers',{cache:'no-store'});
    const data=await res.json();
    if(!res.ok)throw Error('SERVICE_UNAVAILABLE');
    if(data.enabled!==true){
      offers=[];offersRoot.replaceChildren();
      offersStatus.textContent='صفحة العروض قيد التفعيل.';
      return;
    }
    offers=Array.isArray(data.items)?data.items:[];
    render();
  }catch(_){
    offersRoot.replaceChildren();
    offersStatus.textContent='تعذّر تحميل العروض. راجع اتصال الإنترنت وأعد المحاولة.';
  }
}
document.getElementById('offers-refresh').addEventListener('click',load);
load();
setInterval(render,30000);
setInterval(load,180000);
