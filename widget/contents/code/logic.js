.pragma library

// Pure helpers (no QML/Plasma access) so they can be unit-tested with Node.

function pad(n) { return n < 10 ? "0" + n : "" + n; }
function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
function toDate(day, hhmm) {
    var p = day.split("-"), t = hhmm.split(":");
    return new Date(+p[0], +p[1] - 1, +p[2], +t[0], +t[1]);
}
function addDays(iso, n) {
    var p = iso.split("-");
    return isoDate(new Date(+p[0], +p[1] - 1, +p[2] + n));
}

var MONTHS = { jan: 1, feb: 2, mac: 3, mar: 3, apr: 4, mei: 5, may: 5, jun: 6, jul: 7,
               ogos: 8, ogo: 8, aug: 8, sep: 9, okt: 10, oct: 10, nov: 11, dis: 12, dec: 12 };

// "08-Okt-2026" (Malay or English month) -> "2026-10-08", null if unparseable.
function parseApiDate(s) {
    var p = String(s).split("-");
    if (p.length !== 3) return null;
    var m = MONTHS[p[1].toLowerCase()];
    if (!m || isNaN(+p[0]) || isNaN(+p[2])) return null;
    return p[2] + "-" + pad(m) + "-" + pad(+p[0]);
}

function hhmm(s) { return String(s).substring(0, 5); }

// e-solat TakwimSolat JSON response -> [{ d, h, t: [imsak, fajr, syuruk, dhuhr, asr, maghrib, isha] }]
function parseApi(text) {
    var j = JSON.parse(text);
    if (!j.prayerTime || !j.prayerTime.length)
        throw new Error("no prayer times returned (status: " + j.status + ")");
    return j.prayerTime.map(function (a) {
        var d = parseApiDate(a.date);
        if (!d) throw new Error("bad date " + a.date);
        return { d: d, h: a.hijri, t: [a.imsak, a.fajr, a.syuruk, a.dhuhr, a.asr, a.maghrib, a.isha].map(hhmm) };
    });
}

// The API rejects ranges crossing a year boundary, so split per year.
function yearChunks(start, end) {
    var out = [], from = start;
    while (from <= end) {
        var yearEnd = from.substring(0, 4) + "-12-31";
        var to = end < yearEnd ? end : yearEnd;
        out.push([from, to]);
        from = addDays(to, 1);
    }
    return out;
}

function covers(store, zone, today, minAhead) {
    if (!store || !store.days || !store.days.length || store.zone !== zone) return false;
    return store.days[0].d <= today && store.days[store.days.length - 1].d >= addDays(today, minAhead);
}

// Index into store.days of the current prayer day. The day runs from Imsak to
// the next Imsak, so between midnight and Imsak it is still yesterday's.
function dayIndex(store, now) {
    if (!store || !store.days) return -1;
    var key = isoDate(now), real = -1;
    for (var i = 0; i < store.days.length; i++) {
        if (store.days[i].d === key) { real = i; break; }
    }
    if (real < 0) return -1;
    if (real > 0 && toDate(store.days[real].d, store.days[real].t[0]) > now) return real - 1;
    return real;
}

// End of the window in which prayer i (index into t) can still be done.
function windowEnd(day, i) {
    if (i === 1) return toDate(day.d, day.t[2]);                                   // Subuh ends at Syuruk
    if (i === 6) return new Date(toDate(day.d, day.t[6]).getTime() + 4 * 3600000); // Isyak: stop late at night
    return toDate(day.d, day.t[i + 1]);
}

// 0 = none, 1 = within 10 min of the next prayer time, 2 = within 5 min. Not for Isyak.
function warnLevel(leftMs, i) {
    if (i === 6) return 0;
    if (leftMs <= 5 * 60000) return 2;
    if (leftMs <= 10 * 60000) return 1;
    return 0;
}

function pruneDone(map, today, keepDays) {
    var cutoff = addDays(today, -keepDays), out = {};
    for (var k in map) if (k >= cutoff) out[k] = map[k];
    return out;
}

function shellQuote(v) { return "'" + String(v).replace(/'/g, "'\\''") + "'"; }
