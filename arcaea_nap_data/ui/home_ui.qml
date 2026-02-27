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

    // Profile data from account_connections.json
    property var profileData: ({})

    // Profile image path (refreshed on settingsChanged so Home reflects Settings changes)
    property string profileImagePath: (settingsHandler && settingsHandler.getProfileImage()) ? settingsHandler.getProfileImage() : ""

    // Potential 등급별 색상
    function getPotentialColor(rating) {
        if (rating === null || rating === undefined || rating < 0) return "#999999" // 미사용 시 (회색)
        if (rating >= 1300) return "#D14A6B" // 13.00 ~ : 밝은 크림슨/핑크 (3★)
        if (rating >= 1200) return "#C12955" // 12.00 ~ 12.99 : 진한 크림슨/레드 (1★, 2★)
        if (rating >= 1100) return "#C62828" // 11.00 ~ 11.99 : 붉은색
        if (rating >= 1000) return "#8E24AA" // 10.00 ~ 10.99 : 짙은 보라
        if (rating >= 700)  return "#AB47BC" // 7.00 ~ 9.99  : 보라
        if (rating >= 300)  return "#4CAF50" // 3.00 ~ 6.99  : 초록
        return "#29B6F6"                     // 0.00 ~ 2.99  : 파랑/하늘색
    }

    // Potential 등급 배지 텍스트
    function getPotentialBadge(rating) {
        if (rating === null || rating === undefined) return ""
        if (rating >= 1300) return "TRIPLE STAR"
        if (rating >= 1250) return "DOUBLE STAR"
        if (rating >= 1200) return "STAR"
        if (rating >= 1100) return "RED"
        if (rating >= 700)  return "PURPLE"
        if (rating >= 350)  return "GREEN"
        return "BLUE"
    }

    // Potential 등급에 따른 별 개수
    function getPotentialStars(rating) {
        if (rating === null || rating === undefined) return 0
        if (rating >= 1300) return 3
        if (rating >= 1250) return 2
        if (rating >= 1200) return 1
        return 0
    }

    // user_code를 "XXX XXX XXX" 형태로 포맷
    function formatUserCode(code) {
        if (!code || code.length === 0) return ""
        var digits = code.replace(/\s/g, '')
        if (digits.length !== 9) return code
        return digits.substring(0, 3) + " " + digits.substring(3, 6) + " " + digits.substring(6, 9)
    }

    function loadProfile() {
        if (profileHandler) {
            profileData = profileHandler.getProfile() || {}
        }
    }

    Connections {
        target: statsHandler
        function onStatsChanged() {
            playCountText.text = statsHandler.getTotalPlayCount()
            playTimeText.text = statsHandler.getTotalPlayTime()
            difficultyStatsData = statsHandler.getDifficultyStats()
            updateTop10()
        }
    }

    Connections {
        target: profileHandler
        function onProfileChanged() {
            loadProfile()
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
        function onSettingsChanged() {
            profileImagePath = (settingsHandler && settingsHandler.getProfileImage()) ? settingsHandler.getProfileImage() : ""
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
        loadProfile()
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
                id: profileCardRect
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
                    z: 2
                    anchors.fill: parent
                    spacing: -16

                    // 정보 텍스트 영역
                    Item {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        
                        ColumnLayout {
                            id: profileInfoCol
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
                                text: profileData.connected ? (profileData.name || "—") : "—"
                                color: "#1A1A1A"
                                font.pixelSize: 42
                                font.bold: true
                            }

                            Text {
                                text: profileData.connected && profileData.user_code
                                      ? "ID: " + formatUserCode(profileData.user_code)
                                      : ""
                                color: "#999999"
                                font.pixelSize: 16
                                visible: profileData.connected && profileData.user_code ? true : false
                            }

                            Item { height: 20 } // Spacer

                            Text {
                                text: "POTENTIAL"
                                color: "#999999"
                                font.pixelSize: 12
                                font.letterSpacing: 1.5
                            }

                            Column {
                                id: potentialContainer
                                spacing: 2
                                
                                property string colorTheme: getPotentialColor(profileData.connected ? profileData.rating : null)
                                property int starCount: getPotentialStars(profileData.connected ? profileData.rating : null)
                                property bool hasRating: profileData.connected && profileData.rating !== null && profileData.rating !== undefined

                                // Rating Value (floating directly on background)
                                Text {
                                    text: potentialContainer.hasRating ? (profileData.rating / 100).toFixed(2) : "—"
                                    color: potentialContainer.hasRating ? "#2A2A2A" : "#999999"
                                    font.pixelSize: 42
                                    font.bold: true
                                }

                                // Stars inside a small pill-shaped border
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: potentialContainer.starCount > 0
                                    
                                    width: starsRow.implicitWidth + 24
                                    height: starsRow.implicitHeight + 8
                                    radius: 3 // 곡률 확 줄임
                                    color: "transparent"
                                    border.color: Qt.rgba(Qt.color(potentialContainer.colorTheme).r, Qt.color(potentialContainer.colorTheme).g, Qt.color(potentialContainer.colorTheme).b, 0.4)
                                    border.width: 1.5
                                    
                                    // Subtle tint inside
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 1.5
                                        radius: 1.5
                                        color: Qt.rgba(Qt.color(potentialContainer.colorTheme).r, Qt.color(potentialContainer.colorTheme).g, Qt.color(potentialContainer.colorTheme).b, 0.05)
                                    }

                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: Qt.rgba(Qt.color(potentialContainer.colorTheme).r, Qt.color(potentialContainer.colorTheme).g, Qt.color(potentialContainer.colorTheme).b, 0.2)
                                        shadowBlur: 8
                                    }

                                    Row {
                                        id: starsRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        
                                        Repeater {
                                            model: potentialContainer.starCount
                                            Text {
                                                text: "★"
                                                color: potentialContainer.colorTheme
                                                font.pixelSize: 14
                                                
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    shadowEnabled: true
                                                    shadowColor: Qt.rgba(Qt.color(potentialContainer.colorTheme).r, Qt.color(potentialContainer.colorTheme).g, Qt.color(potentialContainer.colorTheme).b, 0.5)
                                                    shadowBlur: 4
                                                    shadowHorizontalOffset: 0
                                                    shadowVerticalOffset: 0
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Item { height: 10 }

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

                // 프로필 이미지 영역: 패널 너비 60%, 우측 정렬 오버레이, 좌 10% / 우 5% 페이드 그라데이션
                Item {
                    id: profileImageClipArea
                    anchors.right: profileCardRect.right
                    anchors.top: profileCardRect.top
                    anchors.bottom: profileCardRect.bottom
                    width: profileCardRect.width * 0.6
                    z: 1
                    clip: true

                    // Rounded mask + 좌측 10%·우측 5% 투명도 페이드 (이미지 영역 기준)
                    Item {
                        id: profileImageMaskItem
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        layer.smooth: true
                        layer.samples: 4
                        Rectangle {
                            id: maskRect
                            anchors.fill: parent
                            radius: 30
                            antialiasing: true
                            smooth: true

                            // 프로필 텍스트 영역 침범 너비를 동적으로 계산하여 그라데이션 위치 자동 확장
                            property real overlapRatio: {
                                if (!profileInfoCol) return 0;
                                var textEnd = profileCardRect.width * 0.1 + profileInfoCol.implicitWidth;
                                var imageStart = profileCardRect.width * 0.4;
                                var overlap = textEnd - imageStart;
                                return overlap / profileImageClipArea.width;
                            }
                            
                            property real fadeEndRatio: {
                                // 텍스트 끝나는 지점에서 좀 더 넉넉한 여유(약 12% 가량)를 두고 100% 선명해지도록 설정
                                var end = Math.max(0.2, maskRect.overlapRatio + 0.12); 
                                return Math.min(0.85, end);
                            }
                            property real fullyOpaqueRatio: {
                                // 꼬리를 0.15 비율(전체 너비의 약 15%)까지 더 길게 빼서 극도로 완만하게 연장합니다.
                                return Math.min(0.92, maskRect.fadeEndRatio + 0.15);
                            }

                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                
                                // 초중반에 미리 선명도(알파값)를 끌어올려 끝단에서 튀는 현상을 막는 Ease-Out 형태의 곡선입니다.
                                GradientStop { position: 0;                                  color: "#00000000" } // 0%
                                GradientStop { position: maskRect.fadeEndRatio * 0.10;       color: "#1AFFFFFF" } // 10% (기존 5%보다 진하게)
                                GradientStop { position: maskRect.fadeEndRatio * 0.20;       color: "#33FFFFFF" } // 20%
                                GradientStop { position: maskRect.fadeEndRatio * 0.35;       color: "#59FFFFFF" } // 35%
                                GradientStop { position: maskRect.fadeEndRatio * 0.50;       color: "#80FFFFFF" } // 50% (기존 30%에서 대폭 끌어올림)
                                GradientStop { position: maskRect.fadeEndRatio * 0.65;       color: "#A6FFFFFF" } // 65%
                                GradientStop { position: maskRect.fadeEndRatio * 0.80;       color: "#CCFFFFFF" } // 80%
                                GradientStop { position: maskRect.fadeEndRatio * 0.90;       color: "#E0FFFFFF" } // 88%
                                GradientStop { position: maskRect.fadeEndRatio;              color: "#E6FFFFFF" } // 90% (연장 구간 초입에 이미 거의 다 선명해짐)
                                
                                // 연장 꼬리 구간: 이미 90%까지 도달해 있으므로, 남은 10%의 투명도만 아주 얕고 길게 펴발라 끝이 튀는 현상을 방지
                                GradientStop { position: maskRect.fadeEndRatio + (maskRect.fullyOpaqueRatio - maskRect.fadeEndRatio) * 0.2; color: "#EBFFFFFF" } // 92%
                                GradientStop { position: maskRect.fadeEndRatio + (maskRect.fullyOpaqueRatio - maskRect.fadeEndRatio) * 0.4; color: "#F0FFFFFF" } // 94%
                                GradientStop { position: maskRect.fadeEndRatio + (maskRect.fullyOpaqueRatio - maskRect.fadeEndRatio) * 0.6; color: "#F5FFFFFF" } // 96%
                                GradientStop { position: maskRect.fadeEndRatio + (maskRect.fullyOpaqueRatio - maskRect.fadeEndRatio) * 0.8; color: "#FAFFFFFF" } // 98%
                                GradientStop { position: maskRect.fullyOpaqueRatio;                                                         color: "#FFFFFFFF" } // 100% 완전 선명
                                
                                // 우측 코너 페이드: 시각적으로 완전히 투명해진 것처럼 보이지만,
                                // 너무 일찍 이미지가 사라져버리는 현상을 막기 위해 끝단 투명도를 0%가 아닌 5~10% 수준으로 살짝 남깁니다.
                                GradientStop { position: 0.920;                              color: "#FFFFFFFF" } // 100% 선명
                                GradientStop { position: 0.950;                              color: "#B3FFFFFF" } // 70%
                                GradientStop { position: 0.975;                              color: "#66FFFFFF" } // 40%
                                GradientStop { position: 1.000;                              color: "#1AFFFFFF" } // 약 10% 불투명 (거의 투명하게 보이지만 형태의 끝단까지 형체가 유지됨)
                            }
                        }
                    }

                    // 이미지 콘텐츠 (라운드 마스크 적용, 세로 꽉 채운 뒤 가로는 비율 유지)
                    Item {
                        id: profileImageContentWrapper
                        anchors.fill: parent
                        layer.enabled: true
                        layer.smooth: true
                        layer.samples: 4
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: profileImageMaskItem
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                        }

                        // 세로 꽉 채움 우선: 높이=영역 높이, 너비=비율에 따라 확장 (중앙 정렬해 넘치는 부분 clip)
                        Item {
                            id: profileImageInner
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: profileImageHome.status === Image.Ready && profileImageHome.implicitHeight > 0
                                ? Math.max(profileImageClipArea.width, profileImageClipArea.height * profileImageHome.implicitWidth / profileImageHome.implicitHeight)
                                : profileImageClipArea.width

                            Image {
                                id: profileImageHome
                                anchors.fill: parent
                                source: profileImagePath ? ("file:///" + profileImagePath.replace(/\\/g, '/')) : ""
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                                smooth: true
                                visible: status === Image.Ready
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "#F0F0F0"
                                border.color: "#E0E0E0"
                                border.width: 1
                                visible: profileImagePath !== "" && !profileImageHome.visible
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "No Image"
                                color: "#999999"
                                font.pixelSize: 12
                                visible: profileImagePath !== "" && !profileImageHome.visible
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