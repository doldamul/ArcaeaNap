import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: aboutWindow
    width: 480
    // The final height is locked once after the About data has been assigned.
    // Keep a valid initial size while the window is still hidden.
    height: 480
    minimumWidth: 480
    maximumWidth: 480
    title: usesMacCocoaWindow ? "" : "About"
    color: Theme.bgCard
    transientParent: null
    flags: usesAppWindowTitleBar ? (Qt.Dialog | Qt.WindowCloseButtonHint | Qt.WindowTitleHint) : (Qt.Dialog | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint)

    property QtObject nativeBridge: aboutNativeBridge
    property bool isNativeBridgeReady: nativeBridge ? nativeBridge.available : false

    property real safeAreaTop: usesMacCocoaWindow ? (nativeBridge ? nativeBridge.safeAreaTop : 0) : 0
    property real titleBarHeight: usesAppWindowTitleBar ? (nativeBridge ? nativeBridge.height : 0) : 52

    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: titleBarHeight
        acceptedButtons: Qt.LeftButton
        z: 999
        onPressed: aboutWindow.startSystemMove()
    }
    Component.onCompleted: {
        bridgeManager.attachBridgeStyle(aboutNativeBridge, aboutWindow, 1)
    }

    Connections {
        target: nativeBridge
        function onAvailableChanged() {
            if (isNativeBridgeReady && nativeBridge) {
                nativeBridge.setDarkMode(Theme.isDarkMode)
                if (usesAppWindowTitleBar) {
                    aboutWindow.width = 480
                }
            }
        }
        function onMetricsChanged() {
            Qt.callLater(aboutWindow.updateNativeDragRegions);
        }
    }

    Connections {
        target: Theme
        function onIsDarkModeChanged() {
            if (nativeBridge) nativeBridge.setDarkMode(Theme.isDarkMode)
        }
    }

    function updateNativeDragRegions() {
        if (!usesAppWindowTitleBar || !isNativeBridgeReady) return;
        const dragRects = [{ x: 0, y: 0, width: aboutWindow.width, height: titleBarHeight }];
        if (nativeBridge) {
            nativeBridge.setDragRectangles(dragRects);
        }
    }
    onWidthChanged: { Qt.callLater(updateNativeDragRegions); }
    onHeightChanged: { Qt.callLater(updateNativeDragRegions); }

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
    property bool windowSizeLocked: false
    property bool windowSizeLockScheduled: false

    function lockInitialWindowSize() {
        if (windowSizeLocked || windowSizeLockScheduled)
            return

        windowSizeLockScheduled = true
        // ColumnLayout completes its first measurement after the Window has
        // been shown. Defer two layout turns so implicitHeight is final.
        Qt.callLater(function() {
            Qt.callLater(function() {
                if (windowSizeLocked)
                    return

                // contentCol.implicitHeight + anchors.margins (top 48 + bottom 24) = 72, plus safe buffer
                var targetHeight = Math.ceil(contentCol.implicitHeight + 96)

                windowSizeLocked = true
                height = targetHeight
                minimumHeight = targetHeight
                maximumHeight = targetHeight
            })
        })
    }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.topMargin: 48
        anchors.bottomMargin: 24
        anchors.leftMargin: 24
        anchors.rightMargin: 24
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
                        color: Theme.textTitle
                    }
                    Text {
                        text: "Version " + aboutWindow.appVersion
                        font.pixelSize: 18
                        color: Theme.textSecondary
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
                    color: Theme.textSecondary
                }
                Text {
                    width: parent.width
                    text: "Author: doldamul"
                    font.pixelSize: 14
                    color: Theme.textSecondary
                }
                Text {
                    width: parent.width
                    textFormat: Text.RichText
                    text: "Repository: <a href=\"" + aboutWindow.repositoryUrl + "\">" + aboutWindow.repositoryUrl + "</a>"
                    font.pixelSize: 14
                    color: Theme.textSecondary
                    linkColor: Theme.accent
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
                    color: Theme.textPrimary
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
                            case "available": return Theme.bgSelected
                            case "not-available": return Theme.googleBg
                            case "error": return Theme.statusOff
                            default: return Theme.bgHover
                            }
                        }
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            font.pixelSize: 12
                            color: {
                                switch (updateHandler ? updateHandler.phase : "") {
                                case "not-available": return Theme.googleTitle
                                case "error": return Theme.textTitle
                                default: return Theme.textSecondary
                                }
                            }
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
                        color: Theme.accent
                    }

                    Basic.Button {
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
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 6
                            color: !parent.enabled ? Theme.bgInput
                                  : (parent.down ? Theme.accentHover
                                  : (parent.hovered ? Theme.bgHover : Theme.bgButton))
                            border.color: Theme.borderCard
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Basic.Button {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!updateHandler && updateHandler.phase === "downloaded"
                        text: "Show in Folder"
                        onClicked: { if (updateHandler) updateHandler.revealDownload() }
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 6
                            color: !parent.enabled ? Theme.bgInput
                                  : (parent.down ? Theme.accentHover
                                  : (parent.hovered ? Theme.bgHover : Theme.bgButton))
                            border.color: Theme.borderCard
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: !!updateHandler && updateHandler.phase === "downloaded" && !updateHandler.isFrozen
                    text: "In-app install isn't supported in dev builds. Use 'Show in Folder' to install manually."
                    font.pixelSize: 12
                    color: Theme.textLight
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
                        color: Theme.borderCard
                        Rectangle {
                            height: parent.height
                            radius: 3
                            color: Theme.accent
                            width: parent.width * ((updateHandler ? updateHandler.progressPercent : 0) / 100.0)
                        }
                    }

                    Text {
                        width: parent.width
                        font.pixelSize: 12
                        color: Theme.textSecondary
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
                    color: Theme.textSecondary
                    linkColor: Theme.accent
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }

            // Open Source Licenses Button
            Basic.Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Third-Party Licenses & Notices"
                height: 36
                onClicked: aboutWindow.openOssRequested()
                hoverEnabled: true
                background: Rectangle {
                    radius: 6
                    color: !parent.enabled ? Theme.bgInput
                          : (parent.down ? Theme.accentHover
                          : (parent.hovered ? Theme.bgHover : Theme.bgButton))
                    border.color: Theme.borderCard
                }
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Copyright Section
            Text {
                Layout.fillWidth: true
                text: "Arcaea and all related assets are the property of lowiro.\nAll rights reserved."
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                color: Theme.textMuted
                lineHeight: 1.2
            }

            // Bottom Links
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 24

                Text {
                    text: "Homepage ↗"
                    font.pixelSize: 13
                    color: homepageMouseArea.containsMouse ? Theme.textTitle : Theme.textSecondary
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
                    color: privacyMouseArea.containsMouse ? Theme.textTitle : Theme.textSecondary
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
                    color: termsMouseArea.containsMouse ? Theme.textTitle : Theme.textSecondary
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
