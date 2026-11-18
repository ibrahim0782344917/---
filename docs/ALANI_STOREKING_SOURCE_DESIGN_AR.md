# تصميم متجر السيد إبراهيم العاني — مرجع ملفات StoreKing الأصلية

## الملفات التي فُحصت
- `web.zip` (280,417,845 bytes): مشروع StoreKing بموقع Laravel / Vue؛ يحتوي أيضاً مجلدات `vendor` وملف `.env` لا يجوز نقلها إلى مستودع عام.
- `customer-app.zip` (4,698,854 bytes): تطبيق Flutter باسم مجلد `storeking-customer-app`.
- `web/resources/js/components/frontend/home/HomeComponent.vue`
- `web/resources/js/components/frontend/home/SliderComponent.vue`
- `web/resources/js/components/frontend/home/CategoryComponent.vue`
- `web/resources/js/components/frontend/home/PromotionComponent.vue`
- `web/resources/js/components/frontend/home/MostPopularComponent.vue`
- `web/resources/js/components/frontend/home/ProductSectionComponent.vue`
- `web/resources/js/components/frontend/home/FlashSaleComponent.vue`
- `web/resources/js/components/frontend/home/BenefitComponent.vue`
- `storeking-customer-app/lib/app/modules/home/views/home_screen.dart`
- `storeking-customer-app/lib/app/modules/home/widgets/category.dart`
- `storeking-customer-app/lib/config/theme/app_color.dart`

## عناصر مُستلهمة من المصدر (مع تكييف خاص)
1. **الشريط العلوي**: هوية المحل والبحث والتنقل الواضح.
2. **السلايدر**: العرض الدوّار ونقاط التحكم وإيقاف الدوران عند التركيز؛ ليست فيه خصومات غير موجودة.
3. **التصنيفات**: بطاقات أفقية في التطبيق وشبكة متجاوبة على الموقع؛ أصلها StoreKing category cards.
4. **المنتجات**: بطاقات وسعر بالدينار العراقي ومخزون وفتح تفاصيل وإضافة للسلة.
5. **المحتوى**: فيديوهات ووصفات ومدونة أُضيفت خصيصاً لهذا المتجر؛ ليست نسخاً أصلية من StoreKing.
6. **المزايا**: أربعة عناصر توضح مصادر البيانات والمحتوى والموقع، بدلاً من وعود توصيل غير مثبتة.
7. **الألوان**: أخضر `#01BE5F` وخلفية `#FFFFFF` ونص `#1F1F39` وبطاقات `#F7F7FC` مأخوذة من `app_color.dart`.

## ما لم يُنقل
- لم يُنقل ملف `.env`، أو `google-services.json`، أو أي بيانات تسجيل دخول من المرفقات.
- لم يُستبدل خادم شتريد Supabase بخادم Laravel الموجود في الأرشيف.
- لم تُنسخ بيانات المنتجات أو الصور التجريبية وكأنها بضائع من متجر السيد إبراهيم العاني.
- لم يُرفع الأرشيف المرخّص إلى المستودع العام، ولم يُلغِ التصميم الجديد التزامات ترخيص StoreKing.

## التحقق
- المشروع المتأثر: `alani_site` (الموقع ولوحة الإدارة) و`lib/alani/alani_shop.dart` (تطبيق المتجر).
- فرع العمل: `feature/alani-herbal-store-app-20261118`.
- لا تغيير في `main` أو قاعدة بيانات الإنتاج.
- يُعدّ نجاح الفحص الآلي والنشر التجريبي مرحلة تحقق تقني، وليس إثباتاً نهائياً للتصميم بصرياً على جميع الأجهزة.
