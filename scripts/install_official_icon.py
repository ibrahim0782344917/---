#!/usr/bin/env python3
"""Install the user-provided Shitreed icon in a generated Flutter Android app.

The original upload was 1536x1536; the committed WebP is an optimized
192x192 launcher source. The 512x512 original-quality Play icon is
distributed separately for Play Console upload.
"""
import argparse
import base64
from io import BytesIO
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "assets" / "branding" / "shitreed_official_icon.webp.b64"
ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)

SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def install(android_root: Path) -> None:
    manifest = android_root / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        raise SystemExit("Missing AndroidManifest.xml: run flutter create first.")

    encoded = "".join(ASSET.read_text(encoding="ascii").split())
    data = base64.b64decode(encoded, validate=True)
    with Image.open(BytesIO(data)) as img:
        img.verify()
    with Image.open(BytesIO(data)) as img:
        icon = img.convert("RGBA")
    if icon.size != (192, 192):
        raise SystemExit(f"Unexpected launcher source dimensions: {icon.size}")

    res_root = manifest.parent / "res"
    for density, size in SIZES.items():
        destination = res_root / f"mipmap-{density}"
        destination.mkdir(parents=True, exist_ok=True)
        resized = icon.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(destination / "ic_launcher.png")
        resized.save(destination / "ic_launcher_round.png")

    tree = ET.parse(manifest)
    app = tree.getroot().find("application")
    if app is None:
        raise SystemExit("Missing Android application in manifest")
    app.set(f"{{{ANDROID}}}icon", "@mipmap/ic_launcher")
    app.set(f"{{{ANDROID}}}roundIcon", "@mipmap/ic_launcher_round")
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    print("Installed the same official icon in all five Android densities.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("android_root", type=Path)
    args = parser.parse_args()
    install(args.android_root)
