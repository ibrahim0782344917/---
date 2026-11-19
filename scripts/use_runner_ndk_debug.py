#!/usr/bin/env python3
"""Select an already-installed Android NDK for a customer DEBUG preview build.

Flutter 3.47 defaults to NDK 28.2.13676358, which GitHub hosted runners
may not have. Gradle then downloads ~GB of NDK as part of the build and
a transient network truncation ("Premature EOF") can fail the job.

This script patches ONLY the generated Android project in CI.
Do not use it for Play Store release/AAB builds: those should use
Flutter's default/current NDK and verify 16 KB page-size compatibility.
"""
import os
from pathlib import Path
import re

project = Path("android/app/build.gradle.kts")
if not project.is_file():
    raise SystemExit("Missing generated android/app/build.gradle.kts")

candidates = []
for env in ("ANDROID_NDK_ROOT", "ANDROID_NDK_HOME", "ANDROID_NDK"):
    value = os.environ.get(env)
    if value:
        candidates.append(Path(value))
for env in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
    value = os.environ.get(env)
    if value:
        base = Path(value) / "ndk"
        if base.is_dir():
            candidates.extend(base.iterdir())

versions = []
for location in candidates:
    props = location / "source.properties"
    if not props.is_file():
        continue
    match = re.search(r"(?m)^Pkg\.Revision\s*=\s*(\d+(?:\.\d+)+)\s*$", props.read_text())
    if match:
        version = match.group(1)
        if re.fullmatch(r"\d+(?:\.\d+)+", version):
            versions.append((tuple(int(x) for x in version.split(".")), version, location))

if not versions:
    raise SystemExit(
        "No complete preinstalled NDK. Check the GitHub hosted runner image."
    )

_, version, ndk_path = max(versions, key=lambda item: item[0])
original = project.read_text()
needle = "ndkVersion = flutter.ndkVersion"
if original.count(needle) != 1:
    raise SystemExit("Unexpected Flutter Gradle template: ndkVersion anchor missing")
modified = original.replace(needle, f'ndkVersion = "{version}"')
project.write_text(modified)

print(f"Debug preview uses preinstalled NDK {version}: {ndk_path}")
print("Play/AAB release must use the Flutter default NDK and be validated separately.")
