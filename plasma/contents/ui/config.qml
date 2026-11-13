import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout

    property alias formLayout: root

    property string cfg_Image
    property alias cfg_Dim: dimSlider.value
    property alias cfg_Position: positionBox.currentIndex

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: "Prayer times, zone, language and reminders are managed by the Waktu Solat panel widget (right-click it → Configure)."
    }

    RowLayout {
        Kirigami.FormData.label: "Background:"
        QQC2.TextField {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            text: root.cfg_Image
            placeholderText: "No image (gradient)"
            onEditingFinished: root.cfg_Image = text
        }
        QQC2.Button {
            icon.name: "document-open"
            text: "Browse…"
            onClicked: fileDialog.open()
        }
        QQC2.Button {
            icon.name: "edit-clear"
            QQC2.ToolTip.text: "Use plain gradient"
            QQC2.ToolTip.visible: hovered
            onClicked: root.cfg_Image = ""
        }
    }

    RowLayout {
        Kirigami.FormData.label: "Dim background:"
        QQC2.Slider {
            id: dimSlider
            from: 0
            to: 80
            stepSize: 5
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }
        QQC2.Label {
            text: dimSlider.value + "%"
        }
    }

    QQC2.ComboBox {
        id: positionBox
        Kirigami.FormData.label: "Position:"
        model: ["Top left", "Left", "Bottom left", "Top right", "Right", "Bottom right"]
    }

    FileDialog {
        id: fileDialog
        title: "Choose background image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif *.svg)"]
        onAccepted: root.cfg_Image = selectedFile.toString()
    }
}
