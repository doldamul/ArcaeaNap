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
                            Layout.fillWidth: true
                            height: 60
                            color: "#F8F8F8"
                            radius: 15
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 15

                                Row { 
                                    spacing: 8
                                    Rectangle { width: 12; height: 12; radius: 6; color: "#CCCCCC"; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Browser Closed"; color: "#AAA"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                }
                                Rectangle { width: 1; height: 15; color: "#DDD" }
                                
                                Row { 
                                    spacing: 8
                                    Rectangle { width: 12; height: 12; radius: 6; color: "#CCCCCC"; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Logging In"; color: "#AAA"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                }
                                Rectangle { width: 1; height: 15; color: "#DDD" }

                                Row { 
                                    spacing: 8
                                    Rectangle { width: 12; height: 12; radius: 6; color: "#00FF00"; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Ready"; color: "#333"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                    }

                    // 1-2. 오른쪽 장식
                    Item {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 250
                        visible: analyzeRoot.width > 750

                        Rectangle {
                            anchors.centerIn: parent
                            width: 200; height: 200
                            color: "transparent"
                            
                            Rectangle { x: 20; y: 20; width: 80; height: 80; color: "#D0A0FF"; opacity: 0.5; rotation: 15 }
                            Rectangle { x: 80; y: 40; width: 100; height: 100; color: "#6A0DAD"; opacity: 0.8; rotation: -10 }
                            Rectangle { x: 60; y: 100; width: 60; height: 60; color: "#A0E0FF"; opacity: 0.6; rotation: 30 }
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
                        Text { text: "Last Saved"; font.pixelSize: 18; font.bold: true; color: "#1A1A1A" }
                    }


                    // --- Pin Data ---
                    property var pinDates: ({})

                    Component.onCompleted: {
                        updatePinDates()
                    }

                    Connections {
                        target: analysisHandler
                        function onPinUpdated() {
                            lastSavedInfoContent.updatePinDates()
                        }
                    }

                    function updatePinDates() {
                        pinDates = analysisHandler.getPinDates()
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
                                { label: "BYD", color: "#E04040", code: 3 },
                                { label: "ETR", color: "#808080", code: 4 }
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
                                    
                                    Text { 
                                        Layout.fillWidth: true
                                        text: lastSavedInfoContent.formatPinDate(lastSavedInfoContent.pinDates[String(modelData.code)])
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#333"
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