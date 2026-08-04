import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

FocusScope {
    id: root

    property string mode: "system"
    signal modeRequested(string requestedMode)

    readonly property var options: [
        { mode: "system", label: "System" },
        { mode: "light", label: "Light" },
        { mode: "dark", label: "Dark" }
    ]
    readonly property int selectedIndex: indexForMode(mode)
    readonly property real segmentWidth: 88
    readonly property real innerHeight: 32

    implicitWidth: segmentWidth * options.length + 8
    implicitHeight: innerHeight + 8

    function indexForMode(value) {
        var normalized = String(value || "").toLowerCase()
        for (var i = 0; i < options.length; ++i) {
            if (options[i].mode === normalized)
                return i
        }
        return 0
    }

    function requestIndex(index) {
        var wrapped = (index + options.length) % options.length
        var item = optionRepeater.itemAt(wrapped)
        if (item)
            item.forceActiveFocus()
        modeRequested(options[wrapped].mode)
    }

    function optionChecked(index) {
        var item = optionRepeater.itemAt(index)
        return item ? item.checked : false
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.themeSelectorTrack
    }

    Rectangle {
        id: selectedCapsule
        x: 4 + root.selectedIndex * root.segmentWidth
        y: 4
        width: root.segmentWidth
        height: root.innerHeight
        radius: height / 2
        color: Theme.themeSelectorSelected
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }

    ButtonGroup {
        id: themeButtonGroup
        exclusive: true
    }

    Row {
        x: 4
        y: 4

        Repeater {
            id: optionRepeater
            model: root.options

            delegate: Basic.RadioButton {
                id: optionButton
                required property var modelData
                required property int index

                objectName: "themeOption-" + modelData.mode
                width: root.segmentWidth
                height: root.innerHeight
                text: modelData.label
                checked: root.selectedIndex === index
                hoverEnabled: true
                activeFocusOnTab: index === root.selectedIndex
                focusPolicy: Qt.StrongFocus
                ButtonGroup.group: themeButtonGroup

                indicator: Item {}

                background: Rectangle {
                    radius: height / 2
                    color: (optionButton.hovered || optionButton.activeFocus)
                        && !optionButton.checked
                        ? Theme.themeSelectorHover
                        : Theme.themeSelectorClear

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }

                contentItem: Text {
                    text: optionButton.text
                    color: optionButton.checked
                        ? Theme.themeSelectorTextSelected
                        : Theme.themeSelectorText
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }

                Accessible.role: Accessible.RadioButton
                Accessible.name: text
                Accessible.checked: checked

                onClicked: root.modeRequested(modelData.mode)

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Left) {
                        root.requestIndex(index - 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Right) {
                        root.requestIndex(index + 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return
                               || event.key === Qt.Key_Enter) {
                        root.modeRequested(modelData.mode)
                        event.accepted = true
                    }
                }
            }
        }
    }
}
