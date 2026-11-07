#!/usr/bin/env python3
"""Prepare the generated Flutter Android manifest for Shitreed maps.

Run after flutter create. A Google Maps key is intentionally supplied by
GitHub Actions secret GOOGLE_MAPS_API_KEY, not embedded in source control.
If unset, the app shows an honest setup screen and offers Google Maps externally.
"""
import os
from pathlib import Path
from xml.etree import ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)
key_name = f"{{{ANDROID_NS}}}name"
key_value = f"{{{ANDROID_NS}}}value"

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.is_file():
    raise SystemExit("Run flutter create before configuring the maps manifest.")

tree = ET.parse(manifest)
root = tree.getroot()
existing = {node.get(key_name) for node in root.findall("uses-permission")}
for permission in (
    "android.permission.INTERNET",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
):
    if permission not in existing:
        root.insert(0, ET.Element("uses-permission", {key_name: permission}))

application = root.find("application")
if application is None:
    raise SystemExit("AndroidManifest is missing the application element.")

metadata = None
for node in application.findall("meta-data"):
    if node.get(key_name) == "com.google.android.geo.API_KEY":
        metadata = node
        break
if metadata is None:
    metadata = ET.SubElement(application, "meta-data")
metadata.set(key_name, "com.google.android.geo.API_KEY")
metadata.set(key_value, os.getenv("GOOGLE_MAPS_API_KEY", "").strip() or "MAPS_KEY_NOT_CONFIGURED")

tree.write(manifest, encoding="utf-8", xml_declaration=True)
print("Google Maps Android metadata prepared. Key present: " +
      ("yes" if os.getenv("GOOGLE_MAPS_API_KEY", "").strip() else "no"))
