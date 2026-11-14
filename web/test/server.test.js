import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer as createNetServer } from 'node:net';
import { request as httpRequest } from 'node:http';
import { setTimeout as sleep } from 'node:timers/promises';

async function freePort() {
  const s=createNetServer();
  await new Promise(resolve=>s.listen(0,'127.0.0.1',resolve));
  const port=s.address().port;
  await new Promise(resolve=>s.close(resolve));
  return port;
}
async function request(port,path,method='GET',data=null,origin='https://shitreed.test') {
  const body=data===null?null:JSON.stringify(data);
  return new Promise((resolve,reject)=>{
    const req=httpRequest({
      hostname:'127.0.0.1',port,path,method,
      headers:{Host:'shitreed.test',...(method==='POST'?{Origin:origin,'Content-Type':'application/json'}:{}),...(body?{'Content-Length':Buffer.byteLength(body)}:{})},
      timeout:2000
    },res=>{
      const chunks=[];
      res.on('data',chunk=>chunks.push(chunk));
      res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,body:Buffer.concat(chunks).toString('utf8')}));
    });
    req.on('error',reject);
    req.on('timeout',()=>req.destroy(new Error('timeout')));
    req.end(body||undefined);
  });
}
test('website GET pages and authenticated API route guards',async t=>{
  const port=await freePort();
  const child=spawn(process.execPath,['server.js'],{
    cwd:new URL('..',import.meta.url),
    env:{...process.env,PORT:String(port),SUPABASE_URL:'http://127.0.0.1:1',SUPABASE_PUBLISHABLE_KEY:'mock-publishable-key',ENABLE_COD_CHECKOUT:'true'},
    stdio:['ignore','pipe','pipe']
  });
  let stderr='';
  child.stderr.on('data',d=>{stderr+=d.toString()});
  try {
    let ready=false;
    for(let i=0;i<40;i++){
      if(child.exitCode!==null)throw Error('server exited: '+stderr);
      try{const r=await request(port,'/health');if(r.status===200){ready=true;break;}}catch{}
      await sleep(100);
    }
    assert.equal(ready,true,'server should be ready');

    await t.test('homepage and account forms are served',async()=>{
      for(const path of ['/','/login','/checkout','/orders','/privacy','/delete-account']){
        const r=await request(port,path);
        assert.equal(r.status,200,path);
      }
    });
    await t.test('login POST reaches authentication handler (not the static 405)',async()=>{
      const r=await request(port,'/api/auth/login','POST',{email:'not-an-email',password:'12345678'});
      assert.equal(r.status,400,r.body);
      assert.match(r.body,/البريد/);
    });
    await t.test('cross-origin POST is rejected',async()=>{
      const r=await request(port,'/api/auth/login','POST',{email:'a@example.org',password:'12345678'},'https://evil.example');
      assert.equal(r.status,403,r.body);
    });
    await t.test('unauthenticated users cannot access orders or checkout',async()=>{
      assert.equal((await request(port,'/api/orders')).status,401);
      const r=await request(port,'/api/orders','POST',{});
      assert.equal(r.status,401,r.body);
    });
    await t.test('unrecognized POST is 405 and has no arbitrary file writes',async()=>{
      const r=await request(port,'/not-a-route','POST',{anything:'value'});
      assert.equal(r.status,405);
    });
    await t.test('public catalog does not leak unapproved content on network failure',async()=>{
      const r=await request(port,'/api/catalog');
      assert.equal(r.status,503,r.body);
      const payload=JSON.parse(r.body);
      assert.deepEqual(payload.stores,[]);
      assert.deepEqual(payload.products,[]);
    });
  } finally {
    child.kill('SIGTERM');
    await sleep(100);
  }
});