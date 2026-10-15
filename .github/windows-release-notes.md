نسخة تجريبية من اقرأ وارتق لنظام Windows (64 بت — x64).

يعمل على أجهزة Intel و AMD، وعلى أجهزة Windows بمعالج Arm عبر المحاكاة.

لا توجد نسخة 32 بت: إطار العمل الذي بُني به التطبيق لا يُنتج ملفات 32 بت أصلًا، ولا توجد نسخة arm64 أصيلة بعد لأن أدوات البناء لا تُصدرها لنظام Windows حتى الآن.

فُكّ ضغط الملف كاملًا في أي مكان — لا تشغّله من داخل الملف المضغوط — ثم شغّل mirqat.exe. لا يحتاج إلى تثبيت. أبقِ الملفات ومجلد data بجانبه.
قد يظهر تحذير من Windows في أول تشغيل لأن الملف غير موقّع: اضغط «مزيد من المعلومات» ثم «التشغيل على أي حال».

داخل الملف المضغوط «اقرأ وارتق - طريقة التشغيل.txt»: الخطوات كاملة بالعربية.
وتحمل هذه النسخة معها مكتبات Visual C++ التي يحتاجها التطبيق، فلا تظهر رسالة MSVCP140.dll على جهاز لم تُثبَّت عليه من قبل.

---

A beta of Iqra Wartaq for Windows (64-bit, x64).

Runs on Intel and AMD machines, and on Windows on Arm machines under emulation.

There is no 32-bit build: the framework this app is built with produces no 32-bit Windows binaries at all. There is no native arm64 build either — the build tooling does not yet publish a Windows arm64 toolchain.

Unzip the whole folder anywhere — do not run it from inside the zip — and run mirqat.exe. Nothing is installed. Keep the DLLs and the data folder beside it.
The file is not code-signed, so Windows SmartScreen may warn on first run: choose "More info", then "Run anyway".

"Iqra Wartaq - How to run.txt" inside the zip has the whole thing in English.
This build also carries the Visual C++ runtime it is linked against, so "MSVCP140.dll was not found" no longer greets a machine that has never run a C++ program.

{{SHA256}}
