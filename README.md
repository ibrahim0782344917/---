# شتريد؟ موجود! 🛍️

**Android Flutter — تطبيق الزبون الأول** لأسواق ومتاجر وخدمات بغداد.

## النسخة الحالية
- تصميم عربي بنفسجي/برتقالي، شاشة بداية، أقسام، بحث محلي وصفحات متاجر.
- **واجهة تسجيل حساب حقيقي بالبريد وكلمة المرور** باستخدام Supabase Auth.
- **قراءة متاجر حقيقية معتمدة** من Supabase بتطبيق سياسات RLS (عند تفعيل الاتصال).
- مخطط PostgreSQL آمن للزبائن والمتاجر والمنتجات في `supabase/migrations/`.
- سلة التجربة ما زالت **محلية وغير قابلة لإرسال طلب حقيقي**.
- عدم توصيل Supabase خلال البناء: التطبيق يعمل بنسخة البيانات **التجريبية المعلَّمة بوضوح**.

**لا توجد قاعدة Supabase خاصة بشتريد مرتبطة بعد**. لا تنسخ مفاتيح سرية إلى الكود. لا تخلط قاعدة المشروع بمشاريع Siraj القديمة.

## البناء التجريبي بدون قاعدة سحابية
استخدم [GitHub Actions](https://github.com/ibrahim0782344917/---/actions) لبناء APK تجريبي بدون ربط Supabase.

```bash
flutter create --org com.shitreed --project-name shitreed_customer --platforms android .
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## البناء المتصل بقاعدة مستقلة
بعد إنشاء مشروع Supabase مخصص، تطبيق migration، واستخراج بيانات الاتصال العلنية فقط:

```bash
flutter build apk --debug \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_PUBLIC_KEY
```

اقرأ [إعداد قاعدة البيانات](docs/BACKEND_SETUP.md).

## لم يكتمل بعد
خرائط Google وموقع GPS، المنتجات المباشرة والأسعار من التجار الحقيقيين، الطلبات والتوصيل، الدفع، تطبيق صاحب المتجر، المندوب، والإدارة. هذه الميزات بحاجة تنفيذ واختبارات قبل النشر.

الاسم «شتريد» يخضع لفحص توفر العلامة التجارية قبل النشر العام.
