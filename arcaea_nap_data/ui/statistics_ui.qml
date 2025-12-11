import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Shapes 1.15

Item {
    id: statsRoot
    anchors.fill: parent

    // [수정] 반응형 기준점 세분화
    // 1. 완전 모바일 모드 진입 시점 (StackView 전환)
    property bool isNarrow: width < 850
    
    // 2. [신규 요청] 데스크탑 모드이지만, 우측 패널의 난이도 카드 4개가 비좁아지는 중간 시점
    // 이 때는 스플릿 뷰를 유지하되 난이도 패널만 SwipeView로 보여줍니다.
    property bool isDiffCramped: width < 1250

    property var currentSong: songListModel.get(0)
    property int currentSongIndex: 0

    // =========================================================================
    // [1] 재사용 가능한 컴포넌트 정의 (Components)
    // =========================================================================

    // [신규 컴포넌트] SwipeView 양 옆에 화살표를 달아주는 래퍼(Wrapper)
    component ArrowNav: Item {
        default property alias content: container.data // 내부에 SwipeView를 넣기 위함
        property SwipeView targetView: null // 제어할 대상 SwipeView

        anchors.fill: parent
        
        // 실제 컨텐츠가 들어갈 공간
        Item { id: container; anchors.fill: parent }

        // 왼쪽 화살표 버튼
        Rectangle {
            width: 30; height: 30; radius: 15
            color: "#FFFFFF"; border.color: "#E0E0E0";
            anchors.left: parent.left; anchors.leftMargin: -10 // 살짝 걸치게
            anchors.verticalCenter: parent.verticalCenter
            z: 10 // 컨텐츠 위에 표시
            // 첫 페이지면 숨김
            visible: targetView && targetView.currentIndex > 0
            
            Text { text: "❮"; anchors.centerIn: parent; color: "#6A0DAD"; font.bold: true }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onEntered: parent.color = "#F0F0F0"
                onExited: parent.color = "#FFFFFF"
                onClicked: targetView.decrementCurrentIndex()
            }
        }

        // 오른쪽 화살표 버튼
        Rectangle {
            width: 30; height: 30; radius: 15
            color: "#FFFFFF"; border.color: "#E0E0E0";
            anchors.right: parent.right; anchors.rightMargin: -10
            anchors.verticalCenter: parent.verticalCenter
            z: 10
            // 마지막 페이지면 숨김
            visible: targetView && targetView.currentIndex < targetView.count - 1

            Text { text: "❯"; anchors.centerIn: parent; color: "#6A0DAD"; font.bold: true }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onEntered: parent.color = "#F0F0F0"
                onExited: parent.color = "#FFFFFF"
                onClicked: targetView.incrementCurrentIndex()
            }
        }
    }

    // 1-1. 상단 통계 카드 (숫자)
    component StatsCard: Rectangle {
        color: "#FFFFFF"; radius: 20
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 25; spacing: 20
            Column {
                spacing: 5
                RowLayout { Text { text: "TOTAL PLAY COUNT"; font.pixelSize: 11; color: "#999"; font.bold: true } Item { Layout.fillWidth: true } Text { text: "🕒"; color: "#D0A0FF" } }
                Text { text: "4,829"; font.pixelSize: 32; font.bold: true; color: "#D040A0" }
            }
            Column {
                spacing: 5
                RowLayout { Text { text: "AVERAGE POTENTIAL"; font.pixelSize: 11; color: "#999"; font.bold: true } Item { Layout.fillWidth: true } Text { text: "👑"; color: "#4A90E2" } }
                Text { text: "12.54"; font.pixelSize: 32; font.bold: true; color: "#4A60E2" }
            }
        }
    }

    // 1-2. 레이더 차트
    component RadarCard: Rectangle {
        color: "#FFFFFF"; radius: 20
        Text { text: "PERFORMANCE RADAR"; font.pixelSize: 11; color: "#999"; font.bold: true; x: 25; y: 25 }
        Canvas {
            anchors.centerIn: parent; width: 140; height: 140
            onPaint: {
                var ctx = getContext("2d"); ctx.reset();
                ctx.beginPath(); ctx.strokeStyle = "#E0E0E0"; ctx.lineWidth = 1;
                var sides = 5, radius = 60;
                for (var i = 0; i < sides; i++) {
                    var angle = (i * 2 * Math.PI / sides) - (Math.PI / 2);
                    var x = 70 + radius * Math.cos(angle), y = 70 + radius * Math.sin(angle);
                    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
                }
                ctx.closePath(); ctx.stroke();
                ctx.beginPath(); ctx.fillStyle = "rgba(188, 0, 255, 0.2)"; ctx.strokeStyle = "#BC00FF"; ctx.lineWidth = 2;
                var data = [0.8, 0.9, 0.7, 0.6, 0.85];
                for (var j = 0; j < sides; j++) {
                    var dAngle = (j * 2 * Math.PI / sides) - (Math.PI / 2);
                    var dR = radius * data[j];
                    var dx = 70 + dR * Math.cos(dAngle), dy = 70 + dR * Math.sin(dAngle);
                    j === 0 ? ctx.moveTo(dx, dy) : ctx.lineTo(dx, dy);
                }
                ctx.closePath(); ctx.fill(); ctx.stroke();
            }
        }
    }

    // 1-3. 막대 그래프
    component GraphCard: Rectangle {
        color: "#FFFFFF"; radius: 20
        Text { text: "WEEKLY ACTIVITY"; font.pixelSize: 11; color: "#999"; font.bold: true; x: 25; y: 25 }
        RowLayout {
            anchors.bottom: parent.bottom; anchors.bottomMargin: 30
            anchors.horizontalCenter: parent.horizontalCenter; spacing: 15
            Repeater {
                model: [20, 15, 80, 40, 50, 45, 30]
                Rectangle { width: 20; height: modelData; radius: 4; color: index === 2 ? "#A060FF" : "#E0E0E0" }
            }
        }
    }

    // 1-4. 난이도 카드
    component DiffCard: Rectangle {
        property string diffName: "FTR"
        property string diffLevel: "11"
        property string diffColor: "#A060FF"
        property string score: "00,000,000"
        property bool isSelected: false

        Layout.fillWidth: true
        Layout.preferredHeight: 280
        radius: 15
        color: isSelected ? "#FFFFFF" : (diffName === "PST" ? "#F5FCFF" : (diffName === "PRS" ? "#F0FFF0" : "#FFF5F5"))
        border.color: isSelected ? diffColor : "#E0E0E0"
        border.width: isSelected ? 2 : 1

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20
            Text { text: diffName; color: diffColor; font.bold: true; font.pixelSize: 18 }
            Text { text: "LEVEL " + diffLevel; color: "#999"; font.pixelSize: 10 }
            Item { height: 10 }
            Text { text: score; font.bold: true; font.pixelSize: 22; color: "#333" }
            Item { height: 15 }
            RowLayout { Layout.fillWidth: true; Text { text: "Max Combo"; color: "#888"; font.pixelSize: 12 } Item { Layout.fillWidth: true } Text { text: "1450"; color: "#333"; font.bold: true } }
        }
    }

    // =========================================================================
    // [2] 메인 뷰 (Root View)
    // =========================================================================
    StackView {
        id: mobileStack
        anchors.fill: parent
        visible: isNarrow
        initialItem: mainContentComponent
        pushEnter: Transition { PropertyAnimation { property: "x"; from: mobileStack.width; to: 0; duration: 250; easing.type: Easing.OutQuad } }
        pushExit: Transition { PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 250 } }
        popEnter: Transition { PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 250 } }
        popExit: Transition { PropertyAnimation { property: "x"; from: 0; to: mobileStack.width; duration: 250; easing.type: Easing.InQuad } }
    }

    Loader {
        anchors.fill: parent
        visible: !isNarrow
        sourceComponent: mainContentComponent
    }

    // =========================================================================
    // [3] 메인 컨텐츠 컴포넌트
    // =========================================================================
    Component {
        id: mainContentComponent

        ScrollView {
            id: mainScroll // [1] 높이 참조를 위해 ID 부여
            contentWidth: availableWidth
            clip: true
            padding: isNarrow ? 20 : 40

            ColumnLayout {
                width: parent.width
                // [수정] 높이 계산 로직 복구
                // 내용물 크기(implicitHeight)와 화면 높이(padding 제외) 중 큰 값을 사용
                height: Math.max(implicitHeight, mainScroll.height - (mainScroll.padding * 2))

                spacing: 30

                // (A) 상단 대시보드 섹션
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220

                    // [Mobile] SwipeView + [신규] ArrowNav 적용
                    ArrowNav {
                        visible: isNarrow
                        targetView: dashboardSwipe // 타겟 지정
                        
                        SwipeView {
                            id: dashboardSwipe
                            anchors.fill: parent
                            clip: true; spacing: 10
                            StatsCard { }
                            RadarCard { }
                            GraphCard { }
                        }
                    }
                    
                    PageIndicator {
                        visible: isNarrow
                        count: dashboardSwipe.count
                        currentIndex: dashboardSwipe.currentIndex
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        delegate: Rectangle { width: 8; height: 8; radius: 4; color: index === dashboardSwipe.currentIndex ? "#6A0DAD" : "#DDD" }
                    }

                    // [Desktop] RowLayout
                    RowLayout {
                        anchors.fill: parent
                        visible: !isNarrow
                        spacing: 30
                        StatsCard { Layout.fillWidth: true; Layout.fillHeight: true }
                        RadarCard { Layout.fillWidth: true; Layout.fillHeight: true }
                        GraphCard { Layout.preferredWidth: 350; Layout.fillHeight: true }
                    }
                }

                // (B) 하단 컨텐츠 섹션
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 600
                    spacing: 30

                    // (B-1) 곡 목록
                    Rectangle {
                        Layout.preferredWidth: isNarrow ? -1 : 380
                        Layout.fillWidth: isNarrow 
                        Layout.fillHeight: true
                        color: "#FFFFFF"; radius: 20
                        
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 20; spacing: 15
                            Rectangle {
                                Layout.fillWidth: true; height: 40; radius: 10; color: "#F5F5F5"
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10
                                    Text { text: "🔍"; color: "#AAA" }
                                    TextInput { text: "Search songs..."; color: "#333"; font.pixelSize: 14; selectByMouse: true; Layout.fillWidth: true }
                                }
                            }
                            ListView {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                clip: true; model: songListModel; spacing: 10
                                delegate: Rectangle {
                                    width: ListView.view.width; height: 70
                                    color: (!isNarrow && index === currentSongIndex) ? "#F8F0FF" : "transparent"
                                    radius: 10
                                    border.width: (!isNarrow && index === currentSongIndex) ? 1 : 0
                                    border.color: "#D0A0FF"
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        Rectangle { width: 48; height: 48; radius: 6; color: model.colorCode }
                                        Column {
                                            Layout.fillWidth: true
                                            Text { text: model.title; font.bold: true; color: "#333" }
                                            Text { text: model.artist; font.pixelSize: 11; color: "#888" }
                                        }
                                        Column {
                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                            Text { text: model.rank; font.bold: true; color: model.rank === "PM" ? "#FFD700" : "#A060FF"; anchors.right: parent.right }
                                            Text { text: model.score; font.bold: true; color: "#333"; anchors.right: parent.right }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            statsRoot.currentSongIndex = index
                                            statsRoot.currentSong = songListModel.get(index)
                                            if (isNarrow) mobileStack.push(detailPageComponent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // (B-2) 곡 상세 정보
                    Loader {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !isNarrow
                        sourceComponent: detailPageComponent
                    }
                }
            }
        }
    }

    // =========================================================================
    // [4] 상세 페이지 컴포넌트
    // =========================================================================
    Component {
        id: detailPageComponent

        Rectangle {
            color: isNarrow ? "#F3F4F8" : "#FFFFFF" 
            radius: isNarrow ? 0 : 20
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // [Mobile Header]
                Rectangle {
                    Layout.fillWidth: true; height: 60; visible: isNarrow; color: "white"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "❮ Back"; font.bold: true; color: "#6A0DAD"; font.pixelSize: 16 
                            MouseArea { anchors.fill: parent; onClicked: mobileStack.pop() }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: "Song Detail"; font.bold: true; color: "#333"; font.pixelSize: 16 }
                        Item { Layout.fillWidth: true }
                        Item { width: 40 }
                    }
                }

                // [Song Header]
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentWidth: availableWidth; clip: true
                    
                    ColumnLayout {
                        width: parent.width; spacing: 0
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 200
                            gradient: Gradient { GradientStop { position: 0.0; color: "#2A1040" } GradientStop { position: 1.0; color: "#1A0520" } }
                            RowLayout {
                                anchors.fill: parent; anchors.margins: isNarrow ? 20 : 40; spacing: isNarrow ? 20 : 30
                                Rectangle {
                                    width: isNarrow ? 80 : 120; height: isNarrow ? 80 : 120; radius: 10; color: currentSong.colorCode
                                    border.color: "white"; border.width: 2
                                }
                                Column {
                                    Layout.fillWidth: true; spacing: 10
                                    Text { text: currentSong.title; color: "white"; font.bold: true; font.pixelSize: isNarrow ? 24 : 36; wrapMode: Text.Wrap; width: parent.width }
                                    Text { text: currentSong.artist; color: "#CCC"; font.pixelSize: 16 }
                                }
                            }
                        }

                        // [Body] 난이도 카드 섹션
                        ColumnLayout {
                            Layout.fillWidth: true
                            anchors.margins: isNarrow ? 20 : 40
                            Layout.margins: isNarrow ? 20 : 40
                            spacing: 30

                            Text { text: "📊 Difficulty Breakdown"; font.bold: true; font.pixelSize: 18; color: "#333" }

                            // [난이도 패널] SwipeView vs RowLayout
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 300
                                
                                // [신규 적용] ArrowNav + SwipeView
                                // 조건: 모바일 모드(isNarrow) 이거나 중간 단계 비좁은 모드(isDiffCramped) 일 때 표시
                                ArrowNav {
                                    visible: isNarrow || isDiffCramped 
                                    targetView: diffSwipe

                                    SwipeView {
                                        id: diffSwipe
                                        anchors.fill: parent
                                        clip: false; spacing: 15
                                        
                                        DiffCard { diffName: "PST"; diffLevel: "5"; score: "10,000,550"; diffColor: "#00A0E9" }
                                        DiffCard { diffName: "PRS"; diffLevel: "8"; score: "10,000,020"; diffColor: "#50C050" }
                                        DiffCard { diffName: "FTR"; diffLevel: "11"; score: "9,985,420"; diffColor: "#A060FF"; isSelected: true }
                                        DiffCard { diffName: "BYD"; diffLevel: "12"; score: "9,650,200"; diffColor: "#E04040" }
                                    }
                                }

                                PageIndicator {
                                    visible: isNarrow || isDiffCramped
                                    count: 4; currentIndex: diffSwipe.currentIndex
                                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                                    delegate: Rectangle { width: 8; height: 8; radius: 4; color: index === diffSwipe.currentIndex ? "#6A0DAD" : "#DDD" }
                                }

                                // [Desktop] RowLayout
                                // 조건: 완전한 데스크탑 모드일 때만 표시 (!isNarrow 그리고 !isDiffCramped)
                                RowLayout {
                                    anchors.fill: parent
                                    visible: !isNarrow && !isDiffCramped
                                    spacing: 15
                                    DiffCard { diffName: "PST"; diffLevel: "5"; score: "10,000,550"; diffColor: "#00A0E9" }
                                    DiffCard { diffName: "PRS"; diffLevel: "8"; score: "10,000,020"; diffColor: "#50C050" }
                                    DiffCard { diffName: "FTR"; diffLevel: "11"; score: "9,985,420"; diffColor: "#A060FF"; isSelected: true }
                                    DiffCard { diffName: "BYD"; diffLevel: "12"; score: "9,650,200"; diffColor: "#E04040" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ListModel {
        id: songListModel
        ListElement { title: "dWxygfnsJW"; artist: "txPXRrNa"; score: "10,000,985"; rank: "EX+"; colorCode: "#AEEEEE" }
        ListElement { title: "QKZrpaaiKecM"; artist: "UtsYpPVAHssHhE vs bBX"; score: "9,985,420"; rank: "EX"; colorCode: "#4B0082" }
        ListElement { title: "DjhDyAdKqCwkqhb"; artist: "XjtADQrRNEvEMJp"; score: "9,750,110"; rank: "AA"; colorCode: "#0000FF" }
        ListElement { title: "woJipkFq"; artist: "tA"; score: "9,920,300"; rank: "EX"; colorCode: "#87CEEB" }
        ListElement { title: "bEymYYgBBjKtsG"; artist: "nt+p"; score: "10,001,220"; rank: "PM"; colorCode: "#FF0000" }
        ListElement { title: "LdmToDXYVx"; artist: "UtsYpPVAHssHhE"; score: "9,998,500"; rank: "EX+"; colorCode: "#8B0000" }
        ListElement { title: "cMcXKxLfuPAn"; artist: "NEvE"; score: "9,450,660"; rank: "A"; colorCode: "#FFFFFF" }
        ListElement { title: "nPmDdkgHg"; artist: "UtsYpPVAHssHhE vs waEj"; score: "9,890,123"; rank: "EX"; colorCode: "#FFD700" }
    }
}