# شتريد؟ موجود! — تشغيل Google Maps وGoogle Places الحقيقي

**الحالة بتاريخ 16 نوفمبر 2026**

1. تم العثور في Supabase Functions logs على POST 404 لمسار `nearby-shops` (لم تكن الخدمة منشورة).
2. نُشرت الآن الدالة `nearby-shops` على مشروع `ltwncrewggdrjevakwpb`، حالتها ACTIVE، مع `verify_jwt=false` للبحث العام.
3. تم تثبيت حد طلبات Postgres في مخطط `private_places` ومُنحت صلاحية التنفيذ لدور الخادم `service_role` فقط؛ التطبيق والزائر لا يملكان حق استدعاء الميزانية مباشرة.
4. **مهم:** `GOOGLE_PLACES_ENABLED` غير مفعّل؛ الدالة تتوقف بأمان مع `PLACES_NOT_ENABLED` (503). لم تُفعّل أي استعلامات Google مدفوعة ولم نثبت أن API key/Billing مهيأة.
5. تطبيق الزبون يعرض الآن وصف الخطأ الصحيح بمجرد تثبيت APK الجديد. المحلات التي اعتمدها شتريد عبر Supabase تظل قابلة للعرض بشكل مستقل عن نتائج Google.

## خطوات صاحب المشروع في Google Cloud — قبل السماح بتكاليف API
- افتح https://console.cloud.google.com/apis/library/places.googleapis.com واختر مشروع Google Cloud الذي تملكه. فعّل **Places API (New)**، وتأكد من ربط الحساب بالفوترة.
- افتح https://console.cloud.google.com/google/maps-apis/quotas واضبط حدود الاستعلامات وميزانية التنبيهات. **تنبيه الميزانية ليس سقفاً مالياً بحد ذاته**، لذلك لا تعتمد عليه وحده. تأكد من الحد الفعلي في Google API quotas، مع مراعاة سقف الخادم (100 طلب يومياً).
- أنشئ مفتاحاً منفصلاً لخادم Places (New) مع تقييد **API Restrictions** إلى Places API (New) فقط. إن تعذّر تقييد عنوان IP بسبب عناوين الخروج المتغيرة لـSupabase Edge، لا تعرض المفتاح في APK أو GitHub؛ راجع حماية الخادم ومراقبة الاستهلاك أولاً.
- من https://supabase.com/dashboard/project/ltwncrewggdrjevakwpb/functions ابحث عن `nearby-shops` ثم افتح إعدادات Secrets وضع:
  - `GOOGLE_PLACES_API_KEY`: مفتاح الخادم الجديد.
  - `GOOGLE_PLACES_RATE_SALT`: قيمة عشوائية طويلة (16 حرفاً على الأقل) لا تعيد استخدامها في مكان آخر.
  - **بعد موافقتك على الاستعلامات المدفوعة فقط:** `GOOGLE_PLACES_ENABLED=true`.
- لا ترسل مفاتيح Google عبر المحادثات ولا تضعها في متغيرات `--dart-define` للهواتف. المفاتيح الخادمية تبقى في Supabase Secrets.

## خريطة Android داخل التطبيق — إعداد منفصل عن البحث الخادمي
- خدمة `nearby-shops` ترجع بيانات محلات Google عبر Supabase؛ أما **الخريطة البصرية داخل التطبيق** فتتطلب Maps SDK for Android ومفتاح Android منفصلاً مقيداً بـPackage Name وبصمة SHA-1 للتوقيع الفعلي.
- في GitHub Actions يمكن إضافة Secret باسم `SHITREED_GOOGLE_MAPS_ANDROID_KEY` وRepository Variable باسم `SHITREED_GOOGLE_MAPS_APPROVED` بقيمة `true` **بعد تهيئة القيد والفوترة والموافقة**. من دونهما تظل الخريطة الداخلية غير مفعّلة، مع زر فتح خرائط Google الخارجية.
- تأكد من Application ID وبصمة SHA-1 للتطبيق المبني فعلياً، فبصمة Debug تختلف عن التوقيع النهائي/Play App Signing.
- روابط الإجراءات في GitHub: https://github.com/ibrahim0782344917/---/pull/7

## خطوات الاختبار بعد الإعداد والموافقة
1. استدعاء `nearby-shops` من حساب اختبار في بغداد مرة واحدة فقط، والتحقق من HTTP 200 و`places` وعلامة Google.
2. التحقق من أن حد 100 طلب باليوم و8 طلبات بالدقيقة يعمل ويمتنع عند تجاوز الحدود، ثم مراجعة Google Cloud usage/billing.
3. البناء الجديد ببيانات Maps Android المقيدة ثم التجربة على هاتف Android حقيقي.
4. عدم تسجيل نتائج Places في قاعدة بيانات شتريد كمتاجر تجارية دون مطالبة ملكية حقيقية؛ Google يظهر كمصدر مستقل.
5. تأكيد توافق التخزين والإسناد (Google attributions) وعدم إنشاء منتجات أو تقييمات وهمية.

**قاعدة السلامة:** نشر الدالة أو ظهور Google Maps الخارجي لا يثبت نجاح الاتصال المدفوع الحقيقي. لا تُعلن الميزة جاهزة للإنتاج حتى اجتياز الاختبارات كلها.
