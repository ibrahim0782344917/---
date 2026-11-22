const form=document.getElementById('deletion-form');
const result=document.getElementById('result');
form?.addEventListener('submit',async(event)=>{
  event.preventDefault();
  const button=document.getElementById('send');
  button.disabled=true;
  result.textContent='جارٍ تسجيل طلبك…';
  let token;
  try{
    const login=await fetch('/api/login',{method:'POST',
      headers:{'content-type':'application/json'},
      body:JSON.stringify({email:form.email.value.trim(),password:form.password.value}),
      cache:'no-store'});
    if(!login.ok)throw new Error('تحقق من بيانات تسجيل الدخول.');
    const session=await login.json();
    token=session.access_token;
    if(!token)throw new Error('تعذر تأكيد الحساب.');
    const request=await fetch('/api/account/deletion-request',{method:'POST',
      headers:{'content-type':'application/json','authorization':'Bearer '+token},
      body:JSON.stringify({reason:form.reason.value.trim()}),
      cache:'no-store'});
    if(!request.ok)throw new Error('تعذر تسجيل الطلب الآن. تحقق من الاتصال أو تواصل مع الدعم.');
    const response=await request.json();
    result.textContent='تم تسجيل الطلب: '+String(response.requestId||'').slice(0,8)+
      ' — لم يُحذف الحساب بعد، وستُراجع المعلومات والالتزامات القانونية.';
    form.password.value='';
  }catch(error){
    result.textContent=error.message||'حدث خطأ أثناء إرسال الطلب.';
  }finally{
    token=undefined;
    button.disabled=false;
  }
});