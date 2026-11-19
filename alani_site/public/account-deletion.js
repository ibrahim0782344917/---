const form=document.getElementById('account-deletion-form');
const message=document.getElementById('delete-message');
const submit=document.getElementById('delete-submit');
form?.addEventListener('submit',async(event)=>{
  event.preventDefault();
  if(!form.checkValidity())return;
  if(submit.disabled)return;
  submit.disabled=true;
  message.textContent='جارٍ التحقق من الحساب وتسجيل الطلب…';
  const email=document.getElementById('delete-email').value.trim();
  const password=document.getElementById('delete-password');
  try{
    const login=await fetch('/api/login',{
      method:'POST',
      headers:{'content-type':'application/json'},
      cache:'no-store',
      body:JSON.stringify({email,password:password.value}),
    });
    password.value='';
    const credentials=await login.json();
    if(!login.ok || typeof credentials.access_token!=='string'){
      throw new Error(credentials.error||'تعذر تسجيل الدخول.');
    }
    const response=await fetch('/api/account-deletion-request',{
      method:'POST',
      headers:{
        'content-type':'application/json',
        'authorization':'Bearer '+credentials.access_token,
      },
      cache:'no-store',
      body:JSON.stringify({
        reason:document.getElementById('delete-reason').value.trim(),
      }),
    });
    const status=await response.json();
    if(!response.ok){
      throw new Error(status.error||'لم يتم تسجيل الطلب.');
    }
    message.textContent=status.alreadySubmitted
      ? 'لديك طلب حذف سابق قيد المعالجة. لا حاجة لإعادة الإرسال.'
      : 'تم تسجيل طلب حذف الحساب للمراجعة. الحالة: قيد المعالجة.';
    if(!status.alreadySubmitted)form.reset();
  }catch(error){
    password.value='';
    message.textContent=error.message||'تعذر إكمال طلب حذف الحساب.';
  }finally{
    submit.disabled=false;
  }
});
