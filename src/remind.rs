//! Prayer check-off state and the notification daemon that asks about it.
//!
//! Done prayers are kept in ~/.local/state/solat/done.json, and today's
//! are mirrored into kscreenlockerrc (`Done`) so the lock screen can draw
//! check marks; the lock screen itself cannot write anything.

use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::time::Duration;

use chrono::{DateTime, Local, NaiveDate, NaiveTime, TimeDelta, TimeZone};
use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::Value;

use crate::{load_store, read_cfg, write_cfg, Result};

/// Indices into `Day::t` that are prayers to check off (not Imsak or Syuruk).
pub const PRAYERS: [usize; 5] = [1, 3, 4, 5, 6];

const KEYS: [&[&str]; 7] = [
    &["imsak"],
    &["subuh", "fajr", "suboh"],
    &["syuruk", "sunrise"],
    &["zohor", "zuhur", "dhuhr", "zuhr", "jumaat"],
    &["asar", "asr"],
    &["maghrib"],
    &["isyak", "isha", "isya"],
];
const NAMES_MS: [&str; 7] = ["Imsak", "Subuh", "Syuruk", "Zohor", "Asar", "Maghrib", "Isyak"];
const NAMES_EN: [&str; 7] = ["Imsak", "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"];

pub fn prayer_index(name: &str) -> Result<usize> {
    let name = name.to_ascii_lowercase();
    PRAYERS
        .into_iter()
        .find(|&i| KEYS[i].contains(&name.as_str()))
        .ok_or_else(|| format!("unknown prayer {name:?} (subuh, zohor, asar, maghrib, isyak)"))
}

fn display_name(i: usize, date: NaiveDate, english: bool) -> &'static str {
    use chrono::Datelike;
    if i == 3 && date.weekday() == chrono::Weekday::Fri {
        return if english { "Jumu'ah" } else { "Jumaat" };
    }
    if english { NAMES_EN[i] } else { NAMES_MS[i] }
}

fn english() -> bool {
    read_cfg("English").as_deref() == Some("true")
}

// ---- done state ----

type DoneMap = BTreeMap<String, Vec<usize>>;

fn state_path() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"));
    let path = base.join("solat/done.json");
    // Carry history over from the old name (solat-lock).
    let old = base.join("solat-lock/done.json");
    if !path.exists() && old.exists() {
        let _ = std::fs::create_dir_all(path.parent().unwrap());
        let _ = std::fs::copy(&old, &path);
    }
    path
}

fn load_done_map() -> DoneMap {
    std::fs::read_to_string(state_path()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

pub fn done_on(date: NaiveDate) -> Vec<usize> {
    load_done_map().remove(&date.format("%Y-%m-%d").to_string()).unwrap_or_default()
}

pub fn set_done(date: NaiveDate, idx: usize, done: bool) -> Result<()> {
    let mut map = load_done_map();
    let key = date.format("%Y-%m-%d").to_string();
    let list = map.entry(key.clone()).or_default();
    list.retain(|&i| i != idx);
    if done {
        list.push(idx);
        list.sort_unstable();
    }
    let path = state_path();
    std::fs::create_dir_all(path.parent().unwrap()).map_err(|e| format!("creating state dir: {e}"))?;
    std::fs::write(&path, serde_json::to_string(&map).unwrap()).map_err(|e| format!("writing {path:?}: {e}"))?;
    if date == prayer_day(Local::now()) {
        mirror_today()?;
    }
    Ok(())
}

/// The date a moment belongs to for check-offs. The day starts at Imsak, not
/// midnight, so between midnight and Imsak it is still yesterday's day.
pub fn prayer_day(now: DateTime<Local>) -> NaiveDate {
    let today = now.date_naive();
    let fmt = |d: NaiveDate| d.format("%Y-%m-%d").to_string();
    let yesterday = today - TimeDelta::days(1);
    if let Some(store) = load_store() {
        let imsak = store
            .days
            .iter()
            .find(|d| d.d == fmt(today))
            .and_then(|d| NaiveTime::parse_from_str(&d.t[0], "%H:%M").ok());
        if imsak.is_some_and(|t| now.time() < t) && store.days.iter().any(|d| d.d == fmt(yesterday)) {
            return yesterday;
        }
    }
    today
}

/// Copies the current prayer day's done list into kscreenlockerrc for the lock screen.
pub fn mirror_today() -> Result<()> {
    let today = prayer_day(Local::now());
    let value = serde_json::json!({ "d": today.format("%Y-%m-%d").to_string(), "p": done_on(today) }).to_string();
    if read_cfg("Done").as_deref() != Some(value.as_str()) {
        write_cfg("Done", &value)?;
    }
    Ok(())
}

/// The prayer whose time is currently in effect, or the latest one today.
pub fn latest_prayer(now: DateTime<Local>) -> Result<usize> {
    let today = times_for(prayer_day(now))?;
    PRAYERS
        .into_iter()
        .rev()
        .find(|&i| today[i] <= now)
        .ok_or_else(|| "no prayer time has started yet today".to_string())
}

pub fn times_for(date: NaiveDate) -> Result<[DateTime<Local>; 7]> {
    let store = load_store().ok_or("no cached data yet, run `solat sync` first")?;
    let key = date.format("%Y-%m-%d").to_string();
    let day = store.days.iter().find(|d| d.d == key).ok_or("today is not in the cache, run `solat sync`")?;
    let mut out = [Local::now(); 7];
    for (slot, t) in out.iter_mut().zip(&day.t) {
        let t = NaiveTime::parse_from_str(t, "%H:%M").map_err(|e| format!("bad time {t:?}: {e}"))?;
        *slot = Local.from_local_datetime(&date.and_time(t)).earliest().ok_or("invalid local time")?;
    }
    Ok(out)
}

/// End of the window in which we keep asking about prayer `i`.
fn window_end(i: usize, times: &[DateTime<Local>; 7]) -> DateTime<Local> {
    match i {
        1 => times[2],                          // Subuh ends at Syuruk
        6 => times[6] + TimeDelta::hours(4),    // Isyak: stop nagging late at night
        _ => times[i + 1],
    }
}

// ---- notification daemon ----

const DEST: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";


struct Ask {
    id: u32,
    next: DateTime<Local>,
    /// Pre-deadline warnings already sent: 0 none, 1 at 10 min, 2 at 5 min.
    warn: u8,
}

#[derive(Clone, Copy)]
enum Kind {
    Start,
    Reminder,
    /// The next prayer time is close (level 1 = 10 min, 2 = 5 min).
    Warn(u8),
}

/// Minutes before the end of a prayer's window at which we warn.
const WARN_MINS: [i64; 2] = [10, 5];

fn proxy(conn: &Connection) -> zbus::Result<Proxy<'static>> {
    Proxy::new(conn, DEST, PATH, DEST)
}

/// Forwards notification button clicks as (notification id, action key).
fn listen_actions(conn: Connection, tx: Sender<(u32, String)>) {
    std::thread::spawn(move || -> zbus::Result<()> {
        for msg in proxy(&conn)?.receive_signal("ActionInvoked")? {
            if tx.send(msg.body().deserialize()?).is_err() {
                break;
            }
        }
        Ok(())
    });
}

fn send(p: &Proxy, replaces: u32, i: usize, date: NaiveDate, at: DateTime<Local>, kind: Kind) -> zbus::Result<u32> {
    let en = english();
    let name = display_name(i, date, en);
    let time = at.format("%H:%M");
    let next_name = display_name(if i == 1 { 2 } else { i + 1 }, date, en);
    let reminder = matches!(kind, Kind::Reminder);
    let (summary, body, yes, later) = if en {
        (
            match kind {
                Kind::Warn(l) => format!("{next_name} in {} min", WARN_MINS[l as usize - 1]),
                _ if reminder => format!("Reminder: {name}"),
                _ => format!("{name} time ({time})"),
            },
            format!("Have you prayed {name}?"),
            "Prayed ✓",
            "Remind me later",
        )
    } else {
        (
            match kind {
                Kind::Warn(l) => format!("{next_name} dalam {} minit", WARN_MINS[l as usize - 1]),
                _ if reminder => format!("Peringatan: {name}"),
                _ => format!("Masuk waktu {name} ({time})"),
            },
            format!("Sudah solat {name}?"),
            "Sudah solat ✓",
            "Ingatkan nanti",
        )
    };
    let actions = ["done", yes, "later", later];
    let mut hints: HashMap<&str, Value> = HashMap::new();
    hints.insert("urgency", Value::U8(1));
    p.call("Notify", &("Waktu Solat", replaces, "clock", summary, body, &actions[..], hints, -1i32))
}

fn close(p: &Proxy, id: u32) {
    let _: zbus::Result<()> = p.call("CloseNotification", &(id,));
}

fn remind_every() -> TimeDelta {
    let mins = read_cfg("RemindEvery").and_then(|s| s.parse::<i64>().ok()).unwrap_or(30).clamp(5, 240);
    TimeDelta::minutes(mins)
}

pub fn daemon() -> Result<()> {
    let conn = Connection::session().map_err(|e| format!("D-Bus session: {e}"))?;
    let p = proxy(&conn).map_err(|e| format!("notifications proxy: {e}"))?;
    let (tx, rx) = mpsc::channel();
    listen_actions(conn.clone(), tx);

    let mut asks: HashMap<(NaiveDate, usize), Ask> = HashMap::new();
    let mut mirrored_for = None;
    let mut wait = Duration::ZERO; // check right away on startup
    loop {
        let event = rx.recv_timeout(wait);
        wait = Duration::from_secs(20);
        match event {
            Ok((id, action)) => {
                if let Some((&key, _)) = asks.iter().find(|(_, a)| a.id == id) {
                    match action.as_str() {
                        "done" => {
                            if let Err(e) = set_done(key.0, key.1, true) {
                                eprintln!("solat: {e}");
                            }
                            close(&p, id);
                            asks.remove(&key);
                        }
                        "later" => {
                            asks.get_mut(&key).unwrap().next = Local::now() + remind_every();
                            close(&p, id);
                        }
                        _ => {}
                    }
                }
                continue;
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return Err("lost D-Bus connection".into()),
        }

        let now = Local::now();
        let today = prayer_day(now);
        if mirrored_for != Some(today) && mirror_today().is_ok() {
            mirrored_for = Some(today);
        }
        asks.retain(|k, a| {
            let keep = k.0 == today;
            if !keep {
                close(&p, a.id);
            }
            keep
        });
        if read_cfg("Notify").as_deref() == Some("false") {
            for a in asks.values() {
                close(&p, a.id);
            }
            asks.clear();
            continue;
        }
        let Ok(times) = times_for(today) else { continue };
        let done = done_on(today);
        for i in PRAYERS {
            let key = (today, i);
            if done.contains(&i) || now >= window_end(i, &times) {
                if let Some(a) = asks.remove(&key) {
                    close(&p, a.id);
                }
                continue;
            }
            if now < times[i] {
                continue;
            }
            // Warn shortly before the next prayer time (not for Isyak, whose
            // window just ends late at night).
            let left = window_end(i, &times) - now;
            let level = if i == 6 {
                0
            } else if left <= TimeDelta::minutes(WARN_MINS[1]) {
                2
            } else if left <= TimeDelta::minutes(WARN_MINS[0]) {
                1
            } else {
                0
            };
            let (replaces, kind, warn) = match asks.get(&key) {
                None => (0, if level > 0 { Kind::Warn(level) } else { Kind::Start }, level),
                Some(a) if level > a.warn => (a.id, Kind::Warn(level), level),
                Some(a) if now >= a.next => (a.id, Kind::Reminder, a.warn),
                Some(_) => continue,
            };
            match send(&p, replaces, i, today, times[i], kind) {
                Ok(id) => {
                    asks.insert(key, Ask { id, next: now + remind_every(), warn });
                }
                Err(e) => eprintln!("solat: notify failed: {e}"),
            }
        }
    }
}
