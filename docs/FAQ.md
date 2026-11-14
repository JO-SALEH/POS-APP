# FAQ · الأسئلة الشائعة

[← Back to README](../README.md) · [العربية ↓](#الأسئلة-الشائعة-بالعربية)

**Does it need the internet?** No. Selling, products and history work fully offline. The optional PC link only needs the same local Wi-Fi.

**Is it on Google Play? Is it safe?** It is distributed as an APK from this repository's *Releases* page only. Check the `SHA-256` in the release notes against the file you downloaded (Windows: `certutil -hashfile JO_POS.apk SHA256`). The app asks only for Camera and Network, has no ads, accounts or tracking.

**iPhone?** Not available — Android only.

**Do I need JO PHARMA on the PC?** No for selling on the phone. Yes for the automatic hand-over of invoices and the product/price updates.

**Can several phones connect to the same PC?** Yes. Each phone has its own unique invoice ids and pairs with the same QR.

**Does the phone track stock?** No. Stock lives on the PC and is deducted when the invoice arrives.

**Which price is used?** In the shop, the phone's product price. On the PC, the PC price is always the authority, and the phone refreshes its prices from the PC while connected.

**I changed phone / reinstalled — what now?** Restore a backup (*Import products* with your `jo_pos.db`) or import from the PC database and pair again. Invoices that were not sent before uninstalling are lost, so send them first.

**Forgot the password?** There is no recovery (nothing is stored online). Clearing the app data resets it, but **erases everything** — restore from a backup afterwards.

**The camera shows a black screen or says permission denied.** Settings → Apps → JØ PHARMA MOBILE → Permissions → Camera → Allow, then press *Retry* in the app.

**Which barcode types are scanned?** The common 1D (EAN-13/8, UPC, Code 128/39…) and QR/Data Matrix codes.

---

<div dir="rtl">

## الأسئلة الشائعة بالعربية

**هل يحتاج إنترنت؟** لا. البيع والمنتجات والسجل تعمل بالكامل بدون إنترنت. الربط الاختياري بالكمبيوتر يحتاج فقط نفس الواي فاي المحلي.

**هل هو على Google Play؟ وهل هو آمن؟** يُوزَّع كملف APK من صفحة *Releases* في هذا المستودع فقط. قارن بصمة `SHA-256` في ملاحظات الإصدار بالملف الذي نزّلته (ويندوز: `certutil -hashfile JO_POS.apk SHA256`). يطلب فقط الكاميرا والشبكة، وليس فيه إعلانات ولا حسابات ولا تتبّع.

**آيفون؟** غير متاح، أندرويد فقط.

**هل أحتاج JO PHARMA على الكمبيوتر؟** لا للبيع من الموبايل. نعم لتسليم الفواتير تلقائيًا وتحديث المنتجات والأسعار.

**هل يربط أكثر من موبايل بنفس الكمبيوتر؟** نعم. لكل موبايل أرقام فواتير فريدة، ويرتبط بنفس الـ QR.

**هل الموبايل يتابع المخزون؟** لا. المخزون على الكمبيوتر وينخصم عند وصول الفاتورة.

**أي سعر يُستخدم؟** في المحل سعر المنتج على الموبايل. وعلى الكمبيوتر سعر الكمبيوتر هو المعتمد دائمًا، والموبايل يحدّث أسعاره منه أثناء الاتصال.

**غيّرت الموبايل أو أعدت التثبيت، ماذا أفعل؟** استعد نسخة احتياطية (*استيراد المنتجات* بملف `jo_pos.db`) أو استورد من قاعدة الكمبيوتر وأعد الربط. الفواتير التي لم تُرسل قبل الحذف تضيع، فأرسلها أولًا.

**نسيت كلمة المرور؟** لا توجد استعادة (لا شيء على الإنترنت). مسح بيانات التطبيق يعيد ضبطها لكنه **يمسح كل شيء**، فاستعد نسخة احتياطية بعدها.

**الكاميرا سوداء أو تقول الصلاحية مرفوضة.** الإعدادات ← التطبيقات ← JØ PHARMA MOBILE ← الأذونات ← الكاميرا ← سماح، ثم اضغط *إعادة المحاولة* في التطبيق.

**ما أنواع الباركود المدعومة؟** الشائعة (EAN-13/8 وUPC وCode 128/39 …) ورموز QR وData Matrix.

</div>
