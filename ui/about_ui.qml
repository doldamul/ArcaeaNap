import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: aboutWindow
    width: 480
    height: contentCol.implicitHeight + 80   // card margins(16*2) + column margins(24*2)
    minimumWidth: 480
    maximumWidth: 480
    minimumHeight: contentCol.implicitHeight + 80
    maximumHeight: contentCol.implicitHeight + 80
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
            id: contentCol
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

            // Updates Section
            Column {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Updates"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#333"
                }

                Row {
                    spacing: 8

                    Rectangle {
                        radius: 4
                        height: 22
                        width: badgeText.implicitWidth + 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            switch (updateHandler ? updateHandler.phase : "") {
                            case "available": return "#EADCF7"
                            case "not-available": return "#E2EFE2"
                            case "error": return "#F7DCDC"
                            default: return "#E8E8E8"
                            }
                        }
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            font.pixelSize: 12
                            color: "#444"
                            text: {
                                switch (updateHandler ? updateHandler.phase : "") {
                                case "checking": return "Checking"
                                case "available": return "Update available"
                                case "downloading": return "Downloading"
                                case "downloaded": return "Downloaded"
                                case "not-available": return "Up to date"
                                case "error": return "Error"
                                default: return "Not checked"
                                }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!updateHandler
                                 && updateHandler.latestVersion !== ""
                                 && (updateHandler.phase === "available"
                                     || updateHandler.phase === "downloading"
                                     || updateHandler.phase === "downloaded")
                        text: "v" + (updateHandler ? updateHandler.latestVersion : "")
                        font.pixelSize: 13
                        font.bold: true
                        color: "#6A0DAD"
                    }

                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        // dev(비-frozen)에서는 downloaded 상태의 "설치 및 재시작"을 비활성화.
                        enabled: updateHandler
                                 ? (updateHandler.phase !== "checking"
                                    && updateHandler.phase !== "installing"
                                    && !(updateHandler.phase === "downloaded" && !updateHandler.isFrozen))
                                 : true
                        text: {
                            if (!updateHandler) return "Check for Updates"
                            switch (updateHandler.phase) {
                            case "available": return "Download"
                            case "downloading": return "Cancel"
                            case "downloaded": return "Install && Restart"
                            case "installing": return "Installing…"
                            default: return "Check for Updates"
                            }
                        }
                        onClicked: {
                            if (!updateHandler) return
                            switch (updateHandler.phase) {
                            case "available": updateHandler.downloadUpdate(); break
                            case "downloading": updateHandler.cancelDownload(); break
                            case "downloaded": updateHandler.installUpdate(); break
                            default: updateHandler.checkForUpdates()
                            }
                        }
                    }
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!updateHandler && updateHandler.phase === "downloaded"
                        text: "Show in Folder"
                        onClicked: { if (updateHandler) updateHandler.revealDownload() }
                    }
                }

                Text {
                    width: parent.width
                    visible: !!updateHandler && updateHandler.phase === "downloaded" && !updateHandler.isFrozen
                    text: "In-app install isn't supported in dev builds. Use 'Show in Folder' to install manually."
                    font.pixelSize: 12
                    color: "#999"
                    wrapMode: Text.Wrap
                }

                Column {
                    width: parent.width
                    spacing: 4
                    visible: !!updateHandler && updateHandler.phase === "downloading"

                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: "#E0E0E0"
                        Rectangle {
                            height: parent.height
                            radius: 3
                            color: "#6A0DAD"
                            width: parent.width * ((updateHandler ? updateHandler.progressPercent : 0) / 100.0)
                        }
                    }

                    Text {
                        width: parent.width
                        font.pixelSize: 12
                        color: "#666"
                        text: {
                            if (!updateHandler) return ""
                            function fmt(b) {
                                if (b < 0) return "?"
                                var u = ["B", "KB", "MB", "GB"], i = 0, v = b
                                while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
                                return v.toFixed(1) + u[i]
                            }
                            return updateHandler.progressPercent + "%  ·  "
                                 + fmt(updateHandler.transferredBytes) + " / " + fmt(updateHandler.totalBytes)
                                 + "  ·  " + fmt(updateHandler.bytesPerSecond) + "/s"
                        }
                    }
                }

                Text {
                    width: parent.width
                    textFormat: Text.RichText
                    text: "<a href=\"" + aboutWindow.repositoryUrl + "/releases\">View releases</a>"
                    font.pixelSize: 13
                    color: "#555"
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
