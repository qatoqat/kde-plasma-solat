import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support

// Panel widget: compact view shows the next prayer, the popup lists the day
// and lets you tick prayers off. State comes from `solat status` (JSON), so it
// shares the cache, check marks and Imsak-to-Imsak day with the lock screen.
PlasmoidItem {
    id: root

    property var st: null
    property date now: new Date()
    readonly property bool english: st ? st.english : false
    readonly property var day: st ? st.day : null
    readonly property var done: st ? st.done : []

    readonly property var keys: ["", "subuh", "", "zohor", "asar", "maghrib", "isyak"]
    readonly property var namesMs: ["Imsak", "Subuh", "Syuruk", "Zohor", "Asar", "Maghrib", "Isyak"]
    readonly property var namesEn: ["Imsak", "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    readonly property var monthsMs: ["Januari", "Februari", "Mac", "April", "Mei", "Jun", "Julai", "Ogos", "September", "Oktober", "November", "Disember"]
    readonly property var daysMs: ["Ahad", "Isnin", "Selasa", "Rabu", "Khamis", "Jumaat", "Sabtu"]

    function toDate(d, hhmm) {
        const p = d.split("-"), t = hhmm.split(":");
        return new Date(+p[0], +p[1] - 1, +p[2], +t[0], +t[1]);
    }
    // "2026-10-08 20:55" -> formatted with the system locale (date and time).
    function fetchedText(f) {
        const m = /^(\d+)-(\d+)-(\d+) (\d+):(\d+)/.exec(f);
        if (!m) return f;
        return Qt.formatDateTime(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]), Qt.locale(), Locale.ShortFormat);
    }
    function isFri(d) { return toDate(d, "00:00").getDay() === 5; }
    function nameOf(i, d) {
        if (i === 3 && isFri(d)) return english ? "Jumu'ah" : "Jumaat";
        return (english ? namesEn : namesMs)[i];
    }
    function fmt(hhmm) {
        if (!st || !st.use12h) return hhmm;
        const t = hhmm.split(":"), h = +t[0];
        return ((h + 11) % 12 + 1) + ":" + t[1] + (h < 12 ? " AM" : " PM");
    }
    function startedAt(i) { return toDate(day.d, day.t[i]) <= now; }

    // Next prayer (Imsak not counted): { index, at, d }
    readonly property var next: {
        if (!day) return null;
        for (let i = 1; i < 7; i++) {
            const at = toDate(day.d, day.t[i]);
            if (at > now) return { index: i, at: at, d: day.d };
        }
        const n = st.next;
        return n ? { index: 1, at: toDate(n.d, n.t[1]), d: n.d } : null;
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
        if (h === 0) return m + (english ? " min" : " min");
        return h + (english ? " h " : " j ") + m + " min";
    }
    // Current prayer started but not ticked: nudge in the compact view.
    readonly property bool pending: current > 0 && keys[current] !== "" && done.indexOf(current) < 0

    Plasmoid.icon: "clock"
    toolTipMainText: next ? nameOf(next.index, next.d) + " " + Qt.formatTime(next.at, "HH:mm") : "Waktu Solat"
    toolTipSubText: next ? (english ? "in " : "dalam ") + countdown : ""

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf(" status") >= 0 && data["exit code"] === 0) {
                try { root.st = JSON.parse(data["stdout"]); } catch (e) {}
            } else if (source.indexOf(" status") < 0 && source.indexOf("systemsettings") < 0) {
                root.refresh();
            }
        }
    }
    readonly property string bin: 'PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH" solat'
    function refresh() { runner.connectSource(bin + " status"); }
    function setDone(i, value) {
        const list = done.filter(p => p !== i);
        if (value) list.push(i);
        st = Object.assign({}, st, { done: list });
        runner.connectSource(bin + (value ? " done " : " undo ") + keys[i]);
    }

    Timer { interval: 15000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    onExpandedChanged: if (expanded) refresh()

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
                source: "clock"
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

    // Pinned = popup stays open when it loses focus (same as the System Tray).
    property bool pinned: false
    hideOnWindowDeactivate: !pinned

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
                    text: (root.english ? "Prayer Times" : "Waktu Solat") + (root.st ? " · " + root.st.zone : "")
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "internet-web-browser"
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
                    // Zone, language, 12h and reminders live in Screen Locking → Configure Appearance.
                    onClicked: {
                        runner.connectSource("systemsettings kcm_screenlocker");
                        root.expanded = false;
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
            visible: root.st !== null && !!root.st.fetched
            Layout.topMargin: Kirigami.Units.smallSpacing
            opacity: 0.6
            font: Kirigami.Theme.smallFont
            text: root.st ? (root.english ? "Last updated: " : "Waktu kemaskini: ") + root.fetchedText(root.st.fetched) : ""
        }
        PlasmaComponents3.Label {
            visible: root.day === null
            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.negativeTextColor
            text: "Tiada data / no data. Run: solat sync"
        }
        }
    }
}
