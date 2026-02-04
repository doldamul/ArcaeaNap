import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Item {
    id: analyzeRoot
    anchors.fill: parent

    // --- 메인 컨텐츠 영역 ---
    ScrollView {
        id: scrollView
        anchors.fill: parent
        
        // contentHeight 설정 삭제 (GridLayout의 height를 따르도록 자동 처리)
        contentWidth: availableWidth
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

                        Item { Layout.preferredHeight: 20; Layout.fillHeight: true }

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

                    Row {
                        spacing: 10
                        Text { text: "●"; color: "#BC00FF"; font.pixelSize: 16 }
                        Text { text: "Last Synced"; font.pixelSize: 18; font.bold: true; color: "#1A1A1A" }
                    }


                    // --- Pin Data ---
                    property var pinDates: ({})
                    property var progressData: ({})

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
                            lastSavedInfoContent.updateProgressData()
                        }
                    }

                    function updatePinDates() {
                        pinDates = analysisHandler.getPinDates()
                    }

                    function updateProgressData() {
                        progressData = analysisHandler.getProgress()
                    }
                    
                    function formatPinDate(timestamp) {
                        if (!timestamp || timestamp <= 0) return "-"
                        var date = new Date(timestamp)
                        var now = new Date()
                        
                        // Calculate days difference based on calendar dates
                        var dateOnly = new Date(date.getFullYear(), date.getMonth(), date.getDate())
                        var nowOnly = new Date(now.getFullYear(), now.getMonth(), now.getDate())
                        var daysDiff = Math.floor((nowOnly - dateOnly) / (1000 * 60 * 60 * 24))
                        
                        // Format absolute datetime
                        var absDate = date.getFullYear() + "-" + 
                               (date.getMonth() + 1).toString().padStart(2, '0') + "-" + 
                               date.getDate().toString().padStart(2, '0') + " " +
                               date.getHours().toString().padStart(2, '0') + ":" +
                               date.getMinutes().toString().padStart(2, '0')
                        
                        // Format relative date
                        var relDate = ""
                        if (daysDiff === 0) {
                            relDate = "Today"
                        } else if (daysDiff === 1) {
                            relDate = "Yesterday"
                        } else {
                            relDate = daysDiff + " days ago"
                        }
                        
                        return absDate + " (" + relDate + ")"
                    }

                    // --- Difficulty Date List ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        
                        Repeater {
                            model: [
                                { label: "PST", color: "#00A0E9", code: 0 },
                                { label: "PRS", color: "#50C050", code: 1 },
                                { label: "FTR", color: "#A060FF", code: 2 },
                                { label: "ETR", color: "#808080", code: 4 },
                                { label: "BYD", color: "#E04040", code: 3 }
                            ]
                            
                            delegate: Item {
                                Layout.fillWidth: true
                                height: 42
                                
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: 1
                                    color: "#F0F0F0"
                                    visible: index < 4
                                }
                                
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 12
                                    
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
                                    
                                    // Content Container
                                    Item {
                                        id: progressContainer
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        property bool hasPinInfo: {
                                            var ts = lastSavedInfoContent.pinDates[String(modelData.code)]
                                            return (ts && ts > 0) === true
                                        }
                                        property bool isWebPageOpen: statusBar.analysisStatus !== "closed"
                                        
                                        property var diffProgress: lastSavedInfoContent.progressData[String(modelData.code)] || {}
                                        property bool hasTotal: diffProgress.total !== undefined && diffProgress.total !== null
                                        property int totalPages: hasTotal ? diffProgress.total : 0
                                        property int checkedPages: diffProgress.checked || 0
                                        
                                        // Show Progress Bar only when: web page open AND total_page known AND no pin data
                                        property bool showProgressBar: isWebPageOpen && hasTotal && !hasPinInfo

                                        // 1. Date Text
                                        Text { 
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            visible: !progressContainer.showProgressBar
                                            text: lastSavedInfoContent.formatPinDate(lastSavedInfoContent.pinDates[String(modelData.code)])
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: "#333"
                                            elide: Text.ElideRight
                                        }

                                        // 2. Progress Bar Row
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
                                                    // Width logic: 
                                                    // If totalPages known > 0: calculate percentage
                                                    // If totalPages known == 0 (start): 0
                                                    // If totalPages unknown (null): show full bar (or indeterminate style if preferred, here indeterminate -> 0 or handling separate?)
                                                    // Actually if total is unknown, we can't show progress.
                                                    // The requirement: "Show progress bar". If unknown, maybe show "0%" or "??"
                                                    // Let's implement: if total known -> progress. if total unknown -> 0 width
                                                    
                                                    width: progressContainer.totalPages > 0 ? 
                                                           (parent.width * (progressContainer.checkedPages / progressContainer.totalPages)) : 0
                                                           
                                                    color: modelData.color
                                                    radius: 3
                                                    
                                                    Behavior on width { NumberAnimation { duration: 200 } }
                                                }
                                            }
                                            
                                            // Percentage Label
                                            Text {
                                                text: progressContainer.hasTotal && progressContainer.totalPages > 0
                                                      ? Math.floor((progressContainer.checkedPages / progressContainer.totalPages) * 100) + "%" 
                                                      : "?%"
                                                font.pixelSize: 11
                                                font.weight: Font.Normal
                                                color: "black"
                                                Layout.minimumWidth: 20
                                                horizontalAlignment: Text.AlignRight
                                            }
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

                    Connections {
                        target: analysisHandler
                        function onLogAdded(message) {
                            logModel.append({ "logText": message })
                            if (logView.count > 0) {
                                logView.positionViewAtEnd()
                            }
                        }
                    }

                    Row {
                        spacing: 8
                        Text { text: "📓"; font.pixelSize: 12 }
                        Text { text: "LIVE LOGS"; color: "#888"; font.bold: true; font.pixelSize: 11 }
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
                                text: logText
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                color: "#666"
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }
}