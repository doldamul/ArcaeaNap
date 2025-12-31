import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Item {
    id: homeRoot
    anchors.fill: parent

    // [변경 1] ScrollView 추가 (여백 및 스크롤 담당)
    Connections {
        target: statsHandler
        function onStatsChanged() {
            playCountText.text = statsHandler.getTotalPlayCount()
            playTimeText.text = statsHandler.getTotalPlayTime()
        }
    }
    
    Component.onCompleted: {
        if (statsHandler) {
            playCountText.text = statsHandler.getTotalPlayCount()
            playTimeText.text = statsHandler.getTotalPlayTime()
        }
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent
        
        contentWidth: availableWidth
        clip: true
        
        // [핵심] 상하좌우 여백 40px 통일
        padding: 40 

        // [변경 2] GridLayout 도입 (반응형 배치 및 여백 채우기)
        GridLayout {
            id: mainGrid
            
            // 너비: 여백을 뺀 내부 공간
            width: scrollView.availableWidth
            
            // 높이: 내용물 크기 vs 화면 높이(여백 제외) 중 큰 값
            height: Math.max(implicitHeight, scrollView.height - 80)
            
            // 900px 기준으로 1열/2열 변경
            property bool isNarrow: homeRoot.width < 900
            columns: isNarrow ? 1 : 2
            
            columnSpacing: 30
            rowSpacing: 30

            // --- 2. 왼쪽: 플레이어 프로필 카드 ---
            Rectangle {
                // [변경 3] 반응형 레이아웃 속성 적용
                Layout.fillWidth: true
                // 화면이 넓을 땐 높이 꽉 채움, 좁을 땐 고정 높이
                Layout.fillHeight: !mainGrid.isNarrow

                // 가중치 6 (6:4 비율)
                Layout.preferredWidth: 6
                Layout.preferredHeight: mainGrid.isNarrow ? 600 : -1

                color: "#FFFFFF"
                radius: 30
                
                // 그림자 효과 흉내 (border 이용)
                border.color: "#E0E0E0"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // 정보 텍스트 영역
                    Item {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width * 0.8
                            spacing: 15

                            Text {
                                text: "PLAYER PROFILE"
                                color: "#999999"
                                font.pixelSize: 12
                                font.letterSpacing: 1.5
                            }

                            Text {
                                text: "Nickname"
                                color: "#1A1A1A"
                                font.pixelSize: 42
                                font.bold: true
                            }

                            Text {
                                text: "ID: 123 456 789"
                                color: "#999999"
                                font.pixelSize: 16
                            }

                            Item { height: 20 } // Spacer

                            Text {
                                text: "POTENTIAL"
                                color: "#999999"
                                font.pixelSize: 12
                                font.letterSpacing: 1.5
                            }

                            RowLayout {
                                spacing: 15
                                Text {
                                    text: "12.50"
                                    color: "#BC00FF" // 밝은 보라색
                                    font.pixelSize: 56
                                    font.bold: true
                                }
                                
                                // Double Star 배지
                                Rectangle {
                                    width: 100; height: 24
                                    color: "#F0E0FF"
                                    radius: 12
                                    Text {
                                        text: "DOUBLE STAR"
                                        color: "#6A0DAD"
                                        font.bold: true
                                        font.pixelSize: 10
                                        anchors.centerIn: parent
                                    }
                                }
                            }
                            
                            Item { height: 20 }

                            // Stats Row
                            RowLayout {
                                spacing: 30
                                Layout.alignment: Qt.AlignLeft // Center in parent Layout

                                Column {
                                    spacing: 5
                                    Text { 
                                        text: "TOTAL PLAY" 
                                        color: "#999999" 
                                        font.pixelSize: 10 
                                        font.bold: true
                                        font.letterSpacing: 1.0
                                    }
                                    Text { 
                                        id: playCountText
                                        text: "0" 
                                        color: "#333333" 
                                        font.pixelSize: 20 
                                        font.bold: true 
                                    }
                                }
                                
                                Rectangle { width: 1; height: 30; color: "#DDDDDD" }

                                Column {
                                    spacing: 5
                                    Text { 
                                        text: "PLAY TIME" 
                                        color: "#999999" 
                                        font.pixelSize: 10 
                                        font.bold: true
                                        font.letterSpacing: 1.0
                                    }
                                    Text { 
                                        id: playTimeText
                                        text: "0h 0m" 
                                        color: "#333333" 
                                        font.pixelSize: 20 
                                        font.bold: true 
                                    }
                                }
                            }

                            Item { height: 40 } // Spacer

                            // Export Button
                            Rectangle {
                                width: 180
                                height: 44
                                radius: 22
                                border.color: "#E0B0FF"
                                border.width: 1
                                color: "transparent"
                                
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { text: "🔗"; font.pixelSize: 14 } // 아이콘 대체
                                    Text { 
                                        text: "Export to Image"
                                        color: "#6A0DAD"
                                        font.bold: true
                                    }
                                }
                                
                                // 버튼 클릭 효과 (옵션)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
            }

            // --- 3. 오른쪽: Most Played 리스트 ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: !mainGrid.isNarrow

                // 가중치 4 (6:4 비율)
                Layout.preferredWidth: 4
                Layout.preferredHeight: mainGrid.isNarrow ? 600 : -1
                
                color: "#FFFFFF"
                radius: 30
                border.color: "#E0E0E0"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 20

                    // 헤더
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Most Played"
                            font.pixelSize: 22
                            font.bold: true
                        }
                        Text {
                            text: "Top 10"
                            color: "#999999"
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignLeft
                        }
                    }

                    // 리스트 뷰
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: songModel
                        spacing: 15

                        delegate: RowLayout {
                            width: ListView.view.width
                            height: 60
                            spacing: 15

                            // 순위
                            Text {
                                text: index + 1
                                color: "#999999"
                                font.pixelSize: 16
                                Layout.preferredWidth: 20
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // 곡 아이콘 (사각형으로 대체)
                            Rectangle {
                                width: 50; height: 50
                                radius: 10
                                color: model.colorCode // 목업 데이터 색상
                                
                                // 실제 이미지라면 아래와 같이 사용
                                // Image { source: model.iconSource; anchors.fill: parent; radius: 10 }
                            }

                            // 곡 정보
                            Column {
                                Layout.fillWidth: true
                                Text {
                                    text: model.title
                                    font.bold: true
                                    font.pixelSize: 16
                                    color: "#333"
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    text: model.artist
                                    color: "#888"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }

                            // 플레이 횟수
                            Column {
                                // RowLayout 내에서 Column 자체를 수직 중앙, 필요하다면 우측으로 정렬
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter 

                                Text {
                                    text: model.playCount
                                    color: "#6A0DAD"
                                    font.bold: true
                                    font.pixelSize: 16
                                    // 텍스트를 Column의 오른쪽 끝에 맞춤
                                    anchors.right: parent.right 
                                }
                                Text {
                                    text: "plays"
                                    color: "#999"
                                    font.pixelSize: 10
                                    // 텍스트를 Column의 오른쪽 끝에 맞춤
                                    anchors.right: parent.right
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 목업 데이터 모델 ---
    ListModel {
        id: songModel
        
        ListElement { title: "dWxygfnsJW"; artist: "txPXRrNa"; playCount: 402; colorCode: "#AEEEEE" }
        ListElement { title: "QKZrpaaiKecM"; artist: "UtsYpPVAHssHhE vs bBX"; playCount: 389; colorCode: "#4B0082" }
        ListElement { title: "DjhDyAdKqCwkqhb"; artist: "XjtADQrRNEvEMJp"; playCount: 356; colorCode: "#0000FF" }
        ListElement { title: "woJipkFq"; artist: "tA"; playCount: 312; colorCode: "#87CEEB" }
        ListElement { title: "bEymYYgBBjKtsG"; artist: "nt+p"; playCount: 298; colorCode: "#FF0000" }
        ListElement { title: "LdmToDXYVx"; artist: "UtsYpPVAHssHhE"; playCount: 245; colorCode: "#8B0000" }
        ListElement { title: "cMcXKxLfuPAn"; artist: "NEvE"; playCount: 221; colorCode: "#FFFFFF" }
        ListElement { title: "nPmDdkgHg"; artist: "UtsYpPVAHssHhE vs waEj"; playCount: 198; colorCode: "#FFD700" }
    }
}