#!/usr/bin/env bash
# Reverts install.sh: restores the default lock screen wallpaper and removes both packages.
set -euo pipefail
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}"/icons/hicolor/*/apps/kde-plasma-solat.png
kpackagetool6 -t Plasma/Applet -r solat.widget || true
kpackagetool6 -t Plasma/Wallpaper -r solat.lockscreen || true
