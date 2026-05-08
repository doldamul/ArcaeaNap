import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: aboutWindow
    width: 480
    height: 420
    minimumWidth: 480
    maximumWidth: 480
    minimumHeight: 420
    maximumHeight: 420
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
    property string websiteUrl: ""
    property string privacyPolicyUrl: ""
    property string termsOfServiceUrl: ""
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

            // Open Source Licenses Button
            Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Open Source Licenses"
                height: 36
                onClicked: aboutWindow.openOssRequested()
            }

            // Copyright Section
            Text {
                Layout.fillWidth: true
                text: "Arcaea and all related assets are the property of lowiro.\nAll rights reserved."
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                color: "#777"
                lineHeight: 1.2
            }

            // Bottom Links
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 24

                Text {
                    text: "Homepage ↗"
                    font.pixelSize: 13
                    color: homepageMouseArea.containsMouse ? "#1A1A1A" : "#555"
                    font.underline: homepageMouseArea.containsMouse
                    MouseArea {
                        id: homepageMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(aboutWindow.websiteUrl)
                    }
                }

                Text {
                    text: "Privacy Policy ↗"
                    font.pixelSize: 13
                    color: privacyMouseArea.containsMouse ? "#1A1A1A" : "#555"
                    font.underline: privacyMouseArea.containsMouse
                    MouseArea {
                        id: privacyMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(aboutWindow.privacyPolicyUrl)
                    }
                }

                Text {
                    text: "Terms of Service ↗"
                    font.pixelSize: 13
                    color: termsMouseArea.containsMouse ? "#1A1A1A" : "#555"
                    font.underline: termsMouseArea.containsMouse
                    MouseArea {
                        id: termsMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(aboutWindow.termsOfServiceUrl)
                    }
                }
            }
        }
    }
}
