# عرض المحلات المسجلة على Google — «شتريد؟ موجود!»

## ما أُضيف
- عند فتح الخريطة، يعرض التطبيق محلات Google Maps القريبة من مركز بغداد، من دون الادعاء أنها متاجر معتمدة.
- زر «ابحث بهذه المنطقة» يحدّث النتائج عند تحريك الخريطة، وزر الموقع يبحث قرب المستخدم بإذنه.
- أسماء المحلات وعناوينها ومواقعها تُطلب مباشرة من Places API (New) عبر Supabase Edge Function آمنة نسبياً ضد إساءة الاستخدام، ولا تُخزَّن في Supabase.
- دبوس مختلف وعلامة «من Google Maps»، مع الاتجاهات إلى Google Maps الخارجية.
- قائمة «المتاجر المعتمدة» تبقى منفصلة ويظل شراء المنتجات خاصاً بالمتاجر التي وافق مالكها على النشر.
- النتائج 20 محلّاً كحد أقصى لكل منطقة؛ ليس فهرساً كاملاً لبغداد.

## التفعيل (مطلوب حتى تظهر المحلات)
1. داخل Google Cloud، فعّل **Places API (New)** وBilling لمشروعك.
2. أنشئ **مفتاح Google Places جديداً** منفصلاً عن مفتاح **Maps SDK for Android**، وقيّده باستخدام API Restrictions على **Places API (New)** فقط. لا تضع المفتاح في Flutter أو GitHub أو نص دردشة.
3. ضع القيمة في **Supabase > Edge Functions > Secrets** باسم GOOGLE_PLACES_API_KEY. يمكن إضافة GOOGLE_PLACES_RATE_SALT كقيمة عشوائية خاصة.
4. اضبط حدود **quota لكل يوم** في Google Cloud ونبّه على تجاوز الميزانية. وظيفة التحكّم في Supabase ليست بديلاً عن حدّ Google Cloud.
5. طبّق migration: supabase/migrations/20261109110000_google_places_request_limits.sql، ثم انشر Edge Function اسمها nearby-shops مع verify_jwt=false بحسب supabase/config.toml.
6. ابنِ تطبيق العميل من GitHub Actions وثبّته على هاتفك، وتحقّق من ظهور محلات جوجل في الخريطة وعنوان المحل وفتح الاتجاهات.
7. حدّث شروط الاستخدام وسياسة الخصوصية: معلومات Google Maps تُعرض مع نسب المصدر وشروط Google. الموقع اختياري ويستخدم بعد طلب الإذن.

## اختبار قبل الإنتاج
- عدم توفر سر Places يعطي خطأ خدمة غير جاهزة، ولا يؤثر على المتاجر المعتمدة.
- استعلام خارج منطقة بغداد يرفض.
- طلبات متكررة أكثر من 8 في الدقيقة من نفس IP تُرفض.
- تحريك الخريطة وحده لا يصدر طلبات مدفوعة؛ يحتاج ضغط «ابحث بهذه المنطقة».
- لا تضع صوراً أو أسعاراً أو منتجات لأي محل من Google ما لم يسجّل التاجر ويضيفها بنفسه.
- اعتمد المزامنة مع Google فقط للمكان والاسم والعنوان الحالي، بدون تخزين دائم لبيانات Google.

مصادر رسمية:
- https://developers.google.com/maps/documentation/places/web-service/nearby-search
- https://developers.google.com/maps/documentation/places/web-service/policies
- https://supabase.com/docs/guides/functions/auth-headers
