import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Shapes 1.15
import QtQuick.Effects

Item {
    id: statsRoot
    anchors.fill: parent

    // [수정] 반응형 기준점 세분화
    // 1. 완전 모바일 모드 진입 시점 (StackView 전환)
    property bool isNarrow: width < 850
    
    // 2. [신규 요청] 데스크탑 모드이지만, 우측 패널의 난이도 카드 4개가 비좁아지는 중간 시점
    // 이 때는 스플릿 뷰를 유지하되 난이도 패널만 SwipeView로 보여줍니다.
    property bool isDiffCramped: width < 1250

    // Data from statisticsHandler
    property var listData: statisticsHandler ? statisticsHandler.getListModel() : []
    property var currentSong: statisticsHandler ? statisticsHandler.getSelectedItem() : null
    property int currentSongIndex: -1
    property string searchText: ""  // Search text managed at root level
    
    // Search debounce timer
    Timer {
        id: searchDebounce
        interval: 300
        onTriggered: if (statisticsHandler) statisticsHandler.setSearchText(statsRoot.searchText)
    }
    
    // Update list when handler data changes
    Connections {
        target: statisticsHandler
        function onDataChanged() {
            statsRoot.listData = statisticsHandler.getListModel()
        }
        function onSelectedItemChanged() {
            statsRoot.currentSong = statisticsHandler.getSelectedItem()
        }
    }

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

    // 1-2. Flag filter helper component (Moved to root)
    component FlagSegmentedControl: RowLayout {
        id: flagSegmentRoot
        property string flagName: ""
        property int selectedIndex: 1  // 0=Hide, 1=Show, 2=Only
        signal indexChanged(int idx)
        
        spacing: 0
        
        Text { 
            text: flagName
            color: "#333"
            Layout.preferredWidth: 100
        }
        
        Repeater {
            model: ["Hide", "Show", "Only"]
            
            Rectangle {
                width: 50; height: 28
                radius: index === 0 ? 4 : (index === 2 ? 4 : 0)
                color: flagSegmentRoot.selectedIndex === index ? "#6A0DAD" : "#F0F0F0"
                border.color: "#D0D0D0"
                border.width: flagSegmentRoot.selectedIndex === index ? 0 : 1
                
                // Round only left/right corners based on position
                Rectangle {
                    visible: index === 0
                    anchors.right: parent.right; width: 4; height: parent.height
                    color: parent.color
                }
                Rectangle {
                    visible: index === 2
                    anchors.left: parent.left; width: 4; height: parent.height
                    color: parent.color
                }
                
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: 11
                    color: flagSegmentRoot.selectedIndex === index ? "white" : "#666"
                }
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        flagSegmentRoot.selectedIndex = index
                        flagSegmentRoot.indexChanged(index)
                    }
                }
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
        property int score: 0
        property string rank: ""
        property int pure: 0
        property int shinyPure: 0
        property int far: 0
        property int lost: 0
        property int clearType: 0
        property bool isSelected: false
        property int difficulty: 2  // Numeric difficulty for click handling
        
        signal clicked(int diff)
        
        // Helper function for rank color
        function getRankColor(r) {
            if (r === "PM") return "#FFD700"
            if (r === "EX+" || r === "EX") return "#A060FF"
            if (r === "AA") return "#4A90E2"
            return "#666"
        }
        
        // Helper function for clear type text
        function getClearTypeText(t) {
            switch(t) {
                case 0: return "Track Lost"
                case 1: return "Track Complete"
                case 2: return "Full Recall"
                case 3: return "Pure Memory"
                case 4: return "Easy Clear"
                case 5: return "Hard Clear"
                default: return ""
            }
        }

        Layout.fillWidth: true
        Layout.preferredHeight: 280
        radius: 15
        color: isSelected ? "#FFFFFF" : (diffName === "PST" ? "#F5FCFF" : (diffName === "PRS" ? "#F0FFF0" : (diffName === "ETR" ? "#F5F0F5" : "#FFF5F5")))
        border.color: isSelected ? diffColor : "#E0E0E0"
        border.width: isSelected ? 2 : 1
        
        // Clickable area for radio-button behavior
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked(parent.difficulty)
        }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 8
            
            // Header: Difficulty Name + Level
            RowLayout {
                Layout.fillWidth: true
                Text { text: diffName; color: diffColor; font.bold: true; font.pixelSize: 18 }
                Item { Layout.fillWidth: true }
                Text { text: getClearTypeText(clearType); color: "#888"; font.pixelSize: 10; visible: score > 0 }
            }
            Text { text: "LEVEL " + diffLevel; color: "#999"; font.pixelSize: 10 }
            
            Item { Layout.preferredHeight: 10 }
            
            // Score + Rank
            Text { 
                text: score > 0 ? score : "-"
                font.bold: true; font.pixelSize: 24; color: "#333" 
            }
            Text { 
                text: rank
                font.bold: true; font.pixelSize: 14
                color: getRankColor(rank)
                visible: rank !== ""
            }
            
            Item { Layout.fillHeight: true }
            
            // Stats Grid: Pure, Far, Lost
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 6
                columnSpacing: 10
                
                Text { text: "Pure"; color: "#888"; font.pixelSize: 12 }
                Text { 
                    text: score > 0 ? pure + (shinyPure > 0 ? " (" + shinyPure + ")" : "") : "-"
                    color: "#333"; font.bold: true; font.pixelSize: 12
                    Layout.alignment: Qt.AlignRight
                }
                
                Text { text: "Far"; color: "#888"; font.pixelSize: 12 }
                Text { 
                    text: score > 0 ? far.toString() : "-"
                    color: "#E0A000"; font.bold: true; font.pixelSize: 12
                    Layout.alignment: Qt.AlignRight
                }
                
                Text { text: "Lost"; color: "#888"; font.pixelSize: 12 }
                Text { 
                    text: score > 0 ? lost.toString() : "-"
                    color: "#E04040"; font.bold: true; font.pixelSize: 12
                    Layout.alignment: Qt.AlignRight
                }
            }
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



                // (B) 하단 컨텐츠 섹션
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 600
                    spacing: 30

                    // (B-1) 곡 목록
                    Rectangle {
                        id: songListContainer
                        Layout.preferredWidth: isNarrow ? -1 : 420
                        Layout.fillWidth: isNarrow 
                        Layout.fillHeight: true
                        color: "#FFFFFF"; radius: 20
                        
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 20; spacing: 12
                            
                            // Search Bar
                            Rectangle {
                                Layout.fillWidth: true; height: 40; radius: 10; color: "#F5F5F5"
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10
                                    Text { text: "🔍"; color: "#AAA" }
                                    TextInput { 
                                        id: searchInput
                                        text: statsRoot.searchText
                                        color: "#333"; font.pixelSize: 14
                                        selectByMouse: true; Layout.fillWidth: true
                                        clip: true
                                        onTextChanged: {
                                            statsRoot.searchText = text
                                            searchDebounce.restart()
                                        }
                                        
                                        // Placeholder text
                                        Text {
                                            anchors.fill: parent
                                            text: "Search songs..."
                                            color: "#999"
                                            font.pixelSize: 14
                                            visible: !searchInput.text && !searchInput.activeFocus
                                        }
                                    }
                                }
                            }
                            
                            // Controls Row: Song/Chart Switch + Sort
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                
                                // Song/Chart Mode Switcher
                                Rectangle {
                                    Layout.preferredWidth: 110
                                    Layout.preferredHeight: 32
                                    radius: 6
                                    color: "#F0F0F0"
                                    
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                        
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 6
                                            color: statisticsHandler && statisticsHandler.displayMode === "song" ? "#6A0DAD" : "transparent"
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Song"
                                                font.pixelSize: 12
                                                font.bold: statisticsHandler && statisticsHandler.displayMode === "song"
                                                color: statisticsHandler && statisticsHandler.displayMode === "song" ? "white" : "#666"
                                            }
                                            
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (statisticsHandler) statisticsHandler.setDisplayMode("song")
                                            }
                                        }
                                        
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 6
                                            color: statisticsHandler && statisticsHandler.displayMode === "chart" ? "#6A0DAD" : "transparent"
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Chart"
                                                font.pixelSize: 12
                                                font.bold: statisticsHandler && statisticsHandler.displayMode === "chart"
                                                color: statisticsHandler && statisticsHandler.displayMode === "chart" ? "white" : "#666"
                                            }
                                            
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (statisticsHandler) statisticsHandler.setDisplayMode("chart")
                                            }
                                        }
                                    }
                                }
                                
                                Item { Layout.fillWidth: true }

                                // Filter Button
                                Rectangle {
                                    Layout.preferredWidth: 80; Layout.preferredHeight: 32
                                    radius: 6
                                    color: filterMouse.containsMouse ? "#E0E0E0" : "#F0F0F0"
                                    
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text { text: "🔽"; font.pixelSize: 12; color: "#666" }
                                        Text { text: "Filters"; font.pixelSize: 12; color: "#666"; font.bold: true }
                                    }
                                    
                                    MouseArea {
                                        id: filterMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: filterPopup.open()
                                    }
                                }
                                
                                // Item { Layout.fillWidth: true }
                                
                                Item { Layout.fillWidth: true }
                                
                                // Sort Dropdown
                                ComboBox {
                                    id: sortCombo
                                    Layout.preferredWidth: 100
                                    Layout.preferredHeight: 32
                                    model: ["Title", "Score", "MAX", "Total Play", "This Year Play", "Recent", "Level (BP)", "S-BP", "P-BP", "Length"]
                                    
                                    property var sortModes: ["title", "score", "max", "total_play_count", "this_year_play_count", "recent_played", "level", "s_bp", "perceived_bp", "length"]
                                    
                                    onCurrentIndexChanged: {
                                        if (statisticsHandler && currentIndex >= 0) {
                                            statisticsHandler.setSortMode(sortModes[currentIndex])
                                        }
                                    }

                                    // Custom Styling
                                    background: Rectangle {
                                        color: parent.hovered ? "#E0E0E0" : "#F0F0F0"
                                        radius: 6
                                    }
                                    
                                    contentItem: Text {
                                        text: parent.displayText
                                        font.pixelSize: 12
                                        color: "#666"
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        leftPadding: 10
                                        rightPadding: 20
                                    }
                                    
                                    indicator: Text {
                                        x: parent.width - width - 8
                                        y: (parent.height - height) / 2
                                        text: "▼"
                                        color: "#666"
                                        font.pixelSize: 10
                                    }

                                    delegate: ItemDelegate {
                                        width: parent.width
                                        contentItem: Text {
                                            text: modelData
                                            color: "#333"
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            color: parent.highlighted ? "#E0E0E0" : "transparent"
                                        }
                                    }
                                }
                                
                                Item { Layout.fillWidth: true }
                                
                                // Ascending/Descending Toggle
                                Rectangle {
                                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                                    radius: 6
                                    color: sortOrderMouse.containsMouse ? "#E0E0E0" : "#F0F0F0"
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: statisticsHandler && statisticsHandler.sortAscending ? "↑" : "↓"
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: "#6A0DAD"
                                    }
                                    
                                    MouseArea {
                                        id: sortOrderMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: if (statisticsHandler) statisticsHandler.toggleSortOrder()
                                    }
                                }
                            }
                            
                            // Item count label
                            Text {
                                text: listData.length + " items"
                                font.pixelSize: 11
                                color: "#999"
                            }
                            
                            // Song/Chart ListView Wrapper
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true

                                ListView {
                                    id: songListView
                                    anchors.fill: parent
                                    anchors.rightMargin: 14 // Make room for scrollbar
                                    clip: true
                                    model: listData
                                    spacing: 8
                                    
                                    ScrollBar.vertical: listVerticalBar
                                    
                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: 70
                                        color: (!isNarrow && index === currentSongIndex) ? "#F8F0FF" : (delegateMouse.containsMouse ? "#FAFAFA" : "transparent")
                                        radius: 10
                                        border.width: (!isNarrow && index === currentSongIndex) ? 1 : 0
                                        border.color: "#D0A0FF"
                                        
                                        property var itemData: modelData
                                        
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 0
                                            anchors.topMargin: 10
                                            anchors.bottomMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 10
                                            
                                            // Index
                                            Text {
                                                text: index + 1
                                                font.pixelSize: 11
                                                color: "#888"
                                                Layout.preferredWidth: 22
                                                horizontalAlignment: Text.AlignRight
                                            }
                                            
                                            // Thumbnail (uses real image with fallback to colored rectangle)
                                            Rectangle { 
                                                id: thumbRect
                                                width: 48; height: 48; radius: 6
                                                color: itemData.difficultyColor || "#E0E0E0"
                                                clip: true
                                                
                                                Image {
                                                    id: thumbImage
                                                    anchors.fill: parent
                                                    anchors.margins: -1 // Slight negative margin to avoid edge artifacts
                                                    source: statsHandler ? statsHandler.getThumbnailPathForDifficulty(itemData.arcaeaId || "", itemData.thumbnailDifficulty !== undefined ? itemData.thumbnailDifficulty : itemData.difficulty) : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    visible: status === Image.Ready
                                                }
                                                
                                                // Show 3-letter difficulty code ONLY when no thumbnail is loaded
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: itemData.difficultyName || ""
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    color: "white"
                                                    visible: thumbImage.status !== Image.Ready
                                                }
                                            }
                                            
                                            Column {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text { 
                                                    text: itemData.title || ""
                                                    font.bold: true
                                                    color: "#333"
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                                Text { 
                                                    text: itemData.artist || ""
                                                    font.pixelSize: 11
                                                    color: "#888"
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                            }
                                            
                                            // Dynamic display value (based on sort mode) with difficulty info
                                            Column {
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                                spacing: 2
                                                
                                                // Helper properties for sort mode checks
                                                property bool isTitleSort: statisticsHandler && statisticsHandler.sortMode === "title"
                                                property bool isLevelSort: statisticsHandler && statisticsHandler.sortMode === "level"
                                                // Standalone modes: title and level sort show difficulty as main display
                                                property bool isStandaloneMode: isTitleSort || isLevelSort
                                                
                                                // Display value (score, play count, etc.) - hidden in standalone modes
                                                Text {
                                                    anchors.right: parent.right
                                                    text: itemData.displayValue || ""
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                    color: "#7A6090"
                                                    visible: !parent.isStandaloneMode && itemData.displayValue && itemData.displayValue !== ""
                                                }
                                                
                                                // Song mode: show all difficulty levels with colors
                                                // In standalone modes: main display (font 13), otherwise secondary info (font 11)
                                                // In specific sort modes, only highlight the "best" difficulty
                                                Row {
                                                    id: difficultyRow
                                                    anchors.right: parent.right
                                                    spacing: 0
                                                    visible: statisticsHandler && statisticsHandler.displayMode === "song" && itemData.filteredDifficulties
                                                    
                                                    // Helper function to get the best difficulty for current sort mode
                                                    // Returns -1 for modes that should highlight all difficulties
                                                    function getBestDiffForSort() {
                                                        if (!statisticsHandler) return -1
                                                        var mode = statisticsHandler.sortMode
                                                        // Check if value is a valid difficulty (>=0), -1 means no data
                                                        if (mode === "score" && itemData.bestDiffForScore >= 0) return itemData.bestDiffForScore
                                                        if (mode === "max" && itemData.bestDiffForMax >= 0) return itemData.bestDiffForMax
                                                        if (mode === "recent_played" && itemData.bestDiffForRecent >= 0) return itemData.bestDiffForRecent
                                                        if (mode === "level" && itemData.bestDiffForLevel >= 0) return itemData.bestDiffForLevel
                                                        if (mode === "s_bp" && itemData.bestDiffForSBp >= 0) return itemData.bestDiffForSBp
                                                        if (mode === "perceived_bp" && itemData.bestDiffForPerceivedBp >= 0) return itemData.bestDiffForPerceivedBp
                                                        return -1  // No highlighting for other modes (title, total_play_count, length)
                                                    }
                                                    
                                                    property int bestDiff: getBestDiffForSort()
                                                    property bool isStandaloneMode: statisticsHandler && (statisticsHandler.sortMode === "title" || statisticsHandler.sortMode === "level")
                                                    property bool isLevelSort: statisticsHandler && statisticsHandler.sortMode === "level"
                                                    
                                                    Repeater {
                                                        model: itemData.filteredDifficulties || []
                                                        
                                                        Row {
                                                            property bool isHighlighted: {
                                                                // In title sort or modes without best tracking, highlight all
                                                                if (difficultyRow.bestDiff < 0) return true
                                                                // Otherwise, only highlight if this is the best difficulty
                                                                return modelData.difficulty === difficultyRow.bestDiff
                                                            }
                                                            spacing: 0
                                                            // Separator (before each item except the first)
                                                            Text {
                                                                text: " / "
                                                                font.pixelSize: difficultyRow.isStandaloneMode ? 13 : 11
                                                                color: "#AAA"
                                                                visible: index > 0
                                                            }
                                                            // Level with difficulty color (or gray if not highlighted)
                                                            Text {
                                                                text: modelData.level || ""
                                                                font.bold: true
                                                                font.pixelSize: difficultyRow.isStandaloneMode ? 13 : 11
                                                                color: parent.isHighlighted ? (modelData.difficultyColor || "#888") : "#BBB"
                                                            }
                                                        }
                                                    }
                                                    
                                                    // BP value in parentheses for level sort (song mode)
                                                    Text {
                                                        text: " (" + (itemData.bp ? itemData.bp.toFixed(1) : "0.0") + ")"
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: "#7A6090"
                                                        visible: difficultyRow.isLevelSort
                                                    }
                                                }
                                                
                                                // Chart mode: show "BYD 9+" format with optional BP
                                                // In standalone modes: main display (font 13), otherwise secondary info (font 11)
                                                Row {
                                                    anchors.right: parent.right
                                                    spacing: 0
                                                    visible: statisticsHandler && statisticsHandler.displayMode === "chart"
                                                    
                                                    property bool isStandaloneMode: statisticsHandler && (statisticsHandler.sortMode === "title" || statisticsHandler.sortMode === "level")
                                                    property bool isLevelSort: statisticsHandler && statisticsHandler.sortMode === "level"
                                                    
                                                    Text {
                                                        text: (itemData.difficultyName || "") + " " + (itemData.level || "")
                                                        font.bold: true
                                                        font.pixelSize: parent.isStandaloneMode ? 13 : 11
                                                        color: itemData.difficultyColor || "#888"
                                                    }
                                                    
                                                    // BP value in parentheses for level sort (chart mode)
                                                    Text {
                                                        text: " (" + (itemData.bp ? itemData.bp.toFixed(1) : "0.0") + ")"
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: "#7A6090"
                                                        visible: parent.isLevelSort
                                                    }
                                                }
                                            }
                                        }
                                        
                                        MouseArea {
                                            id: delegateMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                statsRoot.currentSongIndex = index
                                                if (statisticsHandler) statisticsHandler.selectItem(index)
                                                if (isNarrow) mobileStack.push(detailPageComponent)
                                            }
                                        }
                                    }
                                    
                                    // Empty state
                                    Text {
                                        anchors.centerIn: parent
                                        text: "No songs found"
                                        color: "#999"
                                        font.pixelSize: 14
                                        visible: listData.length === 0
                                    }
                                }

                                // Independent ScrollBar anchored to the container
                                ScrollBar {
                                    id: listVerticalBar
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.rightMargin: 0
                                    active: true
                                    width: 12
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
            
            // Get difficulties to display (filteredDifficulties for Song mode, single item for Chart mode)
            property var difficultiesToShow: {
                if (!currentSong) return []
                // In song mode, use filteredDifficulties
                if (currentSong.filteredDifficulties) {
                    return currentSong.filteredDifficulties
                }
                // In chart mode, currentSong IS the chart, so wrap it in array
                return [currentSong]
            }

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
                        
                        // Song info header
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 200
                            gradient: Gradient { GradientStop { position: 0.0; color: "#2A1040" } GradientStop { position: 1.0; color: "#1A0520" } }
                            
                            RowLayout {
                                anchors.fill: parent; anchors.margins: isNarrow ? 20 : 40; spacing: isNarrow ? 20 : 30
                                
                                // Thumbnail with real image
                                Rectangle {
                                    width: isNarrow ? 120 : 260; height: isNarrow ? 120 : 260; radius: 15
                                    color: currentSong ? (currentSong.difficultyColor || "#6A0DAD") : "#6A0DAD"
                                    border.color: "white"; border.width: 2
                                    clip: true
                                    
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: -1 // Slight negative margin to avoid edge artifacts
                                        source: statsHandler && currentSong ? statsHandler.getThumbnailPathForDifficulty(currentSong.arcaeaId || "", currentSong.thumbnailDifficulty !== undefined ? currentSong.thumbnailDifficulty : currentSong.difficulty) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        visible: status === Image.Ready
                                    }
                                }
                                
                                Column {
                                    Layout.fillWidth: true; spacing: 10
                                    
                                    // BPM and Length badges
                                    RowLayout {
                                        spacing: 10
                                        visible: Boolean(currentSong)
                                        
                                        Rectangle {
                                            visible: Boolean(currentSong) && Boolean(currentSong.bpm)
                                            Layout.preferredWidth: bpmText.width + 16
                                            Layout.preferredHeight: 24
                                            radius: 12
                                            color: "#6A0DAD"
                                            Text {
                                                id: bpmText
                                                anchors.centerIn: parent
                                                text: Boolean(currentSong) && Boolean(currentSong.bpm) ? ("BPM: " + currentSong.bpm) : ""
                                                color: "white"; font.pixelSize: 11
                                            }
                                        }
                                        
                                        Rectangle {
                                            visible: Boolean(currentSong) && Number(currentSong.length) > 0
                                            Layout.preferredWidth: lengthText.width + 16
                                            Layout.preferredHeight: 24
                                            radius: 12
                                            color: "#4A90E2"
                                            Text {
                                                id: lengthText
                                                anchors.centerIn: parent
                                                text: {
                                                    if (!currentSong || !currentSong.length) return ""
                                                    var len = currentSong.length
                                                    return "Length: " + Math.floor(len / 60) + ":" + (len % 60).toString().padStart(2, '0')
                                                }
                                                color: "white"; font.pixelSize: 11
                                            }
                                        }
                                    }
                                    
                                    Text { 
                                        text: currentSong ? currentSong.title : "Select a song"
                                        color: "white"; font.bold: true
                                        font.pixelSize: isNarrow ? 24 : 36
                                        elide: Text.ElideRight
                                        width: parent.width 
                                    }
                                    Text { 
                                        text: currentSong ? currentSong.artist : ""
                                        color: "#CCC"; font.pixelSize: 16 
                                    }
                                }
                            }
                        }

                        // [Body] 난이도 카드 섹션
                        ColumnLayout {
                            Layout.fillWidth: true
                            anchors.margins: isNarrow ? 20 : 40
                            Layout.margins: isNarrow ? 20 : 40
                            spacing: 30
                            
                            visible: currentSong !== null

                            Text { text: "📊 Difficulty Breakdown"; font.bold: true; font.pixelSize: 18; color: "#333" }

                            // [난이도 패널] SwipeView vs RowLayout
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 300
                                visible: difficultiesToShow.length > 0
                                
                                // [SwipeView for mobile/cramped]
                                ArrowNav {
                                    visible: isNarrow || isDiffCramped 
                                    targetView: diffSwipe

                                    SwipeView {
                                        id: diffSwipe
                                        anchors.fill: parent
                                        clip: false; spacing: 15
                                        
                                        Repeater {
                                            model: difficultiesToShow
                                            
                                            DiffCard {
                                                diffName: modelData.difficultyName || ""
                                                diffLevel: modelData.level || ""
                                                diffColor: modelData.difficultyColor || "#888"
                                                score: modelData.bestScore || 0
                                                rank: modelData.rank || ""
                                                pure: modelData.pure || 0
                                                shinyPure: modelData.shinyPure || 0
                                                far: modelData.far || 0
                                                lost: modelData.lost || 0
                                                clearType: modelData.bestClearType || 0
                                                difficulty: modelData.difficulty || 0
                                                isSelected: statisticsHandler && modelData.difficulty === statisticsHandler.selectedDifficulty
                                                
                                                onClicked: function(diff) {
                                                    if (statisticsHandler) {
                                                        statisticsHandler.setSelectedDifficulty(diff)
                                                        diffSwipe.currentIndex = index
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                PageIndicator {
                                    visible: (isNarrow || isDiffCramped) && difficultiesToShow.length > 1
                                    count: difficultiesToShow.length
                                    currentIndex: diffSwipe.currentIndex
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    delegate: Rectangle { width: 8; height: 8; radius: 4; color: index === diffSwipe.currentIndex ? "#6A0DAD" : "#DDD" }
                                }

                                // [Desktop] RowLayout
                                RowLayout {
                                    anchors.fill: parent
                                    visible: !isNarrow && !isDiffCramped
                                    spacing: 15
                                    
                                    Repeater {
                                        model: difficultiesToShow
                                        
                                        DiffCard {
                                            diffName: modelData.difficultyName || ""
                                            diffLevel: modelData.level || ""
                                            diffColor: modelData.difficultyColor || "#888"
                                            score: modelData.bestScore || 0
                                            rank: modelData.rank || ""
                                            pure: modelData.pure || 0
                                            shinyPure: modelData.shinyPure || 0
                                            far: modelData.far || 0
                                            lost: modelData.lost || 0
                                            clearType: modelData.bestClearType || 0
                                            difficulty: modelData.difficulty || 0
                                            isSelected: statisticsHandler && modelData.difficulty === statisticsHandler.selectedDifficulty
                                            
                                            onClicked: function(diff) {
                                                if (statisticsHandler) {
                                                    statisticsHandler.setSelectedDifficulty(diff)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Empty state when no song selected
                            Text {
                                visible: !currentSong
                                text: "Select a song from the list to view details"
                                color: "#999"
                                font.pixelSize: 16
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
    
    // =========================================================================
    // Filter Popup
    // =========================================================================
    Popup {
        id: filterPopup
        width: 400
        height: 500
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        property bool initialized: false  // Prevent filter updates during initialization
        
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        
        Component.onCompleted: {
            // Mark as initialized after all components are ready
            initialized = true
        }
        
        background: Rectangle {
            color: "#FFFFFF"
            radius: 15
            border.color: "#E0E0E0"
            border.width: 1
            
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 4
                shadowBlur: 1.0 // Normalized value roughly corresponding to radius
                shadowColor: "#40000000"
            }
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20
            
            // Header
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Filters"; font.pixelSize: 20; font.bold: true; color: "#333" }
                Item { Layout.fillWidth: true }
                Text { 
                    text: "Reset All"
                    font.pixelSize: 12
                    color: "#6A0DAD"
                    font.underline: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Reset all filters
                            if (statisticsHandler) {
                                statisticsHandler.setFilter("difficulties", [0, 1, 2, 3, 4])
                                statisticsHandler.setFilter("clear_types", [0, 1, 2, 3, 4, 5])
                            }
                            pstCheck.checked = true
                            prsCheck.checked = true
                            ftrCheck.checked = true
                            etrCheck.checked = true
                            bydCheck.checked = true
                            
                            // Reset Range Slider
                            rangeSlider.bpMode = false
                            rangeSlider.handleAIndex = 0
                            rangeSlider.handleBIndex = rangeSlider.currentList.length > 0 ? rangeSlider.currentList.length - 1 : 0
                            filterPopup.updateRangeFilter()  // Apply the reset to backend
                            
                            ignoreFlagSegment.selectedIndex = 1 // Show
                            skillFlagSegment.selectedIndex = 1 // Show
                            slowFlagSegment.selectedIndex = 1 // Show
                            
                            clearType0.checked = true
                            clearType1.checked = true
                            clearType2.checked = true
                            clearType3.checked = true
                            clearType4.checked = true
                            clearType5.checked = true
                        }
                    }
                }
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                
                ColumnLayout {
                    width: parent.width - 24  // Right padding for scroll indicator
                    spacing: 20
                    
                    // Difficulty Filter
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Difficulties"; font.pixelSize: 14; font.bold: true; color: "#333" }
                        
                        GridLayout {
                            columns: 5
                            columnSpacing: 15
                            rowSpacing: 8
                            
                            CheckBox {
                                id: pstCheck
                                text: "PST"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            CheckBox {
                                id: prsCheck
                                text: "PRS"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            CheckBox {
                                id: ftrCheck
                                text: "FTR"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            CheckBox {
                                id: etrCheck
                                text: "ETR"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            CheckBox {
                                id: bydCheck
                                text: "BYD"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                        }
                    }
                    
                    // Level/BP Range Filter
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        // Header with Mode Toggle
                        RowLayout {
                            width: parent.width
                            
                            Text { text: "Range Filter"; font.pixelSize: 14; font.bold: true; color: "#333" }
                            
                            Item { Layout.fillWidth: true }
                            
                            // Level/BP Toggle
                            Rectangle {
                                width: 100; height: 28
                                radius: 4
                                color: "#F0F0F0"
                                
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0
                                    
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        radius: 4; color: !rangeSlider.bpMode ? "#6A0DAD" : "transparent"
                                        Text { anchors.centerIn: parent; text: "Level"; font.pixelSize: 11; color: !rangeSlider.bpMode ? "white" : "#666" }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: rangeSlider.setBpMode(false) }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        radius: 4; color: rangeSlider.bpMode ? "#6A0DAD" : "transparent"
                                        Text { anchors.centerIn: parent; text: "BP"; font.pixelSize: 11; color: rangeSlider.bpMode ? "white" : "#666" }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: rangeSlider.setBpMode(true) }
                                    }
                                }
                            }
                        }
                        
                        // Range Slider
                        Item {
                            id: rangeSlider
                            width: parent.width
                            height: 60
                            
                            property bool bpMode: false
                            property var levels: statisticsHandler ? statisticsHandler.availableLevels : []
                            property var bps: statisticsHandler ? statisticsHandler.availableBPs : []
                            property var currentList: bpMode ? bps : levels
                            
                            // Independent handle indices (not constrained to be lower/upper)
                            property int handleAIndex: 0
                            property int handleBIndex: currentList.length > 0 ? currentList.length - 1 : 0
                            
                            // Computed min/max based on handle values
                            property int minIndex: Math.min(handleAIndex, handleBIndex)
                            property int maxIndex: Math.max(handleAIndex, handleBIndex)

                            property var levelBoundaries: statisticsHandler ? statisticsHandler.levelBoundaries : ({})
                            
                            function setBpMode(mode) {
                                if (mode !== bpMode) {
                                    // Convert current selection to new mode
                                    var oldMinIdx = minIndex
                                    var oldMaxIdx = maxIndex
                                    
                                    if (mode) {
                                        // Level -> BP conversion
                                        var minLevel = levels[oldMinIdx]
                                        var maxLevel = levels[oldMaxIdx]
                                        
                                        // Get BP range from levelBoundaries
                                        var minBp = levelBoundaries[minLevel] ? levelBoundaries[minLevel].min : bps[0]
                                        var maxBp = levelBoundaries[maxLevel] ? levelBoundaries[maxLevel].max : bps[bps.length - 1]
                                        
                                        // Find indices in BP list
                                        bpMode = true  // Change mode first so currentList updates
                                        handleAIndex = findClosestIndex(bps, minBp, true)
                                        handleBIndex = findClosestIndex(bps, maxBp, false)
                                    } else {
                                        // BP -> Level conversion
                                        var selectedMinBp = bps[oldMinIdx]
                                        var selectedMaxBp = bps[oldMaxIdx]
                                        
                                        // Find levels that contain this BP range
                                        var newMinLevelIdx = 0
                                        var newMaxLevelIdx = levels.length - 1
                                        
                                        for (var i = 0; i < levels.length; i++) {
                                            var lvl = levels[i]
                                            var bounds = levelBoundaries[lvl]
                                            if (bounds) {
                                                if (bounds.min <= selectedMinBp && bounds.max >= selectedMinBp) {
                                                    newMinLevelIdx = i
                                                    break
                                                }
                                            }
                                        }
                                        
                                        for (var j = levels.length - 1; j >= 0; j--) {
                                            var lvl2 = levels[j]
                                            var bounds2 = levelBoundaries[lvl2]
                                            if (bounds2) {
                                                if (bounds2.min <= selectedMaxBp && bounds2.max >= selectedMaxBp) {
                                                    newMaxLevelIdx = j
                                                    break
                                                }
                                            }
                                        }
                                        
                                        bpMode = false
                                        handleAIndex = newMinLevelIdx
                                        handleBIndex = newMaxLevelIdx
                                    }
                                    
                                    filterPopup.updateRangeFilter()
                                }
                            }
                            
                            function findClosestIndex(list, value, isMin) {
                                if (!list || list.length === 0) return 0
                                
                                var closest = 0
                                var minDiff = Math.abs(list[0] - value)
                                
                                for (var i = 1; i < list.length; i++) {
                                    var diff = Math.abs(list[i] - value)
                                    if (diff < minDiff) {
                                        minDiff = diff
                                        closest = i
                                    } else if (diff === minDiff) {
                                        // For equal distance, prefer lower for min, higher for max
                                        closest = isMin ? Math.min(closest, i) : Math.max(closest, i)
                                    }
                                }
                                return closest
                            }
                            
                            function getDisplayValue(idx) {
                                if (idx >= 0 && idx < currentList.length) {
                                    var val = currentList[idx]
                                    // Format BP values with 1 decimal place
                                    if (bpMode && typeof val === 'number') {
                                        return val.toFixed(1)
                                    }
                                    return val.toString()
                                }
                                return ""
                            }
                            
                            // Track
                            Rectangle {
                                id: track
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -10
                                height: 6; radius: 3
                                color: "#E0E0E0"
                                
                                // Tick marks
                                Repeater {
                                    model: rangeSlider.currentList.length
                                    
                                    Rectangle {
                                        visible: rangeSlider.shouldShowTick(index)
                                        // Use same calculation as handles: offset by half handle width
                                        x: rangeSlider.currentList.length > 1 ? 
                                            10 + (index / (rangeSlider.currentList.length - 1)) * (parent.width - 20) - 1 : 0
                                        y: -3
                                        width: 2; height: 12
                                        radius: 1
                                        color: "#C0C0C0"
                                    }
                                }
                                
                                // Active region
                                Rectangle {
                                    x: rangeSlider.currentList.length > 1 ? (rangeSlider.minIndex / (rangeSlider.currentList.length - 1)) * parent.width : 0
                                    width: rangeSlider.currentList.length > 1 ? 
                                        ((rangeSlider.maxIndex - rangeSlider.minIndex) / (rangeSlider.currentList.length - 1)) * parent.width : parent.width
                                    height: parent.height; radius: 3
                                    color: "#6A0DAD"
                                }
                            }
                            
                            // Determine if a tick mark should be shown at given index
                            function shouldShowTick(idx) {
                                if (currentList.length <= 1) return false
                                // Skip endpoints - removed as per request
                                // if (idx === 0 || idx === currentList.length - 1) return false
                                
                                var value = currentList[idx]
                                
                                if (bpMode) {
                                    // BP mode: show at .0 for all, and .5 only for values > 8.0
                                    if (typeof value === 'number') {
                                        var decimal = value - Math.floor(value)
                                        var isInteger = Math.abs(decimal) < 0.01
                                        var isHalf = Math.abs(decimal - 0.5) < 0.01
                                        
                                        if (value <= 8.0) {
                                            return isInteger
                                        } else {
                                            return isInteger || isHalf
                                        }
                                    }
                                    return false
                                } else {
                                    // Level mode: show at non-plus levels only (e.g., "9", "10", not "9+")
                                    if (typeof value === 'string') {
                                        return value.indexOf('+') === -1
                                    }
                                    return false
                                }
                            }
                            
                            // Helper function to snap handle position to discrete index
                            function snapToIndex(pixelX) {
                                if (currentList.length <= 1) return 0
                                var ratio = pixelX / (track.width - 20)  // 20 = handle width
                                var idx = Math.round(ratio * (currentList.length - 1))
                                return Math.max(0, Math.min(idx, currentList.length - 1))
                            }
                            
                            function getSnapPosition(idx) {
                                if (currentList.length <= 1) return 0
                                return (idx / (currentList.length - 1)) * (track.width - 20)
                            }
                            
                            // Handle A (independent)
                            Rectangle {
                                id: handleA
                                width: 20; height: 20; radius: 10
                                color: handleAMouse.pressed ? "#5A0D9D" : "#6A0DAD"
                                border.color: "white"; border.width: 2
                                x: rangeSlider.currentList.length > 1 ? 
                                    (rangeSlider.handleAIndex / (rangeSlider.currentList.length - 1)) * (track.width - width) : 0
                                anchors.verticalCenter: track.verticalCenter
                                
                                Text {
                                    id: handleALabel
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // Show above if: handles are close AND this handle is to the right
                                    property bool tooClose: Math.abs(handleA.x - handleB.x) < 20
                                    property bool isRightHandle: handleA.x > handleB.x
                                    property bool showAbove: tooClose && isRightHandle
                                    y: showAbove ? -height - 4 : parent.height + 4
                                    text: rangeSlider.getDisplayValue(rangeSlider.handleAIndex)
                                    font.pixelSize: 10; font.bold: true; color: "#333"
                                }
                                
                                MouseArea {
                                    id: handleAMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -20; anchors.bottomMargin: -20
                                    anchors.leftMargin: 0; anchors.rightMargin: 0
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    property int startIndex: 0
                                    property real pressGlobalX: 0
                                    
                                    onPressed: (mouse) => {
                                        startIndex = rangeSlider.handleAIndex
                                        // Map to track coordinates for stable reference
                                        var mapped = mapToItem(track, mouse.x, mouse.y)
                                        pressGlobalX = mapped.x
                                    }
                                    
                                    onPositionChanged: (mouse) => {
                                        if (pressed && rangeSlider.currentList.length > 1) {
                                            var mapped = mapToItem(track, mouse.x, mouse.y)
                                            var deltaX = mapped.x - pressGlobalX
                                            
                                            // Calculate how many index steps this delta represents
                                            var stepWidth = (track.width - parent.width) / (rangeSlider.currentList.length - 1)
                                            var indexDelta = Math.round(deltaX / stepWidth)
                                            
                                            var newIdx = Math.max(0, Math.min(startIndex + indexDelta, rangeSlider.currentList.length - 1))
                                            rangeSlider.handleAIndex = newIdx
                                        }
                                    }
                                    
                                    onReleased: {
                                        filterPopup.updateRangeFilter()
                                    }
                                }
                            }
                            
                            // Handle B (independent)
                            Rectangle {
                                id: handleB
                                width: 20; height: 20; radius: 10
                                color: handleBMouse.pressed ? "#5A0D9D" : "#6A0DAD"
                                border.color: "white"; border.width: 2
                                x: rangeSlider.currentList.length > 1 ? 
                                    (rangeSlider.handleBIndex / (rangeSlider.currentList.length - 1)) * (track.width - width) : track.width - width
                                anchors.verticalCenter: track.verticalCenter
                                
                                Text {
                                    id: handleBLabel
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // Show above if: handles are close AND this handle is to the right
                                    property bool tooClose: Math.abs(handleA.x - handleB.x) < 20
                                    property bool isRightHandle: handleB.x > handleA.x
                                    property bool showAbove: tooClose && isRightHandle
                                    y: showAbove ? -height - 4 : parent.height + 4
                                    text: rangeSlider.getDisplayValue(rangeSlider.handleBIndex)
                                    font.pixelSize: 10; font.bold: true; color: "#333"
                                }
                                
                                MouseArea {
                                    id: handleBMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -20; anchors.bottomMargin: -20
                                    anchors.leftMargin: 0; anchors.rightMargin: 0
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    property int startIndex: 0
                                    property real pressGlobalX: 0
                                    
                                    onPressed: (mouse) => {
                                        startIndex = rangeSlider.handleBIndex
                                        var mapped = mapToItem(track, mouse.x, mouse.y)
                                        pressGlobalX = mapped.x
                                    }
                                    
                                    onPositionChanged: (mouse) => {
                                        if (pressed && rangeSlider.currentList.length > 1) {
                                            var mapped = mapToItem(track, mouse.x, mouse.y)
                                            var deltaX = mapped.x - pressGlobalX
                                            
                                            var stepWidth = (track.width - parent.width) / (rangeSlider.currentList.length - 1)
                                            var indexDelta = Math.round(deltaX / stepWidth)
                                            
                                            var newIdx = Math.max(0, Math.min(startIndex + indexDelta, rangeSlider.currentList.length - 1))
                                            rangeSlider.handleBIndex = newIdx
                                        }
                                    }
                                    
                                    onReleased: {
                                        filterPopup.updateRangeFilter()
                                    }
                                }
                            }
                        }
                    }
                    
                    Rectangle { height: 1; Layout.fillWidth: true; color: "#E0E0E0" }
                    
                    // Chart Flags
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Consultant Sheet Flags"; font.pixelSize: 14; font.bold: true; color: "#333" }
                        
                        // Flag filter helper component
                        // (Moved to root)
                            

                        
                        Column {
                            spacing: 8
                            
                            FlagSegmentedControl {
                                id: ignoreFlagSegment
                                flagName: "⛔ trap"
                                selectedIndex: 1  // Default: Show
                                onIndexChanged: filterPopup.updateFlagFilter()
                            }
                            
                            FlagSegmentedControl {
                                id: skillFlagSegment
                                flagName: "⚠️ individual"
                                selectedIndex: 1  // Default: Show
                                onIndexChanged: filterPopup.updateFlagFilter()
                            }
                            
                            FlagSegmentedControl {
                                id: slowFlagSegment
                                flagName: "🔀 bpm"
                                selectedIndex: 1  // Default: Show
                                onIndexChanged: filterPopup.updateFlagFilter()
                            }
                        }
                    }
                    
                    Rectangle { height: 1; Layout.fillWidth: true; color: "#E0E0E0" }
                    
                    // Clear Type Filter
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Clear Types"; font.pixelSize: 14; font.bold: true; color: "#333" }
                        
                        GridLayout {
                            columns: 2
                            columnSpacing: 15
                            rowSpacing: 8
                            
                            CheckBox {
                                id: clearType0
                                text: "Track Lost"
                                checked: true
                                onCheckedChanged: filterPopup.updateClearTypeFilter()
                            }
                            CheckBox {
                                id: clearType1
                                text: "Track Complete"
                                checked: true
                                onCheckedChanged: filterPopup.updateClearTypeFilter()
                            }
                            CheckBox {
                                id: clearType2
                                text: "Full Recall"
                                checked: true
                                onCheckedChanged: filterPopup.updateClearTypeFilter()
                            }
                            CheckBox {
                                id: clearType3
                                text: "Pure Memory"
                                checked: true
                                onCheckedChanged: filterPopup.updateClearTypeFilter()
                            }
                            CheckBox {
                                id: clearType4
                                text: "Easy Clear"
                                checked: true
                                onCheckedChanged: filterPopup.updateClearTypeFilter()
                            }
                            CheckBox {
                                id: clearType5
                                text: "Hard Clear"
                                checked: true
                                onCheckedChanged: filterPopup.updateClearTypeFilter()
                            }
                        }
                    }
                }
            }
            
            // Footer buttons
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                
                Button {
                    text: "Close"
                    onClicked: filterPopup.close()
                }
            }
        }
        
        function updateDifficultyFilter() {
            if (!initialized) return  // Skip during initialization
            
            var diffs = []
            if (pstCheck.checked) diffs.push(0)
            if (prsCheck.checked) diffs.push(1)
            if (ftrCheck.checked) diffs.push(2)
            if (bydCheck.checked) diffs.push(3)
            if (etrCheck.checked) diffs.push(4)
            
            if (statisticsHandler) {
                statisticsHandler.setFilter("difficulties", diffs)
            }
        }
        
        function updateRangeFilter() {
            if (!initialized) return
            
            if (statisticsHandler && rangeSlider.currentList.length > 0) {
                var minVal = rangeSlider.currentList[rangeSlider.minIndex]
                var maxVal = rangeSlider.currentList[rangeSlider.maxIndex]
                
                if (rangeSlider.bpMode) {
                    statisticsHandler.setFilter("bp_mode", true)
                    statisticsHandler.setFilter("bp_min", minVal)
                    statisticsHandler.setFilter("bp_max", maxVal)
                } else {
                    statisticsHandler.setFilter("bp_mode", false)
                    // Convert level string to numeric for filtering
                    statisticsHandler.setFilter("level_min_str", minVal)
                    statisticsHandler.setFilter("level_max_str", maxVal)
                }
            }
        }
        
        function updateFlagFilter() {
            if (!initialized) return
            
            // Map: 0=Hide(off), 1=Show(contain), 2=Only(only)
            var map = ["off", "contain", "only"]
            
            if (statisticsHandler) {
                statisticsHandler.setFilter("ignore_chart", map[ignoreFlagSegment.selectedIndex])
                statisticsHandler.setFilter("skill_issues", map[skillFlagSegment.selectedIndex])
                statisticsHandler.setFilter("contain_slowspeed", map[slowFlagSegment.selectedIndex])
            }
        }

        function updateClearTypeFilter() {
            if (!initialized) return  // Skip during initialization
            
            var types = []
            if (clearType0.checked) types.push(0)
            if (clearType1.checked) types.push(1)
            if (clearType2.checked) types.push(2)
            if (clearType3.checked) types.push(3)
            if (clearType4.checked) types.push(4)
            if (clearType5.checked) types.push(5)
            
            if (statisticsHandler) {
                statisticsHandler.setFilter("clear_types", types)
            }
        }
    }
}