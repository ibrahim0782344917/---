const pages = {
  '/welcome': {
    title:'أهلاً وسهلاً بكم',
    html: `<div class="welcome-visual"><span class="welcome-icon" aria-hidden="true">🌿</span><span class="overline">من قلب بغداد — الغزالية</span><h1>مرحباً بكم في متجر<br>السيد إبراهيم العاني</h1><p>نرحّب بكم في متجرنا المتخصص بالزيوت والأعشاب والعسل والمنتجات الطبيعية. نعرض منتجات المحل وأسعارها الفعلية، مع فيديوهات ومقالات ووصفات معلوماتية.</p><div class="welcome-buttons"><a class="button primary" href="/">ابدأ التسوق</a><a class="button ghost" href="/about-us">تعرّف علينا</a></div></div>
      <div class="info-tiles"><a href="/payment-policy"><strong>💵 الدفع عند الاستلام</strong><span>أجور التوصيل ٥٬٠٠٠ د.ع</span></a><a href="/return-policy"><strong>↺ نرحب بطلبات الاسترجاع</strong><span>اطلع على الشروط قبل طلبك</span></a><a href="/broken-product"><strong>🛡️ التعويض عن الكسر</strong><span>نراجع حالة التلف ونعالجها</span></a></div>`
  },
  '/about-us': {
    title:'من نحن',
    html: `<span class="overline">عن المتجر</span><h1>السيد إبراهيم العاني</h1><p class="lead">متجر عراقي للزيوت والأعشاب والعسل والمنتجات الطبيعية في بغداد — الغزالية.</p>
      <h2>رسالتنا</h2><p>نسعى إلى تقديم منتجات معروضة بمعلومات واضحة وأسعار فعلية بالدينار العراقي، وتسهيل التسوق واستلام الطلبات، وتوضيح سياسة الاسترجاع والتعويض قبل الشراء.</p>
      <h2>منتجاتنا ومحتوانا</h2><p>ستجد ضمن متجرنا الزيوت الطبيعية والأعشاب والعسل ومنتجات العناية، بحسب ما هو منشور ومتوفر في المخزون. ننشر مقالات ووصفات وفيديوهات تعريفية لأغراض تثقيفية فقط.</p>
      <h2>التواصل والشفافية</h2><p>موقع المتجر في بغداد — الغزالية. يمكن إرسال استفساراتك عبر وسائل الاتصال الرسمية التي يعلنها صاحب المتجر، ومراجعة طلبات الاسترجاع من <a href="/return-request">صفحة الاسترجاع</a> بعد تفعيلها.</p>
      <div class="policy-note">المواد التثقيفية عن الأعشاب لا تمثل تشخيصاً أو علاجاً أو بديلاً عن رأي مختص صحي.</div>`
  },
  '/payment-policy': {
    title:'سياسة الدفع والتوصيل',
    html: `<span class="overline">وضوح قبل الطلب</span><h1>الدفع عند الاستلام والتوصيل</h1><p class="lead">طريقة الدفع المعتمدة في متجر السيد إبراهيم العاني هي النقد عند استلام الطلب، ولا نفرض الدفع الإلكتروني المسبق على الزبون.</p>
      <div class="rate-card"><div><span>طريقة الدفع</span><strong>نقداً عند الاستلام</strong></div><div><span>أجور التوصيل المعلنة</span><strong>٥٬٠٠٠ د.ع</strong></div></div>
      <h2>كيف يتم الدفع؟</h2><p>بعد تأكيد الطلب وتوفر المنتج، يتم تنسيق التسليم. يدفع الزبون قيمة المنتجات مع أجور التوصيل عند استلام الطلب، ويجب توضيح الإجمالي النهائي قبل تأكيده.</p>
      <h2>الرسوم</h2><p>أجور التوصيل المحددة للطلب هي <strong>٥٬٠٠٠ دينار عراقي</strong>. أي اختلاف في منطقة الخدمة أو رسوم إضافية لا يُطبّق إلا بعد توضيحه للزبون وموافقته قبل تأكيد الطلب.</p>
      <h2>هل يوجد دفع ببطاقة؟</h2><p>لا توجد في النسخة الحالية وسيلة دفع إلكتروني مفعّلة، لذلك لا تطلب المنصة بيانات بطاقتك المصرفية.</p>
      <div class="policy-note">نظام الطلب من الموقع ما زال مغلقاً في النسخة التجريبية حتى اكتمال الاختبارات. عرض السياسة لا يعني أن تقديم الطلبات التجارية فُعّل.</div>
      <p><a href="/return-policy" class="button ghost">اطلع على سياسة الاسترجاع</a></p>`
  },
  '/return-policy': {
    title:'سياسة الاسترجاع والاستبدال',
    html: `<span class="overline">بعد الاستلام</span><h1>الاسترجاع والاستبدال</h1><p class="lead">نقبل تقديم طلبات إرجاع المنتجات بعد الاستلام. تُراجع كل حالة بحسب حالة المنتج وسبب الإرجاع وحقوق الزبون المقررة قانوناً.</p>
      <div class="rate-card"><div><span>التوصيل الأول</span><strong>٥٬٠٠٠ د.ع</strong></div><div><span>نقل الإرجاع الاختياري</span><strong>٥٬٠٠٠ د.ع</strong></div></div>
      <h2>عند رغبتك في إرجاع منتج سليم</h2><p>إذا غيّر الزبون رأيه بعد استلام منتج سليم، تُحسب أجور التوصيل الأول <strong>٥٬٠٠٠ دينار</strong> وأجور إرجاع المنتج <strong>٥٬٠٠٠ دينار</strong> عندما تُنفذ الخدمتان فعلياً. أي مبلغ يعاد للزبون يُحدد بعد مراجعة تفاصيل الطلب والخدمات المنفذة والتوافق مع القانون.</p>
      <h2>إذا وصل المنتج مكسوراً أو تالفاً أو مخالفاً للوصف</h2><p>يتحمل المتجر مسؤولية معالجة الخلل الذي يعود إلى التعبئة أو التجهيز أو التوصيل، بعد مراجعة الأدلة والتحقق من سبب الضرر، مع التعويض أو الاستبدال أو رد المبلغ بحسب الحالة والحقوق القانونية. <strong>لا نخصم رسوم إرجاع اختيارية من الزبون عند ثبوت خطأ المتجر.</strong></p>
      <h2>طريقة تقديم طلب الاسترجاع</h2><ol><li>احتفظ برقم الطلب ومعلومات الاستلام.</li><li>قدّم السبب ووصف الحالة من صفحة <a href="/return-request">طلب الاسترجاع</a>.</li><li>عند وجود تلف، أرفق أو جهّز صور المنتج والغلاف إن توفرت.</li><li>يراجع الفريق الحالة ويتواصل معك بشأن المعالجة وآلية الإرجاع والتعويض.</li></ol>
      <h2>شروط عامة</h2><p>عند الإرجاع الاختياري يُرجى الحفاظ على المنتج والعبوة دون استخدام غير ضروري بقدر الإمكان. لا تؤدي هذه الشروط إلى تقييد الحقوق الإلزامية عند وجود عيب أو خطأ في المنتج. لم تُحدَّد بعد مدة تجارية إضافية لقبول الإرجاع؛ لذلك لا نعرض مدة من عندنا.</p>
      <div class="policy-note"><strong>مهم:</strong> أي خصومات تُراجع قبل تطبيقها، ولا تُفرض على الحالات التي يحميها القانون العراقي. <a href="/broken-product">تفاصيل التعويض عن الكسر</a>.</div>
      <p><a class="button primary" href="/return-request">قدم طلب استرجاع</a></p>`
  },
  '/broken-product': {
    title:'التعويض عن المنتج المكسور',
    html: `<span class="overline">حقوق الزبون</span><h1>إذا وصلك منتج مكسور، نعالج المشكلة</h1><p class="lead">نحرص على وصول الزيوت والعسل والمنتجات الأخرى بحالة سليمة، وإذا استلمت منتجاً مكسوراً أو مسرباً بسبب التغليف أو النقل، نراجع الحالة ونتعامل معها بإنصاف.</p>
      <h2>التعويض والاستبدال</h2><p>عند ثبوت التلف أو الكسر الذي لا يعود إلى سوء استخدام الزبون، نعمل على تعويضه، أو إرسال بديل سليم، أو رد قيمة المنتج وفق طبيعة الحالة وحقوقه القانونية.</p>
      <h2>هل تُخصم أجور توصيل وإرجاع؟</h2><p><strong>لا تُحمَّل للزبون أجور التوصيل أو الرجوع الناتجة عن خطأ مثبت من المتجر أو مسؤول التوصيل.</strong> رسوم الإرجاع العادية تخص طلب إرجاع منتج سليم لسبب اختياري فقط.</p>
      <h2>ماذا تفعل عند وجود كسر؟</h2><ol><li>أبلغنا بعد اكتشاف الضرر في أقرب فرصة.</li><li>احتفظ بالمنتج والعبوة قدر الإمكان.</li><li>جهّز صور العبوة والمنتج المتضرر ورقم الطلب.</li><li>قدّم طلباً مع اختيار «مكسور أو تالف» حتى نراجعه.</li></ol>
      <p><a class="button primary" href="/return-request">الإبلاغ عن منتج مكسور</a></p>`
  },
  '/help': {
    title:'الأسئلة الشائعة',
    html: `<span class="overline">مساعدة الزبون</span><h1>الأسئلة الشائعة</h1>
      <details open><summary>كيف أدفع ثمن طلبي؟</summary><p>الدفع نقداً عند الاستلام، بعد تفعيل نظام الطلبات واعتماد تفاصيل الطلب.</p></details>
      <details><summary>كم سعر التوصيل؟</summary><p>أجور التوصيل المعلنة ٥٬٠٠٠ دينار عراقي للطلب، ويُبلغ الزبون بأي اختلاف قبل التأكيد.</p></details>
      <details><summary>هل أستطيع إرجاع المنتج بعد الاستلام؟</summary><p>يمكنك تقديم طلب مراجعة إرجاع. بالنسبة للمنتج السليم المُرجع اختيارياً، أجور التوصيل ٥٬٠٠٠ دينار وأجور الرجوع ٥٬٠٠٠ دينار عند تنفيذ الخدمتين.</p></details>
      <details><summary>ماذا لو وصل الزيت أو العسل مكسوراً؟</summary><p>سنراجع الحالة، وعند ثبوت الضرر الذي يعود للمتجر أو التوصيل، نُعالج الحالة بالتعويض أو الاستبدال أو استرداد المبلغ وفق الحقوق القانونية، دون فرض رسوم خطأ المتجر عليك.</p></details>
      <details><summary>كيف أطلب استرجاعاً؟</summary><p>استخدم <a href="/return-request">صفحة طلب الاسترجاع</a>. تحتاج إلى رقم الطلب وحساب المشتري، ويُفعَّل الإرسال بعد إكمال قاعدة البيانات.</p></details>
      <details><summary>هل وصفات الأعشاب بديل عن الطبيب؟</summary><p>لا، هي معلومات عامة تثقيفية، ولا تعني ادعاء علاج الأمراض.</p></details>`
  },
  '/settings': {
    title:'الإعدادات',
    html: `<span class="overline">تخصيص التجربة</span><h1>إعدادات العرض</h1><p class="lead">يمكنك تعديل حجم الخط وأسلوب عرض الصفحات على جهازك. تُحفظ تفضيلات العرض محلياً في هذا المتصفح فقط.</p>
      <div class="setting-line"><label for="setting-text-size">حجم الخط</label><select id="setting-text-size"><option value="normal">عادي</option><option value="large">كبير</option></select></div>
      <div class="setting-line"><label for="setting-contrast">تباين مرتفع</label><input type="checkbox" id="setting-contrast"></div>
      <div class="setting-line"><label>اللغة</label><strong>العربية (RTL)</strong></div>
      <p class="small">لا نعدّل حسابك أو بيانات الطلبات عند تغيير هذه الخيارات.</p>
      <p><a class="button ghost" href="/privacy">سياسة الخصوصية</a></p>`
  },
  '/return-request': {
    title:'تقديم طلب استرجاع أو تعويض',
    html: `<span class="overline">خدمة ما بعد الاستلام</span><h1>طلب استرجاع أو تعويض</h1><p class="lead">نرحب بمراجعة حالات الاسترجاع والمنتجات المكسورة بعد استلام الطلب. أكمل معلوماتك وسيُرسل الطلب فقط عند تفعيل الخدمة وتأمين بياناتها.</p>
      <div class="policy-note"><strong>الرسوم:</strong> التوصيل ٥٬٠٠٠ د.ع، ونقل الإرجاع الاختياري لمنتج سليم ٥٬٠٠٠ د.ع. لا تُفرض أجور خطأ المتجر عند ثبوت الكسر أو الخلل.</div>
      <form id="return-form" class="return-form">
        <label>بريد حساب الشراء<input id="return-email" type="email" autocomplete="email" required></label>
        <label>كلمة مرور الحساب<input id="return-password" type="password" autocomplete="current-password" minlength="8" required></label>
        <label>رقم الطلب (UUID)<input id="return-order" type="text" minlength="36" maxlength="36" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" required></label>
        <label>سبب الطلب<select id="return-reason" required><option value="change_mind">إرجاع اختياري لمنتج سليم</option><option value="damaged">مكسور أو متضرر</option><option value="wrong_item">منتج مختلف عن الطلب</option><option value="defective">عيب في المنتج</option></select></label>
        <label>تفاصيل الحالة<textarea id="return-details" maxlength="2000" minlength="15" rows="5" placeholder="اكتب وصف الحالة، تاريخ الاستلام، نوع الضرر إن وجد…" required></textarea></label>
        <label>رابط صورة المنتج أو العلبة (اختياري)<input id="return-photo" type="url" placeholder="https://..."></label>
        <div class="policy-note">لا تضع أي صور هوية أو بيانات مصرفية. رفع الصور مباشرةً إلى تخزين المتجر لم يُفعّل بعد؛ لا ترسل صوراً حساسة عبر روابط عامة.</div>
        <button class="button primary full" type="submit" id="return-submit">إرسال طلب المراجعة</button>
        <p id="return-result" class="form-message" role="status"></p>
      </form>
      <p class="small">يحق لصاحب الطلب متابعة استفساره. إرسال الطلب لا يعني الموافقة الآلية على التعويض أو الخصم، بل تتم مراجعته.</p>`
  }
};
function renderPage(){
  const key=location.pathname.replace(/\/+$/,'')||'/welcome';
  const item=pages[key]||pages['/welcome'];
  document.title=item.title+' | السيد إبراهيم العاني';
  const target=document.getElementById('page-content');
  target.innerHTML=item.html;
  document.querySelectorAll('.info-sidebar a,.side-menu a').forEach(a=>{
    if(a.getAttribute('href')===key)a.setAttribute('aria-current','page');
  });
  if(key==='/settings')setupSettings();
  if(key==='/return-request')setupReturnForm();
}
function setupMenu(){
  const trigger=document.getElementById('info-menu-trigger');
  const menu=document.getElementById('info-side-menu');
  const overlay=document.getElementById('info-menu-overlay');
  function toggle(open){
    trigger.setAttribute('aria-expanded',String(open));
    menu.setAttribute('aria-hidden',String(!open));
    menu.classList.toggle('open',open);
    overlay.hidden=!open;
    if(open)document.getElementById('info-menu-close').focus();
    else trigger.focus();
  }
  trigger.addEventListener('click',()=>toggle(true));
  document.getElementById('info-menu-close').addEventListener('click',()=>toggle(false));
  overlay.addEventListener('click',()=>toggle(false));
  document.addEventListener('keydown',e=>{
    if(e.key==='Escape'&&menu.classList.contains('open'))toggle(false);
  });
}
function setupSettings(){
  const s=document.getElementById('setting-text-size'),c=document.getElementById('setting-contrast');
  s.value=localStorage.getItem('alani_font')==='large'?'large':'normal';
  c.checked=localStorage.getItem('alani_contrast')==='high';
  s.addEventListener('change',()=>{localStorage.setItem('alani_font',s.value);applySettings()});
  c.addEventListener('change',()=>{localStorage.setItem('alani_contrast',c.checked?'high':'normal');applySettings()});
}
function applySettings(){
  document.documentElement.classList.toggle('large-text',localStorage.getItem('alani_font')==='large');
  document.documentElement.classList.toggle('high-contrast',localStorage.getItem('alani_contrast')==='high');
}
function setupReturnForm(){
  const form=document.getElementById('return-form');
  const button=document.getElementById('return-submit');
  const result=document.getElementById('return-result');
  button.disabled=true;
  result.textContent='جارٍ التحقق من تفعيل استقبال طلبات الاسترجاع…';
  fetch('/api/returns/config').then(response=>response.json())
    .then(config=>{
      button.disabled=config.enabled!==true;
      button.textContent=config.enabled===true
        ? 'إرسال طلب المراجعة':'استقبال الاسترجاع الإلكتروني قيد التجهيز';
      result.textContent=config.enabled===true
        ? 'يمكنك تقديم الطلب بعد تسجيل الدخول بحساب الشراء.'
        : 'صفحة الاسترجاع جاهزة، لكن إرسال الطلبات غير مفعل حتى نختبر الحماية.';
    }).catch(()=>{
      button.disabled=true;
      result.textContent='تعذر التحقق من خدمة الاسترجاع حالياً.';
    });
  form.addEventListener('submit',async(event)=>{
    event.preventDefault();
    const result=document.getElementById('return-result');
    const button=document.getElementById('return-submit');
    result.textContent='جارٍ التحقق…';button.disabled=true;
    try{
      const authResponse=await fetch('/api/login',{
        method:'POST',headers:{'content-type':'application/json'},
        body:JSON.stringify({
          email:document.getElementById('return-email').value.trim(),
          password:document.getElementById('return-password').value
        })
      });
      const auth=await authResponse.json();
      if(!authResponse.ok||!auth.access_token)throw Error(auth.error||'بيانات الدخول غير صحيحة.');
      const response=await fetch('/api/return-requests',{
        method:'POST',
        headers:{'content-type':'application/json','authorization':'Bearer '+auth.access_token},
        body:JSON.stringify({
          orderId:document.getElementById('return-order').value.trim(),
          reason:document.getElementById('return-reason').value,
          details:document.getElementById('return-details').value.trim(),
          photoUrl:document.getElementById('return-photo').value.trim()
        })
      });
      const outcome=await response.json();
      if(!response.ok)throw Error(outcome.error||'تعذر استقبال طلب الاسترجاع.');
      result.textContent='تم استلام طلب المراجعة بنجاح، رقم الطلب: '+String(outcome.id).slice(0,8);
      form.reset();
    }catch(error){
      result.textContent=error.message||'تعذر إرسال الطلب، لم يتم تسجيله.';
    }finally{button.disabled=false;}
  });
}
applySettings();
setupMenu();
renderPage();