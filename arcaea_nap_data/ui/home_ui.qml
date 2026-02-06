import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects

Item {
    id: homeRoot
    anchors.fill: parent

    // [변경 1] ScrollView 추가 (여백 및 스크롤 담당)

    // Stats data fetched from backend
    property var difficultyStatsData: []
    
    // Cache migration state - prevents image load errors during migration
    property bool isMigrating: false

    Connections {
        target: statsHandler
        function onStatsChanged() {
            playCountText.text = statsHandler.getTotalPlayCount()
            playTimeText.text = statsHandler.getTotalPlayTime()
            difficultyStatsData = statsHandler.getDifficultyStats()
            updateTop10()
        }
    }
    
    // Refresh thumbnail paths after cache migration
    Connections {
        target: settingsHandler
        function onCacheMigrationStarting() {
            homeRoot.isMigrating = true
        }
        function onCacheMigrationFinished(error) {
            homeRoot.isMigrating = false
            if (error === "") {
                updateTop10()
            }
        }
    }
    
    function updateTop10() {
        var top10 = statsHandler.getMostPlayed()
        songModel.clear()
        for (var i = 0; i < top10.length; i++) {
            songModel.append(top10[i])
        }
    }
    
    Component.onCompleted: {
        if (statsHandler) {
            playCountText.text = statsHandler.getTotalPlayCount()
            playTimeText.text = statsHandler.getTotalPlayTime()
            difficultyStatsData = statsHandler.getDifficultyStats()
            updateTop10()
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

                            // Stats & Difficulty Group (3-Column Layout for alignment)
                            RowLayout {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignLeft
                                spacing: 20
                                
                                // --- COLUMN 1: Play Count (Right-aligned) ---
                                ColumnLayout {
                                    spacing: 16
                                    
                                    // Header (fixed height for alignment)
                                    Item {
                                        Layout.preferredHeight: 40
                                        // Use implicit width from child Column so it contributes to parent width
                                        implicitWidth: headerCol1.implicitWidth
                                        
                                        Column {
                                            id: headerCol1
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 5
                                            Text { 
                                                text: "PLAY COUNT" 
                                                color: "#999999" 
                                                font.pixelSize: 10 
                                                font.bold: true
                                                font.letterSpacing: 1.0
                                                anchors.right: parent.right
                                            }
                                            Text { 
                                                id: playCountText
                                                text: "0" 
                                                color: "#333333" 
                                                font.pixelSize: 20 
                                                font.bold: true 
                                                anchors.right: parent.right
                                            }
                                        }
                                    }
                                    
                                    // Spacer between header and list
                                    Item { Layout.preferredHeight: 0 }
                                    
                                    // List items
                                    Repeater {
                                        model: difficultyStatsData
                                        Text {
                                            Layout.alignment: Qt.AlignRight
                                            Layout.preferredHeight: 22
                                            verticalAlignment: Text.AlignVCenter
                                            text: modelData.count
                                            font.pixelSize: 15
                                            color: "#888"
                                        }
                                    }
                                }
                                
                                // --- COLUMN 2: Divider & Pills (Center-aligned) ---
                                ColumnLayout {
                                    spacing: 16
                                    
                                    // Divider (matches header height)
                                    Item {
                                        Layout.preferredWidth: 50
                                        Layout.preferredHeight: 40
                                        Rectangle { 
                                            width: 1; height: 30; color: "#DDDDDD" 
                                            anchors.centerIn: parent
                                        }
                                    }
                                    
                                    // Spacer between header and list
                                    Item { Layout.preferredHeight: 0 }
                                    
                                    // Difficulty Text
                                    Repeater {
                                        model: difficultyStatsData
                                        Text {
                                            Layout.preferredHeight: 22
                                            Layout.alignment: Qt.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData.name
                                            color: modelData.color
                                            font.bold: true
                                            font.pixelSize: 14
                                        }
                                    }
                                }
                                
                                // --- COLUMN 3: Play Time (Left-aligned) ---
                                ColumnLayout {
                                    spacing: 16
                                    
                                    // Header (fixed height for alignment)
                                    Item {
                                        Layout.preferredHeight: 40
                                        // Use implicit width from child Column so it contributes to parent width
                                        implicitWidth: headerCol3.implicitWidth
                                        
                                        Column {
                                            id: headerCol3
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
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
                                    
                                    // Spacer between header and list
                                    Item { Layout.preferredHeight: 0 }
                                    
                                    // List items
                                    Repeater {
                                        model: difficultyStatsData
                                        Text {
                                            Layout.alignment: Qt.AlignLeft
                                            Layout.preferredHeight: 22
                                            verticalAlignment: Text.AlignVCenter
                                            text: modelData.time
                                            font.pixelSize: 15
                                            color: "#888"
                                        }
                                    }
                                }
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
                    anchors.topMargin: 30
                    anchors.leftMargin: 30
                    anchors.rightMargin: 30
                    anchors.bottomMargin: 10
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
                        spacing: 2

                        delegate: RowLayout {
                            width: ListView.view.width
                            spacing: 4

                            // Calculate rank-specific properties
                            readonly property bool isRank1: index === 0
                            readonly property bool isRank2: index === 1
                            readonly property bool isRank3: index === 2
                            readonly property bool isTop3: index < 3
                            
                            // Dynamic sizes
                            readonly property int rowHeight: isRank1 ? 70 : (isRank2 ? 66 : (isRank3 ? 63 : 60))
                            readonly property int thumbSize: isRank1 ? 64 : (isRank2 ? 58 : (isRank3 ? 54 : 50))
                            readonly property real rankFontSize: isRank1 ? 22 : (isRank2 ? 20 : 18)
                            readonly property real titleFontSize: isRank1 ? 24 : (isRank2 ? 21 : (isRank3 ? 18 : 16))
                            readonly property real playCountFontSize: isRank1 ? 26 : (isRank2 ? 23 : (isRank3 ? 20 : 18))
                            
                            // Colors
                            readonly property string playCountColor: isRank1 ? "#C5A028" : (isRank2 ? "#7A7A7A" : (isRank3 ? "#A0522D" : "#984AD0"))
                            readonly property string rankDiamondBgColor: isRank1 ? "#c2a955" : (isRank2 ? "#8c8f93" : "#b16a48")
                            readonly property string rankDiamondBorderColor: isRank1 ? "#B8860B" : (isRank2 ? "#636363" : "#8B4513")
                            readonly property string rankNumberColor: isTop3 ? "white" : "#999999"
                            readonly property string titleColor: "#333"
                            readonly property string artistColor: "#888"
                            readonly property string playsLabelColor: "#999"
                            
                            height: rowHeight

                            // Rank Indicator Container
                            Item {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignVCenter
                                
                                // Diamond Background for top 3
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: isRank1 ? 28 : (isRank2 ? 26 : 24)
                                    height: width
                                    rotation: 45
                                    visible: isTop3
                                    
                                    color: rankDiamondBgColor
                                    
                                    border.color: rankDiamondBorderColor
                                    border.width: 1
                                    
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: "#40000000"
                                        shadowBlur: 4
                                        shadowHorizontalOffset: 1
                                        shadowVerticalOffset: 1
                                    }
                                }

                                // Rank Number
                                Text {
                                    anchors.centerIn: parent
                                    text: index + 1
                                    color: rankNumberColor
                                    font.pixelSize: rankFontSize
                                    font.bold: isTop3
                                    
                                    // Add shadow to text for better visibility on metallic backgrounds
                                    layer.enabled: isTop3
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: "#80000000"
                                        shadowBlur: 0.5
                                        shadowHorizontalOffset: 0.5
                                        shadowVerticalOffset: 0.5
                                    }
                                }
                            }

                            // Spacing
                            Item { width: 6 }

                            // Thumbnail Container (fixed width for center alignment)
                            Item {
                                Layout.preferredWidth: 64  // Max thumbnail size for alignment
                                Layout.preferredHeight: rowHeight
                                
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: thumbSize; height: thumbSize
                                    color: "transparent"
                                    
                                    // Actual Image (No masking/rounding)
                                    Image {
                                        id: thumbnailImage
                                        anchors.fill: parent
                                        source: (statsHandler && !homeRoot.isMigrating) ? statsHandler.getThumbnailPath(model.arcaeaId) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        mipmap: true
                                        antialiasing: true
                                        smooth: true // Keep smooth scaling for image quality, user likely meant edge AA
                                        sourceSize: Qt.size(width * 2, height * 2)
                                        visible: status === Image.Ready
                                    }
                                    
                                    // Placeholder / border
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#EEEEEE"
                                        border.color: "#E0E0E0"
                                        border.width: 1
                                        visible: thumbnailImage.status !== Image.Ready
                                        z: -1
                                    }
                                }
                            }

                            // Dynamic spacing to align text start position
                            Item { 
                                Layout.preferredWidth: (thumbSize - 50) / 2
                            }

                            // Song Info
                            Column {
                                Layout.fillWidth: true
                                Text {
                                    text: model.title
                                    font.bold: true
                                    font.pixelSize: titleFontSize
                                    color: titleColor
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    text: model.artist
                                    color: artistColor
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }

                            // Play Count
                            Column {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter 

                                Text {
                                    text: model.playCount
                                    color: playCountColor
                                    font.bold: true
                                    font.pixelSize: playCountFontSize
                                    anchors.right: parent.right 
                                }
                                Text {
                                    text: "plays"
                                    color: playsLabelColor
                                    font.pixelSize: 12
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
        // Data populated from statsHandler
    }
}