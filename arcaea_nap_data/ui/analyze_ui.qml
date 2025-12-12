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
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 20

                    Row {
                        spacing: 10
                        Text { text: "●"; color: "#BC00FF"; font.pixelSize: 16 }
                        Text { text: "Scraping Progress"; font.pixelSize: 18; font.bold: true; color: "#1A1A1A" }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Overall Status"; color: "#888"; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                            Text { text: "70% Complete"; color: "#BC00FF"; font.bold: true; font.pixelSize: 12 }
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 8
                            color: "#F0F0F0"
                            radius: 4
                            Rectangle {
                                width: parent.width * 0.7
                                height: parent.height
                                radius: 4
                                color: "#BC00FF"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Info Items
                        Rectangle {
                            Layout.fillWidth: true; height: 60; color: "#F8F9FC"; radius: 12
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 20; spacing: 15
                                Rectangle { width: 30; height: 30; radius: 8; color: "white"; border.color: "#EEE"; Text { text: "📚"; anchors.centerIn: parent } }
                                Text { text: "Songs Parsed"; color: "#666"; font.pixelSize: 14; Layout.fillWidth: true }
                                Text { text: "120"; color: "#333"; font.bold: true; font.pixelSize: 18 }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 60; color: "#F8F9FC"; radius: 12
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 20; spacing: 15
                                Rectangle { width: 30; height: 30; radius: 8; color: "white"; border.color: "#EEE"; Text { text: "📄"; anchors.centerIn: parent } }
                                Text { text: "Queue Pending"; color: "#666"; font.pixelSize: 14; Layout.fillWidth: true }
                                Text { text: "50"; color: "#333"; font.bold: true; font.pixelSize: 18 }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 60; color: "#F8F9FC"; radius: 12
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 20; spacing: 15
                                Rectangle { width: 30; height: 30; radius: 8; color: "white"; border.color: "#EEE"; Text { text: "🕒"; anchors.centerIn: parent } }
                                Text { text: "Est. Remaining"; color: "#666"; font.pixelSize: 14; Layout.fillWidth: true }
                                Text { text: "10s"; color: "#333"; font.bold: true; font.pixelSize: 18 }
                            }
                        }
                    }

                    Item { height: 10 }

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

                        Text {
                            anchors.fill: parent
                            anchors.margins: 15
                            font.family: "Consolas, monospace"
                            font.pixelSize: 11
                            lineHeight: 1.5
                            color: "#999"
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            text: "[10:42:01] Initializing headless browser...<br>" +
                                  "[10:42:03] Connection established.<br>" +
                                  "[10:42:05] Navigating to arcaea.lowiro.com...<br>" +
                                  "[10:42:08] Requesting packet 401... <font color='#4CAF50'><b>OK</b></font><br>" +
                                  "[10:42:11] Parsing 'Song_A'... <font color='#007AFF'><b>Done</b></font><br>" +
                                  "[10:42:12] Parsing 'Song_B'... <font color='#007AFF'><b>Done</b></font>"
                        }
                    }
                }
            }
        }
    }
}