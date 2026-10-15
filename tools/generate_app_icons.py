#!/usr/bin/env python3
"""Generate app icons from assets/icon/app icon.jpeg (4 profiles artwork).
- Detects non-white bbox, crops, centers on white square.
- Standard master (1024) with 8% padding.
- Safe master (maskable/adaptive foreground) with 28% padding.
- Exports Android/iOS/Web/Windows/macOS.
"""
from PIL import Image, ImageOps
import os

ROOT = r"D:\antigravity\dr_tarek_platform_final"
SRC = os.path.join(ROOT, "assets", "icon", "app icon.jpeg")
OUT_DIR = os.path.join(ROOT, "assets", "icon", "generated")
os.makedirs(OUT_DIR, exist_ok=True)

BG = (255, 255, 255)

def load_source():
    im = Image.open(SRC).convert("RGB")
    return im

def content_bbox(im, thresh=248):
    # non-white pixels mask
    gray = im.convert("L")
    # bbox where pixel < thresh
    try:
        import numpy as np
        a = np.array(gray)
        mask = a < thresh
        if not mask.any():
            return (0, 0, im.width, im.height)
        ys, xs = mask.nonzero()
        return (int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1)
    except ImportError:
        # fallback: scan
        w, h = im.size
        px = gray.load()
        minx, miny, maxx, maxy = w, h, 0, 0
        for y in range(0, h, 2):
            for x in range(0, w, 2):
                if px[x, y] < thresh:
                    minx = min(minx, x); miny = min(miny, y)
                    maxx = max(maxx, x); maxy = max(maxy, y)
        return (minx, miny, maxx+1, maxy+1)

def make_square(im_crop, size, padding_ratio):
    # fit contain into size with padding
    target = int(size * (1 - padding_ratio*2))
    im2 = im_crop.copy()
    im2.thumbnail((target, target), Image.LANCZOS)
    canvas = Image.new("RGB", (size, size), BG)
    canvas.paste(im2, ((size-im2.width)//2, (size-im2.height)//2))
    return canvas

def save(im, path, size=None):
    if size and im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    im.save(path, "PNG")
    print(f"wrote {path} {im.size}")

def main():
    src = load_source()
    print("src", src.size)
    bbox = content_bbox(src)
    print("bbox", bbox)
    # add 2% margin
    x0, y0, x1, y1 = bbox
    mw = int((x1-x0)*0.02); mh = int((y1-y0)*0.02)
    x0 = max(0, x0-mw); y0 = max(0, y0-mh)
    x1 = min(src.width, x1+mw); y1 = min(src.height, y1+mh)
    crop = src.crop((x0, y0, x1, y1))
    print("crop", crop.size)

    standard = make_square(crop, 1024, 0.08)
    safe = make_square(crop, 1024, 0.28)

    standard.save(os.path.join(OUT_DIR, "master-1024.png"))
    safe.save(os.path.join(OUT_DIR, "master-safe-1024.png"))
    # also save into assets/icon for reference
    standard.save(os.path.join(ROOT, "assets", "icon", "app-icon-1024.png"))
    safe.save(os.path.join(ROOT, "assets", "icon", "app-icon-safe-1024.png"))
    print("masters done")

    # ---- Android mipmap (legacy, from standard) ----
    mip = {"mipmap-mdpi":48, "mipmap-hdpi":72, "mipmap-xhdpi":96, "mipmap-xxhdpi":144, "mipmap-xxxhdpi":192}
    for d, s in mip.items():
        p = os.path.join(ROOT, "android", "app", "src", "main", "res", d, "ic_launcher.png")
        save(standard, p, s)

    # ---- Android adaptive (API 26+) ----
    # foreground 432px (xxxhdpi 108dp*4) from safe master content
    fg_dir = os.path.join(ROOT, "android", "app", "src", "main", "res", "drawable-xxxhdpi")
    os.makedirs(os.path.join(ROOT, "android", "app", "src", "main", "res", "drawable"), exist_ok=True)
    # foregrounds per density from safe master
    fg_map = {"drawable-mdpi":108, "drawable-hdpi":162, "drawable-xhdpi":216, "drawable-xxhdpi":324, "drawable-xxxhdpi":432}
    for d, s in fg_map.items():
        dd = os.path.join(ROOT, "android", "app", "src", "main", "res", d)
        os.makedirs(dd, exist_ok=True)
        save(safe, os.path.join(dd, "ic_launcher_foreground.png"), s)
    # monochrome (themed icon Android 13+): grayscale silhouette on transparent-> use white bg with dark glyph
    mono = safe.convert("L").point(lambda v: 0 if v < 200 else 255, mode="1").convert("RGB")
    # invert to dark glyph on white? For themed icons system tints, provide alpha. Keep simple: dark gray glyph
    for d, s in fg_map.items():
        dd = os.path.join(ROOT, "android", "app", "src", "main", "res", d)
        save(mono, os.path.join(dd, "ic_launcher_monochrome.png"), s)
    # colors + anydpi xml
    values_dir = os.path.join(ROOT, "android", "app", "src", "main", "res", "values")
    with open(os.path.join(values_dir, "ic_launcher_colors.xml"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n')
    anydpi = os.path.join(ROOT, "android", "app", "src", "main", "res", "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background"/>\n    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n</adaptive-icon>\n')
    print("android done")

    # ---- iOS ----
    ios_dir = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    ios_sizes = {"Icon-App-20x20@2x.png":40,"Icon-App-20x20@3x.png":60,"Icon-App-29x29@1x.png":29,"Icon-App-29x29@2x.png":58,"Icon-App-29x29@3x.png":87,"Icon-App-40x40@2x.png":80,"Icon-App-40x40@3x.png":120,"Icon-App-60x60@2x.png":120,"Icon-App-60x60@3x.png":180,"Icon-App-20x20@1x.png":20,"Icon-App-29x29@2x-ipad.png":58,"Icon-App-40x40@1x.png":40,"Icon-App-40x40@2x-ipad.png":80,"Icon-App-76x76@1x.png":76,"Icon-App-76x76@2x.png":152,"Icon-App-83.5x83.5@2x.png":167,"Icon-App-1024x1024@1x.png":1024}
    # map to actual filenames in Contents.json
    name_map = {"Icon-App-20x20@1x.png":20,"Icon-App-20x20@2x.png":40,"Icon-App-20x20@3x.png":60,"Icon-App-29x29@1x.png":29,"Icon-App-29x29@2x.png":58,"Icon-App-29x29@3x.png":87,"Icon-App-40x40@2x.png":80,"Icon-App-40x40@3x.png":120,"Icon-App-60x60@2x.png":120,"Icon-App-60x60@3x.png":180,"Icon-App-76x76@1x.png":76,"Icon-App-76x76@2x.png":152,"Icon-App-83.5x83.5@2x.png":167,"Icon-App-1024x1024@1x.png":1024}
    # ipad extras with same names overwritten - handle explicitly
    for name, s in name_map.items():
        save(standard, os.path.join(ios_dir, name), s)
    # ipad 20@1x=20,29@1x=29,40@1x=40 already covered by same pixel sizes; ensure files exist for Contents.json entries:
    # Contents.json references Icon-App-20x20@1x.png (20), Icon-App-29x29@2x.png etc - all covered.
    print("ios done")

    # ---- Web ----
    web_icons = os.path.join(ROOT, "web", "icons")
    save(standard, os.path.join(web_icons, "Icon-192.png"), 192)
    save(standard, os.path.join(web_icons, "Icon-512.png"), 512)
    save(safe, os.path.join(web_icons, "Icon-maskable-192.png"), 192)
    save(safe, os.path.join(web_icons, "Icon-maskable-512.png"), 512)
    save(standard, os.path.join(ROOT, "web", "favicon.png"), 64)
    print("web done")

    # ---- Windows ico ----
    win_ico = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    # Pillow can save multi-size ico
    sizes = [(16,16),(32,32),(48,48),(256,256)]
    icon_imgs = [standard.resize(s, Image.LANCZOS) for s in sizes]
    icon_imgs[0].save(win_ico, sizes=sizes)
    print("windows done", win_ico)

    # ---- macOS ----
    mac_dir = os.path.join(ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for name, s in {"app_icon_16.png":16,"app_icon_32.png":32,"app_icon_64.png":64,"app_icon_128.png":128,"app_icon_256.png":256,"app_icon_512.png":512,"app_icon_1024.png":1024}.items():
        save(standard, os.path.join(mac_dir, name), s)
    print("macos done")
    print("ALL DONE")

if __name__ == "__main__":
    main()
