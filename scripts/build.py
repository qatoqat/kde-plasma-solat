#!/usr/bin/env python3
"""Builds dist/solat.widget.plasmoid and dist/solat.lockscreen.plasmoid (zip archives
with metadata.json at the root, as the KDE Store and kpackagetool6 expect)."""
import os
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "dist")
SKIP = {"test-logic.mjs"}

os.makedirs(OUT, exist_ok=True)
for src, name in [("widget", "solat.widget.plasmoid"), ("plasma", "solat.lockscreen.plasmoid")]:
    out = os.path.join(OUT, name)
    base = os.path.join(ROOT, src)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for d, _, files in sorted(os.walk(base)):
            for f in sorted(files):
                if f in SKIP:
                    continue
                p = os.path.join(d, f)
                z.write(p, os.path.relpath(p, base))
    print(out)
