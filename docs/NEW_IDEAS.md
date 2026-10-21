# New Ideas — أفكار جديدة

Ideas for features that serve the app's purpose — memorizing the Quran by listening,
repetition, and review — gathered from the traditional hifz methods (talqeen,
sabaq/sabqi/manzil), from the learning science on retrieval and spacing, and from what
comparable apps do. Every idea below was checked against the project contract
(`CLAUDE.md`): most need **no new package and no network beyond what A.2 allows**; the
few that do are marked **[blocker]** and would have to be raised as numbered blockers
per rule A.2.5. Nothing here touches ayah text bytes or recitation audio (rules 1 and 6).

The document is in two halves: English first, then the same ideas in Arabic.

> **Where each idea stands** is said under each section (*Status*), with
> the commits in `docs/IMPLEMENTATION_PLAN.md`. Each status names what was
> built, what was built differently from the idea, and any problem left.
>
> | | |
> |---|---|
> | **Done** | §1 recall, §2 review ladder and Today, §3 stumble marks and the surah-list heatmap, §4 mutashabihat and browsing, §5 sleep timer, "three more", the listen loop and the bookends, §6 hifz plan and quiet stats, §7 tasmee', §8 backup, §9 presets, resume, about-the-surah |
> | **Partly done** | §4 menu entry does not name the twins · §9 presets are fixed, not saved by the reader; the surah line has no juz span |
> | **Not built yet** | §4 mutashabihat drill |
> | **Problem in a built feature** | §8 on Android the backup sits in the app's own folder, hard to reach since Android 11 and deleted with the app |
> | **Not taken** | §9 multiple reading marks (CLAUDE.md A.5 fixes one) · streaks (BRAND_GUIDE §6) |
> | **Blocked on a package** | daily reminder · record-and-compare · system share sheet |
>
> **حال كل فكرة** مذكور تحت قسمها (*الحال*)، والإيداعات في
> `docs/IMPLEMENTATION_PLAN.md`. يذكر كل «حال» ما بُني، وما بُني على غير ما في
> الفكرة، وما بقي فيه من مشكلة.
>
> | | |
> |---|---|
> | **تمّ** | §١ الاسترجاع، §٢ سلّم المراجعة وبطاقة اليوم، §٣ علامات التعثر وخريطة الضعف على الفهرس، §٤ المتشابهات وتصفّحها، §٥ مؤقّت النوم و«ثلاثًا أيضًا» وحلقة السماع وطرفا الليل والنهار، §٦ خطة الحفظ والإحصاء الهادئ، §٧ التسميع، §٨ النسخ الاحتياطي، §٩ الإعدادات المسماة والاستئناف وسطر السورة |
> | **تمّ بعضه** | §٤ خيار القائمة لا يسمّي الشبيهات · §٩ الإعدادات ثابتة لا يحفظها القارئ؛ وسطر السورة بلا مدى الأجزاء |
> | **لم يُبنَ بعد** | §٤ تمرين المتشابهات |
> | **مشكلة في ميزة مبنية** | §٨ النسخة على أندرويد في مجلد التطبيق نفسه، يصعب بلوغه منذ أندرويد ١١، ويُحذف بحذف التطبيق |
> | **لن يُؤخذ** | §٩ علامات قراءة متعددة (العقد A.5 يحدّها بواحدة) · الأيام المتتالية (دليل الهوية §٦) |
> | **ينتظر حزمة** | التنبيه اليومي · سجّل وقارن · نافذة المشاركة النظامية |

---

## English

### 1. Recall mode — the session tests, not just teaches

> **Status: done.** Recall rounds (`786003d`): recite into the gap, the ayah
> veiled on the page, the answer played once. The veil and progressive
> fading are the *memorization view* (`3c05ad8`): off / first words /
> ayah markers only, a tap on a covered word to peek. "What comes next?"
> (`3a3f249`). Self-grading (`8c5f8ee`), with the scheduler.
> *Built differently:* the grade is one for the session's whole range,
> not one per ayah — one tap, as the idea asked, and the ladder keeps
> ranges, not ayahs.

The single highest-value addition. Learning science is clear that *retrieval* — making
yourself produce the ayah — strengthens memory far more than another passive listen
(the "testing effect"). Today the session only plays; these steps make it ask.

- **Recite-into-the-gap rounds.** After the normal "listen and repeat" rounds of an
  ayah, the plan appends *recall rounds*: the queue plays a silence of the ayah's own
  measured length (loop the bundled `silence_400ms.wav` spacer N times —
  `AyahDurationService` already knows the duration), during which the reader recites
  from memory, then plays the ayah once as the answer. Pure `RepetitionPlanBuilder` +
  `PlaybackQueue` work; no new package, works offline for anything downloaded.
- **Veiled text on the page.** During recall rounds (or on demand), the mushaf page
  draws a soft veil *over* each word of the ayah being tested — tap a word to peek,
  tap again to re-veil. The `Word` objects and their bytes are untouched; this is
  presentation the reader switches on, like the text-size setting, so rule 1 holds
  (and rule 7 is honored because nothing is truncated — only covered, by the reader's
  own choice, as a hand covers the page in a traditional tasmee').
- **Progressive fading.** Three veil levels the reader steps through as confidence
  grows: show all words → show only each ayah's first word (the cue) → show only the
  ayah markers. The classic "cover the page a little more each pass" technique.
- **"What comes next?" chaining drill.** The queue plays ayah N, then a gap for the
  reader to recite ayah N+1, then plays N+1 as the answer, and walks the range. This
  tests the *links* between ayahs — exactly where recall usually breaks — and is pure
  queue logic over existing sources.
- **Self-grading at the end of a session.** One screen, three buttons per drilled
  ayah or for the range as a whole: *solid / shaky / forgot*. Stored locally
  (Hive/progress DB) and fed into the review scheduler below. No typing, one tap.

### 2. A review scheduler — sabaq, sabqi, manzil as a feature

> **Status: done** (`8c5f8ee`, presets `fda6c1e`). The 1–3–7–14–30–90-day
> ladder, solid/shaky/forgot after a session, the Today card, and the
> new/recent/old presets. *Built differently:* the tier comes from a
> range's age — under 7 days sabaq, under 30 sabqi, then manzil — and
> manzil reviews fall due by the ladder, not by a fixed juz-a-day rotation.
> A review left from an earlier day is "due now", never "overdue"
> (BRAND_GUIDE §6).

The traditional madrasa structure maps beautifully onto spaced repetition, and the app
already has progress tracking and session plans to build on:

- **Three tiers, kept automatically.** What was memorized this week is *sabaq* (drill
  daily, full repetitions); the last month or so is *sabqi* (every few days, fewer
  repetitions); everything older is *manzil* (a rotating cycle — e.g. one juz-portion a
  day — at one or two listens with recall gaps). The app knows the dates; the reader
  never files anything.
- **Expanding intervals with self-grading.** A memorized range starts on a
  1–3–7–14–30–90-day review ladder; *solid* advances it a step, *shaky* repeats the
  step, *forgot* drops it back to daily. This is standard spaced-repetition practice
  and what the strongest competing apps do. All local, all in the progress store.
- **"Today" card on the home screen.** One card: today's new portion, today's recent
  review, today's old review — each a single tap that opens the reading view with the
  session pre-configured. The reader should never have to *plan*; the app carries the
  notebook the madrasa teacher keeps.
- **Review sessions are lighter by design.** A revision session defaults to fewer
  repetitions and more recall gaps than a new-memorization session — presets named
  *new / recent / old* rather than numbers.

### 3. Trouble spots — remember where it breaks

> **Status: stumble marks done** (`1dd3af2`): *I stumble here* in the ayah
> menu, a dotted underline on the page, two extra repeats inside any
> session, and the Weak spots screen that launches a session over them.
> **Heatmap done** (`eea3f0f`): each surah row and grid tile shows how much
> of it is memorized and, when there are any, how many of its ayahs are
> marked — «Weak spots: 3», in the muted tone of the reading-only marker,
> never a warning colour (BRAND_GUIDE §6). It follows a mark made or
> cleared anywhere while the list is on screen.

- **Mark a stumble.** During a session or plain reading, the ayah's existing menu gets
  *I stumble here*. Stumble-marked ayahs: get extra repetitions automatically when
  they fall inside a session, show a subtle tint in reading (like the reading mark,
  by the reader's leave), and gather on one "weak spots" screen that can launch a
  session over just them. Entirely local.
- **Error heatmap over the surah list.** Each surah row can carry a quiet indicator of
  how much of it is memorized and how much is marked weak — the "which surahs are
  strong" view at a glance, computed from local progress only.

### 4. Mutashabihat — the confusable verses

> **Status:** built in October 2026; its data was imported on 21 October
> 2026. QUL's *Mutashabihat ul Quran* (resource 73) is served only to a
> signed-in account; its JSON zip (named `.json.bz2` on download, but a zip)
> is rebuilt with `python3 tool/build_mutashabihat.py path/to/the.zip
> --correct 4970:48:10:23-27=23-25`. The tool checks every reference
> against `quran.db` and refuses a source that disagrees; the one reference
> that does — phrase 4970 in 48:10, recorded as words 23-27 of an ayah of
> 25 — is corrected by name to 23-25, the ayah's last three words. 807 of 814 phrases are kept; the 7 found in more than 40
> ayahs are too common to be what confuses a reader.
> Since then the whole list can be browsed from the top of Settings
> (`3c101ed`): a card per phrase, narrowed by surah, each opening every
> ayah it is in. **Partly done:** the ayah menu says *Similar ayahs* but
> does not name them (*this resembles 2:48 / 2:123*). **Not built yet:**
> the drill.

The most common failure of established memorization is sliding from one ayah into its
near-twin elsewhere. Several dedicated apps exist for this alone.

- **A pairs data file, not code.** Ship (or serve from the CDN beside the manifest) a
  JSON of similar-verse pairs/groups referencing ayahs by surah:ayah — pure data, no
  surah-specific code, exactly like `reciters.json`. The classical lists (e.g. ~270
  well-known pairs) are public scholarship; the file is reviewed once, not generated.
- **Side-by-side comparison view.** Both ayahs on one screen, rendered byte-for-byte
  by `AyahText` as always; the reader sees where they diverge by reading, and can play
  the two recitations back-to-back through the normal resolver.
- **A "twins" badge in reading.** An ayah that has a known twin shows a small marker in
  its menu — *this resembles 2:48 / 2:123* — so the reader learns the trap exists
  before falling into it.
- **Later: a drill.** Play one of the pair, veil the text, reader says which it is and
  continues it; the answer plays. Builds entirely on recall mode above.

### 5. Listening that serves memorization

> **Status:** sleep timer and "this ayah again ×3" **done** (`06c89fc`) —
> the extra repeats are a button on the session bar, not a long press.
> **Listen-only loop done:** *Listen from here* in the ayah menu plays to
> the end of the surah, once; and the session sheet's **Listen** preset
> plays the chosen range straight through, nothing asked back, as many
> times as the repeat stepper says — the range M times. **Bedtime and
> morning bookends done:** a switch in Settings (off until chosen). From
> 19:00 into the small hours the Today card offers the portion first
> memorized that day, to hear once more; from 04:00 to noon, the one
> memorized the day before, to recite back — in place of its ladder review,
> not beside it. Taken up, a suggestion is not made again; outside the two
> windows nothing is said, so no time is ever "missed". *Built
> differently:* without notifications (a package blocker) the app cannot
> call the reader at bedtime; the suggestion waits on the home screen.

- **Listen-only loop.** "Play this range on repeat M times" with no drill structure —
  for the commute, for cooking, for the pre-memorization familiarization pass that
  talqeen traditionally begins with. It is the session engine with repetitions=1 and
  joining off; mostly UI.
- **Sleep timer.** Stop after N minutes or at the end of the current pass. Pairs with
  the sleep-consolidation evidence: review last, sleep on it. Trivial with the
  existing player service.
- **Bedtime + morning bookends.** A gentle option in the plan: the scheduler suggests
  the same portion last thing at night and first thing the next day. Mazza et al.
  (2016, *Psychological Science*) found sleep between two practice sessions roughly
  halved the practice needed and improved six-month retention.
- **Per-ayah repetition overrides.** Inside a running session: *this ayah again ×3* —
  a long-press on the bar, feeding the queue without rebuilding the plan.

### 6. Plans and habit

> **Status:** hifz plan **done** (`bacfb05`): a passage in N days, split by
> recited length; a day's portion counts once it is graded solid or shaky.
> Quiet stats **done** (`3ea5bc8`): totals only. *Problem found and
> fixed:* the first draft counted a streak and said how far the plan was
> behind; both were removed under BRAND_GUIDE §6. Daily reminder: still
> **[blocker]**.

- **A khatmah-of-hifz plan.** Pick a goal — e.g. Juz ʿAmma in 90 days — and the app
  divides it into daily portions by ayah weight (the admin tool's `recitationWeight`
  arithmetic already measures how long text takes to recite; reuse the idea, not the
  code). The "Today" card then has real content from day one.
- **Quiet stats.** Days practiced, ayahs held, minutes listened — totals, computed
  locally, shown humbly. **No streaks**, and nothing that marks a day missed:
  `docs/BRAND_GUIDE.md` §6 rules out loss-aversion pointed at someone's relationship
  with the Quran, and `test/core/brand_voice_test.dart` enforces it.
- **Daily reminder notification. [blocker]** Needs `flutter_local_notifications` (or
  similar) — not on the approved list. Worth a numbered blocker: a fixed local
  reminder at a user-chosen time is the single cheapest habit feature, and it needs
  no network and no account.

### 7. Tasmee' — reciting to someone

> **Status: hand-the-phone done** (`16cee2c`). *Built differently:* a slip
> is noted at its ayah (as a stumble mark), not at the word, and the
> session does not replay from there — the listener follows a voice, so a
> slip is said back at once with an undo, and ending leads to Weak spots.
> Record-and-compare: still **[blocker]**.

- **Hand-the-phone mode.** The listener holds the phone and sees the page; the reciter
  sees nothing. The listener taps a word where a mistake happened — it is recorded as
  a stumble mark (§3) and the session can replay from there. No second device, no
  account, no network: the oldest hifz practice, with the phone as the teacher's
  mushaf.
- **Record-and-compare. [blocker]** Record the reader's own recitation of the range
  and play it interleaved with the reciter (A–B). Needs a recording package
  (e.g. `record`) — not on the approved list, and microphone permission is a real
  product decision. High value, but strictly behind a blocker.

### 8. Export, portability, peace of mind

> **Status: done, with a problem** (`c477ea0`). Export writes one JSON
> file; import merges it and never deletes. On iOS the file is in the
> app's folder in the Files app. **Problem:** on Android it is written to
> the app's own external folder (`Android/data/<app>/files`), which the
> Files app cannot open since Android 11, and which is deleted when the
> app is uninstalled — so moving to a new phone needs a computer. The app
> already has a native share channel of its own (the shared ayah image
> uses it), so the file can be handed to the system share sheet with no
> new package; that is the fix.

- **Progress export/import as a file.** One JSON of progress, marks, and the review
  ladder, written to a user-chosen place and read back on a new phone. Keeps the
  no-account promise while removing the fear of losing years of review history.
  Writing to the app's documents directory and letting the user pick it up needs no
  new package; invoking the system share sheet would need one **[blocker:
  `share_plus`]** — the file-based version first.

### 9. Smaller touches

> **Status:** resume **done** (`292d69e`). Presets **partly done**
> (`fda6c1e`): four fixed ones — new, recent, old, deep — not ones the
> reader saves from the form. About-the-surah **partly done** (`35e0296`):
> Makki/Madani and the ayah count, in every ayah's menu rather than the
> surah header; the juz span is not shown. Multiple reading marks: **not
> taken** — CLAUDE.md A.5 fixes one reading mark, so it is a product
> decision.

- **Multiple reading marks** in distinct tints (the current mark is one), each with the
  same ribbon and menu behavior — hifz naturally keeps several places at once (sabaq,
  sabqi, manzil are three bookmarks by nature).
- **Session presets with names** — *new memorization / quick review / deep drill* —
  saved from the session form, so the three-tier routine is three taps.
- **Resume an interrupted session** exactly where it stopped (plan position persisted
  on every step), so a phone call does not cost the evening's sabaq.
- **An "about this surah" line** from data already in `quran.db` (revelation,
  ayah count, juz span) on the surah's first page header menu — orientation helps
  memory anchoring, and it is pure existing data.

### Priority, if asked

1. Recall mode (§1) — turns the player into a memorizer; everything else feeds it.
2. Review scheduler + Today card (§2) — turns sessions into a method.
3. Stumble marks (§3) — cheap, and the scheduler gets better the moment it exists.
4. Listen-only loop + sleep timer (§5) — very cheap, widens daily use.
5. Mutashabihat data + comparison view (§4) — distinctive, data-driven, no code risk.

---

## العربية

أفكارٌ لميزات تخدم غاية التطبيق — حفظ القرآن بالسماع والتكرار والمراجعة — مستخلصة من
طرق التحفيظ الموروثة (التلقين، والسبق والسبقي والمنزل)، ومن علم التعلّم في الاسترجاع
والمباعدة، ومما تقدمه التطبيقات المشابهة. كل فكرة أدناه رُوجعت على عهد المشروع
(`CLAUDE.md`): أكثرها لا يحتاج حزمةً جديدة ولا شبكةً فوق ما يسمح به البند A.2؛ وما
احتاج فهو موسوم **[عائق]** ويُرفع عائقًا مرقّمًا وفق القاعدة A.2.5. ولا شيء هنا يمسّ
نصّ الآيات بايتًا واحدًا ولا الصوت (القاعدتان 1 و6).

### ١. وضع الاسترجاع — جلسة تَختبر لا تُسمِع فحسب

> **الحال: تمّ.** جولات الاسترجاع (`786003d`): القراءة في الفراغ، والآية مستورة،
> والجواب يُسمَع مرة. والستر وتدرّج الإخفاء هما *عرض الحفظ* (`3c05ad8`): بلا
> ستر / أوائل الكلمات / علامات الآيات وحدها، ولمسة على كلمة مستورة تكشفها. وتمرين
> «ما بعدها؟» (`3a3f249`). والتقييم الذاتي (`8c5f8ee`) مع جدول المراجعة.
> *على غير ما في الفكرة:* التقييم واحدٌ لنطاق الجلسة كله لا لكل آية — لمسة
> واحدة كما طُلب، والسلّم يحفظ النطاقات لا الآيات.

أعلى الإضافات قيمةً. علم التعلّم قاطع في أن *الاسترجاع* — أن تُخرج الآية من صدرك —
يرسّخ الحفظ أضعاف ما يرسّخه سماعٌ آخر (أثر الاختبار). الجلسة اليوم تُسمِع فقط؛ هذه
الخطوات تجعلها تسأل:

- **جولات «اقرأ في الفراغ».** بعد جولات السماع والترديد المعتادة للآية، تُلحق الخطة
  *جولات استرجاع*: يشغّل الصفّ سكوتًا بطول الآية نفسها (تكرار مقطع الصمت المرفق —
  وخدمة أطوال الآيات تعرف الطول)، يقرأ فيه الحافظ من صدره، ثم تُسمَع الآية مرةً
  جوابًا. عملٌ خالص في باني الخطة وصفّ التشغيل؛ لا حزمة جديدة، ويعمل دون اتصال لكل
  ما هو محمَّل.
- **سترُ النص على الصفحة.** في جولات الاسترجاع (أو عند الطلب) تُسدَل غشاوة خفيفة
  *فوق* كل كلمة من الآية المختبَرة — لمسةٌ تكشف الكلمة، ولمسةٌ تردّ الستر. كائنات
  الكلمات وبايتاتها لا تُمسّ؛ هذا عرضٌ يُشغّله القارئ بنفسه كإعداد حجم الخط، فالقاعدة
  الأولى محفوظة (والسابعة كذلك: لا بترَ ولا اجتزاء — سترٌ بإذن القارئ، كما تُغطَّى
  الصفحة باليد في التسميع).
- **تدرّج الإخفاء.** ثلاث درجات يرتقيها القارئ كلما اشتد حفظه: كل الكلمات ظاهرة ← أول
  كلمة من كل آية فقط (المفتاح) ← علامات الآيات وحدها. وهي طريقة «غطِّ الصفحة شيئًا
  فشيئًا» المعروفة.
- **تمرين «ما بعدها؟» للربط.** يُسمِع الصفُّ الآيةَ، ثم فراغًا يقرأ فيه القارئ الآية
  التالية، ثم تُسمَع التالية جوابًا، ويمضي كذلك في النطاق. هذا يختبر *الوصل* بين
  الآيات — وهو موضع الانقطاع الأغلب — وهو منطق صفٍّ خالص فوق المصادر القائمة.
- **تقييم ذاتي في ختام الجلسة.** شاشة واحدة وثلاثة أزرار للآية أو للنطاق كله:
  *متقَن / متذبذب / نسيت*. يُحفظ محليًّا ويغذّي جدول المراجعة أدناه. لمسة واحدة بلا
  كتابة.

### ٢. جدول المراجعة — السبق والسبقي والمنزل ميزةً في التطبيق

> **الحال: تمّ** (`8c5f8ee`، والإعدادات `fda6c1e`). سلّم ١–٣–٧–١٤–٣٠–٩٠ يومًا،
> ومتقَن/متذبذب/نسيت بعد الجلسة، وبطاقة اليوم، وإعدادات جديد/قريب/بعيد. *على غير
> ما في الفكرة:* الطبقة من عمر النطاق — دون ٧ أيام سبق، ودون ٣٠ سبقي، ثم منزل —
> ومراجعة المنزل يحين وقتها بالسلّم لا بدورة جزءٍ في اليوم. والمراجعة الباقية من
> يوم سابق «حان وقتها» لا «متأخرة» (دليل الهوية §٦).

نظام الكتاتيب الموروث ينطبق انطباقًا حسنًا على التكرار المتباعد، وفي التطبيق أصلًا
تتبّعُ تقدمٍ وخططُ جلسات يُبنى عليها:

- **ثلاث طبقات تُدار آليًّا.** ما حُفظ هذا الأسبوع *سبقٌ* (يُدرَّس يوميًّا بتكرار
  كامل)؛ وما حُفظ في نحو الشهر الأخير *سبقيٌّ* (كل بضعة أيام بتكرار أخف)؛ وما قبل
  ذلك *منزلٌ* (دورة راتبة — قدرُ جزءٍ في اليوم مثلًا — بسماعٍ أو سماعين مع فراغات
  استرجاع). التطبيق يعرف التواريخ؛ والقارئ لا يُقيّد شيئًا.
- **فترات متباعدة تتسع مع التقييم الذاتي.** يبدأ النطاق المحفوظ على سلّم مراجعة
  ١–٣–٧–١٤–٣٠–٩٠ يومًا؛ *متقَن* يرقّيه درجة، و*متذبذب* يعيد الدرجة، و*نسيت* يردّه
  إلى اليومي. هذا هو المعمول به في علم المباعدة وفي أقوى التطبيقات المنافسة. كله
  محلي وفي مخزن التقدم.
- **بطاقة «اليوم» في الرئيسة.** بطاقة واحدة: مقطعُ اليوم الجديد، ومراجعةُ القريب،
  ومراجعةُ البعيد — كلٌّ بلمسة تفتح صفحة القراءة والجلسة معدّة. لا ينبغي للقارئ أن
  *يخطط*؛ التطبيق يحمل دفترَ الشيخ.
- **جلسات المراجعة أخفّ بطبعها.** جلسة المراجعة تَفترض تكرارًا أقل وفراغات استرجاع
  أكثر من جلسة الحفظ الجديد — إعداداتٌ مسماة: *جديد / قريب / بعيد* لا أرقام.

### ٣. مواضع التعثر — تذكّرْ أين ينقطع الحبل

> **الحال: علامات التعثر تمّت** (`1dd3af2`): «أتعثر هنا» في قائمة الآية، وخط
> منقّط تحتها في الصفحة، وتكراران زائدان في كل جلسة، وشاشة مواضع الضعف تُطلق
> جلسة عليها. **خريطة الضعف تمّت** (`eea3f0f`): صفّ السورة وبطاقتها
> في الشبكة يُظهران مقدار المحفوظ، وعدد الآيات الموسومة إن وُجدت — «مواضع ضعف:
> ٣» — بلون العلامات الهادئ لا بلون التحذير (دليل الهوية §٦)، ويتبعان أي علامة
> تُوضع أو تُرفع والفهرس ظاهر.

- **علامة تعثّر.** في الجلسة أو في القراءة، يُزاد في قائمة الآية خيار *أتعثر هنا*.
  الآيات الموسومة: تنال تكرارًا زائدًا آليًّا متى وقعت في جلسة، وتُظلَّل تظليلًا
  خفيفًا في القراءة (كعلامة القراءة، بإذن القارئ)، وتُجمع في شاشة «مواضع الضعف»
  تُطلق جلسةً عليها وحدها. محليٌّ كله.
- **خريطة ضعفٍ على فهرس السور.** يحمل صفُّ كل سورة مؤشرًا هادئًا بمقدار المحفوظ منها
  ومقدار الموسوم ضعفًا — نظرة «أي السور راسخة» بلمحة، محسوبة من التقدم المحلي وحده.

### ٤. المتشابهات — الآيات المتقاربات

> **الحال:** بُنيت الميزة في أكتوبر ٢٠٢٦، وأُدخلت بياناتها في ٢١ أكتوبر ٢٠٢٦.
> «متشابهات القرآن» في QUL (المورد ٧٣) لا يُنزَّل إلا بحساب مسجَّل، ويُعاد بناؤه
> بالأمر `python3 tool/build_mutashabihat.py path/to/the.zip --correct 4970:48:10:23-27=23-25`.
> يتحقق الأمر من كل إحالة على `quran.db` ويرفض المصدر إن خالفه؛ والإحالة
> الوحيدة المخالفة — العبارة ٤٩٧٠ في الآية ٤٨:١٠، مسجّلة كلماتٍ ٢٣–٢٧ وفي الآية
> ٢٥ كلمة — تُصحَّح باسمها إلى ٢٣–٢٥، أي آخر ثلاث كلمات في الآية. أُبقي ٨٠٧ عبارات من ٨١٤، واستُبعدت ٧ ترد في أكثر
> من ٤٠ آية لشيوعها. ويظهر «آيات متشابهة» في قائمة كل آية لها نظير.
> ثم صار تصفّح القائمة كلها من أعلى الإعدادات (`3c101ed`): بطاقة لكل عبارة،
> وتضييقٌ بالسورة، وكل بطاقة تفتح كل آية ترد فيها. **تمّ بعضه:** قائمة الآية تقول
> «آيات متشابهة» ولا تسمّيها (*تشبه ٢:٤٨ / ٢:١٢٣*). **لم يُبنَ بعد:** التمرين.

أشيعُ خللٍ في الحفظ المستقر هو الانزلاق من آيةٍ إلى شبيهتها في موضع آخر، وقد قامت
تطبيقات كاملة على هذا وحده.

- **ملف أزواجٍ بياناتٌ لا شيفرة.** يُرفق (أو يُنشر على الـCDN بجوار الـmanifest) ملف
  JSON بأزواج/مجموعات المتشابهات يشير إلى الآيات بسورة:آية — بياناتٌ خالصة، لا شيفرة
  لسورة بعينها، على مثال `reciters.json` سواء. والقوائم المصنّفة (نحو ٢٧٠ زوجًا
  مشهورًا) علمٌ مبذول؛ يُراجَع الملف مرةً ولا يُولَّد توليدًا.
- **عرض المقارنة جنبًا إلى جنب.** الآيتان في شاشة واحدة، تُرسمان بايتًا ببايت عبر
  `AyahText` كالعهد دائمًا؛ يرى القارئ موضع الافتراق بالقراءة، ويُسمِع التلاوتين
  متتابعتين عبر المحلّل المعتاد.
- **شارة «لها شبيهة» في القراءة.** الآية التي لها شبيهة معلومة تحمل في قائمتها إشارةً
  صغيرة — *تشبه ٢:٤٨ / ٢:١٢٣* — فيعلم القارئ بالمزلّة قبل الوقوع فيها.
- **لاحقًا: تمرين.** تُسمَع إحدى الآيتين والنص مستور، فيقول القارئ أيتهما هي ويُتمّها،
  ثم يُسمَع الجواب. يُبنى كله على وضع الاسترجاع في §١.

### ٥. سماعٌ في خدمة الحفظ

> **الحال:** مؤقّت النوم و«هذه الآية ثلاثًا أيضًا» **تمّا** (`06c89fc`) — والزيادة
> زرٌّ في شريط الجلسة لا ضغطة مطولة. **حلقة السماع تمّت:** «استمع من هنا» في قائمة
> الآية يُسمِع إلى آخر السورة مرة؛ وإعداد **استماع** في نافذة الجلسة يُسمِع النطاق
> المختار متصلًا بلا سؤال، بعدد ما في عدّاد التكرار — النطاقَ كذا مرة.
> **طرفا الليل والنهار تمّا:** مفتاح في
> الإعدادات (مطفأ حتى يختاره القارئ). من السابعة مساءً إلى ما بعد منتصف الليل تقترح
> بطاقة اليوم المقطعَ الذي حُفظ أولَ مرة ذلك اليوم ليُسمع مرة أخرى؛ ومن الرابعة إلى
> الظهر المقطعَ الذي حُفظ أمس ليُقرأ من الحفظ — مكانَ مراجعته في السلّم لا بجوارها.
> وما أُخذ من الاقتراحات لا يُعاد؛ وخارج الوقتين لا يُقال شيء، فلا وقتَ «يفوت».
> *على غير ما في الفكرة:* بلا تنبيهات (عائق حزمة) لا يستطيع التطبيق أن يدعو القارئ
> عند النوم؛ فالاقتراح ينتظر في الرئيسة.

- **حلقة سماع فقط.** «شغّل هذا النطاق مكررًا كذا مرة» بلا بنية تدريس — للطريق
  وللمطبخ، ولجولة الاستئناس التي يُفتتح بها التلقين تقليدًا. هي محرك الجلسة بتكرارٍ
  واحد وبلا جمع؛ أغلبها واجهة.
- **مؤقّت النوم.** توقّفٌ بعد كذا دقيقة أو عند تمام الجولة الجارية. يوافق أدلة ترسيخ
  النوم: راجِع آخرَ شيء، ونَم عليه. يسيرٌ بخدمة التشغيل القائمة.
- **طرفا الليل والنهار.** خيار لطيف في الخطة: يقترح الجدول المقطعَ نفسه آخرَ الليل
  وأولَ الصباح. وجدت دراسة Mazza وزملائه (٢٠١٦، Psychological Science) أن نومةً بين
  جلستي تدريب تكاد تُنصّف الجهد اللازم وتحسّن البقاء بعد ستة أشهر.
- **زيادة تكرار آيةٍ بعينها.** في أثناء الجلسة: *هذه الآية ثلاثًا أيضًا* — ضغطة مطولة
  على الشريط تغذّي الصفّ دون إعادة بناء الخطة.

### ٦. الخطط والعادة

> **الحال:** خطة الحفظ **تمّت** (`bacfb05`): مقطعٌ في عدد من الأيام، مقسومٌ على
> طول التلاوة؛ ويُحسب قدرُ اليوم متى قُيِّم متقَنًا أو متذبذبًا. والإحصاء الهادئ
> **تمّ** (`3ea5bc8`): مجاميع فقط. *مشكلة وُجدت وأُصلحت:* المسودة الأولى عدّت
> أيامًا متتالية وذكرت تأخر الخطة؛ فحُذف الأمران وفق دليل الهوية §٦. والتنبيه
> اليومي ما زال **[عائق]**.

- **خطة ختمة حفظ.** يختار القارئ غايةً — جزء عمّ في ٩٠ يومًا مثلًا — فيقسمها التطبيق
  مقاطعَ يومية على وزن الآيات (حسابُ `recitationWeight` في أداة الإدارة يقيس أصلًا
  طولَ التلاوة من النص؛ تُستعاد الفكرة لا الشيفرة). فتمتلئ بطاقة «اليوم» من أول يوم.
- **إحصاء هادئ.** أيام الممارسة، والآيات المحفوظة، ودقائق السماع — مجاميع تُحسب
  محليًّا وتُعرض بتواضع. **بلا أيام متتالية** ولا علامة على يوم فات: دليل الهوية
  (§٦) يمنع الضغط بخوف الخسارة على صلة المرء بالقرآن، واختبار `brand_voice_test`
  يحرس ذلك.
- **تنبيه يومي. [عائق]** يحتاج `flutter_local_notifications` أو نحوها — ليست في
  القائمة المعتمدة. يستحق عائقًا مرقّمًا: تذكيرٌ محلي ثابت في وقتٍ يختاره القارئ هو
  أرخص ميزات العادة جميعًا، ولا يحتاج شبكةً ولا حسابًا.

### ٧. التسميع — القراءة على مُسمِّع

> **الحال: وضع ناول الهاتف تمّ** (`16cee2c`). *على غير ما في الفكرة:* يُقيَّد
> الخطأ عند آيته (علامةَ تعثّر) لا عند الكلمة، ولا تُعاد الجلسة من هناك — فالمسمِّع
> يتبع صوتًا، فيُعلَن القيد فورًا مع «تراجع»، وينتهي إلى مواضع الضعف. وسجّل وقارن
> ما زال **[عائق]**.

- **وضع ناولِ الهاتف.** يمسك المُسمِّعُ الهاتفَ ويرى الصفحة، والقارئ لا يرى شيئًا.
  يلمس المُسمِّع الكلمةَ التي وقع عندها الخطأ — فتُقيَّد علامةَ تعثّر (§٣) ويعيد
  التشغيل من هناك إن شاء. لا جهاز ثانٍ ولا حساب ولا شبكة: أقدم ممارسات الحفظ،
  والهاتف مصحفُ الشيخ.
- **سجّل وقارن. [عائق]** تسجيل قراءة القارئ للنطاق وتشغيلها بالتناوب مع القارئ
  المعتمد. يحتاج حزمة تسجيل (`record` مثلًا) — ليست معتمدة، وإذن الميكروفون قرارُ
  منتجٍ حقيقي. قيمته عالية، لكنه خلف عائقٍ لا محالة.

### ٨. التصدير والنقل وطمأنينة البال

> **الحال: تمّ، وفيه مشكلة** (`c477ea0`). التصدير يكتب ملف JSON واحدًا، والاستيراد
> يدمجه ولا يحذف شيئًا. وعلى iOS يظهر الملف في مجلد التطبيق في تطبيق «الملفات».
> **المشكلة:** على أندرويد يُكتب في مجلد التطبيق الخارجي (`Android/data/<app>/files`)،
> وتطبيق الملفات لا يفتحه منذ أندرويد ١١، ويُحذف بحذف التطبيق — فالانتقال إلى
> هاتف جديد يحتاج حاسوبًا. وللتطبيق قناة مشاركة أصلية خاصة به (تستعملها صورة
> الآية)، فيمكن تسليم الملف لنافذة المشاركة النظامية بلا حزمة جديدة؛ وذلك هو
> الإصلاح.

- **تصدير التقدم واستيراده ملفًّا.** ملف JSON واحد بالتقدم والعلامات وسلّم المراجعة،
  يُكتب حيث يختار القارئ ويُسترد على هاتف جديد. يحفظ عهدَ «لا حسابات» ويرفع خوفَ
  ضياع سنين من المراجعة. الكتابة في مجلد مستندات التطبيق لا تحتاج حزمة؛ أما نافذة
  المشاركة النظامية فتحتاج **[عائق: `share_plus`]** — فليُقدَّم الحل الملفي أولًا.

### ٩. لمسات أصغر

> **الحال:** الاستئناف **تمّ** (`292d69e`). والإعدادات المسماة **تمّ بعضها**
> (`fda6c1e`): أربعة ثابتة — جديد، قريب، بعيد، تثبيت — لا يحفظها القارئ من
> النموذج. وسطر «عن هذه السورة» **تمّ بعضه** (`35e0296`): مكية/مدنية وعدد الآيات،
> في قائمة كل آية لا في رأس السورة، وبلا مدى الأجزاء. وعلامات القراءة المتعددة
> **لن تُؤخذ** — العقد A.5 يحدّها بعلامة واحدة، فهي قرار منتج.

- **علامات قراءة متعددة** بألوان متمايزة (العلامة اليوم واحدة)، لكلٍّ الشريطُ والقائمة
  نفسها — فالحفظ بطبعه يمسك مواضعَ عدة (السبق والسبقي والمنزل ثلاث علامات بالفطرة).
- **إعدادات جلسة مسماة** — *حفظ جديد / مراجعة سريعة / تثبيت عميق* — تُحفظ من نموذج
  الجلسة، فيصير وِردُ الطبقات الثلاث ثلاثَ لمسات.
- **استئناف الجلسة المقطوعة** من موضعها سواء (يُحفظ موضع الخطة عند كل خطوة)، فلا
  تُكلّف مكالمةٌ هاتفيةٌ سبقَ الليلة كلّه.
- **سطر «عن هذه السورة»** من بيانات `quran.db` القائمة (مكية/مدنية، عدد الآيات، مدى
  الأجزاء) في قائمة رأس السورة — فالتوطئة تُعين رسوخَ الحفظ، وهي بيانات موجودة خالصة.

### الأولوية، إن سُئلنا

١. وضع الاسترجاع (§١) — يحوّل المشغّل محفِّظًا؛ وكل ما سواه يصبّ فيه.
٢. جدول المراجعة وبطاقة اليوم (§٢) — يحوّل الجلسات منهجًا.
٣. علامات التعثر (§٣) — رخيصة، والجدول يحسُن ساعةَ وجودها.
٤. حلقة السماع ومؤقّت النوم (§٥) — يسيرة جدًّا وتوسّع الاستعمال اليومي.
٥. بيانات المتشابهات وعرض المقارنة (§٤) — مميِّزة، بياناتُها قائدتها، بلا خطر على الشيفرة.

---

## Sources — المصادر

- Traditional sabaq/sabqi/manzil structure and revision ratios:
  [Quran Sheikh — Hifz revision schedule](https://www.quransheikh.com/quran-hifz-revision-schedule/),
  [Quran Sheikh — teaching methodology](https://www.quransheikh.com/hifz-teaching-methodology-used-by-quran-sheikh-tutors/),
  [Kalimah Center — the "sticky" hifz method](https://kalimah-center.com/memorize-the-quran-and-never-forget-it/)
- Sleep between practice sessions halves relearning effort and improves 6-month
  retention: [Mazza et al. 2016, *Psychological Science*](https://journals.sagepub.com/doi/ref/10.1177/0956797616659930),
  [Learning Scientists summary](https://www.learningscientists.org/blog/2016/9/15-1)
- Spacing/testing effect background: [spacing effect notes](https://concepts.dsebastien.net/concept/spacing-effect/)
- Comparable apps — hide-and-recite, self-graded review ladders, mutashabihat
  trainers: [HifzPath](https://mwm.ai/apps/hifzpath-quran-memorization/6761689759),
  [Rusukh — رسوخ](https://mwm.ai/apps/app/6790137429),
  [Tarteel — automatic recitation & memorization](https://tarteel.ai/blog/introducing-automatic-recitation-and-memorization-on-tarteel/),
  [Tarteel feature requests — spaced repetition & spot testing](https://feedback.tarteel.ai/feature-requests/p/spaced-repetition-spot-hifdh-testing),
  [Quran Revision Companion (F-Droid)](https://f-droid.org/packages/com.wqar.quran_mem_helper/),
  [Ayaty: Mutashabihat al-Quran](https://apps.apple.com/app/id6756410871),
  [quran.com hifdh feature request](https://feedback.quran.com/feature-requests/p/hifdh-feature)
