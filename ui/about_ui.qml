import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: aboutWindow
    width: 480
    height: 640
    minimumWidth: 480
    maximumWidth: 480
    minimumHeight: 640
    maximumHeight: 640
    title: "About"
    color: "#F3F4F8"
    transientParent: null
    flags: Qt.Dialog | Qt.WindowCloseButtonHint | Qt.WindowTitleHint

    property string appTitle: "ArcaeaNap"
    property string appVersion: ""
    property string appLicense: ""
    property string repositoryUrl: ""
    property string appLogoSource: ""
    property string buildDate: ""
    property var openSourceItems: []
    signal openOssRequested()

    Rectangle {
        anchors.fill: parent
        anchors.margins: 16
        radius: 12
        color: "#FFFFFF"
        border.color: "#D9DCE5"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            // Branding Section
            Row {
                Layout.fillWidth: true
                spacing: 16

                Image {
                    width: 80
                    height: 80
                    source: aboutWindow.appLogoSource
                    visible: source !== ""
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: aboutWindow.appTitle
                        font.pixelSize: 50
                        font.bold: true
                        color: "#1A1A1A"
                    }
                    Text {
                        text: "Version " + aboutWindow.appVersion
                        font.pixelSize: 18
                        color: "#666"
                    }
                }
            }

            // Metadata Section
            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    width: parent.width
                    text: "Build Date: " + aboutWindow.buildDate
                    font.pixelSize: 14
                    color: "#444"
                }
                Text {
                    width: parent.width
                    text: "Author: doldamul"
                    font.pixelSize: 14
                    color: "#444"
                }
                Text {
                    width: parent.width
                    textFormat: Text.RichText
                    text: "Repository: <a href=\"" + aboutWindow.repositoryUrl + "\">" + aboutWindow.repositoryUrl + "</a>"
                    font.pixelSize: 14
                    color: "#444"
                    wrapMode: Text.WrapAnywhere
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#ECEFF5"
            }

            // Disclaimer & Copyright Section (Stretches to fill remaining space)
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true  // Push the button to the bottom
                clip: true
                contentWidth: availableWidth

                Column {
                    width: parent.width
                    spacing: 14

                    Column {
                        width: parent.width
                        spacing: 4
                        Text {
                            width: parent.width
                            text: "Service Information"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#1A1A1A"
                        }
                        Text {
                            width: parent.width
                            text: "ArcaeaNap is an unofficial fan-made tool for Arcaea. This application is not affiliated with, endorsed, or supported by lowiro.\n\nExcessive or abusive access to Arcaea Online may result in account suspension or banning by lowiro. The distributor of this application is not responsible for any such consequences."
                            wrapMode: Text.Wrap
                            font.pixelSize: 13
                            color: "#555"
                            lineHeight: 1.2
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 4
                        Text {
                            width: parent.width
                            text: "Copyright Notice"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#1A1A1A"
                        }
                        Text {
                            width: parent.width
                            text: "Arcaea and all related assets, including but not limited to character art, songs, and game data, are the property of lowiro. All rights reserved."
                            wrapMode: Text.Wrap
                            font.pixelSize: 13
                            color: "#555"
                            lineHeight: 1.2
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 4
                        Text {
                            width: parent.width
                            text: "Disclaimer of Warranty"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#1A1A1A"
                        }
                        Text {
                            width: parent.width
                            text: "THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
                            wrapMode: Text.Wrap
                            font.pixelSize: 12
                            color: "#777"
                            lineHeight: 1.1
                            font.italic: true
                        }
                    }
                }
            }

            // Footer Button
            Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Open Source Licenses"
                width: 200
                height: 40
                onClicked: aboutWindow.openOssRequested()
            }
        }
    }
}
