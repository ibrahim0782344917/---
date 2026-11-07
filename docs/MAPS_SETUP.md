# خرائط بغداد في تطبيق «شتريد؟ موجود!»

## ما تم برمجته
- تبويب **الخريطة** بالتصميم البنفسجي والبرتقالي، بحث بالاسم والمنطقة ونوع الخدمة.
- مواقع المتاجر المعتمدة من Supabase فقط، بشرط توفير latitude وlongitude من صاحب المتجر.
- دبابيس GoogleMap عند تفعيل Maps SDK فعلياً.
- زر **المحلات القريبة مني**: إذن موقع أثناء الاستخدام فقط وبعد الضغط، وترتيب النتائج بالمسافة إن كانت الإحداثيات موجودة.
- زر **الاتجاهات** يفتح الملاحة في Google Maps باستخدام إحداثيات المتجر، بدون تعقب خلفي.
- إذا Google Maps SDK غير مفعّل: تظهر واجهة إعداد واضحة وزر يفتح **Google Maps الخارجي** لمدينة بغداد.

## التفعيل داخل Android
النسخة المبنية على GitHub Actions تقبل مفتاح Maps SDK من **GitHub repository secret** باسم GOOGLE_MAPS_API_KEY.

في Google Cloud:
1. أنشئ/اختر Google Cloud Project واضبط Billing (قد تنشأ رسوم حسب الاستخدام).
2. فعّل Maps SDK for Android.
3. أنشئ مفتاح API مقيّداً إلى Maps SDK for Android فقط.
4. قيّد المفتاح إلى تطبيق Android الصحيح حسب package name وSHA-1 لشهادة توقيع التطبيق. يجب اعتماد توقيع ثابت للإصدار؛ SHA-1 لمفتاح Debug المؤقت على GitHub قد يتغير كل تشغيل.
5. أضف المفتاح إلى GitHub Settings > Secrets and variables > Actions > New repository secret. لا تضفه إلى commit أو رسائل GitHub العامة.
6. أعد تشغيل workflow الخاص بـ Shitreed Customer Connected APK. سكربت scripts/configure_android_maps.py يضيف metadata للتطبيق ويتحقق من وجود المفتاح من غير طباعته في السجل.
7. افحص الدبابيس على هاتف فعلي بعد اعتماد أول متجر موثّق بإحداثيات دقيقة.

**مهم:** المفتاح في APK تطبيق Android قابل للاستخراج بطبيعته؛ تقييد المفتاح بالشهادة واسم الحزمة وSDK مهم جداً لمنع الاستخدام غير المصرح. لا تستخدم service_role أو مفتاح Supabase الإداري داخل تطبيق Android.

### روابط رسمية
- https://developers.google.com/maps/documentation/android-sdk/get-api-key
- https://developers.google.com/maps/documentation/android-sdk/usage-and-billing
- https://pub.dev/packages/google_maps_flutter
- https://pub.dev/packages/geolocator

## ما لم يُنفّذ بعد
- Google Places API ومعلومات المتاجر الخارجية: يحتاج ترخيصاً ومفتاحاً منفصلاً أو إعداد قيود مناسب؛ لا تعني خرائط Google توفّر أسعار منتجات المحلات أو مخزونها.
- ملاحة منعطفاً بمنعطف **داخل التطبيق**. الموجود حالياً فتح Google Maps الخارجي للملاحة.
- متابعة المندوب لحظياً: تحتاج نظاماً منفصلاً وموافقة واضحة وسياسة خصوصية.
- بيانات المتاجر الحقيقية: قاعدة شتريد لا تحتوي على متاجر موثقة منشورة حتى آخر فحص.

## التصميم
تبويب الخريطة بجوار البحث، شريط علوي بنفسجي، بحث أبيض، مرشحات مناطق، مساحة خريطة، زر تحديد الموقع الاختياري، بطاقات محلات واتجاهات. المحتوى يتعامل مع غياب المفتاح أو المواقع بوضوح.
