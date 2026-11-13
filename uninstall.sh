#!/usr/bin/env bash
# Reverts install.sh: restores the default lock screen wallpaper and removes everything.
set -euo pipefail
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
systemctl --user disable --now solat.timer solat.path solat-notify.service || true
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}"/systemd/user/solat{.service,.timer,.path,-notify.service}
systemctl --user daemon-reload
kpackagetool6 -t Plasma/Wallpaper -r solat.lockscreen || true
kpackagetool6 -t Plasma/Applet -r solat.widget || true
cargo uninstall kde-plasma-solat || true
