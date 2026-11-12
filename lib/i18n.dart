/// Tiny bilingual dictionary: key -> [English, Arabic].
const Map<String, List<String>> _s = {
  'app': ['JO POS', 'جو بوس'],
  'tagline': ['Backup point-of-sale assistant', 'مساعد نقطة البيع الاحتياطي'],
  'login': ['Sign in', 'تسجيل الدخول'],
  'username': ['Username', 'اسم المستخدم'],
  'password': ['Password', 'كلمة المرور'],
  'remember': ['Keep me signed in', 'ابقني مسجلاً'],
  'default_hint': ['Default login: admin / 1234', 'الدخول الافتراضي: admin / 1234'],
  'bad_login': ['Wrong username or password', 'اسم المستخدم أو كلمة المرور غير صحيحة'],
  'free_note': ['Free for everyone — no license', 'مجاني للجميع — بدون ترخيص'],
  'nav_sell': ['Sell', 'البيع'],
  'nav_products': ['Products', 'المنتجات'],
  'nav_sales': ['Sales', 'المبيعات'],
  'nav_settings': ['Settings', 'الإعدادات'],
  'search_hint': ['Barcode or product name', 'الباركود أو اسم المنتج'],
  'scan': ['Scan', 'مسح'],
  'cart_empty': ['Cart is empty.\nScan a barcode to start.', 'السلة فارغة.\nامسح باركود للبدء.'],
  'total': ['Total', 'الإجمالي'],
  'checkout': ['Checkout', 'إتمام البيع'],
  'clear_cart': ['Clear', 'تفريغ'],
  'unknown_title': ['New product', 'منتج جديد'],
  'unknown_msg': ['Barcode not found. Add it now:', 'الباركود غير موجود. أضفه الآن:'],
  'barcode': ['Barcode / QR', 'الباركود / QR'],
  'name': ['Product name', 'اسم المنتج'],
  'price': ['Price', 'السعر'],
  'save': ['Save', 'حفظ'],
  'cancel': ['Cancel', 'إلغاء'],
  'delete': ['Delete', 'حذف'],
  'confirm': ['Confirm', 'تأكيد'],
  'add': ['Add', 'إضافة'],
  'required': ['Required', 'مطلوب'],
  'bad_number': ['Invalid number', 'رقم غير صحيح'],
  'dup_barcode': ['This barcode already exists', 'هذا الباركود موجود بالفعل'],
  'add_product': ['Add product', 'إضافة منتج'],
  'edit_product': ['Edit product', 'تعديل المنتج'],
  'no_products': ['No products yet', 'لا توجد منتجات بعد'],
  'alternatives': ['Alternatives', 'البدائل'],
  'add_alt': ['Add alternative', 'إضافة بديل'],
  'no_alts': ['No alternatives', 'لا توجد بدائل'],
  'replace_with': ['Replace with', 'استبدال بـ'],
  'pick_alts': ['Pick alternatives', 'اختر البدائل'],
  'payment': ['Payment', 'الدفع'],
  'cash': ['Cash', 'نقداً'],
  'card': ['Card', 'بطاقة'],
  'wallet': ['Wallet', 'محفظة'],
  'discount': ['Discount', 'الخصم'],
  'net': ['Net total', 'الصافي'],
  'sale_saved': ['Sale saved', 'تم حفظ البيع'],
  'today': ['Today', 'اليوم'],
  'sales_count': ['Invoices', 'الفواتير'],
  'unsynced': ['Not synced', 'غير مزامنة'],
  'synced': ['Synced', 'تمت المزامنة'],
  'no_sales': ['No sales yet', 'لا توجد مبيعات بعد'],
  'sync_wifi': ['Sync over Wi-Fi', 'مزامنة عبر الواي فاي'],
  'export_json': ['Export JSON', 'تصدير JSON'],
  'export_csv': ['Export CSV', 'تصدير CSV'],
  'mark_synced': ['Mark all as synced', 'تعليم الكل كمزامَن'],
  'sync_ok': ['Sent {0} sales ({1} already on desktop)', 'تم إرسال {0} فاتورة ({1} موجودة مسبقاً)'],
  'sync_fail': ['Sync failed: {0}', 'فشلت المزامنة: {0}'],
  'sync_none': ['Nothing to sync', 'لا يوجد ما يُزامَن'],
  'pull_products': ['Get products from desktop', 'جلب المنتجات من الديسك توب'],
  'import_file': ['Import products (Excel / database / CSV)', 'استيراد المنتجات (Excel / قاعدة بيانات / CSV)'],
  'import_hint': [
    'Pick an Excel .xlsx file, the JO PHARMA database file (jo_pharmacy.db), a JO POS backup, CSV or JSON. Columns are found by their names (barcode / name / price, or باركود / الاسم / السعر); without a header the order is barcode, name, price.',
    'اختر ملف Excel بصيغة xlsx، أو ملف قاعدة بيانات JO PHARMA (jo_pharmacy.db)، أو نسخة JO POS، أو CSV أو JSON. الأعمدة تُعرف بأسمائها (باركود / الاسم / السعر)، وبدون عناوين يكون الترتيب: باركود، اسم، سعر.'
  ],
  'import_ok': ['Imported {0} products', 'تم استيراد {0} منتج'],
  'import_empty': [
    'No products found in this file. It needs a barcode column and a name column (and a price column).',
    'لم أجد منتجات في هذا الملف. يلزم عمود للباركود وعمود للاسم (وعمود للسعر).'
  ],
  'import_xls': [
    'Old .xls files are not supported. Open it in Excel, choose Save As .xlsx, then import again.',
    'ملفات xls القديمة غير مدعومة. افتحه في Excel واختر حفظ باسم xlsx ثم استورده مرة أخرى.'
  ],
  'import_db_unknown': [
    'This database has no products table (medications / products).',
    'قاعدة البيانات هذه لا تحتوي جدول المنتجات (medications / products).'
  ],
  'import_fail': ['Import failed: {0}', 'فشل الاستيراد: {0}'],
  'import_btn': ['Import', 'استيراد'],
  'export_db': ['Backup database file', 'نسخة احتياطية لقاعدة البيانات'],
  'server': ['Desktop server', 'سيرفر الديسك توب'],
  'server_hint': ['e.g. 192.168.1.10:8765', 'مثال: 192.168.1.10:8765'],
  'pair_key': ['Pairing key', 'مفتاح الربط'],
  'device_name': ['Device name', 'اسم الجهاز'],
  'test_conn': ['Test connection', 'اختبار الاتصال'],
  'conn_ok': ['Connected to {0}', 'تم الاتصال بـ {0}'],
  'language': ['Language', 'اللغة'],
  'account': ['Account', 'الحساب'],
  'new_username': ['Username', 'اسم المستخدم'],
  'new_password': ['New password (leave empty to keep)', 'كلمة مرور جديدة (اتركها فارغة للإبقاء)'],
  'saved': ['Saved', 'تم الحفظ'],
  'logout': ['Sign out', 'تسجيل الخروج'],
  'about': ['About', 'حول'],
  'about_text': [
    'JO POS is a free backup point-of-sale for when the main system is unavailable. Works fully offline.',
    'جو بوس نقطة بيع احتياطية مجانية للاستخدام عند تعطل النظام الرئيسي. تعمل بالكامل بدون إنترنت.'
  ],
  'scan_hint': ['Point the camera at a barcode or QR', 'وجّه الكاميرا نحو الباركود أو QR'],
  'added': ['Added: {0}', 'تمت الإضافة: {0}'],
  'torch': ['Flash', 'الفلاش'],
  'cam_error': ['Camera unavailable.', 'الكاميرا غير متاحة.'],
  'cam_denied': [
    'Camera permission is denied. Open the phone Settings > Apps > JO POS > Permissions > Camera, allow it, come back and press Retry.',
    'صلاحية الكاميرا مرفوضة. افتح إعدادات الموبايل > التطبيقات > JO POS > الأذونات > الكاميرا واسمح بها، ثم ارجع واضغط إعادة المحاولة.'
  ],
  'cam_retry': ['Retry', 'إعادة المحاولة'],
  'cam_details': ['Details', 'التفاصيل'],
  'cam_starting': ['Starting camera...', 'جارٍ تشغيل الكاميرا...'],
  'confirm_delete': ['Delete this item?', 'حذف هذا العنصر؟'],
  'confirm_clear': ['Clear the cart?', 'تفريغ السلة؟'],
  'invoice': ['Invoice', 'فاتورة'],
  'currency': ['EGP', 'ج.م'],
  'close': ['Close', 'إغلاق'],
  'done': ['Done', 'تم'],
};

class L {
  static String code = 'ar';
  static bool get ar => code == 'ar';

  static String t(String key, [List<Object> args = const []]) {
    final v = _s[key];
    var out = v == null ? key : (ar ? v[1] : v[0]);
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', '${args[i]}');
    }
    return out;
  }
}

String tr(String key, [List<Object> args = const []]) => L.t(key, args);
