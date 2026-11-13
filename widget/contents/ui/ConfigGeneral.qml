import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../code/zones.js" as Zones

Kirigami.FormLayout {
    id: page

    property string cfg_Zone
    property string cfg_ZoneDefault
    property alias cfg_English: englishBox.checked
    property alias cfg_Use12h: use12hBox.checked
    property alias cfg_Notify: notifyBox.checked
    property alias cfg_RemindEvery: remindBox.value
    property alias cfg_LockScreen: lockBox.checked
    property bool cfg_EnglishDefault
    property bool cfg_Use12hDefault
    property bool cfg_NotifyDefault
    property int cfg_RemindEveryDefault
    property bool cfg_LockScreenDefault
    property string cfg_PrayerData
    property string cfg_PrayerDataDefault
    property string cfg_DoneJson
    property string cfg_DoneJsonDefault

    QQC2.ComboBox {
        Kirigami.FormData.label: "Zone:"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        model: Zones.zones.map(z => ({ text: z.code + " — " + z.state + ": " + z.name, code: z.code }))
        textRole: "text"
        valueRole: "code"
        currentIndex: Zones.zones.findIndex(z => z.code === page.cfg_Zone)
        onActivated: page.cfg_Zone = currentValue
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: "Times are downloaded from e-solat.gov.my automatically when the zone changes."
    }

    QQC2.CheckBox {
        id: englishBox
        Kirigami.FormData.label: "Display:"
        text: "English prayer names"
    }
    QQC2.CheckBox {
        id: use12hBox
        text: "12-hour times"
    }

    QQC2.CheckBox {
        id: notifyBox
        Kirigami.FormData.label: "Notifications:"
        text: "Ask whether I have prayed, and warn 10 and 5 minutes before the next prayer"
    }
    RowLayout {
        Kirigami.FormData.label: "Remind every:"
        enabled: notifyBox.checked
        QQC2.SpinBox {
            id: remindBox
            from: 5
            to: 240
            stepSize: 5
        }
        QQC2.Label { text: "minutes, until marked done or the prayer time ends" }
    }

    QQC2.CheckBox {
        id: lockBox
        Kirigami.FormData.label: "Lock screen:"
        text: "Show prayer times on the lock screen"
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: "Needs the Waktu Solat lock screen plugin (solat.lockscreen). Its background and position are set in System Settings → Screen Locking → Appearance."
    }
}
