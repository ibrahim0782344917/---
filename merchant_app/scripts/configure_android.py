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
app = root.find("application")
if app is None:
    raise SystemExit("Generated manifest does not contain application.")
app.set(f"{{{ANDROID_NS}}}label", "شتريد تاجر")
app.set(f"{{{ANDROID_NS}}}icon", "@mipmap/ic_launcher")
tree.write(path, encoding="utf-8", xml_declaration=True)

print("Shitreed Merchant Android manifest configured; official launcher icon is installed separately.")
