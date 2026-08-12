// settings_ui.qml
// Separate window for Settings
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs

Window {
    id: settingsWindow
    width: 600
    height: 800
    minimumWidth: 600
    maximumWidth: 600
    minimumHeight: 600
    title: usesMacCocoaWindow ? "" : "Settings"
    color: Theme.bgWindow

    flags: usesAppWindowTitleBar ? (Qt.Dialog | Qt.WindowCloseButtonHint | Qt.WindowTitleHint) : (Qt.Dialog | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint)

    // 메인 윈도우 위에 고정되지 않도록 부모 관계 해제
    transientParent: null

    property QtObject nativeBridge: settingsNativeBridge
    property bool isNativeBridgeReady: nativeBridge ? nativeBridge.available : false

    property real safeAreaTop: usesMacCocoaWindow ? (nativeBridge ? nativeBridge.safeAreaTop : 0) : 0
    property real titleBarHeight: usesAppWindowTitleBar ? (nativeBridge ? nativeBridge.height : 0) : (usesMacCocoaWindow ? 40 : Math.max(40, safeAreaTop + 12))

    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: titleBarHeight
        acceptedButtons: Qt.LeftButton
        z: 999
        onPressed: settingsWindow.startSystemMove()
    }
    Component.onCompleted: {
        bridgeManager.attachBridgeStyle(settingsNativeBridge, settingsWindow, 2)
    }

    Connections {
        target: nativeBridge
        function onAvailableChanged() {
            if (isNativeBridgeReady && nativeBridge) {
                nativeBridge.setDarkMode(Theme.isDarkMode)
                if (usesAppWindowTitleBar) {
                    settingsWindow.width = 600
                    settingsWindow.height = 800
                }
            }
        }
        function onMetricsChanged() {
            Qt.callLater(settingsWindow.updateNativeDragRegions);
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
        const dragRects = [{ x: 0, y: 0, width: settingsWindow.width, height: titleBarHeight }];
        if (nativeBridge) {
            nativeBridge.setDragRectangles(dragRects);
        }
    }
    onWidthChanged: { Qt.callLater(updateNativeDragRegions); }
    onHeightChanged: { Qt.callLater(updateNativeDragRegions); }

    // No version fetch on visibility change — versions are stored in account_connections.json
    // and loaded on init via getSheetVersions()

    // Cache Migration Loading Modal
    property bool isMigrating: false
    property string pendingCachePath: ""
    property string cachePathModeHelpText: "Hover over an option to see details."
    
    Connections {
        target: settingsHandler
        function onCacheMigrationStarting() {
            settingsWindow.isMigrating = true
            // Use Timer to give QML time to release file handles
            migrationTimer.start()
        }
        function onCacheMigrationFinished(error) {
            settingsWindow.isMigrating = false
            if (error !== "") {
                errorMessageText.text = error
                errorPopup.open()
            }
        }
        function onArcaeaOnlineConnectionChanged() {
            // Force property update by reassigning
            if (arcaeaButton) {
                arcaeaButton.isConnected = settingsHandler.isArcaeaOnlineConnected()
                arcaeaButton.isConnecting = settingsHandler.isArcaeaOnlineConnecting()
                arcaeaButton.connectionInfo = settingsHandler.getArcaeaOnlineConnectionInfo()
            }
        }
        function onGoogleSheetConnectionChanged() {
            // Force property update by reassigning
            if (googleButton) {
                googleButton.isConnected = settingsHandler.isGoogleSheetConnected()
                googleButton.connectionInfo = settingsHandler.getGoogleSheetConnectionInfo()
            }
            // Refresh all sheet binding state when connection changes
            if (sheetMgmtCard) {
                var connected = settingsHandler.isGoogleSheetConnected()
                sheetMgmtCard.isGoogleConnected = connected
                sheetMgmtCard.boundSheetInfo = settingsHandler.getBoundSheetInfo()
                sheetMgmtCard.isBinding = settingsHandler.isBindingSheet()
                // When disconnected, fully reset sheet state so UI reverts to "bind sheet" form
                if (!connected) {
                    sheetMgmtCard.sheetVersions = ({})
                    sheetMgmtCard.lastSynced = 0
                    sheetMgmtCard.isSending = false
                }
            }
        }
        function onSheetBindingChanged() {
            if (sheetMgmtCard) {
                sheetMgmtCard.boundSheetInfo = settingsHandler.getBoundSheetInfo()
                sheetMgmtCard.isBinding = settingsHandler.isBindingSheet()
                sheetMgmtCard.lastSynced = settingsHandler.getLastSyncedTime()
            }
        }
        function onSheetVersionsChanged() {
            if (sheetMgmtCard) {
                sheetMgmtCard.sheetVersions = settingsHandler.getSheetVersions()
            }
        }
        function onSendDataStatusChanged() {
            if (sheetMgmtCard) {
                sheetMgmtCard.isSending = settingsHandler.isSendingData()
                sheetMgmtCard.lastSynced = settingsHandler.getLastSyncedTime()
            }
        }
        function onSongDatabaseWriteConflictDetected(message) {
            songDbWriteConflictText.text = message
            songDbWriteConflictPopup.open()
        }
    }
    
    Timer {
        id: migrationTimer
        interval: 100  // Short delay to ensure image sources are cleared
        repeat: false
        onTriggered: {
            if (settingsHandler) settingsHandler.executeCacheMigration()
        }
    }
    
    // Modal Loading Overlay
    Rectangle {
        id: migrationOverlay
        anchors.fill: parent
        color: Theme.shadowNormal
        visible: settingsWindow.isMigrating
        z: 1000
        
        MouseArea {
            anchors.fill: parent
            // Block all mouse events
        }
        
        Rectangle {
            anchors.centerIn: parent
            width: 280
            height: 120
            radius: 16
            color: Theme.bgCard
            
            Column {
                anchors.centerIn: parent
                spacing: 16
                
                BusyIndicator {
                    running: settingsWindow.isMigrating
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: "Moving cache files..."
                    font.pixelSize: 14
                    font.bold: true
                    color: Theme.textPrimary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
    
    // Error Popup
    Popup {
        id: errorPopup
        anchors.centerIn: parent
        width: 350
        height: errorContent.implicitHeight + 40
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        background: Rectangle {
            color: Theme.bgCard
            radius: 12
            border.color: Theme.statusOff
            border.width: 2
        }
        
        Column {
            id: errorContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            
            Text {
                text: "⚠️ Migration Failed"
                font.bold: true
                font.pixelSize: 16
                color: Theme.statusOff
            }
            
            Text {
                id: errorMessageText
                wrapMode: Text.WordWrap
                width: parent.width
                color: Theme.textPrimary
            }
            
            Basic.Button {
                text: "OK"
                anchors.right: parent.right
                onClicked: errorPopup.close()
                background: Rectangle { color: Theme.bgButton; radius: 6 }
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Popup {
        id: songDbWriteConflictPopup
        anchors.centerIn: parent
        width: 420
        height: conflictContent.implicitHeight + 40
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.bgCard
            radius: 12
            border.color: Theme.browserBtnBg
            border.width: 2
        }

        Column {
            id: conflictContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: "⚠ Concurrent Write Risk Detected"
                font.bold: true
                font.pixelSize: 16
                color: Theme.browserBtnBg
            }

            Text {
                id: songDbWriteConflictText
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.textPrimary
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Basic.Button {
                    text: "Cancel"
                    onClicked: songDbWriteConflictPopup.close()
                    background: Rectangle { color: Theme.bgButton; radius: 6 }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Basic.Button {
                    text: "Force Update"
                    onClicked: {
                        songDbWriteConflictPopup.close()
                        if (settingsHandler) settingsHandler.forceUpdateSongDatabase()
                    }
                    background: Rectangle { color: Theme.browserBtnBg; radius: 6 }
                    contentItem: Text {
                        text: "Force Update"
                        color: Theme.bgCard
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Dialog {
        id: cachePathModeDialog
        parent: settingsWindow.contentItem
        anchors.centerIn: parent
        width: 500
        height: cachePathModeContent.implicitHeight + 24
        modal: true
        padding: 0
        closePolicy: Popup.NoAutoClose
        onClosed: {
            settingsWindow.pendingCachePath = ""
            settingsWindow.cachePathModeHelpText = "Hover over an option to see details."
        }

        background: Rectangle {
            color: Theme.bgCard
            radius: 12
            border.color: Theme.borderCard
            border.width: 1
        }

        ColumnLayout {
            id: cachePathModeContent
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Which cache path data would you like to use?"
                    font.bold: true
                    font.pixelSize: 16
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                }

                Basic.Button {
                    text: "✕"
                    hoverEnabled: true
                    onClicked: cachePathModeDialog.close()
                    background: Rectangle {
                        color: parent.hovered ? Theme.hoverOverlay : "transparent"
                        radius: 12
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
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                text: settingsWindow.cachePathModeHelpText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Theme.textSecondary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Basic.Button {
                    id: useOldCacheDataButton
                    Layout.fillWidth: true
                    text: "Use data from old cache path"
                    hoverEnabled: true
                    onHoveredChanged: {
                        if (hovered) {
                            settingsWindow.cachePathModeHelpText =
                                "Move ArcaeaNap data from your current cache path to the new one.\nExisting files in the new path will be overwritten."
                        } else if (!useNewCacheDataButton.hovered) {
                            settingsWindow.cachePathModeHelpText = "Hover over an option to see details."
                        }
                    }
                    onClicked: {
                        if (settingsHandler && settingsWindow.pendingCachePath !== "") {
                            settingsHandler.prepareCacheMigration(settingsWindow.pendingCachePath)
                        }
                        cachePathModeDialog.close()
                    }
                    background: Rectangle { color: Theme.bgButton; radius: 8 }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Basic.Button {
                    id: useNewCacheDataButton
                    Layout.fillWidth: true
                    text: "Use data from new cache path"
                    hoverEnabled: true
                    onHoveredChanged: {
                        if (hovered) {
                            settingsWindow.cachePathModeHelpText =
                                "Use ArcaeaNap data already in the new cache path.\nNothing will be copied or deleted.\nRecommended for multi-client setups."
                        } else if (!useOldCacheDataButton.hovered) {
                            settingsWindow.cachePathModeHelpText = "Hover over an option to see details."
                        }
                    }
                    onClicked: {
                        if (settingsHandler && settingsWindow.pendingCachePath !== "") {
                            settingsHandler.switchCachePathOnly(settingsWindow.pendingCachePath)
                        }
                        cachePathModeDialog.close()
                    }
                    background: Rectangle { color: Theme.bgButton; radius: 8 }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Item {
        id: settingsScrollArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: parent.top

        ScrollView {
            id: scrollView
            anchors.fill: parent
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            clip: true
            padding: 40
        
        TapHandler {
            onTapped: {
                profileDescArea.focus = false
                profileDescArea.deselect()
            }
        }

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: 30

            // --- 0. Appearance Section ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: appearanceLayout.implicitHeight + 60
                color: Theme.bgCard
                radius: 20
                border.color: Theme.borderCard; border.width: 1

                ColumnLayout {
                    id: appearanceLayout
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 24

                    Text { text: "Appearance"; font.bold: true; font.pixelSize: 18; color: Theme.textPrimary }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        Text { text: "Theme"; font.bold: true; color: Theme.textPrimary }
                        Item { Layout.fillWidth: true }

                        ThemeModeSelector {
                            mode: typeof themeHandler === "undefined" ? "system" : themeHandler.themeMode
                            onModeRequested: function(requestedMode) {
                                if (typeof themeHandler !== "undefined")
                                    themeHandler.setThemeMode(requestedMode)
                            }
                        }
                    }
                }
            }

            // --- 1. General Section ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: generalLayout.implicitHeight + 60
                color: Theme.bgCard
                radius: 20
                border.color: Theme.borderCard; border.width: 1

                ColumnLayout {
                    id: generalLayout
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 24

                    // Header
                    Text { text: "General"; font.bold: true; font.pixelSize: 18; color: Theme.textPrimary }

                    // Account Connections
                    Text { text: "Account Connections"; font.bold: true; color: Theme.textPrimary }
                    RowLayout {
                        spacing: 20
                        
                        // Arcaea Online Button
                        Rectangle {
                            id: arcaeaButton
                            width: 200; height: 80
                            radius: 10
                            color: isConnected ? Theme.arcaeaBg : Theme.bgButton
                            Behavior on color { PropertyAction {} }
                            
                            property bool isConnected: settingsHandler ? settingsHandler.isArcaeaOnlineConnected() : false
                            property bool isConnecting: settingsHandler ? settingsHandler.isArcaeaOnlineConnecting() : false
                            property var connectionInfo: settingsHandler ? settingsHandler.getArcaeaOnlineConnectionInfo() : ({})
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                
                                Text { 
                                    text: "Arcaea Online"
                                    font.bold: true
                                    font.pixelSize: 14
                                    color: arcaeaButton.isConnected ? Theme.accent : Theme.titleOff
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                
                                Text {
                                    visible: arcaeaButton.isConnected
                                    text: {
                                        var info = arcaeaButton.connectionInfo
                                        if (!info || Object.keys(info).length === 0) return ""
                                        var displayName = info.name || info.user_id || ""
                                        if (displayName && info.formatted_date) {
                                            return displayName + "\n" + info.formatted_date
                                        }
                                        return displayName
                                    }
                                    font.pixelSize: 10
                                    color: Theme.settingsTextMuted
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                
                                Text {
                                    visible: !arcaeaButton.isConnected
                                    text: "Not Connected"
                                    font.pixelSize: 11
                                    color: Theme.statusOff
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            
                            // Hover overlay
                            Rectangle {
                                anchors.fill: parent
                                color: Theme.shadowNormal
                                radius: parent.radius
                                visible: arcaeaButtonMouseArea.containsMouse || arcaeaButton.isConnecting
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        if (arcaeaButton.isConnecting) return "Cancel"
                                        return arcaeaButton.isConnected ? "Disconnect" : "Connect"
                                    }
                                    color: {
                                        if (arcaeaButton.isConnecting) {
                                            return arcaeaButtonMouseArea.containsMouse ? "white" : Theme.toggleBorderOff
                                        }
                                        return "white"
                                    }
                                    font.bold: true
                                    font.pixelSize: arcaeaButton.isConnecting ? 12 : 14
                                    visible: true
                                }
                            }

                            SpinnerIndicator {
                                anchors.centerIn: parent
                                width: 64; height: 64
                                lineWidth: 3
                                strokeColor: "white"
                                radiusOffset: 4
                                running: arcaeaButton.isConnecting
                            }

                            MouseArea {
                                id: arcaeaButtonMouseArea
                                anchors.fill: parent
                                cursorShape: arcaeaButton.isConnecting ? Qt.ArrowCursor : Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    if (arcaeaButton.isConnecting) {
                                        if (settingsHandler) settingsHandler.cancelArcaeaOnlineConnection()
                                        return
                                    }
                                    if (arcaeaButton.isConnected) {
                                        disconnectArcaeaDialog.open()
                                    } else {
                                        if (settingsHandler) settingsHandler.connectArcaeaOnline()
                                    }
                                }
                            }
                        }
                        
                        // Google Sheet Button
                        Rectangle {
                            id: googleButton
                            width: 200; height: 80
                            radius: 10
                            color: isConnected ? Theme.googleBg : Theme.bgButton
                            Behavior on color { PropertyAction {} }
                            
                            property bool isConnected: settingsHandler ? settingsHandler.isGoogleSheetConnected() : false
                            property var connectionInfo: settingsHandler ? settingsHandler.getGoogleSheetConnectionInfo() : ({})
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                
                                Text { 
                                    text: "Google Sheet"
                                    font.bold: true
                                    font.pixelSize: 14
                                    color: googleButton.isConnected ? Theme.googleTitle : Theme.titleOff
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                
                                Text {
                                    visible: googleButton.isConnected
                                    text: {
                                        var info = googleButton.connectionInfo
                                        if (!info || Object.keys(info).length === 0) return ""
                                        if (info.user_email) {
                                            if (info.formatted_date) {
                                                return info.user_email + "\n" + info.formatted_date
                                            }
                                            return info.user_email
                                        }
                                        return ""
                                    }
                                    font.pixelSize: 10
                                    color: Theme.settingsTextMuted
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                
                                Text {
                                    visible: !googleButton.isConnected
                                    text: "Not Connected"
                                    font.pixelSize: 11
                                    color: Theme.statusOff
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            
                            // Hover overlay
                            Rectangle {
                                anchors.fill: parent
                                color: Theme.shadowNormal
                                radius: parent.radius
                                visible: googleButtonMouseArea.containsMouse
                                z: 10
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: googleButton.isConnected ? "Disconnect" : "Connect"
                                    color: Theme.overlayText
                                    font.bold: true
                                    font.pixelSize: 14
                                    z: 1
                                }
                            }
                            
                            MouseArea {
                                id: googleButtonMouseArea
                                z: 20
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    if (googleButton.isConnected) {
                                        disconnectGoogleDialog.open()
                                    } else {
                                        if (settingsHandler) settingsHandler.connectGoogleSheet()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Disconnect confirmation dialogs
                    Dialog {
                        id: disconnectArcaeaDialog
                        title: "Disconnect Account"
                        parent: settingsWindow.contentItem
                        anchors.centerIn: parent
                        width: 300
                        height: 140
                        modal: true
                        
                        background: Rectangle {
                            color: Theme.bgCard
                            radius: 12
                            border.color: Theme.borderCard
                            border.width: 1
                        }
                        
                        Column {
                            spacing: 20
                            anchors.fill: parent
                            anchors.margins: 20
                            
                            Text {
                                text: "Disconnect Arcaea Online?"
                                wrapMode: Text.WordWrap
                                width: parent.width
                                color: Theme.textPrimary
                            }
                            
                            RowLayout {
                                anchors.right: parent.right
                                spacing: 10
                                
                                Basic.Button {
                                    text: "Cancel"
                                    onClicked: disconnectArcaeaDialog.close()
                                    background: Rectangle { color: Theme.bgButton; radius: 6 }
                                    contentItem: Text {
                                        text: parent.text
                                        color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                                
                                Basic.Button {
                                    text: "Disconnect"
                                    onClicked: {
                                        if (settingsHandler) settingsHandler.disconnectArcaeaOnline()
                                        disconnectArcaeaDialog.close()
                                    }
                                    background: Rectangle { color: Theme.statusOff; radius: 6 }
                                    contentItem: Text {
                                        text: parent.text
                                        color: Theme.bgCard
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }
                    
                    Dialog {
                        id: disconnectGoogleDialog
                        title: "Disconnect Account"
                        parent: settingsWindow.contentItem
                        anchors.centerIn: parent
                        width: 300
                        height: 140
                        modal: true
                        
                        background: Rectangle {
                            color: Theme.bgCard
                            radius: 12
                            border.color: Theme.borderCard
                            border.width: 1
                        }
                        
                        Column {
                            spacing: 20
                            anchors.fill: parent
                            anchors.margins: 20
                            
                            Text {
                                text: "Disconnect Google Sheet?"
                                wrapMode: Text.WordWrap
                                width: parent.width
                                color: Theme.textPrimary
                            }
                            
                            RowLayout {
                                anchors.right: parent.right
                                spacing: 10
                                
                                Basic.Button {
                                    text: "Cancel"
                                    onClicked: disconnectGoogleDialog.close()
                                    background: Rectangle { color: Theme.bgButton; radius: 6 }
                                    contentItem: Text {
                                        text: parent.text
                                        color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                                
                                Basic.Button {
                                    text: "Disconnect"
                                    onClicked: {
                                        if (settingsHandler) settingsHandler.disconnectGoogleSheet()
                                        disconnectGoogleDialog.close()
                                    }
                                    background: Rectangle { color: Theme.statusOff; radius: 6 }
                                    contentItem: Text {
                                        text: parent.text
                                        color: Theme.bgCard
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Database Management
                    // Arcaea Consultant Sheet Section
                    Text { text: "Arcaea Consultant Sheet"; font.bold: true; color: Theme.textPrimary }
                    
                    // Sheet Management Card
                    Rectangle {
                        id: sheetMgmtCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: sheetMgmtLayout.implicitHeight + 30
                        color: Theme.bgCard
                        radius: 12
                        border.color: Theme.borderCard; border.width: 1
                        
                        property bool isGoogleConnected: settingsHandler ? settingsHandler.isGoogleSheetConnected() : false
                        property var boundSheetInfo: settingsHandler ? settingsHandler.getBoundSheetInfo() : ({})
                        property bool isBinding: settingsHandler ? settingsHandler.isBindingSheet() : false
                        property bool isSending: settingsHandler ? settingsHandler.isSendingData() : false
                        property real lastSynced: settingsHandler ? settingsHandler.getLastSyncedTime() : 0
                        property var sheetVersions: settingsHandler ? settingsHandler.getSheetVersions() : ({})
                        property string parsedSheetVer: "?"
                        property string parsedArcaeaVer: "?"
                        
                        onSheetVersionsChanged: {
                            var v = sheetVersions
                            parsedSheetVer = (v && v.sheet_ver) ? String(v.sheet_ver) : '?'
                            parsedArcaeaVer = (v && v.arcaea_ver) ? String(v.arcaea_ver) : '?'
                        }
                        
                        property bool hasBoundSheet: false
                        property string boundSheetName: ""
                        
                        // Explicitly update derived properties when boundSheetInfo changes
                        // (JavaScript block bindings may fail to re-evaluate after imperative assignment)
                        onBoundSheetInfoChanged: {
                            var info = boundSheetInfo
                            hasBoundSheet = !!(info && info.sheet_id && info.sheet_id !== "")
                            boundSheetName = (info && info.sheet_name) ? info.sheet_name : ""
                        }
                        
                        Component.onCompleted: {
                            // Compute initial derived properties
                            var info = boundSheetInfo
                            hasBoundSheet = !!(info && info.sheet_id && info.sheet_id !== "")
                            boundSheetName = (info && info.sheet_name) ? info.sheet_name : ""

                            var v = sheetVersions
                            parsedSheetVer = (v && v.sheet_ver) ? String(v.sheet_ver) : '?'
                            parsedArcaeaVer = (v && v.arcaea_ver) ? String(v.arcaea_ver) : '?'
                        }
                        
                        ColumnLayout {
                            id: sheetMgmtLayout
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 12
                            
                            // Header removed as requested
                            // Text { text: "Sheet Management"; font.bold: true; color: Theme.googleTitle; font.pixelSize: 13 }
                            
                            // State: No sheet bound - show Bind Sheet button
                            Basic.Button {
                                id: bindSheetButton
                                Layout.fillWidth: true
                                visible: !sheetMgmtCard.hasBoundSheet && !sheetMgmtCard.isBinding
                                text: "Bind Sheet"
                                onClicked: if (settingsHandler) settingsHandler.bindSheet()
                                background: Rectangle {
                                    color: bindSheetButton.down ? Theme.browserBtnBgDown : Theme.browserDesc
                                    radius: 8
                                }
                                contentItem: Text {
                                    text: bindSheetButton.text
                                    color: Theme.bgCard
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            
                            // State: Binding in progress
                            RowLayout {
                                Layout.fillWidth: true
                                visible: sheetMgmtCard.isBinding
                                spacing: 10
                                
                                BusyIndicator {
                                    width: 24; height: 24
                                    running: sheetMgmtCard.isBinding
                                }
                                Text {
                                    text: "Opening Google Picker..."
                                    color: Theme.settingsTextMuted
                                    font.pixelSize: 12
                                    Layout.fillWidth: true
                                }
                                Basic.Button {
                                    text: "Cancel"
                                    onClicked: if (settingsHandler) settingsHandler.cancelBindSheet()
                                    background: Rectangle { color: Theme.bgButton; radius: 6 }
                                    contentItem: Text { text: "Cancel"; color: Theme.textPrimary; font.pixelSize: 11; anchors.centerIn: parent }
                                }
                            }
                            
                            // State: Sheet bound - show sheet info + actions
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: sheetMgmtCard.hasBoundSheet && !sheetMgmtCard.isBinding
                                spacing: 10
                                
                                // Sheet title
                                Text {
                                    text: sheetMgmtCard.boundSheetName
                                    font.bold: true
                                    font.pixelSize: 14
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                // Sheet versions + Open Sheet + Change icon
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    
                                    // Version Badges
                                    RowLayout {
                                        spacing: 8
                                        
                                        Rectangle {
                                            color: Theme.googleBg
                                            radius: 4
                                            implicitWidth: verRow1.implicitWidth + 16
                                            implicitHeight: verRow1.implicitHeight + 8
                                            
                                            RowLayout {
                                                id: verRow1
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: "Sheet"; font.pixelSize: 11; color: Theme.googleTitle; font.bold: true }
                                                SpinnerIndicator {
                                                    implicitWidth: 11; implicitHeight: 11
                                                    lineWidth: 1.5
                                                    strokeColor: Theme.textPrimary
                                                    running: !sheetMgmtCard.parsedSheetVer || sheetMgmtCard.parsedSheetVer === '?'
                                                }
                                                Text {
                                                    text: sheetMgmtCard.parsedSheetVer || ''
                                                    font.pixelSize: 11; color: Theme.textPrimary
                                                    visible: sheetMgmtCard.parsedSheetVer && sheetMgmtCard.parsedSheetVer !== '?'
                                                }
                                            }
                                        }
                                        
                                        Rectangle {
                                            color: Theme.arcaeaBadgeBg
                                            radius: 4
                                            implicitWidth: verRow2.implicitWidth + 16
                                            implicitHeight: verRow2.implicitHeight + 8
                                            
                                            RowLayout {
                                                id: verRow2
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: "Arcaea"; font.pixelSize: 11; color: Theme.arcaeaBadgeText; font.bold: true }
                                                SpinnerIndicator {
                                                    implicitWidth: 11; implicitHeight: 11
                                                    lineWidth: 1.5
                                                    strokeColor: Theme.textPrimary
                                                    running: !sheetMgmtCard.parsedArcaeaVer || sheetMgmtCard.parsedArcaeaVer === '?'
                                                }
                                                Text {
                                                    text: sheetMgmtCard.parsedArcaeaVer || ''
                                                    font.pixelSize: 11; color: Theme.textPrimary
                                                    visible: sheetMgmtCard.parsedArcaeaVer && sheetMgmtCard.parsedArcaeaVer !== '?'
                                                }
                                            }
                                        }
                                    }
                                    
                                    Item { Layout.fillWidth: true }
                                    
                                    // Open Sheet button
                                    Basic.Button {
                                        text: "Open Sheet"
                                        onClicked: if (settingsHandler) settingsHandler.openBoundSheet()
                                        background: Rectangle { color: Theme.btnOpenBg; radius: 4; border.color: Theme.btnOpenBorder }
                                        contentItem: Text { text: "Open Sheet"; color: Theme.btnOpenText; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        implicitHeight: 26
                                    }
                                    
                                    // Change sheet icon button
                                    Basic.Button {
                                        text: "🔄"
                                        onClicked: if (settingsHandler) settingsHandler.bindSheet()
                                        background: Rectangle { color: Theme.bgInput; radius: 4; border.color: Theme.borderCard }
                                        contentItem: Text { text: "🔄"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        implicitWidth: 30; implicitHeight: 26
                                    }
                                }
                                
                                // Spacer for visual balance
                                Item { height: 4 }
                                
                                // Send Data button (full width)
                                Basic.Button {
                                    id: sendDataButton
                                    Layout.fillWidth: true
                                    enabled: !sheetMgmtCard.isSending
                                    onClicked: if (settingsHandler) settingsHandler.sendData()
                                    background: Rectangle {
                                        color: {
                                            if (!sendDataButton.enabled) return Theme.btnDisabled
                                            return sendDataButton.down ? Theme.btnSendPressed : Theme.btnSendBg
                                        }
                                        radius: 8
                                    }
                                    contentItem: RowLayout {
                                        spacing: 8
                                        Item { Layout.fillWidth: true }
                                        SpinnerIndicator {
                                            Layout.preferredWidth: 14
                                            Layout.preferredHeight: 14
                                            lineWidth: 2
                                            strokeColor: "white"
                                            radiusOffset: 1.5
                                            running: sheetMgmtCard.isSending
                                        }
                                        Text {
                                            text: sheetMgmtCard.isSending ? "Sending..." : "Send Data"
                                            color: Theme.bgCard
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                                
                                // Last synced info
                                Text {
                                    text: {
                                        if (sheetMgmtCard.lastSynced <= 0) return "Last synced: Never"
                                        var date = new Date(sheetMgmtCard.lastSynced * 1000)
                                        return "Last synced: " + Qt.formatDateTime(date, "yyyy-MM-dd hh:mm")
                                    }
                                    font.pixelSize: 11
                                    color: Theme.settingsTextMuted
                                }
                            }
                        }
                        
                        // Disabled overlay when Google account not connected
                        Rectangle {
                            anchors.fill: parent
                            color: Theme.overlayLight
                            radius: parent.radius
                            visible: !sheetMgmtCard.isGoogleConnected
                            
                            Text {
                                anchors.centerIn: parent
                                text: "Connect Google account first"
                                font.pixelSize: 12
                                color: Theme.textLight
                                font.italic: true
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                // Block all interactions
                            }
                        }
                    }
                    
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Database Management
                    Text {
                        text: settingsHandler && settingsHandler.isSongsDbExisting ? "Song Database" : "Generate Song Database"
                        font.bold: true; color: Theme.textPrimary
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: 50
                        radius: 10
                        color: Theme.arcaeaBadgeBg
                        border.color: Theme.dbCardBorder
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20; anchors.rightMargin: 20
                            
                            Column {
                                spacing: 2
                                Text {
                                    text: settingsHandler && settingsHandler.isSongsDbExisting ? "Update Song Database" : "Generate Song Database"
                                    font.bold: true; color: Theme.dbTitle
                                }
                                Text {
                                    text: settingsHandler && settingsHandler.isSongsDbExisting ? "Rebuild song database from online sources" : "Generate song database from online sources"
                                    font.pixelSize: 11; color: Theme.dbTitle
                                }
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Basic.Button {
                                id: updateDbButton
                                text: {
                                    if (settingsHandler && settingsHandler.isUpdatingSongDatabase()) {
                                        return "Updating..."
                                    }
                                    return settingsHandler && settingsHandler.isSongsDbExisting ? "Update" : "Generate"
                                }
                                enabled: !settingsHandler || !settingsHandler.isUpdatingSongDatabase()
                                onClicked: if (settingsHandler) settingsHandler.updateSongDatabase()

                                background: Rectangle {
                                    color: {
                                        if (!updateDbButton.enabled) return Theme.btnDisabled
                                        return updateDbButton.down ? Theme.dbBtnBgDown : Theme.dbBtnBg
                                    }
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: updateDbButton.text
                                    color: Theme.bgCard
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Browser Setup
                    Text { text: "Browser"; font.bold: true; color: Theme.textPrimary }

                    Rectangle {
                        id: browserSetupCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: browserSetupLayout.implicitHeight + 30
                        radius: 10
                        color: browserSetupCard.installed ? Theme.googleBg : Theme.bgInput
                        border.color: browserSetupCard.installed ? Theme.browserBorder : Theme.browserBorder
                        border.width: 1

                        property bool installed: settingsHandler ? settingsHandler.isBrowserInstalled() : false
                        property bool installing: settingsHandler ? settingsHandler.isInstallingBrowser() : false
                        property string installLog: ""

                        Connections {
                            target: settingsHandler
                            function onBrowserInstallStatusChanged() {
                                browserSetupCard.installed = settingsHandler.isBrowserInstalled()
                                browserSetupCard.installing = settingsHandler.isInstallingBrowser()
                                if (!browserSetupCard.installing) {
                                    browserSetupCard.installLog = ""
                                }
                            }
                            function onBrowserInstallLogAdded(message) {
                                browserSetupCard.installLog = message
                            }
                        }

                        ColumnLayout {
                            id: browserSetupLayout
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Column {
                                    spacing: 2
                                    Text {
                                        text: browserSetupCard.installed ? "Chromium Installed" : "Chromium Not Installed"
                                        font.bold: true
                                        color: browserSetupCard.installed ? Theme.googleTitle : Theme.browserBtnBg
                                    }
                                    Text {
                                        text: browserSetupCard.installed
                                            ? "Browser is ready for analysis"
                                            : "Required for Arcaea Online analysis"
                                        font.pixelSize: 11
                                        color: browserSetupCard.installed ? Theme.browserDesc : Theme.browserBtnBg
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Basic.Button {
                                    id: installBrowserBtn
                                    text: {
                                        if (browserSetupCard.installing) return "Installing..."
                                        return browserSetupCard.installed ? "Reinstall" : "Install"
                                    }
                                    enabled: !browserSetupCard.installing
                                    onClicked: if (settingsHandler) settingsHandler.installBrowser()
                                    background: Rectangle {
                                        color: {
                                            if (!installBrowserBtn.enabled) return Theme.btnDisabled
                                            return installBrowserBtn.down ? Theme.browserBtnBg : Theme.browserBtnBg
                                        }
                                        radius: 6
                                    }
                                    contentItem: Text {
                                        text: installBrowserBtn.text
                                        color: Theme.bgCard
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }

                            // Log output
                            Text {
                                visible: browserSetupCard.installing && browserSetupCard.installLog !== ""
                                Layout.fillWidth: true
                                text: browserSetupCard.installLog
                                font.pixelSize: 11
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Analyze Mode Toggle
                    RowLayout {
                        Layout.fillWidth: true
                        
                        ColumnLayout {
                            spacing: 4
                            
                            RowLayout {
                                spacing: 6
                                Text { 
                                    text: "Play Count Analyze Mode"
                                    font.bold: true
                                    color: Theme.textPrimary 
                                }
                                
                                Text {
                                    text: "ⓘ"
                                    font.pixelSize: 14
                                    color: helpMouse.containsMouse ? Theme.accent : Theme.textLight
                                    
                                    MouseArea {
                                        id: helpMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }
                                    
                                    Basic.ToolTip {
                                        visible: helpMouse.containsMouse
                                        delay: 100
                                        timeout: -1 // 무기한 표시 (마우스가 떠나면 visible에 의해 사라짐)
                                        x: parent.width + 10
                                        y: -10
                                        
                                        contentItem: Text {
                                            text: "Arcaea Online resets 'Yearly Play Count' data annually on Jan 1st (00:00 GMT).\n\n" +
                                                  "Normally, the analyzer updates play count of a record only when a new score is found, for ensuring record consistency and preventing server strain. Enable this mode to temporarily bypass limits and update play counts for ALL songs.\n" +
                                                  "This is useful for archiving your complete yearly statistics before the reset."
                                            font.pixelSize: 12
                                            color: Theme.bgCard
                                            wrapMode: Text.WordWrap
                                        }
                                        
                                        background: Rectangle {
                                            color: Theme.textPrimary
                                            radius: 6
                                            opacity: 0.95
                                        }
                                        
                                        width: 350
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                        
                        Item {
                            id: analyzeToggle
                            width: 48; height: 26
                            Layout.alignment: Qt.AlignRight
                            property bool checked: settingsHandler ? settingsHandler.getAnalyzeModeEnabled() : false

                            Connections {
                                target: settingsHandler
                                function onAnalyzeModeChanged(enabled) {
                                    analyzeToggle.checked = enabled
                                }
                            }

                            Rectangle {
                                id: toggleTrack
                                anchors.fill: parent
                                radius: 13
                                color: analyzeToggle.checked ? Theme.accent : Theme.borderCard
                                border.color: analyzeToggle.checked ? Theme.accent : Theme.toggleBorderOff
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: analyzeToggle.checked ? parent.width - width - 2 : 2
                                    color: Theme.bgCard
                                    
                                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    analyzeToggle.checked = !analyzeToggle.checked
                                    if (settingsHandler) settingsHandler.setAnalyzeModeEnabled(analyzeToggle.checked)
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Statistics Section
                    Text { text: "Statistics"; font.bold: true; color: Theme.textPrimary }

                    ColumnLayout {
                        spacing: 8
                        Text { text: "Best potential mark"; color: Theme.textPrimary }
                        RowLayout {
                            spacing: 10
                            ThemedRadioButton {
                                text: "None"
                                checked: settingsHandler ? settingsHandler.getBestPotentialMark() === 'none' : true
                                onToggled: if (checked && settingsHandler) settingsHandler.setBestPotentialMark('none')
                            }
                            ThemedRadioButton {
                                text: "B10"
                                checked: settingsHandler ? settingsHandler.getBestPotentialMark() === '10' : false
                                onToggled: if (checked && settingsHandler) settingsHandler.setBestPotentialMark('10')
                            }
                            ThemedRadioButton {
                                text: "B30"
                                checked: settingsHandler ? settingsHandler.getBestPotentialMark() === '30' : false
                                onToggled: if (checked && settingsHandler) settingsHandler.setBestPotentialMark('30')
                            }
                            ThemedRadioButton {
                                text: "B50"
                                checked: settingsHandler ? settingsHandler.getBestPotentialMark() === '50' : false
                                onToggled: if (checked && settingsHandler) settingsHandler.setBestPotentialMark('50')
                            }
                            ThemedRadioButton {
                                text: "B100"
                                checked: settingsHandler ? settingsHandler.getBestPotentialMark() === '100' : false
                                onToggled: if (checked && settingsHandler) settingsHandler.setBestPotentialMark('100')
                            }
                            ThemedRadioButton {
                                text: "All"
                                checked: settingsHandler ? settingsHandler.getBestPotentialMark() === 'all' : false
                                onToggled: if (checked && settingsHandler) settingsHandler.setBestPotentialMark('all')
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Language
                    ColumnLayout {
                        spacing: 8
                        Text { text: "Language"; font.bold: true; color: Theme.textPrimary }
                        RowLayout {
                            spacing: 10
                            Text { text: "Song Title:"; color: Theme.textPrimary }
                            ThemedRadioButton {
                                text: "en"
                                checked: settingsHandler ? settingsHandler.getSongTitleLanguage() === 'en' : true
                                onToggled: if (checked && settingsHandler) settingsHandler.setSongTitleLanguage('en')
                            }
                            ThemedRadioButton {
                                text: "jp"
                                checked: settingsHandler ? settingsHandler.getSongTitleLanguage() === 'jp' : false
                                onToggled: if (checked && settingsHandler) settingsHandler.setSongTitleLanguage('jp')
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Cache Path
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "Cache Path"; font.bold: true; color: Theme.textPrimary }
                        Text { text: "Location where scores and images are stored"; font.pixelSize: 12; color: Theme.textMuted }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            
                            Basic.TextField {
                                id: cachePathField
                                Layout.fillWidth: true
                                text: settingsHandler ? settingsHandler.getCachePath() : ""
                                readOnly: true
                                color: Theme.textPrimary
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bgCard
                                placeholderTextColor: Theme.textPlaceholder
                                background: Rectangle {
                                    color: Theme.bgInput; radius: 8; border.width: 0
                                }
                                
                                // Update when cache path changes
                                Connections {
                                    target: settingsHandler
                                    function onCachePathChanged() {
                                        cachePathField.text = settingsHandler.getCachePath()
                                    }
                                }
                            }
                            
                            // Open folder button
                            Basic.Button {
                                text: "📂"
                                background: Rectangle { color: Theme.bgButton; radius: 8 }
                                onClicked: if (settingsHandler) settingsHandler.openCacheFolder()
                                Basic.ToolTip { text: "Open folder"; visible: parent.hovered }
                            }
                            
                            // Change folder button
                            Basic.Button {
                                text: "📁"
                                background: Rectangle { color: Theme.bgButton; radius: 8 }
                                onClicked: folderDialog.open()
                                Basic.ToolTip { text: "Change folder"; visible: parent.hovered }
                            }
                        }
                    }

                    FolderDialog {
                        id: folderDialog
                        title: "Select Cache Directory"
                        onAccepted: {
                            settingsWindow.pendingCachePath = folderDialog.selectedFolder
                            settingsWindow.cachePathModeHelpText = "Hover over an option to see details."
                            cachePathModeDialog.open()
                        }
                        onRejected: {
                            settingsWindow.pendingCachePath = ""
                        }
                    }
                }
            }

            // --- 2. Profile Section ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: profileLayout.implicitHeight + 60
                color: Theme.bgCard
                radius: 20
                border.color: Theme.borderCard; border.width: 1

                ColumnLayout {
                    id: profileLayout
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 24

                    Text { text: "Profile"; font.bold: true; font.pixelSize: 18; color: Theme.textPrimary }

                    // Profile Actions & Image (Moved)
                    RowLayout {
                        id: profileImageRow
                        Layout.fillWidth: true
                        spacing: 20
                        property string profileImageSource: (settingsHandler && settingsHandler.getProfileImage()) ? settingsHandler.getProfileImage() : ""
                        Connections {
                            target: settingsHandler
                            function onSettingsChanged() {
                                profileImageRow.profileImageSource = (settingsHandler && settingsHandler.getProfileImage()) ? settingsHandler.getProfileImage() : ""
                            }
                        }
                        
                        Rectangle {
                            id: profileImageRect
                            width: 80; height: 80
                            color: Theme.bgButton
                            border.color: Theme.borderCard
                            clip: true
                            property bool hoverActive: false
                            
                            Image {
                                id: profileImageSettings
                                anchors.fill: parent
                                source: profileImageRow.profileImageSource ? ("file:///" + profileImageRow.profileImageSource.replace(/\\/g, '/')) : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: source != ""
                            }
                            
                            Text {
                                anchors.centerIn: parent
                                text: "No\nImg"
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter
                                visible: profileImageSettings.status !== Image.Ready
                            }
                            
                            // Hover overlay: open file dialog on click
                            Rectangle {
                                anchors.fill: parent
                                color: Theme.shadowNormal
                                visible: profileImageRect.hoverActive
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "🖼️"
                                    color: Theme.bgCard
                                    font.pixelSize: 24
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            // Small clear (✕) button on hover, top-right
                            Rectangle {
                                id: profileImageClearButton
                                width: 22; height: 22
                                radius: 11
                                color: clearProfileImageMouse.containsMouse ? Theme.bgButton : Theme.bgHover
                                border.color: Theme.borderCard
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: 4
                                anchors.rightMargin: 4
                                visible: profileImageRect.hoverActive && profileImageSettings.visible
                                z: 200

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    font.pixelSize: 12
                                    color: Theme.textSecondary
                                }

                                MouseArea {
                                    id: clearProfileImageMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (settingsHandler) settingsHandler.setProfileImage("")
                                    }
                                    onEntered: profileImageRect.hoverActive = true
                                    onExited: profileImageRect.hoverActive = profileImageMouse.containsMouse || clearProfileImageMouse.containsMouse
                                }
                            }
                            
                            MouseArea {
                                id: profileImageMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: profileImageRect.hoverActive = true
                                onExited: profileImageRect.hoverActive = profileImageMouse.containsMouse || clearProfileImageMouse.containsMouse
                                onClicked: fileDialog.open()
                            }
                        }
                        
                        ColumnLayout {
                            id: profileInfoLayout
                            
                            property var profileData: profileHandler ? profileHandler.getProfile() : {"connected": false}
                            
                            Connections {
                                target: profileHandler
                                function onProfileChanged() {
                                    profileInfoLayout.profileData = profileHandler.getProfile()
                                }
                            }
                            
                            ColumnLayout {
                                visible: profileInfoLayout.profileData.connected
                                spacing: 2
                                
                                Text {
                                    text: profileInfoLayout.profileData.name || "Unknown"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                                RowLayout {
                                    spacing: 12
                                    Text {
                                        text: "ID: " + (profileInfoLayout.profileData.user_code || "Unknown")
                                        font.pixelSize: 13
                                        color: Theme.textSecondary
                                    }
                                    Text {
                                        text: "PTT: " + (profileInfoLayout.profileData.rating !== undefined && profileInfoLayout.profileData.rating >= 0 ? (profileInfoLayout.profileData.rating / 100).toFixed(2) : "-")
                                        font.pixelSize: 13
                                        color: Theme.textSecondary
                                    }
                                }
                                
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 320
                                    Layout.preferredHeight: 70
                                    color: Theme.bgCard
                                    border.color: profileDescArea.activeFocus ? Theme.browserDesc : Theme.borderCard
                                    radius: 4

                                    TextEdit {
                                        id: profileDescArea
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        text: settingsHandler ? settingsHandler.getProfileDescription() : ""
                                        font.pixelSize: 13
                                        color: Theme.textSecondary
                                        wrapMode: TextEdit.Wrap
                                        selectByMouse: true
                                        
                                        Text {
                                            text: "Write a short description (max 120 chars)..."
                                            color: Theme.textFaint
                                            font.pixelSize: 13
                                            visible: !profileDescArea.text
                                        }

                                        onTextChanged: {
                                            if (text.length > 120) {
                                                var cursor = cursorPosition;
                                                text = text.substring(0, 120);
                                                cursorPosition = cursor > 120 ? 120 : cursor;
                                            }
                                        }
                                        onActiveFocusChanged: {
                                            if (!activeFocus && settingsHandler) {
                                                settingsHandler.setProfileDescription(text)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Item {
                                Layout.preferredHeight: profileInfoLayout.profileData.connected ? 10 : 0
                            }
                        }
                        
                        FileDialog {
                            id: fileDialog
                            title: "Select Profile Image"
                            nameFilters: ["Image files (*.png *.jpg *.jpeg *.webp)"]
                            onAccepted: if (settingsHandler) settingsHandler.setProfileImage(fileDialog.selectedFile)
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Privacy Options
                    Text { text: "Privacy"; font.bold: true; color: Theme.textPrimary }
                    ColumnLayout {
                        spacing: 10
                        RowLayout {
                            spacing: 30
                            ThemedCheckBox {
                                text: "Show Name"
                                checked: settingsHandler ? settingsHandler.getShowName() : true
                                onCheckedChanged: if (settingsHandler) settingsHandler.setShowName(checked)
                            }
                            ThemedCheckBox {
                                text: "Show Friend Code"
                                checked: settingsHandler ? settingsHandler.getShowFriendCode() : false
                                onCheckedChanged: if (settingsHandler) settingsHandler.setShowFriendCode(checked)
                            }
                            ThemedCheckBox {
                                text: "Show Potential"
                                checked: settingsHandler ? settingsHandler.getShowPotential() : false
                                onCheckedChanged: if (settingsHandler) settingsHandler.setShowPotential(checked)
                            }
                        }
                        ThemedCheckBox {
                            text: "Show Description"
                            checked: settingsHandler ? settingsHandler.getShowDescription() : true
                            onCheckedChanged: if (settingsHandler) settingsHandler.setShowDescription(checked)
                        }
                        ThemedCheckBox {
                            id: showPlayCountTimeCheckBox
                            text: "Show Play Count & Play Time"
                            checked: settingsHandler ? settingsHandler.getShowPlayCountTime() : true
                            onCheckedChanged: if (settingsHandler) settingsHandler.setShowPlayCountTime(checked)
                        }
                        
                        // Play Stats Difficulty Filter
                        RowLayout {
                            id: playStatsDiffFilterRow
                            Layout.leftMargin: 20
                            visible: showPlayCountTimeCheckBox.checked
                            
                            property bool pstChecked: true
                            property bool prsChecked: true
                            property bool ftrChecked: true
                            property bool etrChecked: true
                            property bool bydChecked: true
                            property bool isOff: false

                            function loadFromConfig() {
                                if (!settingsHandler) return
                                var raw = settingsHandler.getPlayStatsDiffFilter()
                                if (raw === "all") {
                                    pstChecked = prsChecked = ftrChecked = etrChecked = bydChecked = true
                                    isOff = false
                                } else if (raw === "off") {
                                    pstChecked = prsChecked = ftrChecked = etrChecked = bydChecked = true
                                    isOff = true
                                } else {
                                    isOff = false
                                    var parts = raw ? raw.split(",") : []
                                    pstChecked = parts.indexOf("pst") >= 0
                                    prsChecked = parts.indexOf("prs") >= 0
                                    ftrChecked = parts.indexOf("ftr") >= 0
                                    etrChecked = parts.indexOf("etr") >= 0
                                    bydChecked = parts.indexOf("byd") >= 0
                                }
                                updateAllState()
                            }

                            function applyToConfig() {
                                if (!settingsHandler) return
                                if (isOff) {
                                    settingsHandler.setPlayStatsDiffFilter("off")
                                } else {
                                    var parts = []
                                    if (pstChecked) parts.push("pst")
                                    if (prsChecked) parts.push("prs")
                                    if (ftrChecked) parts.push("ftr")
                                    if (etrChecked) parts.push("etr")
                                    if (bydChecked) parts.push("byd")

                                    if (parts.length === 5) {
                                        settingsHandler.setPlayStatsDiffFilter("all")
                                    } else if (parts.length === 0) {
                                        settingsHandler.setPlayStatsDiffFilter("off")
                                    } else {
                                        settingsHandler.setPlayStatsDiffFilter(parts.join(","))
                                    }
                                }
                                if (typeof statsHandler !== "undefined") statsHandler.refreshStats()
                            }

                            function updateAllState() {
                                if (isOff) {
                                    playStatsAllCheck.checkState = Qt.Unchecked
                                    playStatsAllCheck.text = "Off"
                                } else {
                                    var count =
                                        (pstChecked ? 1 : 0) +
                                        (prsChecked ? 1 : 0) +
                                        (ftrChecked ? 1 : 0) +
                                        (etrChecked ? 1 : 0) +
                                        (bydChecked ? 1 : 0)
                                    if (count === 0) {
                                        playStatsAllCheck.checkState = Qt.Unchecked
                                        playStatsAllCheck.text = "Off"
                                    } else {
                                        playStatsAllCheck.checkState = (count === 5) ? Qt.Checked : Qt.PartiallyChecked
                                        playStatsAllCheck.text = "On"
                                    }
                                }
                            }

                            Component.onCompleted: loadFromConfig()

                            spacing: 10
                            Text { text: "Difficulty Filter:"; color: Theme.textPrimary }

                            ThemedCheckBox {
                                id: playStatsAllCheck
                                text: "On"
                                tristate: true
                                onClicked: {
                                    if (playStatsDiffFilterRow.isOff) {
                                        // turn on (all checked)
                                        playStatsDiffFilterRow.isOff = false
                                        playStatsDiffFilterRow.pstChecked = true
                                        playStatsDiffFilterRow.prsChecked = true
                                        playStatsDiffFilterRow.ftrChecked = true
                                        playStatsDiffFilterRow.etrChecked = true
                                        playStatsDiffFilterRow.bydChecked = true
                                    } else {
                                        var count = (playStatsDiffFilterRow.pstChecked ? 1 : 0) +
                                                    (playStatsDiffFilterRow.prsChecked ? 1 : 0) +
                                                    (playStatsDiffFilterRow.ftrChecked ? 1 : 0) +
                                                    (playStatsDiffFilterRow.etrChecked ? 1 : 0) +
                                                    (playStatsDiffFilterRow.bydChecked ? 1 : 0)
                                        if (count === 5) {
                                            // all checked -> turn off
                                            playStatsDiffFilterRow.isOff = true
                                        } else {
                                            // partial -> check all
                                            playStatsDiffFilterRow.isOff = false
                                            playStatsDiffFilterRow.pstChecked = true
                                            playStatsDiffFilterRow.prsChecked = true
                                            playStatsDiffFilterRow.ftrChecked = true
                                            playStatsDiffFilterRow.etrChecked = true
                                            playStatsDiffFilterRow.bydChecked = true
                                        }
                                    }
                                    playStatsDiffFilterRow.applyToConfig()
                                    playStatsDiffFilterRow.updateAllState()
                                }
                            }

                            ThemedCheckBox {
                                text: "PST"
                                checked: playStatsDiffFilterRow.pstChecked
                                enabled: !playStatsDiffFilterRow.isOff
                                onToggled: {
                                    playStatsDiffFilterRow.pstChecked = checked
                                    playStatsDiffFilterRow.applyToConfig()
                                    playStatsDiffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "PRS"
                                checked: playStatsDiffFilterRow.prsChecked
                                enabled: !playStatsDiffFilterRow.isOff
                                onToggled: {
                                    playStatsDiffFilterRow.prsChecked = checked
                                    playStatsDiffFilterRow.applyToConfig()
                                    playStatsDiffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "FTR"
                                checked: playStatsDiffFilterRow.ftrChecked
                                enabled: !playStatsDiffFilterRow.isOff
                                onToggled: {
                                    playStatsDiffFilterRow.ftrChecked = checked
                                    playStatsDiffFilterRow.applyToConfig()
                                    playStatsDiffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "ETR"
                                checked: playStatsDiffFilterRow.etrChecked
                                enabled: !playStatsDiffFilterRow.isOff
                                onToggled: {
                                    playStatsDiffFilterRow.etrChecked = checked
                                    playStatsDiffFilterRow.applyToConfig()
                                    playStatsDiffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "BYD"
                                checked: playStatsDiffFilterRow.bydChecked
                                enabled: !playStatsDiffFilterRow.isOff
                                onToggled: {
                                    playStatsDiffFilterRow.bydChecked = checked
                                    playStatsDiffFilterRow.applyToConfig()
                                    playStatsDiffFilterRow.updateAllState()
                                }
                            }
                        }
                        
                        ThemedCheckBox {
                            text: "Show Play Count in Most Played"
                            checked: settingsHandler ? settingsHandler.getShowPlayCountMostPlayed() : true
                            onCheckedChanged: if (settingsHandler) settingsHandler.setShowPlayCountMostPlayed(checked)
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }
                    
                    // Most Played Order
                    Text { text: "Most Played Order"; font.bold: true; color: Theme.textPrimary }
                    
                    ColumnLayout {
                        spacing: 15
                        
                        // Grouping Criteria
                        RowLayout {
                            spacing: 10
                            Text { text: "Grouping Criteria:"; color: Theme.textPrimary }
                            ThemedRadioButton {
                                text: "By Song"
                                checked: settingsHandler ? settingsHandler.getGroupingCriteria() === 'song' : true
                                onToggled: if(checked && settingsHandler) settingsHandler.setGroupingCriteria('song')
                            }
                            ThemedRadioButton {
                                text: "By Chart"
                                checked: settingsHandler ? settingsHandler.getGroupingCriteria() === 'chart' : false
                                onToggled: if(checked && settingsHandler) settingsHandler.setGroupingCriteria('chart')
                            }
                        }
                        
                        // Difficulty Filter
                        RowLayout {
                            id: diffFilterRow
                            // 개별 난이도 체크 상태를 로컬로 관리
                            property bool pstChecked: true
                            property bool prsChecked: true
                            property bool ftrChecked: true
                            property bool etrChecked: true
                            property bool bydChecked: true

                            // 설정에서 초기값 로드
                            function loadFromConfig() {
                                if (!settingsHandler) return
                                var raw = settingsHandler.getDifficultyFilter()
                                if (raw === "all") {
                                    pstChecked = prsChecked = ftrChecked = etrChecked = bydChecked = true
                                } else {
                                    var parts = raw ? raw.split(",") : []
                                    pstChecked = parts.indexOf("pst") >= 0
                                    prsChecked = parts.indexOf("prs") >= 0
                                    ftrChecked = parts.indexOf("ftr") >= 0
                                    etrChecked = parts.indexOf("etr") >= 0
                                    bydChecked = parts.indexOf("byd") >= 0
                                }
                                updateAllState()
                            }

                            // 현재 체크 상태를 config 문자열로 반영
                            function applyToConfig() {
                                if (!settingsHandler) return
                                var parts = []
                                if (pstChecked) parts.push("pst")
                                if (prsChecked) parts.push("prs")
                                if (ftrChecked) parts.push("ftr")
                                if (etrChecked) parts.push("etr")
                                if (bydChecked) parts.push("byd")

                                if (parts.length === 5) {
                                    settingsHandler.setDifficultyFilter("all")
                                } else if (parts.length === 0) {
                                    // 아무 난이도도 선택되지 않은 상태는 빈 문자열로 저장
                                    settingsHandler.setDifficultyFilter("")
                                } else {
                                    settingsHandler.setDifficultyFilter(parts.join(","))
                                }
                            }

                            function updateAllState() {
                                var count =
                                    (pstChecked ? 1 : 0) +
                                    (prsChecked ? 1 : 0) +
                                    (ftrChecked ? 1 : 0) +
                                    (etrChecked ? 1 : 0) +
                                    (bydChecked ? 1 : 0)
                                if (count === 0)
                                    allCheck.checkState = Qt.Unchecked
                                else if (count === 5)
                                    allCheck.checkState = Qt.Checked
                                else
                                    allCheck.checkState = Qt.PartiallyChecked
                            }

                            Component.onCompleted: loadFromConfig()

                            spacing: 10
                            Text { text: "Difficulty Filter:"; color: Theme.textPrimary }

                            // All 체크박스: pst/prs/ftr/etr/byd 상태에 따라 삼진(check / partial / unchecked)
                            ThemedCheckBox {
                                id: allCheck
                                text: "All"
                                tristate: true
                                onClicked: {
                                    // 현재 개별 난이도 상태 기준으로 토글:
                                    // 5개 모두 체크 상태이면 모두 해제, 그 외(0개 또는 일부 체크)는 모두 선택
                                    var count =
                                        (diffFilterRow.pstChecked ? 1 : 0) +
                                        (diffFilterRow.prsChecked ? 1 : 0) +
                                        (diffFilterRow.ftrChecked ? 1 : 0) +
                                        (diffFilterRow.etrChecked ? 1 : 0) +
                                        (diffFilterRow.bydChecked ? 1 : 0)
                                    var makeChecked = !(count === 5)
                                    diffFilterRow.pstChecked = makeChecked
                                    diffFilterRow.prsChecked = makeChecked
                                    diffFilterRow.ftrChecked = makeChecked
                                    diffFilterRow.etrChecked = makeChecked
                                    diffFilterRow.bydChecked = makeChecked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }

                            ThemedCheckBox {
                                text: "PST"
                                checked: diffFilterRow.pstChecked
                                onToggled: {
                                    diffFilterRow.pstChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "PRS"
                                checked: diffFilterRow.prsChecked
                                onToggled: {
                                    diffFilterRow.prsChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "FTR"
                                checked: diffFilterRow.ftrChecked
                                onToggled: {
                                    diffFilterRow.ftrChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "ETR"
                                checked: diffFilterRow.etrChecked
                                onToggled: {
                                    diffFilterRow.etrChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            ThemedCheckBox {
                                text: "BYD"
                                checked: diffFilterRow.bydChecked
                                onToggled: {
                                    diffFilterRow.bydChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                        }

                        // Aggregation scope (Most Played count: total vs this year)
                        RowLayout {
                            spacing: 10
                            Text { text: "Aggregation Scope:"; color: Theme.textPrimary }
                            ThemedRadioButton {
                                text: "Total plays"
                                checked: settingsHandler ? settingsHandler.getMostPlayedScope() === 'total' : true
                                onToggled: if(checked && settingsHandler) settingsHandler.setMostPlayedScope('total')
                            }
                            ThemedRadioButton {
                                text: "This year plays"
                                checked: settingsHandler ? settingsHandler.getMostPlayedScope() === 'this_year' : false
                                onToggled: if(checked && settingsHandler) settingsHandler.setMostPlayedScope('this_year')
                            }
                        }
                    }
                }
            }
        }
    }

        Basic.ScrollBar {
            id: settingsVerticalBar
            z: 10
            anchors.top: parent.top
            anchors.topMargin: scrollView.topPadding
            anchors.bottom: parent.bottom
            anchors.bottomMargin: scrollView.bottomPadding
            anchors.right: parent.right
            anchors.rightMargin: 4
            width: 10

            policy: ScrollBar.AlwaysOn
            size: scrollView.contentItem ? scrollView.contentItem.visibleArea.heightRatio : 1
            position: scrollView.contentItem ? scrollView.contentItem.visibleArea.yPosition : 0

            onPositionChanged: {
                if (pressed && scrollView.contentItem)
                    scrollView.contentItem.contentY = position * scrollView.contentItem.contentHeight
            }

            property bool showScrollbar: (scrollView.contentItem && scrollView.contentItem.moving)
                                          || settingsHideTimer.running
                                          || settingsVerticalBar.hovered
                                          || settingsVerticalBar.pressed
            hoverEnabled: true
            active: true

            Timer { id: settingsHideTimer; interval: 1000 }
            Connections {
                target: scrollView.contentItem
                function onMovingChanged() {
                    if (!scrollView.contentItem.moving)
                        settingsHideTimer.restart()
                }
            }
            onPressedChanged: {
                if (!pressed && scrollView.contentItem && !scrollView.contentItem.moving)
                    settingsHideTimer.restart()
            }

            opacity: showScrollbar ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            background: Rectangle { color: "transparent" }
            contentItem: Rectangle {
                implicitWidth: 6
                implicitHeight: 100
                radius: 3
                color: Theme.scrollbar
                opacity: settingsVerticalBar.pressed ? 1.0 : (settingsVerticalBar.hovered ? 1.0 : 0.6)
            }
        }
    }
}
