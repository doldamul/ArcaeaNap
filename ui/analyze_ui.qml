import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls.Basic as Basic

Item {
    id: analyzeRoot
    anchors.fill: parent
    property string writeConflictMessage: ""
    readonly property var appWindow: ApplicationWindow.window
    readonly property string titleFontFamily: (appWindow && appWindow.titleFontFamily)
        ? appWindow.titleFontFamily
        : (appWindow ? appWindow.font.family : "")

    Connections {
        target: analysisHandler
        function onWriteConflictDetected(message) {
            analyzeRoot.writeConflictMessage = message
            writeConflictPopup.open()
        }
        function onBrowserNotInstalled() {
            browserNotInstalledPopup.open()
        }
    }

    Popup {
        id: writeConflictPopup
        anchors.centerIn: parent
        width: 420
        height: writeConflictContent.implicitHeight + 40
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
            id: writeConflictContent
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
                text: analyzeRoot.writeConflictMessage
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#333333"
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Button {
                    text: "Cancel"
                    onClicked: writeConflictPopup.close()
                }

                Button {
                    text: "Force Start"
                    onClicked: {
                        writeConflictPopup.close()
                        analysisHandler.startAnalysisForce()
                    }
                }
            }
        }
    }

    Popup {
        id: browserNotInstalledPopup
        anchors.centerIn: parent
        width: 420
        height: browserNotInstalledContent.implicitHeight + 40
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#FFFFFF"
            radius: 12
            border.color: "#E65100"
            border.width: 2
        }

        Column {
            id: browserNotInstalledContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: "⚠ Browser Not Installed"
                font.bold: true
                font.pixelSize: 16
                color: "#E65100"
            }

            Text {
                text: "Playwright Chromium browser is required for analysis.\nPlease install it from the Settings tab before starting."
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#333333"
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Button {
                    text: "Close"
                    onClicked: browserNotInstalledPopup.close()
                }

                Button {
                    text: "Go to Settings"
                    onClicked: {
                        browserNotInstalledPopup.close()
                        if (analyzeRoot.appWindow && analyzeRoot.appWindow.settingsWindow) {
                            analyzeRoot.appWindow.settingsWindow.show()
                            analyzeRoot.appWindow.settingsWindow.raise()
                            analyzeRoot.appWindow.settingsWindow.requestActivate()
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: dbMissingAnalyzePopup
        anchors.centerIn: parent
        width: 420
        height: dbMissingAnalyzeContent.implicitHeight + 40
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#FFFFFF"
            radius: 12
            border.color: "#E65100"
            border.width: 2
        }

        Column {
            id: dbMissingAnalyzeContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: "⚠ Database Missing"
                font.bold: true
                font.pixelSize: 16
                color: "#E65100"
            }

            Text {
                text: "songs.db is required for analysis.\nPlease generate it from the Settings."
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#333333"
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Button {
                    text: "Close"
                    onClicked: dbMissingAnalyzePopup.close()
                }

                Button {
                    text: "Go to Settings"
                    onClicked: {
                        dbMissingAnalyzePopup.close()
                        if (analyzeRoot.appWindow && analyzeRoot.appWindow.settingsWindow) {
                            analyzeRoot.appWindow.settingsWindow.show()
                            analyzeRoot.appWindow.settingsWindow.raise()
                            analyzeRoot.appWindow.settingsWindow.requestActivate()
                        }
                    }
                }
            }
        }
    }

    // --- 메인 컨텐츠 영역 ---
    ScrollView {
        id: scrollView
        anchors.fill: parent
        
        // contentHeight 설정 삭제 (GridLayout의 height를 따르도록 자동 처리)
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        clip: true

        padding: 40 
        
        GridLayout {
            id: mainGrid
            
            // 너비: 여백 제외한 공간
            width: scrollView.availableWidth
            
            // [수정] availableHeight 대신 scrollView.height 사용 (루프 방지)
            // 전체 높이 - 상하 패딩(40+40=80)
            height: Math.max(implicitHeight, scrollView.height - 80)
            
            property bool isNarrow: analyzeRoot.width < 900
            
            columns: isNarrow ? 1 : 2 
            columnSpacing: 30
            rowSpacing: 30

            // ---------------------------------------------------------
            // [카드 1] Data Synchronization (왼쪽)
            // ---------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                // 화면이 넓을 때(2열)는 높이를 꽉 채우고, 좁을 때(1열)는 고정 높이
                Layout.fillHeight: !mainGrid.isNarrow 
                
                Layout.preferredWidth: 6 
                Layout.preferredHeight: mainGrid.isNarrow ? 600 : -1
                
                color: "#FFFFFF"
                radius: 30
                border.color: "#E0E0E0"
                border.width: 1
                clip: true 

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 40
                    spacing: 20

                    // 1-1. 텍스트 및 버튼 영역
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        spacing: 20

                        Text {
                            text: "Data\nSynchronization"
                            font.pixelSize: 36
                            font.bold: true
                            color: "#1A1A1A"
                            lineHeight: 1.1
                        }

                        Text {
                            text: "Connect to Arcaea Online to retrieve latest scores"
                            color: "#888888"
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true 
                        }

                        Item { Layout.preferredHeight: 20; Layout.fillHeight: true }

                        // Start Button
                        Rectangle {
                            width: 220; height: 60
                            radius: 30
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#BC00FF" }
                                GradientStop { position: 1.0; color: "#D000FF" }
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: 10
                                Text { text: "▶"; color: "white"; font.pixelSize: 18 }
                                Text { text: "Start Analysis"; color: "white"; font.bold: true; font.pixelSize: 18 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: analysisHandler.startAnalysis()
                            }
                        }

                        // Start Analysis 버튼을 위로 더 올리기 위해 간격 추가 확대
                        Item { height: 80 }

                        // Play Count Analyze Mode Toggle (Capsule UI)
                        Rectangle {
                            Layout.alignment: Qt.AlignLeft
                            implicitWidth: analyzeModeRow.implicitWidth + 32
                            height: 46
                            radius: 23
                            color: "#F8F8F8"
                            border.color: "#E0E0E0"
                            border.width: 1

                            RowLayout {
                                id: analyzeModeRow
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 12
                                spacing: 12

                                // 텍스트와 툴팁 영역
                                RowLayout {
                                    spacing: 6
                                    Text { 
                                        text: "Play Count Analyze Mode"
                                        font.bold: true
                                        color: "#333" 
                                    }
                                    
                                    Text {
                                        text: "ⓘ"
                                        font.pixelSize: 14
                                        color: analyzeModeHelpMouse.containsMouse ? "#6A0DAD" : "#999"
                                        
                                        MouseArea {
                                            id: analyzeModeHelpMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }
                                        
                                        Basic.ToolTip {
                                            visible: analyzeModeHelpMouse.containsMouse
                                            delay: 100
                                            timeout: -1
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

                                // 토글 스위치 영역
                                Item {
                                    id: analyzeModeToggle_analyze
                                    width: 48; height: 26
                                    property bool checked: settingsHandler ? settingsHandler.getAnalyzeModeEnabled() : false

                                    Connections {
                                        target: settingsHandler
                                        function onAnalyzeModeChanged(enabled) {
                                            analyzeModeToggle_analyze.checked = enabled
                                        }
                                    }

                                    Rectangle {
                                        id: toggleTrack_analyze
                                        anchors.fill: parent
                                        radius: 13
                                        color: analyzeModeToggle_analyze.checked ? "#6A0DAD" : "#E0E0E0"
                                        border.color: analyzeModeToggle_analyze.checked ? "#6A0DAD" : "#CCCCCC"
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }

                                        Rectangle {
                                            width: 22; height: 22; radius: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: analyzeModeToggle_analyze.checked ? parent.width - width - 2 : 2
                                            color: "white"
                                            
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            analyzeModeToggle_analyze.checked = !analyzeModeToggle_analyze.checked
                                            if (settingsHandler) settingsHandler.setAnalyzeModeEnabled(analyzeModeToggle_analyze.checked)
                                        }
                                    }
                                }
                            }
                        }

                        // 하단 상태바
                        Rectangle {
                            id: statusBar
                            Layout.preferredWidth: 400
                            Layout.preferredHeight: 60
                            color: "#F8F8F8"
                            radius: 15
                            
                            // Status property - updated via signal
                            property string analysisStatus: "closed"  // 'closed', 'login', 'ready', 'analyzing'
                            
                            Component.onCompleted: {
                                analysisStatus = analysisHandler.getStatus()
                            }
                            
                            Connections {
                                target: analysisHandler
                                function onStatusChanged(status) {
                                    statusBar.analysisStatus = status
                                }
                            }
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 15

                                // Browser Closed indicator
                                Row { 
                                    spacing: 8
                                    Rectangle { 
                                        width: 12; height: 12; radius: 6
                                        color: statusBar.analysisStatus === "closed" ? "#FF6B6B" : "#CCCCCC"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text { 
                                        text: "Browser Closed"
                                        color: statusBar.analysisStatus === "closed" ? "#333" : "#AAA"
                                        font.pixelSize: 12
                                        font.bold: statusBar.analysisStatus === "closed"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Rectangle { width: 1; height: 15; color: "#DDD" }
                                
                                // Analyzing indicator (active for 'login' and 'analyzing' states)
                                Row { 
                                    spacing: 8
                                    Rectangle { 
                                        width: 12; height: 12; radius: 6
                                        color: statusBar.analysisStatus === "login" || statusBar.analysisStatus === "analyzing" ? "#FFB74D" : "#CCCCCC"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text { 
                                        // Show "Logging In" during login, otherwise "Analyzing..."
                                        text: statusBar.analysisStatus === "login" ? "Logging In" : "Analyzing..."
                                        color: statusBar.analysisStatus === "login" || statusBar.analysisStatus === "analyzing" ? "#333" : "#AAA"
                                        font.pixelSize: 12
                                        font.bold: statusBar.analysisStatus === "login" || statusBar.analysisStatus === "analyzing"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Rectangle { width: 1; height: 15; color: "#DDD" }

                                // Ready indicator
                                Row { 
                                    spacing: 8
                                    Rectangle { 
                                        width: 12; height: 12; radius: 6
                                        color: statusBar.analysisStatus === "ready" ? "#00FF00" : "#CCCCCC"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text { 
                                        text: "Ready"
                                        color: statusBar.analysisStatus === "ready" ? "#333" : "#AAA"
                                        font.pixelSize: 12
                                        font.bold: statusBar.analysisStatus === "ready"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }

                }

                // 1-2. 오른쪽 장식 (RowLayout에서 분리하여 독립 배치)
                Item {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 350
                    visible: analyzeRoot.width > 750

                    Rectangle {
                        id: decorationContainer
                        anchors.centerIn: parent
                        width: 300; height: 300
                        color: "transparent"
                        
                        property var decorationImages: []
                        Component.onCompleted: decorationImages = analysisHandler.getRandomThumbnails()
                        
                        // 1. Top Left
                        Item { 
                            id: deco1
                            x: 10; y: 40; width: 100; height: 100
                            
                            Rectangle {
                                anchors.fill: parent
                                color: "#D0A0FF"
                                opacity: 0.5
                                visible: decorationContainer.decorationImages.length < 5
                                rotation: 15
                                antialiasing: true
                            }
                            
                            Image {
                                anchors.fill: parent
                                source: decorationContainer.decorationImages.length >= 5 ? decorationContainer.decorationImages[0] : ""
                                visible: decorationContainer.decorationImages.length >= 5
                                fillMode: Image.PreserveAspectCrop
                                rotation: 15
                                antialiasing: true
                                smooth: true
                                mipmap: true
                                sourceSize: Qt.size(width * 2, height * 2)
                            }
                        }

                        // 2. Top Right
                        Item { 
                            id: deco2
                            x: 180; y: 20; width: 90; height: 90
                            
                            Rectangle {
                                anchors.fill: parent
                                color: "#FF80AB"
                                opacity: 0.6
                                visible: decorationContainer.decorationImages.length < 5
                                rotation: -10
                                antialiasing: true
                            }
                            
                            Image {
                                anchors.fill: parent
                                source: decorationContainer.decorationImages.length >= 5 ? decorationContainer.decorationImages[1] : ""
                                visible: decorationContainer.decorationImages.length >= 5
                                fillMode: Image.PreserveAspectCrop
                                rotation: -10
                                antialiasing: true
                                smooth: true
                                mipmap: true
                                sourceSize: Qt.size(width * 2, height * 2)
                            }
                        }

                        // 3. Center (Main)
                        Item { 
                            id: deco3
                            x: 70; y: 80; width: 150; height: 150
                            
                            Rectangle {
                                anchors.fill: parent
                                color: "#6A0DAD"
                                opacity: 0.8
                                visible: decorationContainer.decorationImages.length < 5
                                rotation: -5
                                antialiasing: true
                            }
                            
                            Image {
                                anchors.fill: parent
                                source: decorationContainer.decorationImages.length >= 5 ? decorationContainer.decorationImages[2] : ""
                                visible: decorationContainer.decorationImages.length >= 5
                                fillMode: Image.PreserveAspectCrop
                                rotation: -5
                                antialiasing: true
                                smooth: true
                                mipmap: true
                                sourceSize: Qt.size(width * 2, height * 2)
                            }
                        }
                        
                        // 4. Bottom Left
                        Item { 
                            id: deco4
                            x: 30; y: 160; width: 110; height: 110
                            
                            Rectangle {
                                anchors.fill: parent
                                color: "#80D8FF"
                                opacity: 0.6
                                visible: decorationContainer.decorationImages.length < 5
                                rotation: 25
                                antialiasing: true
                            }
                            
                            Image {
                                anchors.fill: parent
                                source: decorationContainer.decorationImages.length >= 5 ? decorationContainer.decorationImages[3] : ""
                                visible: decorationContainer.decorationImages.length >= 5
                                fillMode: Image.PreserveAspectCrop
                                rotation: 25
                                antialiasing: true
                                smooth: true
                                mipmap: true
                                sourceSize: Qt.size(width * 2, height * 2)
                            }
                        }

                        // 5. Bottom Right
                        Item { 
                            id: deco5
                            x: 170; y: 150; width: 100; height: 100
                            
                            Rectangle {
                                anchors.fill: parent
                                color: "#A0E0FF"
                                opacity: 0.7
                                visible: decorationContainer.decorationImages.length < 5
                                rotation: -20
                                antialiasing: true
                            }
                            
                            Image {
                                anchors.fill: parent
                                source: decorationContainer.decorationImages.length >= 5 ? decorationContainer.decorationImages[4] : ""
                                visible: decorationContainer.decorationImages.length >= 5
                                fillMode: Image.PreserveAspectCrop
                                rotation: -20
                                antialiasing: true
                                smooth: true
                                mipmap: true
                                sourceSize: Qt.size(width * 2, height * 2)
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------------
            // [카드 2] Scraping Progress (오른쪽)
            // ---------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: !mainGrid.isNarrow
                
                Layout.preferredWidth: 4 
                Layout.preferredHeight: mainGrid.isNarrow ? 600 : -1

                color: "#FFFFFF"
                radius: 30
                border.color: "#E0E0E0"
                border.width: 1
                clip: true

                ColumnLayout {
                    id: lastSavedInfoContent
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 20

                    Text { 
                        text: "Synchronization Status" 
                        font.pixelSize: 20
                        font.bold: true
                        color: "#1A1A1A" 
                    }


                    // --- Pin Data ---
                    property var pinDates: ({})
                    property var progressData: ({})
                    property var countModeData: ({})
                    property bool isPlayCountMode: false
                    property int thumbnailDataVersion: 0

                    Component.onCompleted: {
                        updatePinDates()
                        updateProgressData()
                    }

                    Connections {
                        target: analysisHandler
                        function onPinUpdated() {
                            lastSavedInfoContent.updatePinDates()
                        }
                        function onProgressChanged() {
                            Qt.callLater(lastSavedInfoContent.updateProgressData)
                        }
                        function onDataUpdated() {
                            lastSavedInfoContent.thumbnailDataVersion += 1
                        }
                    }

                    function updatePinDates() {
                        pinDates = analysisHandler.getPinDates()
                    }

                    function updateProgressData() {
                        progressData = analysisHandler.getProgress()
                        countModeData = analysisHandler.getCountModeProgress()
                        isPlayCountMode = analysisHandler.isPlayCountMode()
                    }
                    
                    // --- Difficulty Date List ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        
                        // Column Header Labels
                        Item {
                            Layout.fillWidth: true
                            height: 20
                            visible: {
                                // Show header only if at least one difficulty has pin data
                                for (var i = 0; i < 5; i++) {
                                    var pinData = lastSavedInfoContent.pinDates[String(i)]
                                    if (pinData && pinData.updated_at && pinData.updated_at > 0) return true
                                }
                                return false
                            }
                            
                            RowLayout {
                                anchors.fill: parent
                                spacing: 0
                                
                                // Space for badge + gap + thumbnail
                                Item { width: 36 + 24 + 32 }
                                
                                // Last Played label
                                Text {
                                    text: "last played"
                                    font.pixelSize: 10
                                    color: "#999"
                                    Layout.preferredWidth: 120
                                    Layout.leftMargin: 12
                                    Layout.rightMargin: 24
                                }
                                
                                // Last Synced label  
                                Text {
                                    text: "last synced"
                                    font.pixelSize: 10
                                    color: "#999"
                                    Layout.fillWidth: true
                                }
                            }
                        }
                        
                        Repeater {
                            model: [
                                { label: "PST", color: "#00A0E9", code: 0 },
                                { label: "PRS", color: "#50C050", code: 1 },
                                { label: "FTR", color: "#A060FF", code: 2 },
                                { label: "ETR", color: "#808080", code: 4 },
                                { label: "BYD", color: "#E04040", code: 3 }
                            ]
                            
                            delegate: Item {
                                id: pinRow
                                Layout.fillWidth: true
                                height: 48

                                
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: 1
                                    color: "#F0F0F0"
                                    visible: index < 4
                                }
                                
                                // Get pin data for this difficulty
                                property var actualPinData: lastSavedInfoContent.pinDates[String(modelData.code)] || {}
                                property var displayPinData: ({})
                                
                                property bool hasPinInfo: displayPinData.updated_at && displayPinData.updated_at > 0
                                property string arcaeaId: displayPinData.arcaea_id || ""
                                property string chartIdentity: (displayPinData.arcaea_id || "") + ":" + String(modelData.code)
                                property var timePlayed: displayPinData.time_played || 0
                                property var updatedAt: actualPinData.updated_at || 0
                                property bool isPlayCountMode: lastSavedInfoContent.isPlayCountMode
                                
                                property var _animationLastUpdatedAt: 0
                                property string _pendingArcaeaId: ""
                                property string _pendingThumbnailSource: ""
                                property bool _isPinTransitionActive: false
                                property bool _isCheckPhaseCompleted: false
                                property bool _isWaitingForThumbnail: false
                                property bool _exactThumbnailReady: false
                                property bool _timedOutWaiting: false

                                function _clonePinData(data) {
                                    var cloned = {}
                                    if (!data)
                                        return cloned
                                    for (var key in data)
                                        cloned[key] = data[key]
                                    return cloned
                                }

                                function _applyDisplayPinData(data) {
                                    displayPinData = _clonePinData(data)
                                }

                                function _resolveExactThumbnailSource(arcaeaIdValue) {
                                    if (!arcaeaIdValue || !statsHandler || !statsHandler.getExactThumbnailPathForDifficulty)
                                        return ""
                                    return statsHandler.getExactThumbnailPathForDifficulty(arcaeaIdValue, modelData.code)
                                }

                                function _refreshPendingThumbnailCandidate() {
                                    if (!_isPinTransitionActive || !_isWaitingForThumbnail || !_isCheckPhaseCompleted)
                                        return

                                    var exactSrc = _resolveExactThumbnailSource(_pendingArcaeaId)
                                    if (exactSrc === "")
                                        return

                                    _pendingThumbnailSource = exactSrc

                                    if (String(thumbnailNew.source) !== exactSrc) {
                                        _exactThumbnailReady = false
                                        thumbnailNew.opacity = 0
                                        thumbnailNew.source = ""
                                        thumbnailNew.source = exactSrc
                                        return
                                    }

                                    if (thumbnailNew.status === Image.Error) {
                                        _exactThumbnailReady = false
                                        thumbnailNew.opacity = 0
                                        thumbnailNew.source = ""
                                        return
                                    }

                                    if (thumbnailNew.status === Image.Ready) {
                                        _exactThumbnailReady = true
                                        thumbnailNew.opacity = 1
                                        _tryStartCrossfade()
                                    }
                                }

                                function _tryStartCrossfade() {
                                    if (!_isPinTransitionActive || !_isCheckPhaseCompleted)
                                        return

                                    if (!_exactThumbnailReady) {
                                        if (_isWaitingForThumbnail && !_timedOutWaiting)
                                            return
                                        _pendingThumbnailSource = ""
                                        thumbnailNew.source = ""
                                        thumbnailNew.opacity = 0
                                    } else {
                                        thumbnailNew.opacity = 1
                                    }

                                    _isPinTransitionActive = false
                                    _isWaitingForThumbnail = false
                                    thumbnailWaitPoll.stop()
                                    thumbnailWaitTimeout.stop()
                                    crossfadeAnimation.start()
                                }

                                Component.onCompleted: {
                                    _applyDisplayPinData(actualPinData)
                                    _animationLastUpdatedAt = updatedAt
                                }

                                function _resetPinAnimationVisuals() {
                                    _pendingArcaeaId = ""
                                    _pendingThumbnailSource = ""
                                    _isPinTransitionActive = false
                                    _isCheckPhaseCompleted = false
                                    _isWaitingForThumbnail = false
                                    _exactThumbnailReady = false
                                    _timedOutWaiting = false
                                    thumbnailWaitPoll.stop()
                                    thumbnailWaitTimeout.stop()
                                    pinUpdateAnimation.stop()
                                    crossfadeAnimation.stop()
                                    checkOverlay.opacity = 0
                                    checkCircle.scale = 0
                                    thumbnailContainer.opacity = 1
                                    progressContainer.opacity = 1
                                    thumbnailNew.source = ""
                                    thumbnailNew.opacity = 0
                                }

                                function _beginPinUpdateTransition() {
                                    _pendingArcaeaId = actualPinData.arcaea_id || ""
                                    _pendingThumbnailSource = ""
                                    _isPinTransitionActive = true
                                    _isCheckPhaseCompleted = false
                                    _isWaitingForThumbnail = _pendingArcaeaId !== ""
                                    _exactThumbnailReady = false
                                    _timedOutWaiting = false
                                    thumbnailWaitTimeout.stop()
                                    thumbnailWaitPoll.stop()
                                    thumbnailNew.opacity = 0
                                    thumbnailNew.source = ""

                                    crossfadeAnimation.stop()
                                    pinUpdateAnimation.restart()
                                }

                                Timer {
                                    id: thumbnailWaitPoll
                                    interval: 250
                                    repeat: true
                                    onTriggered: pinRow._refreshPendingThumbnailCandidate()
                                }

                                Timer {
                                    id: thumbnailWaitTimeout
                                    interval: 10000
                                    repeat: false
                                    onTriggered: {
                                        if (!pinRow._isPinTransitionActive || !pinRow._isWaitingForThumbnail)
                                            return
                                        pinRow._timedOutWaiting = true
                                        pinRow._isWaitingForThumbnail = false
                                        pinRow.thumbnailWaitPoll.stop()
                                        pinRow._tryStartCrossfade()
                                    }
                                }

                                onUpdatedAtChanged: {
                                    if (isPlayCountMode) {
                                        _resetPinAnimationVisuals()
                                        _applyDisplayPinData(actualPinData)
                                        _animationLastUpdatedAt = updatedAt
                                        return
                                    }

                                    if (_animationLastUpdatedAt > 0 && updatedAt > _animationLastUpdatedAt) {
                                        _beginPinUpdateTransition()
                                    } else {
                                        if (!_isPinTransitionActive)
                                            _applyDisplayPinData(actualPinData)
                                    }
                                    _animationLastUpdatedAt = updatedAt
                                }
                                
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0
                                    
                                    // Colored Pill
                                    Rectangle {
                                        width: 36; height: 20
                                        radius: 6
                                        color: modelData.color
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: "white"
                                        }
                                    }
                                    
                                    // Thumbnail (32x32, or empty space if not available)
                                    Item {
                                        id: thumbnailContainer
                                        width: 32; height: 32
                                        Layout.leftMargin: 24
                                        Layout.rightMargin: 12
                                        
                                        Image {
                                            id: thumbnailImg
                                            anchors.fill: parent
                                            source: {
                                                // 바인딩 재평가용 의존성 키:
                                                // - dataVersion: dataUpdated 시 파일 갱신 신호
                                                // - chartIdentity: (arcaea_id, difficulty) 차트 단위 식별
                                                var dataVersion = lastSavedInfoContent.thumbnailDataVersion
                                                var chartIdentity = pinRow.chartIdentity
                                                return (pinRow.arcaeaId && statsHandler)
                                                    ? statsHandler.getThumbnailPathForDifficulty(pinRow.arcaeaId, modelData.code)
                                                    : ""
                                            }
                                            visible: true
                                            opacity: status === Image.Ready ? 1 : 0
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            mipmap: true
                                            sourceSize: Qt.size(64, 64)
                                        }

                                        Image {
                                            id: thumbnailNew
                                            anchors.fill: parent
                                            source: ""
                                            opacity: 0
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            mipmap: true
                                            sourceSize: Qt.size(64, 64)
                                            onStatusChanged: {
                                                if (!pinRow._isPinTransitionActive || !pinRow._isWaitingForThumbnail)
                                                    return
                                                if (status === Image.Ready && String(source) === pinRow._pendingThumbnailSource) {
                                                    pinRow._exactThumbnailReady = true
                                                    thumbnailNew.opacity = 1
                                                    pinRow._tryStartCrossfade()
                                                } else if (status === Image.Error && String(source) === pinRow._pendingThumbnailSource) {
                                                    pinRow._exactThumbnailReady = false
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: thumbMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }

                                        ToolTip {
                                            id: titleTip
                                            visible: thumbMouseArea.containsMouse && text !== ""
                                            delay: 100
                                            
                                            text: (pinRow.arcaeaId && statsHandler) ? statsHandler.getSongTitleForDifficulty(pinRow.arcaeaId, modelData.code) : ""
                                            
                                            contentItem: Text {
                                                text: titleTip.text
                                                font.family: analyzeRoot.titleFontFamily
                                                font.pixelSize: 12
                                                color: "#FFFFFF"
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            
                                            background: Rectangle {
                                                color: "#E6222222"
                                                radius: 6
                                                border.width: 1
                                                border.color: "#33FFFFFF"
                                            }
                                            
                                            y: parent.height + 6
                                            x: (parent.width - width) / 2
                                            
                                            leftPadding: 8
                                            rightPadding: 8
                                            topPadding: 6
                                            bottomPadding: 6
                                        }
                                        
                                        // Empty placeholder when no thumbnail
                                        Rectangle {
                                            anchors.fill: parent
                                            color: "transparent"
                                            visible: thumbnailImg.opacity === 0 && hasPinInfo
                                        }
                                    }
                                    
                                    // Content Container (dates or progress bar)
                                    Item {
                                        id: progressContainer
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        property bool isWebPageOpen: statusBar.analysisStatus !== "closed"
                                        
                                        property var diffProgress: lastSavedInfoContent.progressData[String(modelData.code)] || {}
                                        property bool hasTotal: diffProgress.total !== undefined && diffProgress.total !== null
                                        property int totalPages: hasTotal ? diffProgress.total : 0
                                        property int checkedPages: diffProgress.checked || 0
                                        
                                        // Show Progress Bar only when: web page open AND total_page known AND no pin data
                                        // Play Count Mode: always show progress bar
                                        property var countProgress: lastSavedInfoContent.countModeData[String(modelData.code)] || {}
                                        property bool isPlayCountMode: lastSavedInfoContent.isPlayCountMode
                                        property bool isCountModeCompleted: countProgress.completed || false
                                        property int countChecked: countProgress.checked || 0
                                        property int countTotal: (countProgress.total !== undefined && countProgress.total !== null) ? countProgress.total : 0
                                        
                                        property bool showProgressBar: (isPlayCountMode && isCountModeCompleted) ||
                                                                       (isPlayCountMode && isWebPageOpen && countTotal > 0) ||
                                                                       (isWebPageOpen && hasTotal && !hasPinInfo)

                                        // Date Display Row (when not showing progress bar)
                                        RowLayout {
                                            anchors.fill: parent
                                            visible: !progressContainer.showProgressBar
                                            spacing: 24
                                            
                                            // Last Played Date (yyyy-mm-dd HH:mm)
                                            Text {
                                                text: displayPinData.formatted_time_played || "-"
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: "#333"
                                                Layout.preferredWidth: 120
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            
                                            // Last Synced (existing format with relative date)
                                            Text { 
                                                Layout.fillWidth: true
                                                verticalAlignment: Text.AlignVCenter
                                                text: displayPinData.formatted_updated_at || "-"
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: "#333"
                                                elide: Text.ElideRight
                                            }
                                        }

                                        // Progress Bar Row
                                        RowLayout {
                                            anchors.fill: parent
                                            visible: progressContainer.showProgressBar
                                            spacing: 8
                                            
                                            // Bar Track
                                            Rectangle {
                                                id: trackRect
                                                Layout.fillWidth: true
                                                height: 6
                                                radius: 3
                                                color: "#E0E0E0"
                                                clip: true
                                                
                                                // Bar Indicator
                                                Rectangle {
                                                    id: pBar
                                                    height: parent.height
                                                    width: {
                                                        if (progressContainer.isPlayCountMode) {
                                                            if (progressContainer.isCountModeCompleted) return parent.width
                                                            return progressContainer.countTotal > 0 ?
                                                                (parent.width * (progressContainer.countChecked / progressContainer.countTotal)) : 0
                                                        }
                                                        return progressContainer.totalPages > 0 ?
                                                            (parent.width * (progressContainer.checkedPages / progressContainer.totalPages)) : 0
                                                    }
                                                           
                                                    color: modelData.color
                                                    radius: 3
                                                    
                                                    Behavior on width { NumberAnimation { duration: 200 } }
                                                }
                                            }
                                            
                                            // Percentage / Count Mode Label
                                            Text {
                                                text: {
                                                    if (progressContainer.isPlayCountMode) {
                                                        if (progressContainer.isCountModeCompleted) return "✓"
                                                        if (progressContainer.countTotal > 0)
                                                            return progressContainer.countChecked + "/" + progressContainer.countTotal
                                                        return "0"
                                                    }
                                                    if (progressContainer.hasTotal && progressContainer.totalPages > 0)
                                                        return Math.floor((progressContainer.checkedPages / progressContainer.totalPages) * 100) + "%"
                                                    return "?%"
                                                }
                                                font.pixelSize: 11
                                                font.weight: progressContainer.isCountModeCompleted ? Font.Bold : Font.Normal
                                                color: progressContainer.isCountModeCompleted ? "#2E7D32" : "black"
                                                Layout.minimumWidth: 20
                                                horizontalAlignment: Text.AlignRight
                                            }
                                        }
                                    }
                                }
                                
                                // Pin Update Animation Overlay
                                Item {
                                    id: checkOverlay
                                    anchors.left: parent.left
                                    anchors.leftMargin: 36 // width of Colored Pill
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    opacity: 0
                                    
                                    Rectangle {
                                        id: checkCircle
                                        anchors.centerIn: parent
                                        width: 28; height: 28
                                        radius: 14
                                        color: modelData.color
                                        scale: 0
                                        
                                        // White check mark
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: "white"
                                            font.pixelSize: 18
                                            font.bold: true
                                        }
                                    }
                                }
                                
                                // Phase 1: 페이드아웃 → 체크 오버레이 → 대기
                                SequentialAnimation {
                                    id: pinUpdateAnimation

                                    // 1. 기존 요소들 페이드 아웃
                                    ParallelAnimation {
                                        NumberAnimation { target: thumbnailContainer; property: "opacity"; from: 1; to: 0; duration: 200 }
                                        NumberAnimation { target: progressContainer; property: "opacity"; from: 1; to: 0; duration: 200 }
                                    }

                                    // 1.5. thumbnailNew 안전 레이어 활성화
                                    PropertyAction { target: thumbnailNew; property: "opacity"; value: 1 }

                                    // 2. 체크 오버레이 표시 및 스프링 애니메이션
                                    PropertyAction { target: checkOverlay; property: "opacity"; value: 1 }
                                    PropertyAction { target: checkCircle; property: "scale"; value: 0 }
                                    NumberAnimation {
                                        target: checkCircle
                                        property: "scale"
                                        from: 0
                                        to: 1
                                        duration: 400
                                        easing.type: Easing.OutElastic
                                        easing.amplitude: 2.0
                                        easing.period: 0.5
                                    }

                                    // 3. 잠시 대기
                                    PauseAnimation { duration: 500 }

                                    onFinished: {
                                        pinRow._isCheckPhaseCompleted = true
                                        if (pinRow._isWaitingForThumbnail && !pinRow._exactThumbnailReady) {
                                            if (!thumbnailWaitTimeout.running)
                                                thumbnailWaitTimeout.restart()
                                            if (!thumbnailWaitPoll.running)
                                                thumbnailWaitPoll.start()
                                            pinRow._refreshPendingThumbnailCandidate()
                                        }
                                        pinRow._tryStartCrossfade()
                                    }
                                }

                                // Phase 2: 크로스페이드 (독립 타이머로 wall-clock 초과 방지)
                                SequentialAnimation {
                                    id: crossfadeAnimation

                                    // 썸네일 페이드인과 동시에 최신 타임스탬프를 반영
                                    ScriptAction {
                                        script: {
                                            pinRow._applyDisplayPinData(pinRow.actualPinData)
                                        }
                                    }

                                    ParallelAnimation {
                                        NumberAnimation { target: checkOverlay; property: "opacity"; from: 1; to: 0; duration: 300 }
                                        NumberAnimation { target: thumbnailContainer; property: "opacity"; from: 0; to: 1; duration: 300 }
                                        NumberAnimation { target: progressContainer; property: "opacity"; from: 0; to: 1; duration: 300 }
                                    }

                                    // 더블 버퍼 정리
                                    ScriptAction {
                                        script: {
                                            thumbnailNew.source = ""
                                            thumbnailNew.opacity = 0
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { height: 10 }
                    
                    // --- Log Data Model ---
                    ListModel {
                        id: logModel
                    }

                    function formatLogHtml(message) {
                        var regex = /^\[([\d:]+)\](?:\[([A-Z]+)\])?\s+([\s\S]*)$/
                        var match = message.match(regex)
                        
                        var timestampColor = "#AAA"
                        var messageColor = "#666"
                        var diffColors = {
                            "PST": "#00A0E9",
                            "PRS": "#50C050",
                            "FTR": "#A060FF",
                            "BYD": "#E04040",
                            "ETR": "#808080"
                        }
                        
                        if (match) {
                            var timestamp = match[1]
                            var diffTag = match[2]
                            var content = match[3]
                            
                            var html = "<span style='color:" + timestampColor + ";'>[" + timestamp + "]</span> "
                            if (diffTag) {
                                var dColor = diffColors[diffTag] || "#888"
                                html += "<span style='color:" + dColor + "; font-weight:bold;'>[" + diffTag + "]</span> "
                            }
                            html += "<span style='color:" + messageColor + ";'>" + content + "</span>"
                            return html
                        }
                        
                        return "<span style='color:" + messageColor + ";'>" + message + "</span>"
                    }

                    Connections {
                        target: analysisHandler
                        function onLogAdded(message) {
                            var html = lastSavedInfoContent.formatLogHtml(message)
                            logModel.append({ "logHtml": html })
                            if (logView.count > 0) {
                                logView.positionViewAtEnd()
                            }
                        }
                    }

                    Text {
                        text: "LIVE LOGS"
                        color: "#888"
                        font.bold: true
                        font.pixelSize: 11
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true 
                        
                        color: "#F8F8F8"
                        radius: 12
                        border.color: "#EEEEEE"

                        ListView {
                            id: logView
                            anchors.fill: parent
                            anchors.margins: 15
                            clip: true
                            model: logModel
                            spacing: 4

                            delegate: Text {
                                width: ListView.view.width
                                textFormat: Text.RichText
                                text: logHtml
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }
}
