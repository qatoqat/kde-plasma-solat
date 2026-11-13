#!/usr/bin/env bash
# Installs the widget and lock screen plugin for the current user (no root, no build step).
# On Arch, prefer the package: cd packaging/arch && makepkg -si
set -euo pipefail
cd "$(dirname "$0")"

install_pkg() {  # type dir id
    if kpackagetool6 -t "$1" -s "$3" >/dev/null 2>&1; then
        kpackagetool6 -t "$1" -u "$2"
    else
        kpackagetool6 -t "$1" -i "$2"
    fi
}
install_pkg Plasma/Applet widget solat.widget
install_pkg Plasma/Wallpaper plasma solat.lockscreen
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$icons"
install -m644 icons/kde-plasma-solat.svg "$icons/"
echo "Done. Add 'Waktu Solat' to a panel (right-click the panel → Add Widgets),"
echo "then pick your zone in the widget's settings."
