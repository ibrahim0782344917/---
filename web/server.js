import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, resolve, sep } from 'node:path';

const port = Number(process.env.PORT || 3000);
const base = resolve(process.cwd(), 'public');
const sbUrl = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const sbKey = process.env.SUPABASE_PUBLISHABLE_KEY || '';
const MIME = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.svg':'image/svg+xml','.ico':'image/x-icon'};
const filePaths = new Map([
 ['/', 'index.html'], ['/index.html','index.html'], ['/merchant','merchant.html'],
 ['/admin','admin.html'], ['/privacy','privacy.html'], ['/terms','terms.html'],
 ['/support','support.html'], ['/delete-account','delete-account.html'],
 ['/app.css','app.css'], ['/app.js','app.js']
]);
const json = (res, code, obj) => { res.writeHead(code, {'content-type':'application/json; charset=utf-8','cache-control':'public, max-age=30','x-content-type-options':'nosniff'});res.end(JSON.stringify(obj)); };
const securityHeaders = {
 'x-content-type-options':'nosniff',
 'referrer-policy':'strict-origin-when-cross-origin',
 'x-frame-options':'DENY',
 'permissions-policy':'geolocation=(), camera=(), microphone=()',
 'content-security-policy':"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' https://*.supabase.co data:; connect-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
};
async function catalog(){
 if(!sbUrl || !sbKey) return {configured:false,stores:[],products:[],note:'ربط كتالوج Supabase قيد الإعداد'};
 const headers={'apikey':sbKey,'accept':'application/json'};
 async function fetchRows(path){
   const ac = new AbortController();
   const timer = setTimeout(()=>ac.abort(), 5500);
   try {
     const response = await fetch(sbUrl+'/rest/v1/'+path, {headers,signal:ac.signal});
     if(!response.ok) throw new Error('Supabase catalog read '+response.status);
     const payload = await response.json();
     return Array.isArray(payload) ? payload : [];
   } finally { clearTimeout(timer); }
 }
 const stores=await fetchRows('stores?select=id,name,area,category,description,opening_hours,logo_url,address,latitude,longitude&status=eq.approved&order=created_at.desc&limit=50');
 const products=await fetchRows('products?select=id,store_id,name,description,price_iqd,image_url,stock_quantity&is_active=eq.true&order=created_at.desc&limit=60');
 const allowed=new Set(stores.map(x=>x.id));
 return {configured:true,stores,products:products.filter(x=>allowed.has(x.store_id))};
}
const server=createServer(async (req,res)=>{
 try {
   for (const [k,v] of Object.entries(securityHeaders)) res.setHeader(k,v);
   if(req.method!=='GET' && req.method!=='HEAD'){res.writeHead(405,{'allow':'GET, HEAD'});return res.end('Method not allowed');}
   const pathname = new URL(req.url||'/', 'http://localhost').pathname;
   if (pathname==='/health'){res.writeHead(200,{'content-type':'application/json'});return res.end('{"ok":true,"app":"shitreed-web"}');}
   if (pathname==='/api/catalog') {
     try {return json(res,200,await catalog());}
     catch(e){console.error('Catalog read failed:',e.message);return json(res,503,{configured:true,stores:[],products:[],note:'تعذر تحميل البيانات حالياً'});}
   }
   const file=filePaths.get(pathname);
   if(!file){res.writeHead(404,{'content-type':'text/plain; charset=utf-8'});return res.end('الصفحة غير موجودة');}
   const full=join(base,file);
   if(!full.startsWith(base+sep)) {res.writeHead(403);return res.end();}
   const bytes=await readFile(full);
   res.writeHead(200,{'content-type':MIME[extname(full)]||'application/octet-stream','cache-control':file.endsWith('.html')?'no-store':'public,max-age=3600'});
   if(req.method==='HEAD')return res.end();
   return res.end(bytes);
 } catch(e){console.error('Request failed:',e.message); if(!res.headersSent)res.writeHead(500);res.end('خطأ مؤقت');}
});
server.listen(port,'0.0.0.0',()=>console.log('Shitreed web listening on '+port));
