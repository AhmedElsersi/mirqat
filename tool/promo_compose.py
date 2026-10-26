#!/usr/bin/env python3
"""Cuts the clips filmed by tool/promo_video.sh into the finished promo videos.

    tool/promo_compose.py <clips dir> <out dir> [--audio <dir of ayah mp3s>]

Each video is sixty seconds: a title card, scenes of the real app in a device
on the brand's green with a caption beside it, and an end card. Under it runs
the recitation of whole ayahs — never cut inside an ayah, never music — from
the same CDN the app streams from. Two shapes of each are made: 1920x1080 for
YouTube and the Play listing's video, 1080x1920 for phones held upright.

Cards and captions are HTML rendered by headless Chrome (the Arabic needs
shaping); the clips are only scaled and placed, never altered.
"""
import argparse
import html
import os
import subprocess
import sys
import tempfile
import urllib.request

from PIL import Image, ImageDraw

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CDN = "https://pub-f2046e05789e4bd5889880fb0c6d3168.r2.dev/audio/ahmed_khalil_shaheen/64/"
ICON = "brand/icon_1024.png"
FPS = 30
FADE = 0.5
LENGTH = 60.0

# A scene: (clip, seconds into the clip, seconds on screen, headline, line).
# A clip of None is a card.
VIDEOS = {
    "iqra-wartaq-1.3-wird": {
        "title": ("الجديد في الإصدار ١٫٣", "وِردك اليومي، وجلسةٌ تختبر حفظك"),
        "ayahs": ["002001", "002002", "002003", "002004", "002005"],
        "scenes": [
            ("intro", 0.3, 14.0, "تعرّف بالطريقة في دقيقة",
             "مقدّمة جديدة: التلقين درجةً درجة"),
            ("today", 0.5, 10.0, "وِردك اليومي في صفحة واحدة",
             "حفظ جديد، ومراجعة القريب، ومراجعة القديم — كلٌّ بضغطة"),
            ("recall", 20.0, 18.0, "جلسةٌ تختبر حفظك",
             "يصمت التطبيق لتقرأ الآية من حفظك، ثم يُسمعك إياها"),
            ("cover", 4.2, 7.5, "استُر الصفحة وسمِّع لنفسك",
             "تظهر أوائل الآيات، وتكشف الباقي بلمسة"),
        ],
    },
    "iqra-wartaq-1.3-tools": {
        "title": ("الجديد في الإصدار ١٫٣", "أدواتٌ تثبّت حفظك"),
        "ayahs": ["067000", "067001", "067002", "067003", "067004"],
        "scenes": [
            ("stumble", 2.0, 9.8, "علِّم مواضع تعثّرك",
             "اضغط مطوّلًا على الآية: «أتعثّر هنا»، فتُكرَّر أكثر"),
            ("index", 3.0, 6.5, "ترى أين تتعثّر",
             "مواضع التعثّر ظاهرة في قائمة السور"),
            # The recorder starts late, so My hifz is on film at the head of
            # the next clip.
            ("font", 0.0, 3.8, "حفظك كلّه في خريطة",
             "ما حفظته جزءًا جزءًا، وأدوات تثبيته في مكان واحد"),
            ("presets", 2.0, 11.5, "جلستك كما تريدها",
             "حفظ جديد، ومراجعة، وتثبيت، واستماع — أو طريقتك أنت"),
            ("today", 12.3, 6.5, "٦٠٤ صفحات كما طُبعت",
             "المصحف كاملًا، يُقرأ دون إنترنت"),
            ("font", 4.2, 9.0, "خطّ مصحف المدينة",
             "اختر خطّ مصحفك وحجمه، بمعاينة حيّة"),
        ],
    },
}
TITLE_SECONDS = 3.0  # silent: the recitation starts as the first scene does

SHAPES = {
    "landscape": (1920, 1080),
    "portrait": (1080, 1920),
}

STYLE = """
html, body { margin: 0; width: %(w)dpx; height: %(h)dpx; overflow: hidden; }
body {
  font-family: "IBM Plex Sans Arabic", "SF Arabic", sans-serif; color: #F9F4E6;
  background:
    radial-gradient(ellipse at 70%% 0%%, #11684A 0%%, rgba(17,104,74,0) 60%%),
    linear-gradient(180deg, #0B4E35 0%%, #04241A 100%%);
}
.badge { display: inline-block; font-weight: 700; color: #04241A;
  background: #E1B45C; border-radius: 999px; }
h1 { margin: 0; font-weight: 700; line-height: 1.25; }
p { margin: 0; font-weight: 500; line-height: 1.5; color: rgba(249,244,230,.8); }
"""
HEAD = ('<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
        '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+'
        'Arabic:wght@500;700&display=block" rel="stylesheet"><style>%s</style>'
        '</head><body>%s</body></html>')


def chrome(page, w, h, out):
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
    Image.open(out).convert("RGB").save(out)


def geometry(shape, shot):
    """Where the device and its screen stand, and where the caption goes."""
    w, h = SHAPES[shape]
    sw, sh = shot
    if shape == "landscape":
        dh = 960
        bezel = 16
        scr_h = dh - 2 * bezel
        scr_w = round(scr_h * sw / sh)
        dw = scr_w + 2 * bezel
        dx, dy = 640 - dw // 2, (h - dh) // 2
        text = "position:absolute; right:110px; width:900px; top:50%; transform:translateY(-50%);"
        sizes = (84, 40, 30)
    else:
        dh = 1360
        bezel = 20
        scr_h = dh - 2 * bezel
        scr_w = round(scr_h * sw / sh)
        dw = scr_w + 2 * bezel
        dx, dy = (w - dw) // 2, h - dh - 90
        text = "position:absolute; left:70px; right:70px; top:110px; text-align:center;"
        sizes = (78, 38, 30)
    return {
        "w": w, "h": h, "dx": dx, "dy": dy, "dw": dw, "dh": dh,
        "sx": dx + bezel, "sy": dy + bezel, "sw": scr_w, "sh": scr_h,
        "radius": round(scr_w * 0.115), "text": text, "sizes": sizes,
    }


def scene_background(g, headline, line, out):
    t, s, b = g["sizes"]
    body = f"""
<div style="{g['text']}">
  <div class="badge" style="font-size:{b}px; padding:{b*.3:.0f}px {b:.0f}px; margin-bottom:28px">جديد في ١٫٣</div>
  <h1 style="font-size:{t}px">{html.escape(headline)}</h1>
  <p style="font-size:{s}px; margin-top:22px">{html.escape(line)}</p>
</div>
<div style="position:absolute; left:{g['dx']}px; top:{g['dy']}px; width:{g['dw']}px;
  height:{g['dh']}px; border-radius:{g['radius'] + (g['sx'] - g['dx'])}px;
  background:linear-gradient(145deg,#2A2F2C,#0C0F0D);
  box-shadow:0 30px 80px rgba(0,0,0,.5), 0 0 0 3px rgba(225,180,92,.55)"></div>"""
    chrome(HEAD % (STYLE % g, body), g["w"], g["h"], out)


def card(g, kind, title, line, out):
    icon = "file://" + os.path.abspath(ICON)
    big = 120 if g["w"] > g["h"] else 104
    if kind == "title":
        body = f"""
<div style="position:absolute; inset:0; display:flex; flex-direction:column;
  align-items:center; justify-content:center; text-align:center; gap:26px">
  <img src="{icon}" style="width:220px; height:220px; border-radius:50px;
    box-shadow:0 20px 60px rgba(0,0,0,.45)">
  <h1 style="font-size:{big}px">اقرأ وارتق</h1>
  <div class="badge" style="font-size:36px; padding:10px 34px">{html.escape(title)}</div>
  <p style="font-size:44px">{html.escape(line)}</p>
</div>"""
    else:
        body = f"""
<div style="position:absolute; inset:0; display:flex; flex-direction:column;
  align-items:center; justify-content:center; text-align:center; gap:24px">
  <img src="{icon}" style="width:200px; height:200px; border-radius:46px;
    box-shadow:0 20px 60px rgba(0,0,0,.45)">
  <h1 style="font-size:{big}px">اقرأ وارتق</h1>
  <p style="font-size:44px">احفظ القرآن بالتلقين، درجةً درجة</p>
  <p style="font-size:34px; color:#E1B45C">بلا إعلانات · بلا حسابات · يعمل دون إنترنت</p>
  <div style="display:flex; gap:22px; margin-top:18px; direction:ltr">
    <span class="badge" style="font-size:34px; padding:12px 34px">App Store</span>
    <span class="badge" style="font-size:34px; padding:12px 34px">Google Play</span>
  </div>
</div>"""
    chrome(HEAD % (STYLE % g, body), g["w"], g["h"], out)


def mask(g, out):
    image = Image.new("L", (g["sw"], g["sh"]), 0)
    ImageDraw.Draw(image).rounded_rectangle(
        (0, 0, g["sw"] - 1, g["sh"] - 1), radius=g["radius"], fill=255)
    image.save(out)


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


def clip_length(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", path], capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


def still(png, seconds, out):
    ffmpeg("-loop", "1", "-framerate", str(FPS), "-i", png, "-t", f"{seconds}",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS), out)


def scene(bg, clip, start, seconds, g, mask_png, out):
    have = clip_length(clip) - start
    # A clip shorter than its place holds its last frame; a longer one is cut.
    pad = max(0.0, seconds - have)
    ffmpeg(
        "-loop", "1", "-framerate", str(FPS), "-i", bg,
        "-i", clip,
        "-loop", "1", "-i", mask_png,
        "-filter_complex",
        # The simulator writes a frame only when the screen changes, so a still
        # screen is one frame and a gap: the rate is made constant first, and
        # the clip cut after, or a seek into the gap finds nothing to show.
        f"[1:v]fps={FPS},trim=start={start},setpts=PTS-STARTPTS,scale={g['sw']}:{g['sh']}:flags=lanczos,setsar=1,"
        f"tpad=stop_mode=clone:stop_duration={pad + 1},format=yuva420p[c];"
        f"[2:v]format=gray,scale={g['sw']}:{g['sh']}[m];"
        f"[c][m]alphamerge[cm];"
        f"[0:v][cm]overlay={g['sx']}:{g['sy']}:shortest=0,format=yuv420p[v]",
        "-map", "[v]", "-t", f"{seconds}", "-an",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", str(FPS), out)


def soundtrack(names, audio_dir, out):
    os.makedirs(audio_dir, exist_ok=True)
    paths = []
    for n in names:
        p = os.path.join(audio_dir, n + ".mp3")
        if not os.path.exists(p):
            req = urllib.request.Request(CDN + n + ".mp3",
                                         headers={"User-Agent": "curl/8"})
            with urllib.request.urlopen(req) as r, open(p, "wb") as f:
                f.write(r.read())
        paths.append(p)
    total = sum(clip_length(p) for p in paths)
    if TITLE_SECONDS + total > LENGTH:
        sys.exit(f"{names}: {total:.1f}s of recitation does not fit")
    inputs = []
    for p in paths:
        inputs += ["-i", p]
    joined = "".join(f"[{i}:a]" for i in range(len(paths)))
    ms = int(TITLE_SECONDS * 1000)
    ffmpeg(*inputs, "-filter_complex",
           f"{joined}concat=n={len(paths)}:v=0:a=1,"
           f"adelay={ms}|{ms},apad=whole_dur={LENGTH}[a]",
           "-map", "[a]", "-t", f"{LENGTH}", "-c:a", "aac", "-b:a", "160k", out)


def build(name, spec, clips, out_dir, audio_dir, shape, work):
    shot = Image.open(os.path.join(work, "_frame.png")).size
    g = geometry(shape, shot)
    m = os.path.join(work, f"mask-{shape}.png")
    mask(g, m)
    end_seconds = LENGTH - TITLE_SECONDS - sum(s[2] for s in spec["scenes"])
    parts, lengths = [], []
    # Every part but the last is FADE longer, the overlap the crossfade eats.
    title_png = os.path.join(work, f"{name}-{shape}-title.png")
    card(g, "title", *spec["title"], title_png)
    p = os.path.join(work, f"{name}-{shape}-00.mp4")
    still(title_png, TITLE_SECONDS + FADE, p)
    parts.append(p); lengths.append(TITLE_SECONDS + FADE)
    for i, (clip, start, seconds, headline, line) in enumerate(spec["scenes"], 1):
        bg = os.path.join(work, f"{name}-{shape}-{i:02d}.png")
        scene_background(g, headline, line, bg)
        p = os.path.join(work, f"{name}-{shape}-{i:02d}.mp4")
        scene(bg, os.path.join(clips, clip + ".mp4"), start, seconds + FADE, g, m, p)
        parts.append(p); lengths.append(seconds + FADE)
        print(f"  {shape} scene {clip}")
    end_png = os.path.join(work, f"{name}-{shape}-end.png")
    card(g, "end", "", "", end_png)
    p = os.path.join(work, f"{name}-{shape}-99.mp4")
    still(end_png, end_seconds, p)
    parts.append(p); lengths.append(end_seconds)

    inputs = []
    for p in parts:
        inputs += ["-i", p]
    chain, last, offset = [], "[0:v]", 0.0
    for i in range(1, len(parts)):
        offset += lengths[i - 1] - FADE
        label = f"[x{i}]"
        chain.append(f"{last}[{i}:v]xfade=transition=fade:duration={FADE}:"
                     f"offset={offset:.3f}{label}")
        last = label
    audio = os.path.join(work, f"{name}.m4a")
    if not os.path.exists(audio):
        soundtrack(spec["ayahs"], audio_dir, audio)
    out = os.path.join(out_dir, f"{name}-{shape}.mp4")
    ffmpeg(*inputs, "-i", audio, "-filter_complex", ";".join(chain),
           "-map", last, "-map", f"{len(parts)}:a", "-t", f"{LENGTH}",
           "-c:v", "libx264", "-preset", "slow", "-crf", "19",
           "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "copy",
           "-movflags", "+faststart", out)
    print(f"{out}: {clip_length(out):.2f}s")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("clips")
    ap.add_argument("out")
    ap.add_argument("--audio", default=None)
    ap.add_argument("--only", default=None, help="one video's name")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    work = tempfile.mkdtemp(prefix="promo_")
    audio_dir = args.audio or os.path.join(work, "audio")
    # The recordings' own size decides the screen's shape.
    first = sorted(f for f in os.listdir(args.clips) if f.endswith(".mp4"))[0]
    ffmpeg("-i", os.path.join(args.clips, first), "-frames:v", "1",
           os.path.join(work, "_frame.png"))
    for name, spec in VIDEOS.items():
        if args.only and name != args.only:
            continue
        print(name)
        for shape in SHAPES:
            build(name, spec, args.clips, args.out, audio_dir, shape, work)


if __name__ == "__main__":
    main()
