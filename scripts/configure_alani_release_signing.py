#!/usr/bin/env python3
"""Fail-closed signing configuration for generated Flutter Kotlin Gradle builds.
Run inside the selected app directory after flutter create. Never write credentials
into the repository or key.properties; Gradle reads runner environment variables.
"""
import os
import re
from pathlib import Path

required = ("ALANI_KEYSTORE_PATH", "ALANI_STORE_PASSWORD", "ALANI_KEY_ALIAS", "ALANI_KEY_PASSWORD")
if any(not os.environ.get(k) for k in required):
    raise SystemExit("Official upload signing settings are missing.")
if not Path(os.environ["ALANI_KEYSTORE_PATH"]).is_file():
    raise SystemExit("Upload keystore not found.")
path = Path("android/app/build.gradle.kts")
s = path.read_text()
marker = 'signingConfig = signingConfigs.getByName("debug")'
if s.count(marker) != 1 or len(re.findall(r"(?m)^android\s*\{", s)) != 1 or "signingConfigs {" in s:
    raise SystemExit("Unexpected Gradle template; review signing configuration manually.")
config = '''android {
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("ALANI_KEYSTORE_PATH") ?: error("Missing keystore"))
            storePassword = System.getenv("ALANI_STORE_PASSWORD") ?: error("Missing store password")
            keyAlias = System.getenv("ALANI_KEY_ALIAS") ?: error("Missing alias")
            keyPassword = System.getenv("ALANI_KEY_PASSWORD") ?: error("Missing key password")
        }
    }
'''
s = re.sub(r"(?m)^android\s*\{", lambda _: config, s, count=1)
s = s.replace(marker, 'signingConfig = signingConfigs.getByName("release")')
path.write_text(s)
print("Official upload signing configured; no credentials printed.")
