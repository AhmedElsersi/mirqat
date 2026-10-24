#!/usr/bin/env python3
"""Frames raw store screenshots the way store listings show them: the brand's
forest green, a headline and a line under it, and the screen in a device.

    tool/store_frames.py <raw dir> <out dir> <phone|tablet> [--size WxH]

    tool/store_frames.py store/raw/iphone        store/apple/iphone  phone  --size 1320x2868
    tool/store_frames.py store/raw/ipad          store/apple/ipad    tablet --size 2064x2752
    tool/store_frames.py store/raw/android-phone store/google/phone  phone  --size 1080x1920
    tool/store_frames.py store/raw/android-tab   store/google/tablet tablet --size 1600x2560

The raw shots come from tool/store_screenshots.sh (or its Android twin) and
are the running app, untouched; only what surrounds them is drawn here. Each
frame is an HTML page rendered by headless Chrome, because the captions are
Arabic and need real text shaping, which Pillow here does not have.

A raw shot that has no caption below is skipped, so the order and the choice
of scenes is this file's CAPTIONS, not the raw directory.
"""
import argparse
import base64
import html
import os
import subprocess
import sys
import tempfile

from PIL import Image

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Store order: the first three are what search results show.
# (raw name, output name, headline, line under it, new in this release)
CAPTIONS = [
    ("01-today", "01-today", "وِردك اليومي في صفحة واحدة",
     "حفظ جديد، ومراجعة القريب، ومراجعة القديم — كلٌّ بضغطة", True),
    ("04-recall", "02-recall", "جلسةٌ تختبر حفظك",
     "يصمت التطبيق لتقرأ الآية من حفظك، ثم يُسمعك إياها", True),
    ("02-reading", "03-reading", "المصحف كاملًا بخط مصحف المدينة",
     "٦٠٤ صفحات كما طُبعت، تُقرأ دون إنترنت", False),
    ("03-session", "04-session", "التلقين يُتلى فوق الصفحة",
     "تسمع الآية وتكرّرها، ثم تصلها بما بعدها", False),
    ("05-memorization", "05-memorization", "استُر الصفحة وسمِّع لنفسك",
     "تظهر أوائل الآيات، وتكشف الباقي بلمسة", True),
    ("06-ayah-menu", "06-stumble", "علِّم مواضع تعثّرك",
     "فتُكرَّر أكثر في جلساتك القادمة", True),
    ("07-presets", "07-presets", "جلستك كما تريدها",
     "حفظ جديد، ومراجعة، وتثبيت، واستماع — أو طريقتك أنت", True),
    ("08-my-hifz", "08-my-hifz", "حفظك كلّه في خريطة",
     "ما حفظته جزءًا جزءًا، ومواضع التعثّر في مكان واحد", True),
    ("09-mushaf-index", "09-index", "سورةً سورة، وجزءًا جزءًا",
     "ومواضع تعثّرك ظاهرة في قائمة السور", False),
    ("10-font", "10-font", "اختر خطّ مصحفك",
     "معاينة حيّة، وحجم الخط كما تحب", True),
]

# Play takes eight phone screenshots; the App Store ten.
LIMITS = {"store/google": 8}

# On a tablet the lists and cards stand small in a sea of cream; the mushaf
# page is what a tablet is bought for, so its set is the scenes built on it.
TABLET = {"02-recall", "03-reading", "04-session", "05-memorization",
          "06-stumble", "07-presets"}

BADGE = "جديد"

# One eight-pointed star, tiled: two squares, one turned by 45°.
PATTERN = base64.b64encode(b"""<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120' viewBox='0 0 120 120'>
<g fill='none' stroke='#E1B45C' stroke-width='1.4'>
<rect x='35' y='35' width='50' height='50'/>
<rect x='35' y='35' width='50' height='50' transform='rotate(45 60 60)'/>
<circle cx='60' cy='60' r='12'/>
<path d='M0 0L25 25M120 0L95 25M0 120L25 95M120 120L95 95'/>
</g></svg>""").decode()

PAGE = """<!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@500;700&display=block" rel="stylesheet">
<style>
  html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; }}
  body {{
    font-family: "IBM Plex Sans Arabic", "SF Arabic", sans-serif;
    background:
      radial-gradient(ellipse at 50% 0%, #11684A 0%, rgba(17,104,74,0) 60%),
      linear-gradient(180deg, #0B4E35 0%, #04241A 100%);
    position: relative;
  }}
  .pattern {{
    position: absolute; inset: 0;
    background-image: url("data:image/svg+xml;base64,{pattern}");
    background-size: {tile}px {tile}px;
    opacity: .07;
  }}
  .head {{
    position: absolute; top: {top}px; left: {side}px; right: {side}px;
    text-align: center; color: #F9F4E6;
  }}
  .badge {{
    display: inline-block; font-weight: 700; font-size: {badge}px;
    color: #04241A; background: #E1B45C; border-radius: 999px;
    padding: {bpy}px {bpx}px; margin-bottom: {gap}px; letter-spacing: 0;
  }}
  h1 {{
    margin: 0; font-weight: 700; font-size: {title}px; line-height: 1.25;
  }}
  p {{
    margin: {gap}px 0 0; font-weight: 500; font-size: {sub}px;
    line-height: 1.45; color: rgba(249,244,230,.78);
  }}
  .device {{
    position: absolute; left: 50%; top: {dtop}px; transform: translateX(-50%);
    width: {dw}px; height: {dh}px; box-sizing: border-box;
    padding: {bezel}px; border-radius: {outer}px;
    background: linear-gradient(145deg, #2A2F2C, #0C0F0D);
    box-shadow: 0 {sy}px {sb}px rgba(0,0,0,.45), 0 0 0 {rim}px rgba(225,180,92,.55);
  }}
  .device img {{
    display: block; width: 100%; height: 100%;
    border-radius: {inner}px; object-fit: cover;
  }}
</style></head>
<body>
  <div class="pattern"></div>
  <div class="head">
    {badge_html}
    <h1>{headline}</h1>
    <p>{line}</p>
  </div>
  <div class="device"><img src="{shot}"></div>
</body></html>
"""


def render(raw, out, kind, w, h, headline, line, new):
    sw, sh = Image.open(raw).size
    u = min(w, h) / 100  # one hundredth of the short side
    title, sub, badge = 7.0 * u, 3.5 * u, 2.7 * u
    if kind == "tablet":
        title, sub, badge = 5.2 * u, 2.7 * u, 2.1 * u
    top = 6.5 * u
    # The same room for every headline, badge or not, one line or two, so the
    # devices stand at one height across the whole set.
    head_h = top + badge * 2.4 + title * 1.25 * 2 + sub * 1.45 + 4 * u
    bezel = 1.6 * u if kind == "phone" else 1.8 * u
    # The device fills what the headline leaves, with a margin at the foot.
    avail_h = h - head_h - 5 * u
    avail_w = w * (0.80 if kind == "phone" else 0.84)
    scale = min((avail_w - 2 * bezel) / sw, (avail_h - 2 * bezel) / sh)
    dw, dh = sw * scale + 2 * bezel, sh * scale + 2 * bezel
    dtop = h - dh - 5 * u
    inner = (11.5 if kind == "phone" else 3.2) * dw / 100
    page = PAGE.format(
        w=w, h=h, pattern=PATTERN, tile=round(13 * u), top=round(top),
        side=round(6 * u), badge=round(badge), bpy=round(badge * 0.28),
        bpx=round(badge * 0.9), gap=round(1.6 * u), title=round(title),
        sub=round(sub), dtop=round(dtop), dw=round(dw), dh=round(dh),
        bezel=round(bezel), outer=round(inner + bezel), inner=round(inner),
        sy=round(2.5 * u), sb=round(7 * u), rim=max(1, round(0.25 * u)),
        badge_html=f'<div class="badge">{BADGE}</div>' if new else "",
        headline=html.escape(headline), line=html.escape(line),
        shot="file://" + os.path.abspath(raw),
    )
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False,
                                     encoding="utf-8") as f:
        f.write(page)
    try:
        subprocess.run([
            CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--allow-file-access-from-files", "--force-device-scale-factor=1",
            f"--window-size={w},{h}", "--virtual-time-budget=8000",
            f"--screenshot={out}", "file://" + f.name,
        ], check=True, capture_output=True)
    finally:
        os.unlink(f.name)
    # The stores refuse an alpha channel, and want the exact size.
    image = Image.open(out).convert("RGB")
    if image.size != (w, h):
        sys.exit(f"{out}: rendered at {image.size}, not {w}x{h}")
    image.save(out, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("kind", choices=["phone", "tablet"])
    ap.add_argument("--size", required=True)
    args = ap.parse_args()
    w, h = (int(n) for n in args.size.split("x"))
    os.makedirs(args.out, exist_ok=True)
    limit = next((n for k, n in LIMITS.items() if k in args.out), len(CAPTIONS))
    made = 0
    for raw_name, out_name, headline, line, new in CAPTIONS:
        raw = os.path.join(args.raw, raw_name + ".png")
        if not os.path.exists(raw) or made >= limit:
            continue
        if args.kind == "tablet" and out_name not in TABLET:
            continue
        render(raw, os.path.join(args.out, out_name + ".png"), args.kind,
               w, h, headline, line, new)
        made += 1
        print("framed", out_name)
    print(f"{made} frames in {args.out}")


if __name__ == "__main__":
    main()
