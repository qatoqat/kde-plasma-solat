import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "../code/zones.js" as Zones

KCM.SimpleKCM {
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

    readonly property var stateNames: Zones.zones.map(z => z.state).filter((v, i, a) => a.indexOf(v) === i)
    readonly property string currentState: {
        const z = Zones.zones.find(z => z.code === cfg_Zone);
        return z ? z.state : stateNames[0];
    }
    readonly property var stateZones: Zones.zones.filter(z => z.state === currentState)
        .map(z => ({ text: z.code + " — " + z.name, code: z.code }))

    Kirigami.FormLayout {
        id: form

        QQC2.ComboBox {
            id: stateBox
            Kirigami.FormData.label: "State:"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            model: page.stateNames
            currentIndex: Math.max(0, page.stateNames.indexOf(page.currentState))
            onActivated: {
                const first = Zones.zones.find(z => z.state === currentText);
                if (first) page.cfg_Zone = first.code;
            }
        }
        QQC2.ComboBox {
            id: zoneBox
            Kirigami.FormData.label: "Zone:"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 28
            model: page.stateZones
            textRole: "text"
            valueRole: "code"
            currentIndex: Math.max(0, page.stateZones.findIndex(z => z.code === page.cfg_Zone))
            onActivated: page.cfg_Zone = currentValue
            popup.width: width
            delegate: QQC2.ItemDelegate {
                required property var modelData
                required property int index
                width: zoneBox.popup.width
                text: modelData.text
                highlighted: zoneBox.highlightedIndex === index
            }
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
}
