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
    color: Theme.bgWindow
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
        color: Theme.bgCard
        border.color: Theme.borderCard

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                color: Theme.bgWindow
                border.color: Theme.borderCard

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
                        color: index === ossWindow.selectedIndex ? Theme.accent : Theme.bgHover
                        border.width: 1
                        border.color: index === ossWindow.selectedIndex ? Theme.accentHover : Theme.borderCard

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            width: parent.width - 20
                            elide: Text.ElideRight
                            text: modelData.name || ""
                            color: index === ossWindow.selectedIndex ? Theme.bgCard : Theme.textPrimary
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
                    color: Theme.bgCard
                    border.color: Theme.borderCard

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
                            color: Theme.textPrimary
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    color: Theme.bgInput
                    border.color: Theme.borderCard

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Text {
                            width: parent.width
                            text: "Copyright Owner: " + (ossWindow.selectedItem ? (ossWindow.selectedItem.copyright || "") : "")
                            font.pixelSize: 16
                            color: Theme.textPrimary
                            linkColor: Theme.accent
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
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
            }
        }
    }
}
