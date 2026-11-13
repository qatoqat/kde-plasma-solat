# kde-plasma-solat

Malaysian prayer times from [JAKIM e-solat](https://www.e-solat.gov.my) on the KDE Plasma 6 lock screen and in a panel widget.

<img src="docs/preview.png" width="420" alt="Prayer times panel on the lock screen">

- All 60 JAKIM zones, picked in System Settings
- Gregorian and Hijri dates, with a countdown to the next prayer
- The current prayer is highlighted
- Tap a prayer on the lock screen or in the panel widget to tick it off ✓
- Check marks reset at Imsak, not midnight: the day runs from Imsak to the next Imsak
- Panel widget showing the next prayer and countdown, with the full list in a popup
- Notifications ask "Sudah solat?" when each prayer time starts, and remind you until you mark it done, with a heads-up 10 and 5 minutes before the next prayer time if it is still unticked
- Works offline: about 60 days of times are cached, with a warning if updates stop
- Malay or English, 24h or 12h

## How it works

KWin doesn't support `ext-session-lock`, so this doesn't replace the KDE locker. KDE still does the locking and checks your password. The project has two parts:

- **`solat`** (Rust): downloads the timetable and stores it in `kscreenlockerrc`, sends the notifications, and keeps track of which prayers are done.
- **`solat.lockscreen`** (QML): a Plasma wallpaper plugin used on the lock screen. It draws the panel above the blur that appears when you move the mouse.
- **`solat.widget`** (QML): a Plasma applet for the taskbar. Right-click the panel → Add Widgets → search "Waktu Solat". It reads `solat status`.

## Install

### Arch Linux

```sh
git clone https://github.com/qatoqat/kde-plasma-solat
cd kde-plasma-solat/packaging/arch
makepkg -si
solat setup        # as your user, not root
```

### Other distros (from source)

You need Rust, Plasma 6, `kpackagetool6` and `kwriteconfig6`.

```sh
./install.sh            # installs to ~/.cargo/bin and ~/.local/share
./uninstall.sh          # undo
```

Then open **System Settings → Screen Locking → Configure Appearance…** and pick your zone. The default is PRK02.

## Usage

```
solat show          today's times and check marks
solat done [PRAYER] mark a prayer done (default: the current one)
solat undo PRAYER   unmark it
solat zone [CODE]   print or set the zone
solat sync --force  re-download now
solat status         state as JSON (used by the panel widget)
```

Prayer names: `subuh`, `zohor` (or `jumaat`), `asar`, `maghrib`, `isyak`. English names also work.

These user services are enabled by `solat setup`:

| Unit | Purpose |
| --- | --- |
| `solat.timer` | Daily sync, plus one 30 s after login |
| `solat.path` | Re-sync when the zone changes in System Settings |
| `solat-notify.service` | Prayer notifications and reminders |

Upgrading from `solat-lock`: `solat setup` retires the old units and history is carried over.

Done history is kept in `~/.local/state/solat/done.json`.

## Notes

- Tapping on the lock screen saves your check-off only if `kscreenlocker` is built without its seccomp sandbox, as Arch builds it. With the sandbox, the tick shows but isn't saved.
- Anyone at your locked computer can tick or untick today's prayers. They can't do anything else.

## License

GPL-2.0-or-later
