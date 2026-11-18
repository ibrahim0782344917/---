#!/usr/bin/env python3
"""Build-time ONLY Android release signing setup for generated Flutter projects.

Never commit a keystore or passwords. Set the required GitHub Actions secrets.
Fail closed on missing/invalid secrets or unexpected Gradle template changes.
"""
from __future__ import annotations

import base64
import binascii
import os
import pathlib
import sys


def main() -> None:
    required = (
        "ANDROID_UPLOAD_KEYSTORE_BASE64",
        "ANDROID_UPLOAD_STORE_PASSWORD",
        "ANDROID_UPLOAD_KEY_ALIAS",
        "ANDROID_UPLOAD_KEY_PASSWORD",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise SystemExit("Release signing secrets are incomplete. No bundle created.")

    root = pathlib.Path.cwd()
    android = root / "android"
    config = android / "app" / "build.gradle.kts"
    if not config.is_file():
        raise SystemExit("Expected Flutter Android Kotlin Gradle template is missing.")

    source = config.read_text(encoding="utf-8")
    debug_signing = 'signingConfig = signingConfigs.getByName("debug")'
    release_signing = 'signingConfig = signingConfigs.getByName("release")'
    if source.count(debug_signing) != 1 or source.count("    buildTypes {") != 1:
        raise SystemExit("Unexpected signing Gradle template; refusing unsafe release build.")
    if 'create("release")' in source:
        raise SystemExit("Release signing already configured; refusing a duplicate block.")

    try:
        binary = base64.b64decode(
            os.environ["ANDROID_UPLOAD_KEYSTORE_BASE64"], validate=True
        )
    except (binascii.Error, ValueError):
        raise SystemExit("Invalid base64 keystore data.") from None
    if len(binary) < 64 or len(binary) > 5 * 1024 * 1024:
        raise SystemExit("Keystore size is invalid.")
    keystore = android / "upload-keystore.jks"
    with keystore.open("wb") as handle:
        os.chmod(keystore, 0o600)
        handle.write(binary)

    signing_block = """    signingConfigs {
        create("release") {
            storeFile = file("../upload-keystore.jks")
            storePassword = System.getenv("ANDROID_UPLOAD_STORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_UPLOAD_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_UPLOAD_KEY_PASSWORD")
        }
    }
    buildTypes {"""
    output = source.replace("    buildTypes {", signing_block, 1)
    output = output.replace(debug_signing, release_signing, 1)
    config.write_text(output, encoding="utf-8")
    print("Android release signing configured from environment secrets.")


if __name__ == "__main__":
    main()
