#!/usr/bin/env python3
"""Validate Firebase Android client configs for Al-Ani; never print credentials.
Read-only. No network, deployment, token collection or notification send.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROLES = ("customer", "merchant", "admin")

def validate(configs, mode):
    projects = set()
    app_ids = set()
    for role in ROLES:
        data = configs[role]
        if not isinstance(data, dict) or "private_key" in data or data.get("type") == "service_account":
            raise ValueError(f"{role}: Android client configuration required, not server credentials")
        project = data.get("project_info", {})
        project_id = project.get("project_id", "")
        number = str(project.get("project_number", ""))
        if not isinstance(project_id, str) or not re.fullmatch(r"[a-z][a-z0-9-]{4,29}", project_id) or not number.isdecimal():
            raise ValueError(f"{role}: missing or invalid project identity")
        package = f"com.ibrahimalani.shitreed_{role}" + (".livepilot" if mode == "pilot" else "")
        matches = [c for c in data.get("client", []) if c.get("client_info", {}).get("android_client_info", {}).get("package_name") == package]
        if len(matches) != 1:
            raise ValueError(f"{role}: expected exactly one Android client for {package}")
        client = matches[0]
        app_id = client.get("client_info", {}).get("mobilesdk_app_id", "")
        if not isinstance(app_id, str) or not re.fullmatch(r"1:" + re.escape(number) + r":android:[a-fA-F0-9]+", app_id):
            raise ValueError(f"{role}: missing or mismatched Android app ID")
        if not any(isinstance(k.get("current_key"), str) and k["current_key"].strip() for k in client.get("api_key", [])):
            raise ValueError(f"{role}: missing Android client API key")
        if app_id in app_ids:
            raise ValueError("Android app IDs must be distinct")
        projects.add((project_id, number))
        app_ids.add(app_id)
    if len(projects) != 1:
        raise ValueError("All three configs must belong to the same approved Firebase project")
    return True

def self_test():
    def config(role):
        return {"project_info":{"project_id":"alani-synthetic","project_number":"123456789"},
                "client":[{"client_info":{"mobilesdk_app_id":f"1:123456789:android:{ROLES.index(role)+1:012x}",
                    "android_client_info":{"package_name":f"com.ibrahimalani.shitreed_{role}.livepilot"}},
                    "api_key":[{"current_key":"SYNTHETIC-NOT-A-KEY"}]}]}
    configs = {role:config(role) for role in ROLES}
    assert validate(configs, "pilot")
    cases = [
        ("wrong package", lambda c:c.update(admin=config("customer"))),
        ("different project", lambda c:c["admin"]["project_info"].update(project_id="other-synthetic")),
        ("server credential", lambda c:c["admin"].update(type="service_account")),
        ("wrong app ID", lambda c:c["admin"]["client"][0]["client_info"].update(mobilesdk_app_id="1:987:android:aaa")),
        ("missing client key", lambda c:c["merchant"]["client"][0].update(api_key=[])),
        ("duplicate app ID", lambda c:c["admin"]["client"][0]["client_info"].update(mobilesdk_app_id=c["customer"]["client"][0]["client_info"]["mobilesdk_app_id"])),
    ]
    for name, mutate in cases:
        values = {role:config(role) for role in ROLES}
        mutate(values)
        try:
            validate(values, "pilot")
        except ValueError:
            continue
        raise AssertionError(f"Failed to reject {name}")
    print("PASS: matching project + 6 negative synthetic cases")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["pilot", "release"], default="pilot")
    parser.add_argument("--self-test", action="store_true")
    for role in ROLES:
        parser.add_argument("--"+role, type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if any(getattr(args, role) is None for role in ROLES):
        parser.error("Provide --customer, --merchant and --admin client config files")
    try:
        configs = {}
        for role in ROLES:
            path = getattr(args, role)
            if path.stat().st_size > 1_000_000:
                raise ValueError(f"{role}: config exceeds size limit")
            configs[role] = json.loads(path.read_text(encoding="utf-8"))
        validate(configs, args.mode)
        print("PASS: three distinct Android clients in one Firebase project; no network or sending tested")
        return 0
    except (OSError, ValueError, TypeError, AttributeError, KeyError):
        print("FAIL: invalid, missing or mismatched client config; inspect the Firebase console", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
