#!/usr/bin/env python3
"""Create a self-contained green/gold Al-Ani launcher emblem with stdlib PNG.

Run after 'flutter create' inside each app. No online fonts/assets, no secrets,
no changes to packageName. The detailed previously designed art remains a
separate marketing asset; this simpler vector-like mark works at icon scale.
"""
from __future__ import annotations
import math
import struct
import sys
import zlib
from pathlib import Path
from xml.etree import ElementTree as ET

APP_NAMES = {
    "customer": "السيد إبراهيم العاني",
    "merchant": "السيد إبراهيم العاني - التاجر",
    "admin": "السيد إبراهيم العاني - الإدارة",
}
RESOLUTIONS = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)


def rounded(x, y, cx, cy, w, h, radius):
    dx = max(abs(x - cx) - (w / 2 - radius), 0)
    dy = max(abs(y - cy) - (h / 2 - radius), 0)
    return dx * dx + dy * dy <= radius * radius and abs(x - cx) <= w / 2 and abs(y - cy) <= h / 2


def leaf(x, y, cx, cy, angle, rx, ry):
    dx, dy = x - cx, y - cy
    ca, sa = math.cos(angle), math.sin(angle)
    px, py = dx * ca + dy * sa, -dx * sa + dy * ca
    return (px / rx) ** 2 + (py / ry) ** 2 <= 1


def pixel(x, y):
    green, pine, gold = (5, 76, 47), (15, 113, 72), (232, 184, 69)
    ivory, amber, olive = (255, 250, 234), (213, 123, 23), (93, 143, 39)
    if not rounded(x, y, 0.5, 0.5, 0.98, 0.98, 0.20):
        return (0, 0, 0, 0)
    rgb = green
    if rounded(x, y, 0.5, 0.5, 0.95, 0.95, 0.18): rgb = gold
    if rounded(x, y, 0.5, 0.5, 0.88, 0.88, 0.17): rgb = green
    if rounded(x, y, 0.5, 0.5, 0.81, 0.81, 0.16): rgb = ivory
    # Shop awning and alternating fabric stripes.
    if rounded(x,y,0.5,0.36,0.72,0.19,0.04): rgb = green
    if rounded(x,y,0.5,0.32,0.74,0.12,0.03): rgb = gold
    if 0.18 < x < 0.82 and 0.30 < y < 0.40:
        if int((x-0.18)/0.107) % 2 == 0: rgb = ivory
        else: rgb = pine
    if rounded(x,y,0.5,0.445,0.65,0.04,0.015): rgb = gold
    # Honey jar with a rim and golden honey.
    if rounded(x,y,0.37,0.64,0.24,0.26,0.035): rgb = amber
    if rounded(x,y,0.37,0.54,0.29,0.042,0.018): rgb = gold
    if rounded(x,y,0.37,0.67,0.17,0.14,0.03): rgb = (246, 192, 78)
    # Stylized olive-oil bottle.
    if rounded(x,y,0.65,0.625,0.18,0.29,0.055): rgb = olive
    if rounded(x,y,0.65,0.455,0.065,0.075,0.015): rgb = pine
    if rounded(x,y,0.65,0.515,0.13,0.036,0.012): rgb = gold
    if rounded(x,y,0.65,0.70,0.10,0.10,0.035): rgb = gold
    # Olive leaves frame the lower design.
    for cx,cy,angle in [(0.24,0.73,-0.7),(0.18,0.65,-0.2),(0.78,0.73,0.7),(0.82,0.63,0.25)]:
        if leaf(x,y,cx,cy,angle,0.058,0.022): rgb = pine
    if rounded(x,y,0.5,0.83,0.48,0.035,0.016): rgb = gold
    return (*rgb, 255)


def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(
        ">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def png(size):
    rows = bytearray()
    for j in range(size):
        rows.append(0)  # PNG filter none.
        for i in range(size):
            rows.extend(pixel((i+0.5)/size, (j+0.5)/size))
    return (b"\x89PNG\r\n\x1a\n" +
        chunk(b"IHDR", struct.pack(">IIBBBBB", size,size,8,6,0,0,0)) +
        chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


def configure(app_path: Path, app_kind: str):
    if app_kind not in APP_NAMES:
        raise ValueError("Expected customer, merchant or admin")
    manifest = app_path / "android/app/src/main/AndroidManifest.xml"
    if not manifest.is_file():
        raise FileNotFoundError("Run flutter create before configuring launcher")
    tree = ET.parse(manifest)
    application = tree.getroot().find("application")
    if application is None:
        raise RuntimeError("Missing Android application")
    application.set("{"+ANDROID_NS+"}label", APP_NAMES[app_kind])
    application.set("{"+ANDROID_NS+"}icon", "@mipmap/ic_launcher")
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    res = app_path / "android/app/src/main/res"
    for density, size in RESOLUTIONS.items():
        target = res / ("mipmap-"+density) / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(png(size))
    print("Generated Al-Ani launcher icon and brand label for "+app_kind)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: configure_alani_icon.py APP_PATH customer|merchant|admin")
    configure(Path(sys.argv[1]), sys.argv[2])
