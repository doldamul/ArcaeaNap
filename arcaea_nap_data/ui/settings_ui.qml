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

    // Re-fetch sheet versions when window becomes visible
    // (Component.onCompleted fires before the window is shown,
    //  so the loading spinner is never seen by the user)
    onVisibleChanged: {
        if (visible && settingsHandler && sheetMgmtCard && sheetMgmtCard.hasBoundSheet) {
            settingsHandler.fetchSheetVersions()
        }
    }

    // Cache Migration Loading Modal
    property bool isMigrating: false
    
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
                    sheetMgmtCard.sheetVersions = "{}"
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
                if (sheetMgmtCard.hasBoundSheet) settingsHandler.fetchSheetVersions()
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

    ScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: availableWidth
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
                        onAccepted: if (settingsHandler) settingsHandler.prepareCacheMigration(folderDialog.selectedFolder)
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
                            property string connectionInfo: settingsHandler ? settingsHandler.getArcaeaOnlineConnectionInfo() : "{}"
                            
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
                                        if (!arcaeaButton.connectionInfo || arcaeaButton.connectionInfo === "{}") return ""
                                        try {
                                            var info = JSON.parse(arcaeaButton.connectionInfo)
                                            var displayName = info.name || info.user_id || ""
                                            if (displayName) {
                                                var date = new Date(info.connected_at * 1000)
                                                return displayName + "\n" + Qt.formatDateTime(date, "yyyy-MM-dd hh:mm")
                                            }
                                        } catch(e) {
                                            console.log("Error parsing Arcaea connection info:", e)
                                        }
                                        return ""
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

                            BusyIndicator {
                                anchors.centerIn: parent
                                width: 64
                                height: 64
                                running: arcaeaButton.isConnecting
                                visible: arcaeaButton.isConnecting
                                
                                contentItem: Item {
                                    anchors.fill: parent
                                    
                                    Canvas {
                                        anchors.fill: parent
                                        rotation: 0
                                        
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.beginPath()
                                            ctx.arc(width/2, height/2, width/2 - 4, 0, 0.7 * Math.PI)
                                            ctx.lineWidth = 3
                                            ctx.strokeStyle = "white"
                                            ctx.lineCap = "round"
                                            ctx.stroke()
                                        }
                                        
                                        RotationAnimation on rotation {
                                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                                            running: arcaeaButton.isConnecting
                                        }
                                        
                                        onAvailableChanged: if(available) requestPaint()
                                    }
                                }
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
                            property string connectionInfo: settingsHandler ? settingsHandler.getGoogleSheetConnectionInfo() : "{}"
                            
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
                                        if (!googleButton.connectionInfo || googleButton.connectionInfo === "{}") return ""
                                        try {
                                            var info = JSON.parse(googleButton.connectionInfo)
                                            if (info && info.user_email) {
                                                var date = new Date(info.connected_at * 1000)
                                                return info.user_email + "\n" + Qt.formatDateTime(date, "yyyy-MM-dd hh:mm")
                                            }
                                        } catch(e) {
                                            console.log("Error parsing Google connection info:", e)
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
                        property string boundSheetInfo: settingsHandler ? settingsHandler.getBoundSheetInfo() : "{}"
                        property bool isBinding: settingsHandler ? settingsHandler.isBindingSheet() : false
                        property bool isSending: settingsHandler ? settingsHandler.isSendingData() : false
                        property real lastSynced: settingsHandler ? settingsHandler.getLastSyncedTime() : 0
                        property string sheetVersions: settingsHandler ? settingsHandler.getSheetVersions() : "{}"
                        property string parsedSheetVer: "?"
                        property string parsedArcaeaVer: "?"
                        
                        onSheetVersionsChanged: {
                            try {
                                var v = JSON.parse(sheetVersions)
                                parsedSheetVer = (v && v.sheet_ver) ? String(v.sheet_ver) : '?'
                                parsedArcaeaVer = (v && v.arcaea_ver) ? String(v.arcaea_ver) : '?'
                            } catch(e) {
                                parsedSheetVer = '?'
                                parsedArcaeaVer = '?'
                            }
                        }
                        
                        property bool hasBoundSheet: false
                        property string boundSheetName: ""
                        
                        // Explicitly update derived properties when boundSheetInfo changes
                        // (JavaScript block bindings may fail to re-evaluate after imperative assignment)
                        onBoundSheetInfoChanged: {
                            try {
                                var info = JSON.parse(boundSheetInfo)
                                hasBoundSheet = !!(info && info.sheet_id && info.sheet_id !== "")
                                boundSheetName = (info && info.sheet_name) ? info.sheet_name : ""
                            } catch(e) {
                                hasBoundSheet = false
                                boundSheetName = ""
                            }
                        }
                        
                        Component.onCompleted: {
                            // Compute initial derived properties
                            try {
                                var info = JSON.parse(boundSheetInfo)
                                hasBoundSheet = !!(info && info.sheet_id && info.sheet_id !== "")
                                boundSheetName = (info && info.sheet_name) ? info.sheet_name : ""
                            } catch(e) {
                                hasBoundSheet = false
                                boundSheetName = ""
                            }
                            try {
                                var v = JSON.parse(sheetVersions)
                                parsedSheetVer = (v && v.sheet_ver) ? String(v.sheet_ver) : '?'
                                parsedArcaeaVer = (v && v.arcaea_ver) ? String(v.arcaea_ver) : '?'
                            } catch(e) {
                                parsedSheetVer = '?'
                                parsedArcaeaVer = '?'
                            }
                            if (settingsHandler && hasBoundSheet) {
                                settingsHandler.fetchSheetVersions()
                            }
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
                                                Item {
                                                    implicitWidth: 11; implicitHeight: 11
                                                    visible: !sheetMgmtCard.parsedSheetVer || sheetMgmtCard.parsedSheetVer === '?'
                                                    Canvas {
                                                        anchors.fill: parent
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.clearRect(0, 0, width, height)
                                                            ctx.beginPath()
                                                            ctx.arc(width/2, height/2, width/2 - 1.5, 0, 1.4 * Math.PI)
                                                            ctx.lineWidth = 1.5
                                                            ctx.strokeStyle = "#333"
                                                            ctx.lineCap = "round"
                                                            ctx.stroke()
                                                        }
                                                        RotationAnimation on rotation {
                                                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                                                            running: parent.visible
                                                        }
                                                        onAvailableChanged: if(available) requestPaint()
                                                    }
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
                                                Item {
                                                    implicitWidth: 11; implicitHeight: 11
                                                    visible: !sheetMgmtCard.parsedArcaeaVer || sheetMgmtCard.parsedArcaeaVer === '?'
                                                    Canvas {
                                                        anchors.fill: parent
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.clearRect(0, 0, width, height)
                                                            ctx.beginPath()
                                                            ctx.arc(width/2, height/2, width/2 - 1.5, 0, 1.4 * Math.PI)
                                                            ctx.lineWidth = 1.5
                                                            ctx.strokeStyle = "#333"
                                                            ctx.lineCap = "round"
                                                            ctx.stroke()
                                                        }
                                                        RotationAnimation on rotation {
                                                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                                                            running: parent.visible
                                                        }
                                                        onAvailableChanged: if(available) requestPaint()
                                                    }
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
                                        Item {
                                            Layout.preferredWidth: 14
                                            Layout.preferredHeight: 14
                                            visible: sheetMgmtCard.isSending
                                            
                                            Canvas {
                                                anchors.fill: parent
                                                onPaint: {
                                                    var ctx = getContext("2d")
                                                    ctx.clearRect(0, 0, width, height)
                                                    ctx.beginPath()
                                                    ctx.arc(width/2, height/2, width/2 - 1.5, 0, 1.4 * Math.PI)
                                                    ctx.lineWidth = 2
                                                    ctx.strokeStyle = "white"
                                                    ctx.lineCap = "round"
                                                    ctx.stroke()
                                                }
                                                RotationAnimation on rotation {
                                                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                                                    running: parent.visible
                                                }
                                                onAvailableChanged: if(available) requestPaint()
                                            }
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
                    Text { text: "Song Database"; font.bold: true; color: "#333" }
                    
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
                                Text { text: "Update Song Database"; font.bold: true; color: "#1976D2" }
                                Text { text: "Rebuild song database from online sources"; font.pixelSize: 11; color: "#1976D2" }
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Basic.Button {
                                id: updateDbButton
                                text: settingsHandler && settingsHandler.isUpdatingSongDatabase() ? "Updating..." : "Update"
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
                        Layout.fillWidth: true
                        spacing: 20
                        
                        Rectangle {
                            width: 80; height: 80
                            radius: 40
                            color: "#F0F0F0"
                            border.color: "#E0E0E0"
                            clip: true
                            
                            Image {
                                anchors.fill: parent
                                source: (settingsHandler && settingsHandler.getProfileImage()) ? "file:///" + settingsHandler.getProfileImage() : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: source != ""
                            }
                            
                            Text {
                                anchors.centerIn: parent
                                text: "No\nImg"
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter
                                visible: parent.children[0].status !== Image.Ready
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
                            
                            Button {
                                text: "Set Profile Image"
                                onClicked: fileDialog.open()
                            }
                        }
                        
                        FileDialog {
                            id: fileDialog
                            title: "Select Profile Image"
                            nameFilters: ["Image files (*.png *.jpg *.jpeg)"]
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
                            spacing: 10
                            Text { text: "Difficulty Filter:" }
                            
                            property string currentFilters: settingsHandler ? settingsHandler.getDifficultyFilter() : 'all'
                            
                            CheckBox {
                                text: "All"
                                checked: parent.currentFilters === 'all'
                                onToggled: if(checked && settingsHandler) settingsHandler.setDifficultyFilter('all')
                            }
                            
                            // Helper to toggle specific diff
                            function toggleDiff(diffCode) {
                                if (!settingsHandler) return
                                if (currentFilters === 'all') {
                                    settingsHandler.setDifficultyFilter(diffCode)
                                } else {
                                    var parts = currentFilters.split(',')
                                    var idx = parts.indexOf(diffCode)
                                    if (idx >= 0) parts.splice(idx, 1)
                                    else parts.push(diffCode)
                                    
                                    if (parts.length === 0) settingsHandler.setDifficultyFilter('all')
                                    else settingsHandler.setDifficultyFilter(parts.join(','))
                                }
                            }
                            
                            function isDiffChecked(diffCode) {
                                return currentFilters !== 'all' && currentFilters.split(',').includes(diffCode)
                            }
                            
                            CheckBox { text: "PST"; checked: parent.isDiffChecked('pst'); onToggled: parent.toggleDiff('pst') }
                            CheckBox { text: "PRS"; checked: parent.isDiffChecked('prs'); onToggled: parent.toggleDiff('prs') }
                            CheckBox { text: "FTR"; checked: parent.isDiffChecked('ftr'); onToggled: parent.toggleDiff('ftr') }
                            CheckBox { text: "ETR"; checked: parent.isDiffChecked('etr'); onToggled: parent.toggleDiff('etr') }
                            CheckBox { text: "BYD"; checked: parent.isDiffChecked('byd'); onToggled: parent.toggleDiff('byd') }
                        }
                    }


                }
            }


            
            // Bottom Spacer
            Item { height: 40 }
        }
    }
}
