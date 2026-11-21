# Connecting JØ PHARMA MOBILE to the PC · الربط بالكمبيوتر

[← Back to README](../README.md) · [العربية ↓](#الربط-بالكمبيوتر-بالعربية)

The link is optional. Without it JØ PHARMA MOBILE works on its own and you can still [export the sales as a file](#no-wi-fi-use-a-file).

## What you need
- A JO PHARMA build with the **Mobile receiver** window (sidebar → *Mobile receiver*).
- The phone and the PC on the **same Wi-Fi / router**. No internet needed.

## Pair once (1 minute)
1. **On the PC:** JO PHARMA → *Mobile receiver* → **Generate QR**. If the PC has several network adapters, choose the one that is on your Wi-Fi. Press **Allow in Windows Firewall** once.
2. **On the phone:** JØ PHARMA MOBILE → *Settings → Connection to the PC → Scan the QR from the PC*.
3. You will see *Connected to \<pharmacy name\>*. Done — you never have to repeat this unless you generate a new QR.

No camera or QR problem? Use **Enter address and code by hand** (the address and code are shown on the PC window).

## What happens next (automatically)
| When | What |
|---|---|
| Right after each sale | The invoice is sent to the PC |
| Every 30 seconds, and when you reopen the app | Any unsent invoice is retried; the connection status refreshes |
| When the product list changes on the PC | Names, prices and all barcodes are updated on the phone (checked every 5 minutes) |

On the PC every phone invoice becomes a normal **sales invoice**, stock is deducted, and the cashier shows as *Mobile – \<name\>*. Invoices from the phone do not issue an electronic tax receipt. The **PC price is the authority**: the phone sends only barcode and quantity.

Safe to repeat: each invoice has a unique id, so a re-send after a dropped connection is recognised and never booked twice.

## Purchase orders from the PC
In the PC program open *Purchase orders*, optionally select some rows (no selection = the whole order) and press **Send to mobile**. It works only while this app is connected (the PC checks that the app asked within the last ~75 seconds); otherwise the PC tells you to open the app and pair. Within 30 seconds the app downloads the PDF and shows a notification; tap it to open *Settings → Purchase orders from the PC*. Orders stay on offer on the PC for 7 days.

## When a barcode is unknown to the PC
The invoice is still received. The unknown lines wait in the PC's **Mobile receiver → Pending** list; link each to the right product there. The phone shows a yellow note on that invoice until then.

## Troubleshooting
| Message / symptom | Likely cause and fix |
|---|---|
| *Cannot reach the PC* | The receiver is not running on the PC (press **Generate QR**) · different Wi-Fi (phone on mobile data or a guest network) · **Windows Firewall** (press **Allow in Windows Firewall** on the PC) · router "AP/client isolation" is on |
| *Wrong code* | A new QR was generated on the PC. Scan it again |
| The PC changed address | The phone searches the Wi-Fi for it by itself; you can also press **Find the PC on the Wi-Fi** |
| Receiver stopped by itself | It switches off after a long idle time to save resources. Press **Generate QR** again |
| Invoice stays "not sent" with a note | Read the note: it explains what the PC refused (for example an item the PC cannot sell) |

**Quick connection test from the phone's browser:** open `http://<PC address>:8765/ping`. Seeing `{"ok":false,"error":"bad_token"}` means the network path works (the page is only missing the secret code) — then the problem is the code, so scan the QR again. If the page does not load at all, it is the network or the firewall.

## No Wi-Fi? Use a file
*Sales → Export JSON*, send the file to the PC (USB, WhatsApp, Drive…), then on the PC *Mobile receiver → Import file*. Duplicates are ignored exactly like over the network.

## Security notes
Traffic stays inside your Wi-Fi and is protected by the secret pairing code from the QR. The PC accepts only local-network addresses. Generating a new QR on the PC disconnects every previously paired phone. Don't show the QR to anyone, and use a trusted Wi-Fi.

---

<div dir="rtl">

## الربط بالكمبيوتر بالعربية

الربط اختياري. بدونه يعمل JØ PHARMA MOBILE وحده ويمكنك [تصدير المبيعات كملف](#بدون-واي-فاي-استخدم-ملفًا).

### المطلوب
- نسخة JO PHARMA فيها نافذة **استقبال من الموبايل** (من القائمة الجانبية).
- الموبايل والكمبيوتر على **نفس الواي فاي / الراوتر**. لا يلزم إنترنت.

### الربط مرة واحدة (دقيقة)
1. **على الكمبيوتر:** JO PHARMA ← *استقبال من الموبايل* ← **توليد QR**. لو عندك أكثر من كارت شبكة اختر الذي على الواي فاي. اضغط **السماح في جدار حماية ويندوز** مرة واحدة.
2. **على الموبايل:** JØ PHARMA MOBILE ← *الإعدادات ← الاتصال بالكمبيوتر ← مسح QR من الكمبيوتر*.
3. ستظهر رسالة *تم الاتصال بـ \<اسم الصيدلية\>*. انتهى، ولا تكرره إلا إذا ولّدت QR جديدًا.

مشكلة في الكاميرا أو الـ QR؟ استخدم **إدخال العنوان والرمز يدويًا** (يظهران في نافذة الكمبيوتر).

### ماذا يحدث بعد ذلك (تلقائيًا)
| متى | ماذا |
|---|---|
| بعد كل بيع مباشرة | تُرسل الفاتورة للكمبيوتر |
| كل 30 ثانية وعند فتح التطبيق | تُعاد محاولة أي فاتورة لم تُرسل وتتحدث حالة الاتصال |
| عند تغيّر المنتجات على الكمبيوتر | تتحدث الأسماء والأسعار وكل الباركودات على الموبايل (فحص كل 5 دقائق) |

على الكمبيوتر تصبح كل فاتورة من الموبايل **فاتورة بيع** عادية وينخصم المخزون ويظهر الكاشير باسم *Mobile – \<الاسم\>*. فواتير الموبايل لا تُصدر إيصالًا إلكترونيًا ضريبيًا. **سعر الكمبيوتر هو المعتمد**: الموبايل يرسل الباركود والكمية فقط.

آمن للتكرار: لكل فاتورة رقم فريد، فإعادة الإرسال بعد انقطاع تُعرَف ولا تُسجَّل مرتين.

### باركود غير معروف عند الكمبيوتر
تصل الفاتورة رغم ذلك، وتنتظر الأسطر المجهولة في قائمة **استقبال من الموبايل ← المعلّقة** على الكمبيوتر لتربط كل سطر بالمنتج الصحيح. يعرض الموبايل ملاحظة صفراء على الفاتورة إلى أن يحدث ذلك.

### حل المشاكل
| الرسالة / العَرَض | السبب والحل |
|---|---|
| *تعذر الوصول للكمبيوتر* | الاستقبال غير شغال (اضغط **توليد QR**) · واي فاي مختلف (الموبايل على بيانات أو شبكة ضيوف) · **جدار حماية ويندوز** (اضغط زر السماح) · عزل الأجهزة في الراوتر مفعّل |
| *الرمز غير صحيح* | وُلّد QR جديد على الكمبيوتر. امسحه من جديد |
| تغيّر عنوان الكمبيوتر | الموبايل يبحث عنه بنفسه، أو اضغط **البحث عن الكمبيوتر على الواي فاي** |
| توقف الاستقبال وحده | يتوقف بعد فترة خمول طويلة لتوفير الموارد. اضغط **توليد QR** من جديد |
| الفاتورة تبقى «غير مرسلة» ومعها ملاحظة | اقرأ الملاحظة، فهي تشرح ما رفضه الكمبيوتر |

**اختبار سريع من متصفح الموبايل:** افتح `http://<عنوان الكمبيوتر>:8765/ping`. إذا ظهر `{"ok":false,"error":"bad_token"}` فمسار الشبكة سليم (ينقص الصفحة الرمز السري فقط) والمشكلة في الرمز، فامسح الـ QR من جديد. وإذا لم تفتح الصفحة أبدًا فالمشكلة في الشبكة أو الجدار الناري.

### بدون واي فاي: استخدم ملفًا
*المبيعات ← تصدير JSON* وأرسل الملف للكمبيوتر (USB أو واتساب أو Drive)، ثم على الكمبيوتر *استقبال من الموبايل ← استيراد ملف*. المكرر يُتجاهل كما عبر الشبكة.

### ملاحظات أمنية
الحركة تبقى داخل الواي فاي وتحميها رمز الربط السري في الـ QR. الكمبيوتر يقبل عناوين الشبكة المحلية فقط. توليد QR جديد على الكمبيوتر يفصل كل الموبايلات المرتبطة سابقًا. لا تُري الـ QR لأحد، واستخدم واي فاي موثوقًا.

</div>
