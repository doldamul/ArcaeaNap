import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: ossWindow
    width: 880
    height: 860
    minimumWidth: 880
    minimumHeight: 680
    title: "Open Source Licenses"
    color: "#F3F4F8"
    transientParent: null

    property var openSourceItems: []
    property int selectedIndex: openSourceItems.length > 0 ? 0 : -1
    readonly property var selectedItem: (selectedIndex >= 0 && selectedIndex < openSourceItems.length) ? openSourceItems[selectedIndex] : null

    onOpenSourceItemsChanged: {
        selectedIndex = openSourceItems.length > 0 ? 0 : -1
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 14
        radius: 12
        color: "#FFFFFF"
        border.color: "#D9DCE5"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                color: "#F0F2F7"
                border.color: "#D3D8E5"

                ListView {
                    id: ossList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: ossWindow.openSourceItems

                    delegate: Rectangle {
                        required property int index
                        required property var modelData

                        width: ossList.width
                        height: 44
                        color: index === ossWindow.selectedIndex ? "#1499C4" : "#E7E9EE"
                        border.width: 1
                        border.color: index === ossWindow.selectedIndex ? "#0E7FA5" : "#D7DAE2"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            width: parent.width - 20
                            elide: Text.ElideRight
                            text: modelData.name || ""
                            color: index === ossWindow.selectedIndex ? "#FFFFFF" : "#2E2E2E"
                            font.pixelSize: 18
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ossWindow.selectedIndex = index
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#FCFCFD"
                    border.color: "#D7DAE2"

                    ScrollView {
                        id: licenseScroll
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        contentWidth: availableWidth

                        Text {
                            width: licenseScroll.availableWidth
                            text: ossWindow.selectedItem ? (ossWindow.selectedItem.license_text || "") : ""
                            wrapMode: Text.Wrap
                            font.family: "Consolas, Courier New, monospace"
                            font.pixelSize: 15
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 21
                            color: "#222"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    color: "#F8F9FC"
                    border.color: "#D7DAE2"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Text {
                            width: parent.width
                            text: "Copyright Owner: " + (ossWindow.selectedItem ? (ossWindow.selectedItem.copyright || "") : "")
                            font.pixelSize: 16
                            color: "#333"
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            textFormat: Text.RichText
                            text: {
                                const link = ossWindow.selectedItem ? (ossWindow.selectedItem.url || "") : ""
                                return "Library Link: <a href=\"" + link + "\">" + link + "</a>"
                            }
                            font.pixelSize: 16
                            color: "#333"
                            elide: Text.ElideRight
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
            }
        }
    }
}
