#!/usr/bin/env python3
"""Run AFTER `flutter create --platforms=android .` : adds camera/internet permissions,
the app name, cleartext LAN HTTP (for Wi-Fi sync) and the gold JØ launcher icons. Safe to run twice."""
import os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "android", "app", "src", "main", "AndroidManifest.xml")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
ICONS = os.path.join(ROOT, "tools", "icons")

if not os.path.exists(MANIFEST):
    sys.exit("android/ folder not found. Run: flutter create --platforms=android --project-name jo_pos_mobile --org com.joroyalty .")

with open(MANIFEST, "r", encoding="utf-8") as f:
    m = f.read()

perms = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-feature android:name="android.hardware.camera" android:required="false"/>',
    '<uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>',
]
add = "".join("    " + p + "\n" for p in perms if p.split('"')[1] not in m)
if add:
    m = re.sub(r"(<manifest[^>]*>\s*)", lambda g: g.group(1) + "\n" + add, m, count=1)

m = re.sub(r'android:label="[^"]*"', 'android:label="JØ PHARMA MOBILE"', m, count=1)
if "usesCleartextTraffic" not in m:
    m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)

with open(MANIFEST, "w", encoding="utf-8") as f:
    f.write(m)

# mobile_scanner 7.x needs minSdk 23; use 24 (Android 7.0) so the camera library always builds
for gradle in ("build.gradle.kts", "build.gradle"):
    gp = os.path.join(ROOT, "android", "app", gradle)
    if os.path.exists(gp):
        with open(gp, "r", encoding="utf-8") as f:
            g = f.read()

        def _min(mo):
            val = mo.group(3)
            return mo.group(0) if (val.isdigit() and int(val) >= 24) else mo.group(1) + mo.group(2) + "24"

        g2 = re.sub(r"(minSdk(?:Version)?)(\s*=\s*|\s+)(flutter\.minSdkVersion|\d+)", _min, g, count=1)
        if g2 != g:
            with open(gp, "w", encoding="utf-8") as f:
                f.write(g2)
            print("minSdk raised to 24 in", gradle)

for dens in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    src = os.path.join(ICONS, f"ic_launcher_{dens}.png")
    dst_dir = os.path.join(RES, f"mipmap-{dens}")
    if os.path.exists(src) and os.path.isdir(dst_dir):
        shutil.copyfile(src, os.path.join(dst_dir, "ic_launcher.png"))

print("Android project patched: permissions, name, cleartext HTTP, minSdk, icons.")
