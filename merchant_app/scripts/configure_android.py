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
# Foreground-only location, requested after a merchant taps "use my location".
# No background location or foreground-service location permission.
for permission in (
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
):
    if permission not in permissions:
        root.insert(0, ET.Element("uses-permission", {name_attr: permission}))
app = root.find("application")
if app is None:
    raise SystemExit("Generated manifest does not contain application.")
app.set(f"{{{ANDROID_NS}}}label", "شتريد تاجر")
app.set(f"{{{ANDROID_NS}}}icon", "@drawable/shitreed_merchant_icon")
tree.write(path, encoding="utf-8", xml_declaration=True)

# Keep the launcher icon separate from the customer app and from Flutter's
# default logo. Android vectors are supported on the Flutter min SDK.
icon_file = Path("android/app/src/main/res/drawable/shitreed_merchant_icon.xml")
icon_file.parent.mkdir(parents=True, exist_ok=True)
icon_file.write_text(
    """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#51159B"
        android:pathData="M14,0 L94,0 Q108,0 108,14 L108,94 Q108,108 94,108 L14,108 Q0,108 0,94 L0,14 Q0,0 14,0 Z"/>
    <path android:fillColor="#FF8C22"
        android:pathData="M24,36 L84,36 L90,52 L18,52 Z"/>
    <path android:fillColor="#FFFFFF"
        android:pathData="M28,54 L80,54 L80,87 L28,87 Z"/>
    <path android:fillColor="#51159B"
        android:pathData="M45,65 L63,65 L63,87 L45,87 Z"/>
    <path android:fillColor="#F6D7FF"
        android:pathData="M31,62 L41,62 L41,76 L31,76 Z M67,62 L77,62 L77,76 L67,76 Z"/>
    <path android:fillColor="#FFFFFF"
        android:pathData="M16,52 L92,52 L87,60 L21,60 Z"/>
</vector>
""",
    encoding="utf-8",
)
print("Shitreed Merchant Android manifest and branded launcher icon configured.")
