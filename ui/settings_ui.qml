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
    title: "Settings"
    color: "#F3F4F8"
    
    // 메인 윈도우 위에 고정되지 않도록 부모 관계 해제
    transientParent: null

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
        color: "#80000000"
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
            color: "#FFFFFF"
            
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
                    color: "#333"
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
            color: "#FFFFFF"
            radius: 12
            border.color: "#E53935"
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
                color: "#E53935"
            }
            
            Text {
                id: errorMessageText
                wrapMode: Text.WordWrap
                width: parent.width
                color: "#333"
            }
            
            Basic.Button {
                text: "OK"
                anchors.right: parent.right
                onClicked: errorPopup.close()
                background: Rectangle { color: "#F0F0F0"; radius: 6 }
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
            color: "#FFFFFF"
            radius: 12
            border.color: "#FB8C00"
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
                color: "#E65100"
            }

            Text {
                id: songDbWriteConflictText
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#333"
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Basic.Button {
                    text: "Cancel"
                    onClicked: songDbWriteConflictPopup.close()
                    background: Rectangle { color: "#F0F0F0"; radius: 6 }
                }

                Basic.Button {
                    text: "Force Update"
                    onClicked: {
                        songDbWriteConflictPopup.close()
                        if (settingsHandler) settingsHandler.forceUpdateSongDatabase()
                    }
                    background: Rectangle { color: "#FB8C00"; radius: 6 }
                    contentItem: Text {
                        text: "Force Update"
                        color: "white"
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
            color: "#FFFFFF"
            radius: 12
            border.color: "#E0E0E0"
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
                    color: "#333"
                    wrapMode: Text.WordWrap
                }

                Basic.Button {
                    text: "✕"
                    hoverEnabled: true
                    onClicked: cachePathModeDialog.close()
                    background: Rectangle {
                        color: parent.hovered ? "#EFEFEF" : "transparent"
                        radius: 12
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
                color: "#444"
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
                    background: Rectangle { color: "#F0F0F0"; radius: 8 }
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
                    background: Rectangle { color: "#F0F0F0"; radius: 8 }
                }
            }
        }
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        clip: true
        padding: 40

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: 30

            // --- 1. General Section ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: generalLayout.implicitHeight + 60
                color: "#FFFFFF"
                radius: 20
                border.color: "#E0E0E0"; border.width: 1

                ColumnLayout {
                    id: generalLayout
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 24

                    // Header
                    Text { text: "General"; font.bold: true; font.pixelSize: 18; color: "#333" }

                    // Account Connections
                    Text { text: "Account Connections"; font.bold: true; color: "#333" }
                    RowLayout {
                        spacing: 20
                        
                        // Arcaea Online Button
                        Rectangle {
                            id: arcaeaButton
                            width: 200; height: 80
                            radius: 10
                            color: isConnected ? "#F3E5F5" : "#F0F0F0"
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
                                    color: arcaeaButton.isConnected ? "#6A0DAD" : "#424242"
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
                                    color: "#757575"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                
                                Text {
                                    visible: !arcaeaButton.isConnected
                                    text: "Not Connected"
                                    font.pixelSize: 11
                                    color: "#E53935"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            
                            // Hover overlay
                            Rectangle {
                                anchors.fill: parent
                                color: "#80000000"
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
                                            return arcaeaButtonMouseArea.containsMouse ? "white" : "#CCCCCC"
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
                            color: isConnected ? "#E8F5E9" : "#F0F0F0"
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
                                    color: googleButton.isConnected ? "#2E7D32" : "#424242"
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
                                    color: "#757575"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                
                                Text {
                                    visible: !googleButton.isConnected
                                    text: "Not Connected"
                                    font.pixelSize: 11
                                    color: "#E53935"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            
                            // Hover overlay
                            Rectangle {
                                anchors.fill: parent
                                color: "#80000000"
                                radius: parent.radius
                                visible: googleButtonMouseArea.containsMouse
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: googleButton.isConnected ? "Disconnect" : "Connect"
                                    color: "white"
                                    font.bold: true
                                    font.pixelSize: 14
                                }
                            }
                            
                            MouseArea {
                                id: googleButtonMouseArea
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
                            color: "#FFFFFF"
                            radius: 12
                            border.color: "#E0E0E0"
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
                                color: "#333"
                            }
                            
                            RowLayout {
                                anchors.right: parent.right
                                spacing: 10
                                
                                Basic.Button {
                                    text: "Cancel"
                                    onClicked: disconnectArcaeaDialog.close()
                                    background: Rectangle { color: "#F0F0F0"; radius: 6 }
                                }
                                
                                Basic.Button {
                                    text: "Disconnect"
                                    onClicked: {
                                        if (settingsHandler) settingsHandler.disconnectArcaeaOnline()
                                        disconnectArcaeaDialog.close()
                                    }
                                    background: Rectangle { color: "#E53935"; radius: 6 }
                                    contentItem: Text {
                                        text: parent.text
                                        color: "white"
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
                            color: "#FFFFFF"
                            radius: 12
                            border.color: "#E0E0E0"
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
                                color: "#333"
                            }
                            
                            RowLayout {
                                anchors.right: parent.right
                                spacing: 10
                                
                                Basic.Button {
                                    text: "Cancel"
                                    onClicked: disconnectGoogleDialog.close()
                                    background: Rectangle { color: "#F0F0F0"; radius: 6 }
                                }
                                
                                Basic.Button {
                                    text: "Disconnect"
                                    onClicked: {
                                        if (settingsHandler) settingsHandler.disconnectGoogleSheet()
                                        disconnectGoogleDialog.close()
                                    }
                                    background: Rectangle { color: "#E53935"; radius: 6 }
                                    contentItem: Text {
                                        text: parent.text
                                        color: "white"
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Database Management
                    // Arcaea Consultant Sheet Section
                    Text { text: "Arcaea Consultant Sheet"; font.bold: true; color: "#333" }
                    
                    // Sheet Management Card
                    Rectangle {
                        id: sheetMgmtCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: sheetMgmtLayout.implicitHeight + 30
                        color: "#FFFFFF"
                        radius: 12
                        border.color: "#E0E0E0"; border.width: 1
                        
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
                            // Text { text: "Sheet Management"; font.bold: true; color: "#2E7D32"; font.pixelSize: 13 }
                            
                            // State: No sheet bound - show Bind Sheet button
                            Basic.Button {
                                id: bindSheetButton
                                Layout.fillWidth: true
                                visible: !sheetMgmtCard.hasBoundSheet && !sheetMgmtCard.isBinding
                                text: "Bind Sheet"
                                onClicked: if (settingsHandler) settingsHandler.bindSheet()
                                background: Rectangle {
                                    color: bindSheetButton.down ? "#43A047" : "#4CAF50"
                                    radius: 8
                                }
                                contentItem: Text {
                                    text: bindSheetButton.text
                                    color: "white"
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
                                    color: "#757575"
                                    font.pixelSize: 12
                                    Layout.fillWidth: true
                                }
                                Basic.Button {
                                    text: "Cancel"
                                    onClicked: if (settingsHandler) settingsHandler.cancelBindSheet()
                                    background: Rectangle { color: "#F0F0F0"; radius: 6 }
                                    contentItem: Text { text: "Cancel"; color: "#333"; font.pixelSize: 11; anchors.centerIn: parent }
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
                                    color: "#333"
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
                                            color: "#E8F5E9"
                                            radius: 4
                                            implicitWidth: verRow1.implicitWidth + 16
                                            implicitHeight: verRow1.implicitHeight + 8
                                            
                                            RowLayout {
                                                id: verRow1
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: "Sheet"; font.pixelSize: 11; color: "#2E7D32"; font.bold: true }
                                                SpinnerIndicator {
                                                    implicitWidth: 11; implicitHeight: 11
                                                    lineWidth: 1.5
                                                    strokeColor: "#333"
                                                    running: !sheetMgmtCard.parsedSheetVer || sheetMgmtCard.parsedSheetVer === '?'
                                                }
                                                Text {
                                                    text: sheetMgmtCard.parsedSheetVer || ''
                                                    font.pixelSize: 11; color: "#333"
                                                    visible: sheetMgmtCard.parsedSheetVer && sheetMgmtCard.parsedSheetVer !== '?'
                                                }
                                            }
                                        }
                                        
                                        Rectangle {
                                            color: "#E3F2FD"
                                            radius: 4
                                            implicitWidth: verRow2.implicitWidth + 16
                                            implicitHeight: verRow2.implicitHeight + 8
                                            
                                            RowLayout {
                                                id: verRow2
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: "Arcaea"; font.pixelSize: 11; color: "#1565C0"; font.bold: true }
                                                SpinnerIndicator {
                                                    implicitWidth: 11; implicitHeight: 11
                                                    lineWidth: 1.5
                                                    strokeColor: "#333"
                                                    running: !sheetMgmtCard.parsedArcaeaVer || sheetMgmtCard.parsedArcaeaVer === '?'
                                                }
                                                Text {
                                                    text: sheetMgmtCard.parsedArcaeaVer || ''
                                                    font.pixelSize: 11; color: "#333"
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
                                        background: Rectangle { color: "#F1F8E9"; radius: 4; border.color: "#C5E1A5" }
                                        contentItem: Text { text: "Open Sheet"; color: "#33691E"; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        implicitHeight: 26
                                    }
                                    
                                    // Change sheet icon button
                                    Basic.Button {
                                        text: "🔄"
                                        onClicked: if (settingsHandler) settingsHandler.bindSheet()
                                        background: Rectangle { color: "#F5F5F5"; radius: 4; border.color: "#E0E0E0" }
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
                                            if (!sendDataButton.enabled) return "#B0BEC5"
                                            return sendDataButton.down ? "#5E35B1" : "#673AB7"
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
                                            color: "white"
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
                                    color: "#757575"
                                }
                            }
                        }
                        
                        // Disabled overlay when Google account not connected
                        Rectangle {
                            anchors.fill: parent
                            color: "#D0FFFFFF"
                            radius: parent.radius
                            visible: !sheetMgmtCard.isGoogleConnected
                            
                            Text {
                                anchors.centerIn: parent
                                text: "Connect Google account first"
                                font.pixelSize: 12
                                color: "#999"
                                font.italic: true
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                // Block all interactions
                            }
                        }
                    }
                    
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Database Management
                    Text {
                        text: settingsHandler && settingsHandler.isSongsDbExisting ? "Song Database" : "Generate Song Database"
                        font.bold: true; color: "#333"
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: 50
                        radius: 10
                        color: "#E3F2FD"
                        border.color: "#90CAF9"
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20; anchors.rightMargin: 20
                            
                            Column {
                                spacing: 2
                                Text {
                                    text: settingsHandler && settingsHandler.isSongsDbExisting ? "Update Song Database" : "Generate Song Database"
                                    font.bold: true; color: "#1976D2"
                                }
                                Text {
                                    text: settingsHandler && settingsHandler.isSongsDbExisting ? "Rebuild song database from online sources" : "Generate song database from online sources"
                                    font.pixelSize: 11; color: "#1976D2"
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
                                        if (!updateDbButton.enabled) return "#B0BEC5"
                                        return updateDbButton.down ? "#42A5F5" : "#64B5F6"
                                    }
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: updateDbButton.text
                                    color: "white"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Browser Setup
                    Text { text: "Browser"; font.bold: true; color: "#333" }

                    Rectangle {
                        id: browserSetupCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: browserSetupLayout.implicitHeight + 30
                        radius: 10
                        color: browserSetupCard.installed ? "#E8F5E9" : "#FFF3E0"
                        border.color: browserSetupCard.installed ? "#A5D6A7" : "#FFCC80"
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
                                        color: browserSetupCard.installed ? "#2E7D32" : "#E65100"
                                    }
                                    Text {
                                        text: browserSetupCard.installed
                                            ? "Browser is ready for analysis"
                                            : "Required for Arcaea Online analysis"
                                        font.pixelSize: 11
                                        color: browserSetupCard.installed ? "#4CAF50" : "#FF9800"
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
                                            if (!installBrowserBtn.enabled) return "#B0BEC5"
                                            return installBrowserBtn.down ? "#E65100" : "#FF9800"
                                        }
                                        radius: 6
                                    }
                                    contentItem: Text {
                                        text: installBrowserBtn.text
                                        color: "white"
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
                                color: "#666666"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

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
                                    color: "#333" 
                                }
                                
                                Text {
                                    text: "🛈"
                                    font.pixelSize: 14
                                    color: helpMouse.containsMouse ? "#6A0DAD" : "#999"
                                    
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
                                            color: "#FFFFFF"
                                            wrapMode: Text.WordWrap
                                        }
                                        
                                        background: Rectangle {
                                            color: "#333333"
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

                            Rectangle {
                                id: toggleTrack
                                anchors.fill: parent
                                radius: 13
                                color: analyzeToggle.checked ? "#6A0DAD" : "#E0E0E0"
                                border.color: analyzeToggle.checked ? "#6A0DAD" : "#CCCCCC"
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: analyzeToggle.checked ? parent.width - width - 2 : 2
                                    color: "white"
                                    
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

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Language
                    ColumnLayout {
                        spacing: 8
                        Text { text: "Language"; font.bold: true; color: "#333333" }
                        RowLayout {
                            spacing: 10
                            Text { text: "Song Title:" }
                            RadioButton {
                                text: "en"
                                checked: settingsHandler ? settingsHandler.getSongTitleLanguage() === 'en' : true
                                onToggled: if (checked && settingsHandler) settingsHandler.setSongTitleLanguage('en')
                            }
                            RadioButton {
                                text: "jp"
                                checked: settingsHandler ? settingsHandler.getSongTitleLanguage() === 'jp' : false
                                onToggled: if (checked && settingsHandler) settingsHandler.setSongTitleLanguage('jp')
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Cache Path
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "Cache Path"; font.bold: true; color: "#333" }
                        Text { text: "Location where scores and images are stored"; font.pixelSize: 12; color: "#888" }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            
                            Basic.TextField {
                                id: cachePathField
                                Layout.fillWidth: true
                                text: settingsHandler ? settingsHandler.getCachePath() : ""
                                readOnly: true
                                background: Rectangle {
                                    color: "#F5F5F5"; radius: 8; border.width: 0
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
                                background: Rectangle { color: "#F0F0F0"; radius: 8 }
                                onClicked: if (settingsHandler) settingsHandler.openCacheFolder()
                                Basic.ToolTip { text: "Open folder"; visible: parent.hovered }
                            }
                            
                            // Change folder button
                            Basic.Button {
                                text: "📁"
                                background: Rectangle { color: "#F0F0F0"; radius: 8 }
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
                color: "#FFFFFF"
                radius: 20
                border.color: "#E0E0E0"; border.width: 1

                ColumnLayout {
                    id: profileLayout
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 24

                    Text { text: "Profile"; font.bold: true; font.pixelSize: 18; color: "#333" }

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
                            color: "#F0F0F0"
                            border.color: "#E0E0E0"
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
                                color: "#80000000"
                                visible: profileImageRect.hoverActive
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "🖼️"
                                    color: "white"
                                    font.pixelSize: 24
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            // Small clear (✕) button on hover, top-right
                            Rectangle {
                                id: profileImageClearButton
                                width: 22; height: 22
                                radius: 11
                                color: clearProfileImageMouse.containsMouse ? "#F0F0F0" : "#E8E8E8"
                                border.color: "#D0D0D0"
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
                                    color: "#666"
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
                                    color: "#333"
                                }
                                RowLayout {
                                    spacing: 12
                                    Text {
                                        text: "ID: " + (profileInfoLayout.profileData.user_code || "Unknown")
                                        font.pixelSize: 13
                                        color: "#666"
                                    }
                                    Text {
                                        text: "PTT: " + (profileInfoLayout.profileData.rating !== undefined && profileInfoLayout.profileData.rating >= 0 ? (profileInfoLayout.profileData.rating / 100).toFixed(2) : "-")
                                        font.pixelSize: 13
                                        color: "#666"
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

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Privacy Options
                    Text { text: "Privacy"; font.bold: true; color: "#333" }
                    RowLayout {
                        spacing: 30
                        CheckBox {
                            text: "Show Friend Code"
                            checked: settingsHandler ? settingsHandler.getShowFriendCode() : false
                            onCheckedChanged: if (settingsHandler) settingsHandler.setShowFriendCode(checked)
                        }
                        CheckBox {
                            text: "Show Potential"
                            checked: settingsHandler ? settingsHandler.getShowPotential() : false
                            onCheckedChanged: if (settingsHandler) settingsHandler.setShowPotential(checked)
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }
                    
                    // Most Played Order
                    Text { text: "Most Played Order"; font.bold: true; color: "#333" }
                    
                    ColumnLayout {
                        spacing: 15
                        
                        // Grouping Criteria
                        RowLayout {
                            spacing: 10
                            Text { text: "Grouping Criteria:" }
                            RadioButton {
                                text: "By Song"
                                checked: settingsHandler ? settingsHandler.getGroupingCriteria() === 'song' : true
                                onToggled: if(checked && settingsHandler) settingsHandler.setGroupingCriteria('song')
                            }
                            RadioButton {
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
                            Text { text: "Difficulty Filter:" }

                            // All 체크박스: pst/prs/ftr/etr/byd 상태에 따라 삼진(check / partial / unchecked)
                            CheckBox {
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

                            CheckBox {
                                text: "PST"
                                checked: diffFilterRow.pstChecked
                                onToggled: {
                                    diffFilterRow.pstChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            CheckBox {
                                text: "PRS"
                                checked: diffFilterRow.prsChecked
                                onToggled: {
                                    diffFilterRow.prsChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            CheckBox {
                                text: "FTR"
                                checked: diffFilterRow.ftrChecked
                                onToggled: {
                                    diffFilterRow.ftrChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            CheckBox {
                                text: "ETR"
                                checked: diffFilterRow.etrChecked
                                onToggled: {
                                    diffFilterRow.etrChecked = checked
                                    diffFilterRow.applyToConfig()
                                    diffFilterRow.updateAllState()
                                }
                            }
                            CheckBox {
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
                            Text { text: "Aggregation Scope:" }
                            RadioButton {
                                text: "Total plays"
                                checked: settingsHandler ? settingsHandler.getMostPlayedScope() === 'total' : true
                                onToggled: if(checked && settingsHandler) settingsHandler.setMostPlayedScope('total')
                            }
                            RadioButton {
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
}
