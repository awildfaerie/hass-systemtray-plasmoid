import QtQuick 2.15
import QtQuick.Controls 2.15 as Controls
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root

    property var entity: ({})
    property bool showName: true
    property bool cameraStreamActive: false
    property bool cameraStreamLoading: false
    property bool cameraStreamEnabled: false
    signal valueRequested(var value)
    signal cameraStreamRequested()

    spacing: 6

    Controls.Label {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: root.showName
        text: root.entity.name || root.entity.entityId || i18n("Entity")
        font.bold: true
        wrapMode: Text.WordWrap
    }

    Controls.Label {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: root.entity.available
              ? root.entity.state + (root.entity.unit && root.entity.controlType === ""
                                     ? " " + root.entity.unit : "")
              : i18n("Unavailable")
        wrapMode: Text.WordWrap
        opacity: 0.8
    }

    Controls.Switch {
        id: toggleControl
        Layout.fillWidth: true
        visible: root.entity.canToggle
        enabled: root.entity.available
        text: checked ? i18n("On") : i18n("Off")
        onToggled: root.valueRequested(checked)

        Binding {
            target: toggleControl
            property: "checked"
            value: root.entity.domain === "cover"
                   ? root.entity.state !== "closed"
                   : root.entity.domain === "media_player"
                     ? root.entity.state === "playing"
                     : root.entity.state === "on"
            when: !toggleControl.down
        }
    }

    Controls.Button {
        Layout.fillWidth: true
        visible: root.entity.controlType === "button"
        enabled: root.entity.available
        text: root.entity.actionLabel || i18n("Activate")
        onClicked: root.valueRequested("press")
    }

    Controls.Button {
        Layout.fillWidth: true
        visible: root.entity.controlType === "camera"
        enabled: root.cameraStreamActive
                 || (root.entity.available && root.cameraStreamEnabled)
        text: root.cameraStreamLoading
              ? i18n("Cancel stream")
              : root.cameraStreamActive ? i18n("Stop stream") : i18n("View stream")
        onClicked: root.cameraStreamRequested()
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.entity.controlType === "number"

        Controls.TextField {
            id: numberField
            Layout.fillWidth: true
            enabled: root.entity.available
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
                bottom: root.entity.minimum
                top: root.entity.maximum
                notation: DoubleValidator.StandardNotation
            }
            text: Number(root.entity.value).toString()
            onEditingFinished: {
                if (acceptableInput) {
                    root.valueRequested(Number(text))
                }
            }

            Binding {
                target: numberField
                property: "text"
                value: Number(root.entity.value).toString()
                when: !numberField.activeFocus
            }
        }

        Controls.Label {
            visible: root.entity.unit !== ""
            text: root.entity.unit
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.entity.controlType === "slider"

        Controls.Slider {
            id: sliderControl
            Layout.fillWidth: true
            enabled: root.entity.available
            from: root.entity.minimum
            to: root.entity.maximum
            value: root.entity.value
            onPressedChanged: {
                if (!pressed) {
                    root.valueRequested(value)
                }
            }

            Binding {
                target: sliderControl
                property: "value"
                value: root.entity.value
                when: !sliderControl.pressed
            }
        }

        Controls.Label {
            text: Number(root.entity.value).toLocaleString(Qt.locale(), "f", 1)
                  + (root.entity.unit ? " " + root.entity.unit : "")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.entity.controlType === "dial"

        Controls.Dial {
            id: dialControl
            Layout.alignment: Qt.AlignHCenter
            enabled: root.entity.available
            from: root.entity.minimum
            to: root.entity.maximum
            value: root.entity.value
            onPressedChanged: {
                if (!pressed) {
                    root.valueRequested(value)
                }
            }

            Binding {
                target: dialControl
                property: "value"
                value: root.entity.value
                when: !dialControl.pressed
            }
        }

        Controls.Label {
            text: Number(root.entity.value).toLocaleString(Qt.locale(), "f", 1)
                  + (root.entity.unit ? " " + root.entity.unit : "")
        }
    }

}
