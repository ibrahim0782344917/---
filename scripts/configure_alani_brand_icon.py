#!/usr/bin/env python3
"""Create an original botanical Al-Ani Android launcher icon.

Pure Python standard library, deterministic output, no external photos/fonts,
no download/network calls. Run AFTER flutter create generates android/.
"""
from __future__ import annotations

import argparse
import math
import pathlib
import struct
import zlib


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], alpha: float):
    t = max(0.0, min(1.0, alpha))
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def _ellipse(x, y, cx, cy, rx, ry, angle):
    ca, sa = math.cos(angle), math.sin(angle)
    dx, dy = x - cx, y - cy
    u = (dx * ca + dy * sa) / rx
    v = (-dx * sa + dy * ca) / ry
    return u * u + v * v <= 1.0


def _pixel(x: float, y: float):
    # Coordinates 0..1. Evergreen base, warm gold monogram and three leaves.
    r = min(0.08, max(0.0, 0.50 - max(abs(x - .5), abs(y - .5))))
    bx, by = max(abs(x - .5) - (.5 - r), 0), max(abs(y - .5) - (.5 - r), 0)
    if (bx * bx + by * by) ** .5 > r and r:
        return 0, 0, 0, 0
    base = _mix((20, 58, 41), (39, 105, 73), min(1, (x + y) * .50))
    dist = math.hypot((x - .5) * .95, (y - .5) * 1.03)
    if .390 < dist < .405:
        base = (233, 190, 106)
    if .367 < dist < .381:
        base = _mix(base, (218, 185, 115), .50)
    cream = (253, 247, 229)
    gold = (239, 192, 105)
    # Three leaves forming a stylized tree of commerce and nature.
    if _ellipse(x, y, .50, .36, .088, .16, 0):
        base = gold
    if _ellipse(x, y, .38, .48, .078, .155, -math.pi / 4):
        base = cream
    if _ellipse(x, y, .62, .48, .078, .155, math.pi / 4):
        base = cream
    # Slender stem
    if abs(x - .5) <= .012 and .46 < y < .745:
        base = gold
    # Small golden earth/roots at the base
    if .719 < y < .750 and abs(x - .5) < .09 * (1 - (y - .719) / .065):
        base = gold
    return *base, 255


def _png(size: int) -> bytes:
    rows = bytearray()
    for j in range(size):
        rows.append(0)
        y = (j + .5) / size
        for i in range(size):
            rows.extend(_pixel((i + .5) / size, y))
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack("!I", len(data)) + kind + data + struct.pack(
            "!I", zlib.crc32(kind + data) & 0xffffffff)
    header = struct.pack("!2I5B", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 8))
            + chunk(b"IEND", b""))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default=".")
    opts = parser.parse_args()
    root = pathlib.Path(opts.app_dir).resolve()
    android = root / "android/app/src/main/res"
    if not android.is_dir():
        raise SystemExit("Android sources missing. Run flutter create first.")
    for density, px in [
        ("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
        ("xxhdpi", 144), ("xxxhdpi", 192),
    ]:
        folder = android / ("mipmap-" + density)
        folder.mkdir(parents=True, exist_ok=True)
        blob = _png(px)
        (folder / "ic_launcher.png").write_bytes(blob)
        (folder / "ic_launcher_round.png").write_bytes(blob)
    print("Generated original Al-Ani botanical launcher icons; package ID unchanged.")


if __name__ == "__main__":
    main()
