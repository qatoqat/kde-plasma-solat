pragma Singleton
import QtQuick

QtObject {
    id: self
    property int formFactor: 0
    function internalAction(name) { return null; }
    // Mirrors contents/config/main.xml (first letter lower-cased: QML cannot declare capitalised
    // properties, so run.py lower-cases `cfg.Key` in its copy of main.qml too).
    property QtObject configuration: QtObject {
        property string zone: "PRK02"
        property bool english: false
        property bool use12h: false
        property bool notify: true
        property int remindEvery: 30
        property bool lockScreen: false
        property bool migrated: true
        property string prayerData: ""
        property string doneJson: "{}"
    }
    // Finished widgets are switched onto this so later config changes do not reach them.
    property QtObject inert: QtObject {
        property string zone: "PRK02"
        property bool english: false
        property bool use12h: false
        property bool notify: false
        property int remindEvery: 30
        property bool lockScreen: false
        property bool migrated: false
        property string prayerData: ""
        property string doneJson: "{}"
    }
    function reset() {
        const c = configuration;
        c.zone = "PRK02"; c.english = false; c.use12h = false; c.notify = true; c.remindEvery = 30;
        c.lockScreen = false; c.migrated = true; c.prayerData = ""; c.doneJson = "{}";
    }
}
