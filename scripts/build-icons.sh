#!/usr/bin/env bash
# Renders icons/kde-plasma-solat.svg to the PNG sizes installed into the hicolor theme.
set -euo pipefail
cd "$(dirname "$0")/.."
for size in 16 22 24 32 48 64 128 256 512; do
    mkdir -p "icons/png/${size}x${size}"
    rsvg-convert -w "$size" -h "$size" icons/kde-plasma-solat.svg -o "icons/png/${size}x${size}/kde-plasma-solat.png"
done
