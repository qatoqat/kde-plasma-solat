import QtQuick
import org.kde.plasma.plasmoid
import TestHooks

Item {
    id: host

    property int passes: 0
    property int fails: 0
    function check(cond, msg) {
        if (cond) { passes++; } else { fails++; console.log("FAIL: " + msg); }
    }
    function section(name) { console.log("ok  - " + name); }

    readonly property var times: ["05:42", "05:52", "07:00", "13:03", "16:24", "19:00", "20:12"]
    readonly property var months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    readonly property string cfgKey: "--file kscreenlockerrc --group Greeter --group Wallpaper --group solat.lockscreen --group General"

    function iso(d) { return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2); }
    function parseIso(s) { const p = s.split("-"); return new Date(+p[0], +p[1] - 1, +p[2]); }
    function dayList(from, to) {
        const out = [];
        for (let d = parseIso(from); iso(d) <= to; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1))
            out.push({ d: iso(d), h: "1448-06-01", t: times });
        return out;
    }
    function store(zone, from, to) { return JSON.stringify({ zone: zone, fetched: "2026-11-01 08:00", days: dayList(from, to) }); }
    // What e-solat answers for a date range (what `curl` would print).
    function apiJson(from, to) {
        return JSON.stringify({ prayerTime: dayList(from, to).map(x => {
            const p = x.d.split("-");
            return { hijri: x.h, date: p[2] + "-" + months[+p[1] - 1] + "-" + p[0], imsak: times[0] + ":00", fajr: times[1] + ":00",
                     syuruk: times[2] + ":00", dhuhr: times[3] + ":00", asr: times[4] + ":00", maghrib: times[5] + ":00", isha: times[6] + ":00" };
        }) });
    }

    property var comp: null
    property var live: []
    // Fresh config + recorder, then a widget whose clock is `when` (local time).
    function make(when, setup, prayerData) {
        if (live.length > 0) { fails++; console.log("FAIL: test bug: make() called while a previous widget is still alive; use one make() per scenario"); }
        TestHooks.reset();
        Plasmoid.reset();
        const c = Plasmoid.configuration;
        c.prayerData = prayerData !== undefined ? prayerData : store("PRK02", "2026-11-01", "2026-12-31");
        if (setup) setup(c);
        const w = comp.createObject(host, { clockOverride: when, cfg: Plasmoid.configuration });
        live.push(w);
        return w;
    }
    function cleanup() {
        TestHooks.accepting = false;                 // ignore whatever the dying widget does
        for (const w of live) { w.cfg = Plasmoid.inert; w.destroy(); }
        live = [];
    }
    function at(w, when) { w.clockOverride = when; w.now = w.clock(); w.notifyTick(); }
    function titles() { return TestHooks.notifications.map(n => n.title); }
    function lastTitle() { const n = TestHooks.notifications; return n.length ? n[n.length - 1].title : ""; }

    // Answers every pending curl download in order; returns the number answered.
    property int answered: 0
    function answerDownloads(fail) {
        let n = 0;
        for (let guard = 0; guard < 10; guard++) {
            const fetches = TestHooks.cmds("# solatfetch:");
            if (fetches.length <= answered) break;
            const cmd = fetches[answered++];
            const m = /datestart=([0-9-]+)&dateend=([0-9-]+)/.exec(cmd);
            if (fail) TestHooks.runner.newData(cmd, { "exit code": 7, stdout: "", stderr: "Failed to connect" });
            else TestHooks.reply(cmd, apiJson(m[1], m[2]));
            n++;
        }
        return n;
    }

    function setup() {
        comp = Qt.createComponent(Qt.resolvedUrl("contents/ui/main.qml"));
        if (comp.status !== Component.Ready) { check(false, "main.qml failed to load: " + comp.errorString()); return false; }
        return true;
    }

    // changing the zone in settings downloads the new zone right away (regression)
    function scenario0() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T12:00:00");
        check(TestHooks.cmds("# solatfetch:").length === 0, "no download when the cache already covers the next 14 days");
        TestHooks.commands = []; answered = 0;
        Plasmoid.configuration.zone = "WLY01";
        f = TestHooks.cmds("# solatfetch:");
        check(f.length >= 1 && f[0].indexOf("zone=WLY01") >= 0, "zone change starts a download for the new zone");
        check(w.syncing, "widget reports it is downloading");
        check(w.store === null, "old zone's data is not shown for the new zone");
        check(answerDownloads() === 2, "year boundary is split into two downloads");
        saved = JSON.parse(Plasmoid.configuration.prayerData);
        check(saved.zone === "WLY01" && saved.days.length === 62, "new zone's timetable saved (62 days)");
        check(!w.syncing && w.syncError === "", "download finished cleanly");
        check(TestHooks.cmds("--key PrayerData").length === 1 && TestHooks.cmds("--key PrayerData")[0].indexOf("WLY01") > 0,
              "new timetable is mirrored to the lock screen");
        check(TestHooks.cmds("--key Zone 'WLY01'").length >= 1 || TestHooks.cmds("--key Zone").some(c => c.indexOf("'WLY01'") > 0),
              "new zone is mirrored to the lock screen");
        cleanup(); section("zone change downloads and mirrors");
    }

    // cache expiring soon triggers a refresh at startup; year boundary chunks
    function scenario1() {
        let w = null, f = null, saved = null;
        w = make("2026-12-20T12:00:00", null, store("PRK02", "2026-12-01", "2026-12-25"));
        answered = 0;
        f = TestHooks.cmds("# solatfetch:");
        check(f.length === 1 && f[0].indexOf("datestart=2026-12-19&dateend=2026-12-31") > 0, "expiring cache refreshes from yesterday to year end first: " + JSON.stringify(f));
        answerDownloads();
        f = TestHooks.cmds("# solatfetch:");
        check(f.length === 2 && f[1].indexOf("datestart=2027-01-01") > 0, "second chunk starts on 1 January");
        check(JSON.parse(Plasmoid.configuration.prayerData).days.length === 62, "both chunks merged");
        cleanup(); section("year boundary sync");
    }

    // download failure is reported, and nothing is overwritten
    function scenario2() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T12:00:00", null, store("PRK02", "2026-11-01", "2026-11-18"));
        answered = 0;
        answerDownloads(true);
        check(!w.syncing && w.syncError.indexOf("Failed to connect") >= 0, "curl failure surfaces as syncError");
        check(JSON.parse(Plasmoid.configuration.prayerData).days.length === 18, "failed download keeps the old timetable");
        cleanup(); section("failed download");
    }

    // other settings take effect immediately and reach the lock screen
    function scenario3() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T12:00:00");
        TestHooks.commands = [];
        Plasmoid.configuration.english = true;
        check(TestHooks.cmds("--key English --type bool 'true'").length === 1, "English toggle mirrored immediately: " + JSON.stringify(TestHooks.commands));
        Plasmoid.configuration.use12h = true;
        check(TestHooks.cmds("--key Use12h --type bool 'true'").length === 1, "12h toggle mirrored immediately");
        check(w.fmt("16:24") === "4:24 PM", "12h format applies immediately");
        cleanup(); section("language / 12h settings");
    }

    // day runs Imsak to Imsak
    function scenario4() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T02:00:00");
        check(w.day.d === "2026-11-12", "02:00 still belongs to yesterday's prayer day");
        w.setDone(6, true);
        check(w.done.indexOf(6) >= 0, "Isyak ticked after midnight counts for yesterday");
        at(w, "2026-11-13T05:41:00");
        check(w.day.d === "2026-11-12", "one minute before Imsak is still yesterday");
        at(w, "2026-11-13T05:42:00");
        check(w.day.d === "2026-11-13" && w.done.length === 0, "check marks reset at Imsak");
        check(JSON.parse(Plasmoid.configuration.doneJson)["2026-11-12"].join() === "6", "yesterday's ticks are kept");
        check(TestHooks.cmds("--key Done").some(c => c.indexOf('"d":"2026-11-12"') > 0), "lock screen was told about the yesterday tick");
        cleanup(); section("Imsak day boundary");
    }

    // notifications: start, reminder, 10 / 5 minute warnings, done
    function scenario5() {
        let w = null, f = null, saved = null;
        const donePrior = c => { c.doneJson = JSON.stringify({ "2026-11-13": [1, 3] }); };
        w = make("2026-11-13T16:30:00", donePrior);
        check(titles().length === 1 && lastTitle() === "Masuk waktu Asar (16:24)", "Asar start notification (got " + titles().join("|") + ")");
        at(w, "2026-11-13T16:45:00");
        check(titles().length === 1, "no extra notification before the reminder interval");
        at(w, "2026-11-13T17:01:00");
        check(titles().length === 2 && lastTitle() === "Peringatan: Asar", "reminder after 30 minutes");
        check(TestHooks.notifications[0].closed, "previous notification is replaced, not stacked");
        at(w, "2026-11-13T18:49:00");
        check(lastTitle() === "Peringatan: Asar", "reminder, not a warning, until 10 minutes before Maghrib");
        const before = titles().length;
        at(w, "2026-11-13T18:50:00");
        check(titles().length === before + 1 && lastTitle() === "Maghrib dalam 10 minit", "10 minute warning (got " + lastTitle() + ")");
        at(w, "2026-11-13T18:55:00");
        check(lastTitle() === "Maghrib dalam 5 minit", "5 minute warning (got " + lastTitle() + ")");
        const n5 = titles().length;
        at(w, "2026-11-13T18:57:00");
        check(titles().length === n5, "no repeat right after a warning");
        w.setDone(4, true);
        check(TestHooks.notifications[TestHooks.notifications.length - 1].closed, "ticking a prayer closes its notification");
        at(w, "2026-11-13T18:58:00");
        check(titles().length === n5, "nothing more for a prayer that is done");
        at(w, "2026-11-13T19:00:00");
        check(lastTitle() === "Masuk waktu Maghrib (19:00)", "Maghrib start notification");
        w.setDone(5, true);
        at(w, "2026-11-13T20:12:00");
        check(lastTitle() === "Masuk waktu Isyak (20:12)", "Isyak start notification");
        const nI = titles().length;
        at(w, "2026-11-13T20:25:00");
        check(titles().length === nI && titles().every(t => t.indexOf("dalam") < 0 || t.indexOf("Isyak") < 0), "no pre-warning for Isyak");
        at(w, "2026-11-14T00:13:00");
        check(titles().length === nI, "Isyak stops nagging after its window");
        cleanup(); section("notifications");
    }

    // Friday shows Jumaat; English names
    function scenario6() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T13:10:00", c => { c.doneJson = JSON.stringify({ "2026-11-13": [1] }); });
        check(lastTitle() === "Masuk waktu Jumaat (13:03)", "Friday Zohor is called Jumaat (got " + lastTitle() + ")");
        section("friday naming");
    }

    // English notification text
    function scenario6b() {
        let w = null;
        w = make("2026-11-13T16:30:00", c => { c.english = true; c.doneJson = JSON.stringify({ "2026-11-13": [1, 3] }); });
        check(lastTitle() === "Asr time (16:24)" && TestHooks.notifications[0].text === "Have you prayed Asr?", "English notification text");
        section("English text");
    }

    // notifications can be switched off, also while one is showing
    function scenario7() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T16:30:00", c => { c.notify = false; c.doneJson = JSON.stringify({ "2026-11-13": [1, 3] }); });
        check(titles().length === 0, "Notify off sends nothing");
        section("notify off");
    }

    // turning notifications off while one is showing
    function scenario7b() {
        let w = null;
        w = make("2026-11-13T16:30:00", c => { c.doneJson = JSON.stringify({ "2026-11-13": [1, 3] }); });
        check(titles().length === 1, "precondition: one notification showing");
        Plasmoid.configuration.notify = false;
        check(TestHooks.notifications[0].closed, "turning notifications off closes the open one immediately");
        section("notify toggle");
    }

    // notification actions
    function scenario8() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T16:30:00", c => { c.doneJson = JSON.stringify({ "2026-11-13": [1, 3] }); });
        let n = TestHooks.notifications[0];
        n.actions[1].activated();
        check(n.closed, "'remind me later' closes the notification");
        at(w, "2026-11-13T16:40:00");
        check(titles().length === 1, "snoozed: nothing new within the snooze time");
        at(w, "2026-11-13T17:01:00");
        check(titles().length === 2, "snoozed notification comes back");
        TestHooks.notifications[1].actions[0].activated();
        check(w.done.indexOf(4) >= 0, "'prayed' action ticks the prayer");
        cleanup(); section("notification actions");
    }

    // lock screen integration
    function scenario9() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T12:00:00");
        const plug = TestHooks.cmds("WallpaperPlugin")[0];
        TestHooks.reply(plug, "solat.lockscreen\n");
        check(Plasmoid.configuration.lockScreen === true, "setting follows the plugin currently in use");
        check(TestHooks.cmds("kwriteconfig6").every(c => c.indexOf("WallpaperPlugin") < 0), "reading the plugin does not rewrite it");
        Plasmoid.configuration.lockScreen = false;
        check(TestHooks.cmds("--key WallpaperPlugin org.kde.image").length === 1, "turning the option off restores the default lock screen");
        Plasmoid.configuration.lockScreen = true;
        check(TestHooks.cmds("--key WallpaperPlugin solat.lockscreen").length === 1, "turning it on selects the plugin");
        // a tick made on the lock screen is adopted
        const doneCmd = TestHooks.cmds("kreadconfig6").filter(c => c.indexOf("--key Done") > 0)[0];
        TestHooks.reply(doneCmd, '{"d":"2026-11-13","p":[1,3,4]}\n');
        check(w.done.join() === "1,3,4", "ticks made on the lock screen reach the widget");
        TestHooks.reply(doneCmd, '{"d":"2026-11-12","p":[1]}\n');
        check(w.done.join() === "1,3,4", "stale lock screen data for another day is ignored");
        cleanup(); section("lock screen");
    }

    // first run imports the old lock-screen settings and does not clobber them
    function scenario10() {
        let w = null, f = null, saved = null;
        w = make("2026-11-13T12:00:00", c => { c.migrated = false; }, "");
        check(TestHooks.cmds("# Migrate:").length === 5, "reads the five old settings");
        check(TestHooks.cmds("kwriteconfig6").length === 0, "nothing is written to the lock screen before the import finishes: " + JSON.stringify(TestHooks.cmds("kwriteconfig6")));
        const vals = { Zone: "JHR01", English: "true", Use12h: "true", Notify: "false", RemindEvery: "45" };
        for (const cmd of TestHooks.cmds("# Migrate:")) TestHooks.reply(cmd, vals[/Migrate:(\w+)/.exec(cmd)[1]] + "\n");
        const c0 = Plasmoid.configuration;
        check(c0.zone === "JHR01" && c0.english && c0.use12h && !c0.notify && c0.remindEvery === 45, "old settings imported");
        check(c0.migrated, "import is marked done");
        answered = 0;
        check(TestHooks.cmds("# solatfetch:").some(c => c.indexOf("zone=JHR01") > 0), "download starts for the imported zone");
        section("first-run import");
    }

    // empty old config keeps the defaults
    function scenario10b() {
        let w = null;
        w = make("2026-11-13T12:00:00", c => { c.migrated = false; }, "");
        for (const cmd of TestHooks.cmds("# Migrate:")) TestHooks.reply(cmd, "\n");
        check(Plasmoid.configuration.zone === "PRK02" && Plasmoid.configuration.notify, "empty old config keeps the defaults");
        section("empty import");
    }

    // browsing days with the header arrows
    function scenarioNav() {
        let w = make("2026-11-13T12:00:00");
        check(w.viewingToday && w.viewDay.d === "2026-11-13" && w.viewOffset === 0, "starts on the current prayer day");
        check(w.canPrev && w.canNext, "arrows available in the middle of the cache");
        w.shiftView(-1);
        check(w.viewDay.d === "2026-11-12" && !w.viewingToday, "left arrow goes to the previous day");
        w.shiftView(5);
        check(w.viewDay.d === "2026-11-17", "right arrow moves forward");
        check(w.day.d === "2026-11-13", "browsing does not change the current day");
        w.shiftView(-1000);
        check(w.viewDay.d === "2026-11-01" && !w.canPrev && w.canNext, "stops at the first cached day");
        w.shiftView(1000);
        check(w.viewDay.d === "2026-12-31" && w.canPrev && !w.canNext, "stops at the last cached day");
        w.shiftView(-1000);
        w.shiftView(3);
        w.expanded = true; w.expanded = false;
        check(w.viewingToday, "closing the popup returns to today");
        // ticking a past day is saved for that day and does not touch the lock screen's current-day copy
        TestHooks.commands = [];
        w.shiftView(-2);
        w.setDone(4, true, w.viewDay.d);
        check(JSON.parse(Plasmoid.configuration.doneJson)["2026-11-11"].join() === "4", "past day tick saved under its own date");
        check(w.viewDone.join() === "4" && w.done.length === 0, "viewed day shows its ticks, current day unaffected");
        check(TestHooks.cmds("--key Done").filter(c => c.indexOf("kwriteconfig6") === 0).length === 0, "past day tick is not mirrored as today's");
        w.setDone(5, true);
        check(TestHooks.cmds("--key Done").filter(c => c.indexOf("kwriteconfig6") === 0).length === 1, "current day tick is mirrored");
        section("day browsing");
    }

    // resync button
    function scenarioResync() {
        let w = make("2026-11-13T12:00:00");
        check(TestHooks.cmds("# solatfetch:").length === 0, "precondition: cache is fresh");
        w.resync();
        let f = TestHooks.cmds("# solatfetch:");
        check(f.length === 1 && f[0].indexOf("zone=PRK02") > 0, "resync downloads even though the cache is fresh");
        check(w.syncing, "resync shows as busy");
        w.resync();
        check(TestHooks.cmds("# solatfetch:").length === 1, "pressing again while downloading does nothing");
        answered = 0;
        answerDownloads();
        check(!w.syncing && JSON.parse(Plasmoid.configuration.prayerData).fetched !== "2026-11-01 08:00", "last sync time is refreshed");
        section("resync");
    }

    // resync requested from the lock screen
    function scenarioLockResync() {
        let w = make("2026-11-13T12:00:00");
        const cmd = TestHooks.cmds("kreadconfig6").filter(c => c.indexOf("--key ResyncRequest") > 0)[0];
        check(cmd !== undefined, "the widget polls for lock screen resync requests");
        TestHooks.reply(cmd, "100\n");
        check(TestHooks.cmds("# solatfetch:").length === 0, "an old request found at startup is not acted on");
        TestHooks.reply(cmd, "200\n");
        check(TestHooks.cmds("# solatfetch:").length === 1, "a new request from the lock screen starts a download");
        TestHooks.reply(cmd, "200\n");
        check(TestHooks.cmds("# solatfetch:").length === 1, "the same request is not repeated");
        section("lock screen resync");
    }

    property int nextScenario: 0
    readonly property var scenarios: ["scenario0", "scenario1", "scenario2", "scenario3", "scenario4", "scenario5", "scenario6", "scenario6b", "scenario7", "scenario7b", "scenario8", "scenario9", "scenario10", "scenario10b", "scenarioNav", "scenarioResync", "scenarioLockResync"]

    // One scenario per event-loop turn so destroyed widgets are really gone (QML destroy() is
    // deferred) before the next scenario changes the shared config.
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (host.nextScenario === 0 && !host.comp && !host.setup()) { stop(); finish(); return; }
            if (host.nextScenario < host.scenarios.length) {
                const fn = host[host.scenarios[host.nextScenario]];
                host.nextScenario++;
                try { fn(); } catch (e) { host.fails++; console.log("FAIL: exception " + e + "\n" + e.stack); }
                host.cleanup();
                gc();
            } else {
                stop();
                finish();
            }
        }
        function finish() {
            console.log("RESULT passes=" + host.passes + " fails=" + host.fails);
            Qt.exit(host.fails > 0 ? 1 : 0);
        }
    }
}
