# Importing products · استيراد المنتجات

[← Back to README](../README.md) · [العربية ↓](#استيراد-المنتجات-بالعربية)

*Settings → Import products* (or the upload icon in the Products tab). The app recognises the file type by itself.

## Supported files
| File | Notes |
|---|---|
| **JO PHARMA database** (`jo_pharmacy.db`) | Best option: name, price, the main barcode **and every extra barcode** of each medicine |
| **JØ PHARMA MOBILE backup** (`jo_pos.db`) | Restores products and their extra barcodes |
| **Excel `.xlsx`** | First sheet that contains products. Old `.xls` is not supported — open it in Excel, *Save As → .xlsx* |
| **CSV / TSV** | Comma, semicolon or tab separated, UTF-8 |
| **JSON** | `{"products":[{"barcode":"…","name":"…","price":12.5,"codes":["…"]}]}` |

The chosen file is never modified: the app works on a copy.

## The mapping screen (tables: Excel / CSV / JSON)
Like the desktop program, the app first **detects the header row and the columns** (even if there are title lines above, or no header at all), then shows a screen where you can:

- change the header row, or say there is none;
- pick the **barcode**, **name**, **Arabic name** and **price** columns, and tick extra-barcode columns;
- choose which name to use (name column or Arabic first);
- choose what happens to products already in the app: **update all**, **prices only**, or **new only**;
- see a **live preview** (first rows, counts, problems) before anything is saved.

Prices are read in any format: `35`, `35.25`, `1,234.50`, `1.234,50`, `12,5`, `٣٫٥`, `EGP 12`. A price of 0 in the file never erases a price the product already has. Old Arabic CSV files (Windows-1256) and `;` / tab separated files are read correctly. JO PHARMA / JØ PHARMA MOBILE databases are imported directly, without this screen.

## Excel / CSV layout
The first row should be a header. Columns are found **by their names**, in Arabic or English, in any order:

| Meaning | Accepted header names (examples) |
|---|---|
| Barcode | `barcode`, `code`, `sku`, `ean`, `باركود`, `الباركود`, `كود`, `كود الصنف` |
| Name | `name`, `item name`, `product`, `اسم`, `الاسم`, `اسم الصنف`, `الصنف` |
| Price | `price`, `sell price`, `سعر`, `السعر`, `سعر الجمهور` |

- **More than one barcode per product:** add more barcode columns (`Barcode 2`, `باركود 2`, …) or write several codes in one cell separated by comma, semicolon or `|`. The first is the main barcode, the others are extra barcodes — scanning any of them finds the product.
- No header? Use the order **barcode, name, price**.
- No price column? Products are imported with price 0 and can be edited later.
- A ready example: [`sample_products.csv`](sample_products.csv).

> **Excel warning:** format the barcode column as **Text** *before* typing or pasting long barcodes. Otherwise Excel turns them into `1.23E+12` and permanently drops the last digits. The app detects this and warns you in the report.

## What is cleaned automatically
Arabic-Indic digits (`٦٢٢١…` → `6221…`), spaces, quotes, invisible characters, scanner prefixes (`]E0`), Excel artefacts (`6221031234567.0`), upper/lower case. The same cleaning is applied when you scan, so the same barcode always matches.

When scanning, a code that differs **only by leading zeros** (for example an EAN-13 and its UPC-A form) still finds the product, but only when exactly one product matches.

## The import report
After every import you see exactly what happened:

| Line | Meaning |
|---|---|
| Rows read | Records found in the file |
| New / Updated / Already up to date | What was added, changed (name or price), or already identical |
| Extra barcodes saved | Additional barcodes stored |
| Skipped: no barcode / no name / unreadable | Rows that could not be used (fix them in the file) |
| Rows merged | Same barcode on several rows: merged into one product (the **first** row wins; a missing price or extra barcodes are filled from the later rows) |
| No name in file / price 0 / prices that are not numbers | Imported anyway (the barcode is used as the name, price 0) and counted so you can fix them |
| Extra barcodes refused | An extra barcode that already belongs to **another** product is never taken over |
| Barcodes damaged by Excel | Re-type them as text and import again |
| Verification | After saving, every barcode, name and price is read back from the database and compared with the file. Any difference is reported |

Importing is **safe to repeat**: products are matched by barcode and updated, never duplicated, and the whole import is all-or-nothing.

---

<div dir="rtl">

## استيراد المنتجات بالعربية

*الإعدادات ← استيراد المنتجات* (أو أيقونة الرفع في تبويب المنتجات). التطبيق يتعرف على نوع الملف وحده.

### الملفات المدعومة
| الملف | ملاحظات |
|---|---|
| **قاعدة بيانات JO PHARMA** (`jo_pharmacy.db`) | الأفضل: الاسم والسعر والباركود الأساسي **وكل الباركودات الإضافية** لكل دواء |
| **نسخة JØ PHARMA MOBILE** (`jo_pos.db`) | تستعيد المنتجات وباركوداتها الإضافية |
| **Excel `.xlsx`** | أول ورقة فيها منتجات. ملفات `.xls` القديمة غير مدعومة: افتحها في Excel واختر *حفظ باسم ← xlsx* |
| **CSV / TSV** | مفصول بفاصلة أو فاصلة منقوطة أو Tab بترميز UTF-8 |
| **JSON** | `{"products":[{"barcode":"…","name":"…","price":12.5,"codes":["…"]}]}` |

الملف المختار لا يُعدَّل أبدًا: التطبيق يعمل على نسخة منه.

### شاشة مطابقة الأعمدة (Excel / CSV / JSON)
مثل برنامج الكمبيوتر، يكتشف التطبيق **صف العناوين والأعمدة** تلقائيًا (حتى لو فوقه أسطر عناوين أو لم يكن هناك عناوين)، ثم تظهر شاشة تستطيع فيها: تغيير صف العناوين، واختيار أعمدة **الباركود والاسم والاسم العربي والسعر**، وتحديد أعمدة الباركود الإضافية، واختيار ما يحدث للمنتجات الموجودة (**تحديث الكل** أو **الأسعار فقط** أو **الجديد فقط**)، ومعاينة النتيجة قبل الحفظ.

الأسعار تُقرأ بأي صيغة: `35` و`35.25` و`1,234.50` و`12,5` و`٣٫٥`. السعر 0 في الملف لا يمسح سعرًا موجودًا. ملفات CSV العربية القديمة (Windows-1256) والمفصولة بـ `;` أو Tab تُقرأ صحيحة. قواعد بيانات JO PHARMA وJØ PHARMA MOBILE تُستورد مباشرة بدون هذه الشاشة.

### شكل ملف Excel / CSV
يفضَّل أن يكون الصف الأول عناوين. تُعرف الأعمدة **بأسمائها** بالعربية أو الإنجليزية وبأي ترتيب:

| المعنى | أسماء العناوين المقبولة (أمثلة) |
|---|---|
| الباركود | `barcode` `code` `sku` `ean` `باركود` `الباركود` `كود` `كود الصنف` |
| الاسم | `name` `item name` `product` `اسم` `الاسم` `اسم الصنف` `الصنف` |
| السعر | `price` `sell price` `سعر` `السعر` `سعر الجمهور` |

- **أكثر من باركود للمنتج:** أضف أعمدة باركود أخرى (`Barcode 2` و`باركود 2` …) أو اكتب عدة أكواد في خانة واحدة تفصلها فاصلة أو فاصلة منقوطة أو `|`. الأول هو الأساسي والباقي إضافي، ومسح أي منها يجد المنتج.
- بدون عناوين؟ الترتيب: **باركود، اسم، سعر**.
- بدون عمود سعر؟ يُستورد المنتج بسعر 0 ويمكن تعديله لاحقًا.
- مثال جاهز: [`sample_products.csv`](sample_products.csv).

> **تحذير Excel:** اجعل عمود الباركود **نصًّا (Text)** *قبل* كتابة أو لصق الباركودات الطويلة. وإلا حوّلها Excel إلى `1.23E+12` وأضاع آخر أرقامها نهائيًا. التطبيق يكتشف ذلك وينبهك في التقرير.

### ما يُنظَّف تلقائيًا
الأرقام العربية، والمسافات، وعلامات الاقتباس، والرموز المخفية، وبادئات الماسح (`]E0`)، وعيوب Excel (`6221031234567.0`)، وحالة الأحرف. ويُطبَّق التنظيف نفسه عند المسح، فيطابق الباركود نفسه دائمًا.

عند المسح، كود يختلف **بالأصفار في أوله فقط** (مثل EAN-13 وصيغة UPC-A) يجد المنتج أيضًا، بشرط أن يطابق منتجًا واحدًا فقط.

### تقرير الاستيراد
بعد كل استيراد تري بالضبط ما حدث: الصفوف المقروءة، والجديد والمحدَّث والمطابق، والباركودات الإضافية المحفوظة، والصفوف المتخطّاة وسببها (صحّحها في الملف)، والصفوف المدمجة (نفس الباركود مكرر: يُعتمد **أول** صف ويُكمَّل الناقص من الباقي)، والمنتجات التي بدون اسم (يُستخدم الباركود اسمًا) أو بسعر 0، والباركودات الإضافية المرفوضة (التي تخص منتجًا **آخر** لا تُنتزع منه أبدًا)، والباركودات التي أفسدها Excel (اكتبها كنص وأعد الاستيراد). وبعد الحفظ تُقرأ كل قيمة من قاعدة البيانات وتُقارن بالملف، وأي فرق يُذكر.

الاستيراد **آمن للتكرار**: المنتجات تُطابَق بالباركود وتُحدَّث ولا تتكرر، والاستيراد كله يتم أو يُلغى بالكامل.

</div>
