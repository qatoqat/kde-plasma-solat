import fs from "node:fs";
import assert from "node:assert/strict";
const src = fs.readFileSync(new URL("./contents/code/logic.js", import.meta.url), "utf8").replace(/^\.pragma library/, "");
const L = new Function(src + "; return {pad,isoDate,toDate,addDays,parseApiDate,parseApi,yearChunks,covers,dayIndex,windowEnd,warnLevel,pruneDone,shellQuote};")();

assert.equal(L.parseApiDate("08-Okt-2026"), "2026-10-08");
assert.equal(L.parseApiDate("1-Mac-2026"), "2026-03-01");
assert.equal(L.parseApiDate("x"), null);
assert.deepEqual(L.yearChunks("2026-12-20", "2027-01-10"), [["2026-12-20", "2026-12-31"], ["2027-01-01", "2027-01-10"]]);
assert.deepEqual(L.yearChunks("2026-11-01", "2026-12-31"), [["2026-11-01", "2026-12-31"]]);
const days = L.parseApi(JSON.stringify({ prayerTime: [
  { hijri: "1448-06-03", date: "13-Nov-2026", imsak: "05:42:00", fajr: "05:52:00", syuruk: "07:00:00", dhuhr: "13:03:00", asr: "16:24:00", maghrib: "19:00:00", isha: "20:12:00" },
  { hijri: "1448-06-04", date: "14-Nov-2026", imsak: "05:42:00", fajr: "05:52:00", syuruk: "07:01:00", dhuhr: "13:03:00", asr: "16:25:00", maghrib: "19:00:00", isha: "20:12:00" }]}));
assert.equal(days[0].d, "2026-11-13"); assert.deepEqual(days[0].t, ["05:42","05:52","07:00","13:03","16:24","19:00","20:12"]);
assert.throws(() => L.parseApi('{"status":"error"}'));
const store = { zone: "PRK02", days: [{ d: "2026-11-12", t: days[0].t }, days[0], days[1]] };
// Imsak boundary: 02:00 on the 13th still belongs to the 12th; 05:42 starts the 13th.
assert.equal(L.dayIndex(store, new Date(2026, 10, 13, 2, 0)), 0);
assert.equal(L.dayIndex(store, new Date(2026, 10, 13, 5, 41)), 0);
assert.equal(L.dayIndex(store, new Date(2026, 10, 13, 5, 42)), 1);
assert.equal(L.dayIndex(store, new Date(2026, 10, 13, 23, 59)), 1);
assert.equal(L.dayIndex(store, new Date(2026, 10, 20, 12, 0)), -1);
// First cached day, before Imsak: no previous day, fall back to itself.
assert.equal(L.dayIndex({ days: [days[0]] }, new Date(2026, 10, 13, 1, 0)), 0);
assert.equal(L.windowEnd(days[0], 1).getHours(), 7);
assert.equal(L.windowEnd(days[0], 4).getHours(), 19);
assert.equal(L.windowEnd(days[0], 6).getHours(), 0 + 0 || 0, "isha+4h = 00:12 next day");
assert.equal(L.warnLevel(11 * 60000, 4), 0); assert.equal(L.warnLevel(10 * 60000, 4), 1);
assert.equal(L.warnLevel(5 * 60000, 4), 2); assert.equal(L.warnLevel(1, 6), 0);
assert.equal(L.covers({ zone: "A", days: [{ d: "2026-11-12" }, { d: "2026-12-07" }] }, "A", "2026-11-13", 14), true);
assert.equal(L.covers({ zone: "A", days: [{ d: "2026-11-12" }, { d: "2026-11-20" }] }, "A", "2026-11-13", 14), false);
assert.equal(L.covers(store, "WLY01", "2026-11-13", 0), false);
assert.deepEqual(L.pruneDone({ "2026-01-01": [1], "2026-11-12": [3] }, "2026-11-13", 60), { "2026-11-12": [3] });
assert.equal(L.shellQuote("a'b"), "'a'\\''b'");
console.log("logic tests passed");
