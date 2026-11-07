#!/usr/bin/env python3
"""Ensure generated Android release/debug manifests allow Supabase HTTPS calls."""
from pathlib import Path
from xml.etree import ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)
name_attr = f"{{{ANDROID_NS}}}name"

path = Path("android/app/src/main/AndroidManifest.xml")
if not path.exists():
    raise SystemExit("Missing AndroidManifest.xml. Run flutter create first.")

tree = ET.parse(path)
root = tree.getroot()
permissions = {item.get(name_attr) for item in root.findall("uses-permission")}
internet = "android.permission.INTERNET"
if internet not in permissions:
    root.insert(0, ET.Element("uses-permission", {name_attr: internet}))
tree.write(path, encoding="utf-8", xml_declaration=True)
print("Android internet permission configured for Supabase.")
