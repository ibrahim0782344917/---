#!/usr/bin/env python3
"""Prepare generated Android project for FCM, using a private downloaded config.
Run AFTER flutter create and AFTER setting the exact livepilot applicationId.
No network, no secret logging, no sender credentials.
"""
import argparse
import json
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = "{http://schemas.android.com/apk/res/android}"
ET.register_namespace("android", ANDROID[1:-1])
PROJECT = "alani-store-e3dc9"

def prepare(root, role, config):
    package = f"com.ibrahimalani.shitreed_{role}.livepilot"
    raw = config.read_bytes()
    if len(raw) > 1_000_000:
        raise ValueError("configuration exceeds size limit")
    data = json.loads(raw)
    info = data.get("project_info", {})
    if info.get("project_id") != PROJECT or "private_key" in data or data.get("type") == "service_account":
        raise ValueError("wrong Firebase project or server credentials")
    clients = [c for c in data.get("client", []) if c.get("client_info", {}).get("android_client_info", {}).get("package_name") == package]
    if len(clients) != 1:
        raise ValueError("expected exactly one matching Android client")
    client = clients[0]
    if not str(client.get("client_info", {}).get("mobilesdk_app_id", "")).startswith("1:" + str(info.get("project_number")) + ":android:"):
        raise ValueError("app id mismatch")
    if not any(k.get("current_key") for k in client.get("api_key", [])):
        raise ValueError("missing Android client key")
    android = root / "android"
    settings = android / "settings.gradle.kts"
    app = android / "app" / "build.gradle.kts"
    manifest = android / "app" / "src" / "main" / "AndroidManifest.xml"
    s = settings.read_text(encoding="utf-8")
    a = app.read_text(encoding="utf-8")
    if not re.search(r'applicationId\s*=\s*"' + re.escape(package) + r'"', a):
        raise ValueError("generated applicationId mismatch")
    def plugin(text, declaration):
        if "com.google.gms.google-services" in text:
            if declaration not in text:
                raise ValueError("existing Google services plugin declaration requires review")
            return text
        match = re.search(r"(?m)^plugins\s*\{", text)
        if not match:
            raise ValueError("unexpected generated Gradle plugins block")
        return text[:match.end()] + "\n    " + declaration + text[match.end():]
    s = plugin(s, 'id("com.google.gms.google-services") version "4.4.4" apply false')
    a = plugin(a, 'id("com.google.gms.google-services")')
    # Firebase Messaging requires Android API 23+ with the pinned SDK.
    a = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', a)
    tree = ET.parse(manifest)
    m = tree.getroot()
    application = m.find("application")
    if application is None:
        raise ValueError("Android application manifest missing")
    if not any(e.get(ANDROID+"name") == "android.permission.POST_NOTIFICATIONS" for e in m.findall("uses-permission")):
        m.insert(0, ET.Element("uses-permission", {ANDROID+"name":"android.permission.POST_NOTIFICATIONS"}))
    for name in ("firebase_messaging_auto_init_enabled", "firebase_analytics_collection_enabled"):
        matches = [e for e in application.findall("meta-data") if e.get(ANDROID+"name") == name]
        if len(matches) > 1:
            raise ValueError("duplicate Firebase metadata")
        e = matches[0] if matches else ET.SubElement(application, "meta-data", {ANDROID+"name":name})
        e.set(ANDROID+"value", "false")
    # Only copy the client required for this app, not the other clients.
    config_out = {"project_info":info, "client":[client], "configuration_version":data.get("configuration_version","1")}
    settings.write_text(s, encoding="utf-8")
    app.write_text(a, encoding="utf-8")
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    out = android / "app" / "google-services.json"
    out.write_text(json.dumps(config_out, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"PASS: {role} Android Firebase client prepared; no network test performed")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-root", required=True, type=Path)
    parser.add_argument("--role", choices=("customer", "merchant", "admin"), required=True)
    parser.add_argument("--config", required=True, type=Path)
    args = parser.parse_args()
    prepare(args.app_root, args.role, args.config)

if __name__ == "__main__":
    main()
