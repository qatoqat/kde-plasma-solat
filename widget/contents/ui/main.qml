import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.notification
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support

import "../code/logic.js" as Logic

// Self-contained prayer-times widget: downloads JAKIM e-solat times, tracks
// check-offs (the day runs Imsak to Imsak), sends reminders, and feeds the
// lock screen plugin through kscreenlockerrc. No external program is needed.
PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration
    readonly property string api: "https://www.e-solat.gov.my/index.php?r=esolatApi/TakwimSolat&period=duration&zone="
    // Tests drive time through clockOverride; production always uses the real clock.
    property var clockOverride: null
    function clock() { return clockOverride ? new Date(clockOverride) : new Date(); }
    property date now: clock()
    property bool syncing: false
    property string syncError: ""

    // ---- data ----
    readonly property var store: {
        try {
            const s = JSON.parse(cfg.PrayerData);
            return s && s.zone === cfg.Zone ? s : null;
        } catch (e) {
            return null;
        }
    }
    readonly property int dayIdx: Logic.dayIndex(store, now)
    readonly property var day: dayIdx >= 0 ? store.days[dayIdx] : null
    readonly property var nextDay: dayIdx >= 0 && dayIdx + 1 < store.days.length ? store.days[dayIdx + 1] : null
    readonly property var doneMap: {
        try { return JSON.parse(cfg.DoneJson) || {}; } catch (e) { return {}; }
    }
    readonly property var done: day && doneMap[day.d] ? doneMap[day.d] : []
    readonly property bool english: cfg.English
    readonly property string fetched: store ? store.fetched : ""

    readonly property var keys: ["", "subuh", "", "zohor", "asar", "maghrib", "isyak"]
    readonly property var namesMs: ["Imsak", "Subuh", "Syuruk", "Zohor", "Asar", "Maghrib", "Isyak"]
    readonly property var namesEn: ["Imsak", "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    readonly property var monthsMs: ["Januari", "Februari", "Mac", "April", "Mei", "Jun", "Julai", "Ogos", "September", "Oktober", "November", "Disember"]
    readonly property var daysMs: ["Ahad", "Isnin", "Selasa", "Rabu", "Khamis", "Jumaat", "Sabtu"]

    function toDate(d, hhmm) { return Logic.toDate(d, hhmm); }
    function nameOf(i, d) {
        if (i === 3 && toDate(d, "00:00").getDay() === 5) return english ? "Jumu'ah" : "Jumaat";
        return (english ? namesEn : namesMs)[i];
    }
    function fmt(hhmm) {
        if (!cfg.Use12h) return hhmm;
        const t = hhmm.split(":"), h = +t[0];
        return ((h + 11) % 12 + 1) + ":" + t[1] + (h < 12 ? " AM" : " PM");
    }
    function startedAt(i) { return toDate(day.d, day.t[i]) <= now; }
    // "2026-10-08 20:55" -> formatted with the system locale.
    function fetchedText(f) {
        const m = /^(\d+)-(\d+)-(\d+) (\d+):(\d+)/.exec(f);
        if (!m) return f;
        return Qt.formatDateTime(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]), Qt.locale(), Locale.ShortFormat);
    }

    // Next prayer (Imsak not counted): { index, at, d, hhmm }
    readonly property var next: {
        if (!day) return null;
        for (let i = 1; i < 7; i++) {
            const at = toDate(day.d, day.t[i]);
            if (at > now) return { index: i, at: at, d: day.d, hhmm: day.t[i] };
        }
        return nextDay ? { index: 1, at: toDate(nextDay.d, nextDay.t[1]), d: nextDay.d, hhmm: nextDay.t[1] } : null;
    }
    readonly property int current: {
        if (!day) return -1;
        let idx = -1;
        for (let i = 1; i < 7; i++) if (startedAt(i)) idx = i;
        return idx === 2 ? -1 : idx;
    }
    readonly property string countdown: {
        if (!next) return "";
        const mins = Math.max(0, Math.ceil((next.at - now) / 60000));
        const h = Math.floor(mins / 60), m = mins % 60;
        if (h === 0) return m + " min";
        return h + (english ? " h " : " j ") + m + " min";
    }
    // Current prayer started but not ticked: nudge in the compact view.
    readonly property bool pending: current > 0 && keys[current] !== "" && done.indexOf(current) < 0

    Plasmoid.icon: "kde-plasma-solat"
    toolTipMainText: next ? nameOf(next.index, next.d) + " " + fmt(next.hhmm) : "Waktu Solat"
    toolTipSubText: next ? (english ? "in " : "dalam ") + countdown : ""

    // Pinned = popup stays open when it loses focus (same as the System Tray).
    property bool pinned: false
    hideOnWindowDeactivate: !pinned

    // ---- check-offs ----
    function setDone(i, value, dayKey) {
        const key = dayKey || (day ? day.d : "");
        if (!key) return;
        const map = Object.assign({}, doneMap);
        const list = (map[key] || []).filter(p => p !== i);
        if (value) list.push(i);
        list.sort();
        map[key] = list;
        cfg.DoneJson = JSON.stringify(Logic.pruneDone(map, Logic.isoDate(clock()), 60));
        writeLock("Done", JSON.stringify({ d: key, p: list }));
        if (value) dropAsk(key + ":" + i);
    }

    // ---- shell access (kwriteconfig6 / kreadconfig6 / systemsettings) ----
    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf("# solatfetch:") > 0)
                root.curlDone(source, data);
            else if (source.indexOf("kreadconfig6") === 0 && source.indexOf("--key Done") > 0)
                root.adoptLockScreenDone((data["stdout"] || "").trim());
            else if (source.indexOf("kreadconfig6") === 0 && source.indexOf("# Migrate:") > 0)
                root.adoptOld(source, (data["stdout"] || "").trim());
            else if (source.indexOf("kreadconfig6") === 0 && source.indexOf("WallpaperPlugin") > 0)
                root.adoptLockPlugin((data["stdout"] || "").trim());
        }
    }
    readonly property string lockGroup: "--file kscreenlockerrc --group Greeter --group Wallpaper --group solat.lockscreen --group General"
    property var mirrored: ({})
    function writeLock(key, value, type) {
        const v = String(value);
        if (mirrored[key] === v) return;
        mirrored[key] = v;
        runner.connectSource("kwriteconfig6 " + lockGroup + " --key " + key + (type ? " --type " + type : "") + " " + Logic.shellQuote(v));
    }
    function mirrorDone() {
        if (day) writeLock("Done", JSON.stringify({ d: day.d, p: done }));
    }
    function mirrorAll() {
        if (cfg.PrayerData !== "") writeLock("PrayerData", cfg.PrayerData);
        writeLock("Zone", cfg.Zone);
        writeLock("English", cfg.English, "bool");
        writeLock("Use12h", cfg.Use12h, "bool");
        mirrorDone();
    }
    // The lock screen can tick prayers itself; pick that up if it changed.
    function pollLockScreen() {
        runner.connectSource("kreadconfig6 " + lockGroup + " --key Done");
    }
    function adoptLockScreenDone(value) {
        if (!value || value === mirrored["Done"] || !day) return;
        try {
            const d = JSON.parse(value);
            if (d.d === day.d && Array.isArray(d.p)) {
                mirrored["Done"] = value;
                const map = Object.assign({}, doneMap);
                map[d.d] = d.p;
                cfg.DoneJson = JSON.stringify(map);
            }
        } catch (e) {}
    }

    // Lock screen plugin on/off follows the "Show on lock screen" setting.
    property string lockPlugin: ""
    property bool lockKnown: false
    function adoptLockPlugin(value) {
        lockPlugin = value || "org.kde.image";
        lockKnown = true;
        const on = lockPlugin === "solat.lockscreen";
        if (cfg.LockScreen !== on) cfg.LockScreen = on;
    }
    // Watch config values through plain properties: their change signals fire
    // reliably when the settings dialog applies, unlike the config map's own.
    readonly property string watchZone: cfg.Zone
    readonly property string watchData: cfg.PrayerData
    readonly property bool watchEnglish: cfg.English
    readonly property bool watchUse12h: cfg.Use12h
    readonly property bool watchLock: cfg.LockScreen
    readonly property bool watchNotify: cfg.Notify
    onWatchZoneChanged: if (cfg.Migrated) sync(false)
    onWatchDataChanged: if (cfg.Migrated) mirrorAll()
    onWatchEnglishChanged: if (cfg.Migrated) mirrorAll()
    onWatchUse12hChanged: if (cfg.Migrated) mirrorAll()
    onWatchNotifyChanged: notifyTick()
    onWatchLockChanged: {
        if (!lockKnown || (lockPlugin === "solat.lockscreen") === cfg.LockScreen) return;
        lockPlugin = cfg.LockScreen ? "solat.lockscreen" : "org.kde.image";
        runner.connectSource("kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin " + lockPlugin);
        if (cfg.LockScreen) mirrorAll();
    }

    // ---- downloading ----
    // XMLHttpRequest first; if it stalls or fails (seen with broken IPv6 routes),
    // fall back to curl through the executable engine.
    property bool useCurl: false
    property var curlJobs: ({})
    property int curlSeq: 0
    function fetchViaCurl(zone, start, end, ok, fail) {
        const id = ++curlSeq;
        curlJobs[id] = { ok: ok, fail: fail };
        runner.connectSource("curl -sS -m 30 -X POST -d " + Logic.shellQuote("datestart=" + start + "&dateend=" + end)
            + " " + Logic.shellQuote(api + zone) + " # solatfetch:" + id);
    }
    function curlDone(source, data) {
        const id = /solatfetch:(\d+)/.exec(source)[1];
        const job = curlJobs[id];
        delete curlJobs[id];
        if (!job) return;
        if (data["exit code"] !== 0) { job.fail("curl: " + ((data["stderr"] || "").trim() || "exit " + data["exit code"])); return; }
        try { job.ok(Logic.parseApi(data["stdout"])); } catch (e) { job.fail(String(e)); }
    }
    function fetchRange(zone, start, end, ok, fail) {
        if (useCurl) { fetchViaCurl(zone, start, end, ok, fail); return; }
        const xhr = new XMLHttpRequest();
        let finished = false;
        const fallback = reason => {
            if (finished) return;
            finished = true;
            xhrWatchdog.stop();
            useCurl = true;
            try { xhr.abort(); } catch (e) {}
            fetchViaCurl(zone, start, end, ok, fail);
        };
        xhrWatchdog.handler = () => fallback("stalled");
        xhrWatchdog.restart();
        xhr.open("POST", api + zone);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || finished) return;
            if (xhr.status !== 200) { fallback("HTTP " + xhr.status); return; }
            let days;
            try { days = Logic.parseApi(xhr.responseText); } catch (e) { fallback(String(e)); return; }
            finished = true;
            xhrWatchdog.stop();
            ok(days);
        };
        xhr.send("datestart=" + start + "&dateend=" + end);
    }
    Timer {
        id: xhrWatchdog
        property var handler: null
        interval: 15000
        onTriggered: if (handler) handler()
    }
    function sync(force) {
        if (syncing || !cfg.Migrated) return;
        const zone = cfg.Zone, today = Logic.isoDate(clock());
        let cur = null;
        try { cur = JSON.parse(cfg.PrayerData); } catch (e) {}
        if (!force && Logic.covers(cur, zone, today, 14)) return;
        syncing = true;
        const chunks = Logic.yearChunks(Logic.addDays(today, -1), Logic.addDays(today, 60));
        let all = [];
        const fail = err => { syncing = false; syncError = err; retryTimer.restart(); };
        const step = k => {
            if (k >= chunks.length) {
                const n = clock();
                cfg.PrayerData = JSON.stringify({ zone: zone, fetched: Logic.isoDate(n) + " " + Logic.pad(n.getHours()) + ":" + Logic.pad(n.getMinutes()), days: all });
                syncing = false;
                syncError = "";
                if (cfg.Zone !== zone) sync(false); // zone changed while downloading
                return;
            }
            fetchRange(zone, chunks[k][0], chunks[k][1], days => { all = all.concat(days); step(k + 1); }, fail);
        };
        step(0);
    }
    Timer { id: retryTimer; interval: 300000; onTriggered: root.sync(false) }
    Timer { interval: 3600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.sync(false) }

    // ---- notifications ----
    property var asks: ({})   // "date:index" -> { notif, next: Date, warn }
    Component {
        id: notifComp
        Notification {
            id: n
            property int idx: 0
            property string dayKey: ""
            componentName: "plasma_workspace"
            eventId: "notification"
            iconName: "clock"
            flags: Notification.Persistent
            actions: [
                NotificationAction {
                    label: root.english ? "Prayed ✓" : "Sudah solat ✓"
                    onActivated: root.setDone(n.idx, true, n.dayKey)
                },
                NotificationAction {
                    label: root.english ? "Remind me later" : "Ingatkan nanti"
                    onActivated: root.snooze(n.dayKey + ":" + n.idx)
                }
            ]
        }
    }
    function snooze(key) {
        const a = asks[key];
        if (!a) return;
        a.next = new Date(clock().getTime() + Math.max(5, Math.min(240, cfg.RemindEvery)) * 60000);
        if (a.notif) a.notif.close();
    }
    function dropAsk(key) {
        const a = asks[key];
        if (!a) return;
        if (a.notif) { a.notif.close(); a.notif.destroy(); }
        delete asks[key];
    }
    function sendAsk(key, i, d, kind, level, warn) {
        const old = asks[key];
        if (old && old.notif) { old.notif.close(); old.notif.destroy(); }
        const name = nameOf(i, d);
        const nextName = nameOf(i === 1 ? 2 : i + 1, d);
        const mins = level === 1 ? 10 : 5;
        const time = fmt(day.t[i]);
        const n = notifComp.createObject(root, {
            idx: i,
            dayKey: d,
            title: kind === "warn" ? (english ? nextName + " in " + mins + " min" : nextName + " dalam " + mins + " minit")
                 : kind === "reminder" ? (english ? "Reminder: " + name : "Peringatan: " + name)
                 : (english ? name + " time (" + time + ")" : "Masuk waktu " + name + " (" + time + ")"),
            text: english ? "Have you prayed " + name + "?" : "Sudah solat " + name + "?"
        });
        n.sendEvent();
        asks[key] = { notif: n, next: new Date(clock().getTime() + Math.max(5, Math.min(240, cfg.RemindEvery)) * 60000), warn: warn };
    }
    function notifyTick() {
        if (!day) return;
        const nowD = clock();
        for (const key in asks) if (key.indexOf(day.d + ":") !== 0) dropAsk(key);
        if (!cfg.Notify) { for (const key in asks) dropAsk(key); return; }
        for (const i of [1, 3, 4, 5, 6]) {
            const key = day.d + ":" + i;
            const end = Logic.windowEnd(day, i);
            if (done.indexOf(i) >= 0 || nowD >= end) { dropAsk(key); continue; }
            if (nowD < toDate(day.d, day.t[i])) continue;
            const level = Logic.warnLevel(end - nowD, i);
            const a = asks[key];
            if (!a) sendAsk(key, i, day.d, level > 0 ? "warn" : "start", level, level);
            else if (level > a.warn) sendAsk(key, i, day.d, "warn", level, level);
            else if (nowD >= a.next) sendAsk(key, i, day.d, "reminder", level, a.warn);
        }
    }
    Timer {
        interval: 20000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.notifyTick()
    }

    Timer { interval: 15000; running: true; repeat: true; onTriggered: root.now = root.clock() }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: { root.pollLockScreen(); if (root.cfg.Migrated) root.mirrorAll(); } }
    // One-time import of Zone, language, 12h and reminder settings that earlier
    // versions kept in the lock screen config, so upgrading changes nothing.
    property int migrating: 0
    function migrate() {
        const keys = ["Zone", "English", "Use12h", "Notify", "RemindEvery"];
        migrating = keys.length;
        for (const k of keys)
            runner.connectSource("kreadconfig6 " + lockGroup + " --key " + k + " --default '' # Migrate:" + k);
    }
    function adoptOld(source, value) {
        const key = /Migrate:(\w+)/.exec(source)[1];
        if (value !== "") {
            if (key === "Zone" && /^[A-Z]{3}[0-9]{2}$/.test(value)) cfg.Zone = value;
            else if (key === "English") cfg.English = value === "true";
            else if (key === "Use12h") cfg.Use12h = value === "true";
            else if (key === "Notify") cfg.Notify = value !== "false";
            else if (key === "RemindEvery" && !isNaN(+value)) cfg.RemindEvery = Math.max(5, Math.min(240, +value));
        }
        if (--migrating === 0) {
            cfg.Migrated = true;
            sync(false);
            mirrorAll();
        }
    }
    Component.onCompleted: {
        runner.connectSource("kreadconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin");
        if (cfg.Migrated) mirrorAll(); else migrate();
        pollLockScreen();
    }

    // ---- views ----
    compactRepresentation: MouseArea {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === 3 // Plasmoid.Vertical
        Layout.minimumWidth: vertical ? 0 : row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        onClicked: root.expanded = !root.expanded
        hoverEnabled: true

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                // Symbolic {8/2} star shipped inside the widget, recoloured to the panel text colour.
                source: Qt.resolvedUrl("../images/solat-symbolic.svg")
                isMask: true
                color: Kirigami.Theme.textColor
                visible: compact.vertical || !root.next
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredWidth: Layout.preferredHeight
            }
            PlasmaComponents3.Label {
                visible: !compact.vertical && root.next !== null
                text: root.next ? root.nameOf(root.next.index, root.next.d) + " " + root.countdown + (root.pending ? " ●" : "") : ""
                font.weight: root.pending ? Font.Bold : Font.Normal
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: implicitHeight
        spacing: 0

        PlasmaExtras.PlasmoidHeading {
            Layout.fillWidth: true
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing
                PlasmaExtras.Heading {
                    level: 1
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (root.english ? "Prayer Times" : "Waktu Solat") + " · " + root.cfg.Zone
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "applications-internet"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: root.english ? "Open e-solat.gov.my" : "Buka e-solat.gov.my"
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    onClicked: Qt.openUrlExternally("https://www.e-solat.gov.my")
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "configure"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: root.english ? "Settings" : "Tetapan"
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    onClicked: {
                        const a = Plasmoid.internalAction("configure");
                        if (a) a.trigger();
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "window-pin"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    checkable: true
                    checked: root.pinned
                    onToggled: root.pinned = checked
                    text: root.english ? "Keep Open" : "Kekalkan terbuka"
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                visible: root.day !== null
                opacity: 0.7
                text: root.day ? root.daysMs[root.toDate(root.day.d, "00:00").getDay()] + ", " + (+root.day.d.split("-")[2]) + " "
                      + root.monthsMs[+root.day.d.split("-")[1] - 1] + " " + root.day.d.split("-")[0] : ""
            }

            Repeater {
                model: root.day ? 7 : 0
                delegate: Rectangle {
                    id: item
                    required property int index
                    readonly property bool isCurrent: root.current === index
                    readonly property bool started: root.startedAt(index)
                    readonly property bool isDone: root.done.indexOf(index) >= 0
                    readonly property bool checkable: root.keys[index] !== "" && started
                    Layout.fillWidth: true
                    implicitHeight: Kirigami.Units.gridUnit * 2
                    radius: Kirigami.Units.cornerRadius
                    color: isCurrent ? Qt.alpha(Kirigami.Theme.highlightColor, 0.18) : "transparent"
                    border.color: isCurrent ? Kirigami.Theme.highlightColor : "transparent"

                    MouseArea {
                        anchors.fill: parent
                        enabled: item.checkable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setDone(item.index, !item.isDone)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: root.nameOf(item.index, root.day.d)
                            font.weight: item.isCurrent ? Font.Bold : Font.Normal
                            opacity: item.started && !item.isCurrent ? 0.5 : 1
                        }
                        PlasmaComponents3.Label {
                            text: root.fmt(root.day.t[item.index])
                            font.weight: item.isCurrent ? Font.Bold : Font.Normal
                            font.features: { "tnum": 1 }
                            opacity: item.started && !item.isCurrent ? 0.5 : 1
                        }
                        PlasmaComponents3.Label {
                            Layout.preferredWidth: Kirigami.Units.gridUnit
                            horizontalAlignment: Text.AlignRight
                            color: Kirigami.Theme.highlightColor
                            font.weight: Font.Bold
                            text: item.isDone ? "✓" : (item.checkable ? "○" : "")
                            opacity: item.isDone ? 1 : 0.5
                        }
                    }
                }
            }
            PlasmaComponents3.Label {
                visible: root.next !== null
                Layout.topMargin: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.highlightColor
                font.weight: Font.DemiBold
                text: root.next ? root.nameOf(root.next.index, root.next.d) + (root.english ? " in " : " dalam ") + root.countdown : ""
            }
            PlasmaComponents3.Label {
                visible: root.fetched !== ""
                Layout.topMargin: Kirigami.Units.smallSpacing
                opacity: 0.6
                font: Kirigami.Theme.smallFont
                text: (root.english ? "Last updated: " : "Waktu kemaskini: ") + root.fetchedText(root.fetched)
            }
            PlasmaComponents3.Label {
                visible: root.day === null
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.syncError !== "" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                text: root.syncing ? (root.english ? "Downloading prayer times…" : "Memuat turun waktu solat…")
                    : root.syncError !== "" ? (root.english ? "Could not download times: " : "Gagal memuat turun: ") + root.syncError
                    : (root.english ? "No prayer times yet." : "Tiada data waktu solat.")
            }
        }
    }
}
