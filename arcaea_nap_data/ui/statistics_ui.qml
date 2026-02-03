import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Basic as Basic
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
    property int currentSongIndex: statisticsHandler ? statisticsHandler.selectedIndex : -1
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

    // 1-3. 난이도 필터 체크박스 (Diamond)
    component DiffFilterCheckbox: Column {
        id: diffCheckRoot
        property bool checked: true
        property string text: ""
        property color diffColor: "#000000"
        
        spacing: 8
        
        // Diamond Indicator using Shape for proper anti-aliasing
        Item {
            width: 32; height: 32
            anchors.horizontalCenter: parent.horizontalCenter
            
            Shape {
                anchors.fill: parent
                antialiasing: true
                
                ShapePath {
                    strokeWidth: 2
                    strokeColor: diffCheckRoot.diffColor
                    fillColor: diffCheckRoot.checked ? diffCheckRoot.diffColor : "transparent"
                    joinStyle: ShapePath.MiterJoin
                    
                    // Diamond: top -> right -> bottom -> left -> top
                    startX: 16; startY: 4
                    PathLine { x: 28; y: 16 }
                    PathLine { x: 16; y: 28 }
                    PathLine { x: 4; y: 16 }
                    PathLine { x: 16; y: 4 }
                }
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    diffCheckRoot.checked = !diffCheckRoot.checked
                }
            }
        }
        
        // Label
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: diffCheckRoot.text
            font.bold: true
            font.pixelSize: 12
            color: diffCheckRoot.checked ? diffCheckRoot.diffColor : "#AAA"
        }
    }

    // 1-4. Difficulty Card (for detailed view)
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
        property bool isFiltered: false  // True if excluded by current filter
        property int playCount: 0
        property string lastPlayedDate: "-"
        property real bp: 0
        property real shinyBp: 0
        property real perceivedBp: 0
        property bool hasScore: false  // True if this chart has been played
        
        signal clicked(int diff)
        
        // Filtered state: keep colors but muted, not fully gray
        // Blend original color with gray for a desaturated look
        function blendWithGray(hexColor, amount) {
            // amount: 0 = original, 1 = full gray
            var r = parseInt(hexColor.substring(1, 3), 16)
            var g = parseInt(hexColor.substring(3, 5), 16)
            var b = parseInt(hexColor.substring(5, 7), 16)
            var grayVal = 160  // Target gray
            r = Math.round(r + (grayVal - r) * amount)
            g = Math.round(g + (grayVal - g) * amount)
            b = Math.round(b + (grayVal - b) * amount)
            return "#" + r.toString(16).padStart(2, '0') + g.toString(16).padStart(2, '0') + b.toString(16).padStart(2, '0')
        }
        
        // Computed colors: filtered = slight desaturation (30%), not full gray
        property string effectiveTextColor: isFiltered ? "#666" : "#333"
        property string effectiveDiffColor: isFiltered ? blendWithGray(diffColor, 0.35) : diffColor
        property string effectiveSubTextColor: isFiltered ? "#999" : "#888"
        
        // Helper function for rank color
        function getRankColor(r) {
            var c = "#666"
            if (r === "PM") c = "#00aaaa"      // Much darker Cyan
            else if (r === "EX+" || r === "EX") c = "#5865F2" // Brighter, slightly purplish Blue
            else if (r === "AA" || r === "A") c = "#9050B0"   // Purple (Desaturated)
            else if (r === "B" || r === "C" || r === "D") c = "#D04040" // Red (Desaturated)
            
            if (isFiltered) return blendWithGray(c, 0.4)
            return c
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
        
        // Helper function for abbreviated clear type text
        function getAbbreviatedClearTypeText(t) {
            switch(t) {
                case 0: return "Lost"
                case 1: return "N. Clear"
                case 2: return "FR"
                case 3: return "PM"
                case 4: return "E. Clear"
                case 5: return "H. Clear"
                default: return ""
            }
        }
        
        // Background color based on state - filtered keeps tint but muted
        function getBackgroundColor() {
            if (isFiltered) {
                switch(diffName) {
                    case "PST": return "#F8FAFA"  // Very light blue-gray
                    case "PRS": return "#F8FAF8"  // Very light green-gray
                    case "FTR": return "#FAF8FC"  // Very light purple-gray
                    case "BYD": return "#FAF8F8"  // Very light red-gray
                    case "ETR": return "#F8F8F8"  // Light gray
                    default: return "#FAF8F8"    // Very light red-gray
                }
            }
            if (isSelected) return "#FFFFFF"
            switch(diffName) {
                case "PST": return "#F5FCFF"
                case "PRS": return "#F0FFF0"
                case "FTR": return "#F8F0FF" // Light purple for Future
                case "BYD": return "#FFF5F5" // Light red for Beyond
                case "ETR": return "#F5F0F5"
                default: return "#FFF5F5"
            }
        }

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 320
        radius: 15
        color: getBackgroundColor()
        border.color: isFiltered ? blendWithGray(diffColor, 0.5) : (isSelected ? diffColor : "#E0E0E0")
        border.width: (isSelected && !isFiltered) ? 2 : 1
        clip: true  // Prevent content from overflowing card boundaries
        
        // Clickable area for radio-button behavior (disabled when filtered)
        MouseArea {
            anchors.fill: parent
            cursorShape: isFiltered ? Qt.ArrowCursor : Qt.PointingHandCursor
            enabled: !isFiltered
            onClicked: parent.clicked(parent.difficulty)
        }
        
        // Diagonal stripes overlay for filtered state (subtle disabled indicator)
        Canvas {
            anchors.fill: parent
            visible: isFiltered
            opacity: 0.03
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "#000000"
                ctx.lineWidth = 1
                var spacing = 12
                for (var i = -height; i < width + height; i += spacing) {
                    ctx.beginPath()
                    ctx.moveTo(i, 0)
                    ctx.lineTo(i + height, height)
                    ctx.stroke()
                }
            }
        }

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 8
            
            // Header: Difficulty Name + Level
            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                spacing: 0
                
                Text { 
                    id: diffTitleText
                    text: diffName + " " + diffLevel
                    color: effectiveDiffColor; font.bold: true; font.pixelSize: 18
                    
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                    // Allow shrinking to prevent layout blowout, ensuring proper width reporting
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Item { Layout.fillWidth: true }
                
                // Metrics for Title (Bold 18px)
                TextMetrics {
                    id: titleMetrics
                    font: diffTitleText.font
                    text: diffTitleText.text
                }
                
                // Metrics for Clear Text (Regular 10px)
                TextMetrics {
                    id: clearTextMeasure
                    text: getClearTypeText(clearType)
                    font.pixelSize: 10
                }

                Text { 
                    id: clearTypeDisplay
                    // Calculate if we need to abbreviate based on accurate metrics
                    // Using implicitWidth vs width is key; titleMetrics provides unelided width
                    property real safetyPadding: 25
                    property bool performAbbreviation: (titleMetrics.width + safetyPadding + clearTextMeasure.width) > headerRow.width
                    
                    text: performAbbreviation ? getAbbreviatedClearTypeText(clearType) : getClearTypeText(clearType)
                    color: effectiveSubTextColor; font.pixelSize: 10
                    visible: hasScore 
                    
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    Layout.bottomMargin: -2 
                }
            }
            
            // BP Metrics (Takes place of previous Level text)
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                
                // Shiny
                Item {
                    id: shinyWrapper
                    Layout.fillWidth: true
                    Layout.preferredHeight: childrenRect.height
                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text { 
                            text: shinyBp > 0 ? shinyBp.toFixed(1) : "-"
                            font.bold: true; font.pixelSize: 12; color: effectiveTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text { 
                            text: shinyWrapper.width < 50 ? "S-BP" : "Shiny"
                            font.pixelSize: 10; color: effectiveSubTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // BP
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: childrenRect.height
                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text { 
                            text: bp > 0 ? bp.toFixed(1) : "-"
                            font.bold: true; font.pixelSize: 12; color: effectiveTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text { 
                            text: "BP"
                            font.pixelSize: 10; color: effectiveSubTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
                
                // Perceived
                Item {
                    id: perceivedWrapper
                    Layout.fillWidth: true
                    Layout.preferredHeight: childrenRect.height
                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text { 
                            text: perceivedBp > 0 ? perceivedBp.toFixed(1) : "-"
                            font.bold: true; font.pixelSize: 12; color: effectiveTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text { 
                            text: perceivedWrapper.width < 50 ? "P-BP" : "Perceived"
                            font.pixelSize: 10; color: effectiveSubTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
            
            Item { Layout.preferredHeight: 2 }
            
            // Score + Rank
            Text { 
                text: hasScore ? score : "-"
                font.bold: true; font.pixelSize: 24; color: effectiveTextColor 
            }
            Text { 
                text: rank !== "" ? rank : "PM"
                font.bold: true; font.pixelSize: 14
                color: getRankColor(rank)
                opacity: rank !== "" ? 1.0 : 0.0
            }
            
            Item { Layout.fillHeight: true }
            
            // Stats Grid: Pure, Far, Lost
            GridLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: Math.min(parent.width * 0.9, parent.width * 0.5 + 50)
                columns: 2
                rowSpacing: 6
                columnSpacing: 10
                
                Text { text: "Pure"; color: effectiveSubTextColor; font.pixelSize: 12 }
                Text { 
                    text: hasScore ? pure + (shinyPure > 0 ? " (" + shinyPure + ")" : "") : "-"
                    color: effectiveTextColor; font.bold: true; font.pixelSize: 12
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                }
                
                Text { text: "Far"; color: effectiveSubTextColor; font.pixelSize: 12 }
                Text { 
                    text: hasScore ? far.toString() : "-"
                    color: isFiltered ? "#C0A060" : "#E0A000"; font.bold: true; font.pixelSize: 12
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                }
                
                Text { text: "Lost"; color: effectiveSubTextColor; font.pixelSize: 12 }
                Text { 
                    text: hasScore ? lost.toString() : "-"
                    color: isFiltered ? "#C08080" : "#E04040"; font.bold: true; font.pixelSize: 12
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                }
                
                // Divider
                Rectangle {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    height: 1
                    color: isFiltered ? "#EFEFEF" : "#E0E0E0"
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                }
                
                // MAX Value
                Text {
                    Layout.columnSpan: 2
                    Layout.alignment: Qt.AlignRight
                    text: {
                        if (!hasScore) return "-"
                        var val = pure + far + lost - shinyPure
                        return val > 0 ? "MAX-" + val : "MAX"
                    }
                    color: isFiltered ? effectiveSubTextColor : "#666"
                    font.pixelSize: 11
                }
                // Play Date Value
                Text {
                    Layout.columnSpan: 2
                    Layout.alignment: Qt.AlignRight
                    text: hasScore ? lastPlayedDate : "-"
                    color: isFiltered ? effectiveSubTextColor : "#666"
                    font.pixelSize: 11
                }
            }
            
            // Play Count Value - Separate to avoid Grid layout influence
            Text {
                Layout.alignment: Qt.AlignRight
                text: {
                    if (playCount <= 0) return "-"
                    return playCount + " plays"
                }
                color: isFiltered ? effectiveSubTextColor : "#666"
                font.pixelSize: 12
                font.bold: true
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

                        // Independent Scrollbar in Padding Area
                        Basic.ScrollBar {
                            id: listVerticalBar
                            z: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            y: songListContentLayout.y + listWrapper.y
                            height: listWrapper.height
                            width: 10
                            
                            policy: ScrollBar.AlwaysOn
                            size: songListView.visibleArea.heightRatio
                            position: songListView.visibleArea.yPosition
                            
                            onPositionChanged: {
                                if (pressed) songListView.contentY = position * songListView.contentHeight
                            }
                            
                            property bool showScrollbar: songListView.moving || hideTimer.running || listVerticalBar.hovered || listVerticalBar.pressed
                            hoverEnabled: true
                            active: true
                            
                            Timer { id: hideTimer; interval: 1000 }
                            Connections {
                                target: songListView
                                function onMovingChanged() { if (!songListView.moving) hideTimer.restart() }
                            }
                            onPressedChanged: { if (!pressed && !songListView.moving) hideTimer.restart() }
                            
                            opacity: showScrollbar ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            
                            background: Rectangle { color: "transparent" }
                            contentItem: Rectangle {
                                implicitWidth: 6; implicitHeight: 100; radius: 3
                                color: "#B090D0"
                                opacity: listVerticalBar.pressed ? 1.0 : (listVerticalBar.hovered ? 1.0 : 0.6)
                            }
                        }
                        
                        ColumnLayout {
                            id: songListContentLayout
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
                                            color: statisticsHandler && statisticsHandler.displayMode === "song" ? "#6A0DAD" : (songMouse.containsMouse ? "#E0E0E0" : "transparent")
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Song"
                                                font.pixelSize: 12
                                                font.bold: statisticsHandler && statisticsHandler.displayMode === "song"
                                                color: statisticsHandler && statisticsHandler.displayMode === "song" ? "white" : "#666"
                                            }
                                            
                                            MouseArea {
                                                id: songMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (statisticsHandler) statisticsHandler.setDisplayMode("song")
                                            }
                                        }
                                        
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 6
                                            color: statisticsHandler && statisticsHandler.displayMode === "chart" ? "#6A0DAD" : (chartMouse.containsMouse ? "#E0E0E0" : "transparent")
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Chart"
                                                font.pixelSize: 12
                                                font.bold: statisticsHandler && statisticsHandler.displayMode === "chart"
                                                color: statisticsHandler && statisticsHandler.displayMode === "chart" ? "white" : "#666"
                                            }
                                            
                                            MouseArea {
                                                id: chartMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (statisticsHandler) statisticsHandler.setDisplayMode("chart")
                                            }
                                        }
                                    }
                                }
                                
                                Item { Layout.fillWidth: true }

                                // Filter Button
                                Rectangle {
                                    Layout.preferredWidth: 60; Layout.preferredHeight: 32
                                    radius: 6
                                    color: filterMouse.containsMouse ? "#E0E0E0" : "#F0F0F0"
                                    
                                    Text { anchors.centerIn: parent; text: "Filters"; font.pixelSize: 12; color: "#666"; font.bold: true }
                                    
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
                                Basic.ComboBox {
                                    id: sortCombo
                                    Layout.preferredWidth: 120
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
                                        height: 32 // Fixed height for consistency
                                        
                                        contentItem: Text {
                                            text: modelData
                                            color: "#333"
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 8
                                        }
                                        
                                        background: Rectangle {
                                            // Add margins to background for floating feel inside popup
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            color: parent.hovered || parent.highlighted ? "#F5F0FA" : "transparent" // Soft purple tint
                                            radius: 4
                                        }
                                    }
                                    
                                    popup: Popup {
                                        y: sortCombo.height + 4
                                        width: sortCombo.width
                                        implicitHeight: contentItem.implicitHeight + 10
                                        padding: 5
                                        
                                        enter: Transition {
                                            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 100 }
                                            NumberAnimation { property: "y"; from: sortCombo.height; to: sortCombo.height + 4; duration: 100; easing.type: Easing.OutQuad }
                                        }
                                        exit: Transition {
                                            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 100 }
                                        }
                                        
                                        contentItem: ListView {
                                            clip: true
                                            implicitHeight: contentHeight
                                            model: sortCombo.popup.visible ? sortCombo.delegateModel : null
                                            currentIndex: sortCombo.highlightedIndex
                                            interactive: false // Disable scrolling
                                        }
                                        
                                        background: Rectangle {
                                            color: "white"
                                            border.color: "#E0E0E0"
                                            border.width: 1
                                            radius: 8
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
                                id: listWrapper
                                Layout.fillWidth: true; Layout.fillHeight: true

                                ListView {
                                    id: songListView
                                    anchors.fill: parent
                                    // lists items expanded to full width (no margin)
                                    clip: true
                                    model: listData
                                    spacing: 8
                                    
                                    delegate: listDelegate
                                    
                                    // No attached ScrollBar to avoid layout conflicts
                                }
                                

                                
                                // Auto-scroll to selected item when list data changes (sort/filter/mode)
                                Connections {
                                    target: statisticsHandler
                                    function onDataChanged() {
                                        // Use Qt.callLater to ensure model is updated before scrolling
                                        Qt.callLater(function() {
                                            var idx = statisticsHandler.selectedIndex
                                            if (idx >= 0 && idx < songListView.count) {
                                                songListView.positionViewAtIndex(idx, ListView.Center)
                                            }
                                        })
                                    }
                                    function onSelectedItemChanged() {
                                        // Also scroll when selection changes (e.g., difficulty change in Chart mode)
                                        Qt.callLater(function() {
                                            var idx = statisticsHandler.selectedIndex
                                            if (idx >= 0 && idx < songListView.count) {
                                                songListView.positionViewAtIndex(idx, ListView.Contain)
                                            }
                                        })
                                    }
                                }
                                
                                // Delegate Component for ListView
                                Component {
                                    id: listDelegate
                                    Rectangle {
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
                                                    mipmap: true
                                                    antialiasing: true
                                                    sourceSize: Qt.size(width * 2, height * 2)
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
                                                if (statisticsHandler) statisticsHandler.selectItem(index)
                                                // Scroll just enough to fully show the item if partially visible at edges
                                                songListView.positionViewAtIndex(index, ListView.Contain)
                                                if (isNarrow) mobileStack.push(detailPageComponent)
                                            }
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
            
            // Get ALL difficulties to display (regardless of Song/Chart mode or filter)
            // Filtered charts will be shown with isFiltered=true for gray styling
            property var difficultiesToShow: {
                if (!currentSong) return []
                // Always use allDifficulties to show all charts (with isFiltered flag)
                if (currentSong.allDifficulties) {
                    return currentSong.allDifficulties
                }
                return []
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
                        Item {
                            id: headerContainer
                            Layout.fillWidth: true; Layout.preferredHeight: 200

                            // Background with Top-Rounded Corners
                            Item {
                                anchors.fill: parent
                                clip: true // Hide bottom overflow

                                // Mask for rounded corners (Following home_ui.qml pattern)
                                Item {
                                    id: headerMaskItem
                                    width: parent.width
                                    height: parent.height + (isNarrow ? 0 : 20)
                                    visible: false
                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.samples: 4
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: isNarrow ? 0 : 20
                                        color: "black"
                                        antialiasing: true
                                        smooth: true
                                    }
                                }

                                // Content with Blur + Mask Effect
                                Item {
                                    id: headerContentWrapper
                                    width: parent.width
                                    height: parent.height + (isNarrow ? 0 : 20)
                                    
                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.samples: 4
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: headerMaskItem
                                        maskThresholdMin: 0.3
                                        maskSpreadAtMin: 0.2
                                    }

                                    // Fallback Background
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#2A1040"
                                    }

                                    // Blurred Background Image
                                    Image {
                                        id: bgImage
                                        anchors.fill: parent
                                        anchors.margins: -20
                                        source: statsHandler && currentSong ? statsHandler.getThumbnailPathForDifficulty(currentSong.arcaeaId || "", currentSong.thumbnailDifficulty !== undefined ? currentSong.thumbnailDifficulty : currentSong.difficulty) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        antialiasing: true
                                        visible: status === Image.Ready
                                        
                                        layer.enabled: visible
                                        layer.effect: MultiEffect {
                                            blurEnabled: true
                                            blur: 0.6
                                            saturation: 0.8
                                        }
                                    }

                                    // Dimming Overlay
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "black"
                                        opacity: 0.5
                                    }
                                }
                            }
                            
                            RowLayout {
                                anchors.fill: parent; anchors.margins: isNarrow ? 15 : 24; spacing: isNarrow ? 15 : 24
                                
                                // Thumbnail with real image + Custom Colored Shadow
                                Item {
                                    Layout.preferredWidth: isNarrow ? 120 : 152
                                    Layout.preferredHeight: isNarrow ? 120 : 152
                                    
                                    // 1. Shadow Layer (Behind) - Implemented as a blurred glowing rectangle
                                    Item {
                                        id: shadowContainer
                                        width: mainThumbRect.width + 20
                                        height: mainThumbRect.height + 20
                                        anchors.centerIn: mainThumbRect
                                        anchors.verticalCenterOffset: 6
                                        
                                        // Properties for efficient shadow updates
                                        property var arcaeaId: statsHandler && currentSong ? (currentSong.arcaeaId || "") : ""
                                        property int diff: statsHandler && currentSong ? (currentSong.thumbnailDifficulty !== undefined ? currentSong.thumbnailDifficulty : currentSong.difficulty) : 0
                                        property string shadowColorString: statsHandler ? statsHandler.getThumbnailColor(arcaeaId, diff) : "#FFFFFF"
                                        property color shadowColor: shadowColorString
                                        
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            blurEnabled: true
                                            blur: 1.0
                                            blurMax: 48 // Very high blur for wide dispersion
                                            saturation: 0.1
                                            brightness: 0.1
                                        }
                                        
                                        Rectangle {
                                            anchors.fill: parent
                                            color: parent.shadowColor
                                            radius: 4
                                            opacity: 0.35 // Very soft opacity
                                        }
                                    }

                                    // 2. Main Thumbnail (Foreground)
                                    Rectangle {
                                        id: mainThumbRect
                                        anchors.fill: parent
                                        radius: 15
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

                            Text {
                                text: {
                                    if (!currentSong) return ""
                                    var count = currentSong.songTotalPlayCount
                                    if (!count || count <= 0) return "Never played"
                                    return count + " plays"
                                }
                                color: "#CCC"
                                font.pixelSize: 13
                                font.bold: true
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: isNarrow ? 15 : 24
                            }
                        }

                        // [Body] 난이도 카드 섹션
                        ColumnLayout {
                            Layout.fillWidth: true
                            anchors.margins: isNarrow ? 20 : 40
                            Layout.margins: isNarrow ? 20 : 40
                            spacing: 30
                            
                            visible: currentSong !== null

                            // [난이도 패널] SwipeView vs RowLayout
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: (isNarrow || isDiffCramped) ? 360 : 330
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
                                                playCount: modelData.totalPlayCount || 0
                                                lastPlayedDate: modelData.lastPlayedDate || "-"
                                                bp: modelData.bp || 0
                                                shinyBp: modelData.s_bp || 0
                                                perceivedBp: modelData.perceived_bp || 0
                                                hasScore: modelData.hasScore || false
                                                isSelected: statisticsHandler && modelData.difficulty === statisticsHandler.selectedDifficulty
                                                isFiltered: modelData.isFiltered || false
                                                
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
                                    id: desktopRow
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
                                            playCount: modelData.totalPlayCount || 0
                                            lastPlayedDate: modelData.lastPlayedDate || "-"
                                            bp: modelData.bp || 0
                                            shinyBp: modelData.s_bp || 0
                                            perceivedBp: modelData.perceived_bp || 0
                                            hasScore: modelData.hasScore || false
                                            isSelected: statisticsHandler && modelData.difficulty === statisticsHandler.selectedDifficulty
                                            isFiltered: modelData.isFiltered || false
                                            
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
        
        // X Close Button (positioned at top-right corner)
        Rectangle {
            id: closeButton
            width: 40; height: 40; radius: 20
            color: closeButtonMouse.containsMouse ? "#F0F0F0" : "#E8E8E8"
            z: 100  // Above all content
            
            // Position so the center is at the popup's top-right corner
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -32  // to center on corner
            anchors.topMargin: -32    // to center on corner
            
            Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 18
                color: "#666"
            }
            
            MouseArea {
                id: closeButtonMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: filterPopup.close()
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
                    text: "↺"
                    font.pixelSize: 26
                    font.bold: true
                    color: "#6A0DAD"
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
                            
                            // Reset Level/BP Range Slider
                            rangeSlider.bpMode = false
                            rangeSlider.handleAIndex = 0
                            rangeSlider.handleBIndex = rangeSlider.currentList.length > 0 ? rangeSlider.currentList.length - 1 : 0
                            filterPopup.updateRangeFilter()  // Apply the reset to backend
                            
                            // Reset Score Range Slider
                            scoreRangeSlider.handleAIndex = 0
                            scoreRangeSlider.handleBIndex = scoreRangeSlider.scoreGrades.length > 0 ? scoreRangeSlider.scoreGrades.length - 1 : 0
                            filterPopup.updateScoreRangeFilter()  // Apply the reset to backend
                            
                            ignoreFlagSegment.selectedIndex = 1 // Show
                            skillFlagSegment.selectedIndex = 1 // Show
                            slowFlagSegment.selectedIndex = 1 // Show
                            
                            clearType0.checked = true
                            clearType1.checked = true
                            clearType2.checked = true
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
                        
                        RowLayout {
                            spacing: 20
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            
                            DiffFilterCheckbox {
                                id: pstCheck
                                text: "PST"
                                diffColor: "#00A0E9"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: prsCheck
                                text: "PRS"
                                diffColor: "#50C050"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: ftrCheck
                                text: "FTR"
                                diffColor: "#A060FF"
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: etrCheck
                                text: "ETR"
                                diffColor: "#808080"  // Gray for ETR
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: bydCheck
                                text: "BYD"
                                diffColor: "#E04040"
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
                            
                            Text { text: rangeSlider.bpMode ? "BP Range" : "Level Range"; font.pixelSize: 14; font.bold: true; color: "#333" }
                            
                            Item { Layout.fillWidth: true }
                            
                            // Level/BP Toggle (Text Only Style)
                            Row {
                                spacing: 15
                                
                                // Level Item
                                MouseArea {
                                    width: levelRow.width; height: 24
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rangeSlider.setBpMode(false)
                                    
                                    Row {
                                        id: levelRow
                                        spacing: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        
                                        Text {
                                            text: "Level"
                                            font.pixelSize: 13
                                            font.bold: !rangeSlider.bpMode
                                            color: !rangeSlider.bpMode ? "#6A0DAD" : "#9E9E9E"
                                        }
                                    }
                                }
                                
                                // BP Item
                                MouseArea {
                                    width: bpRow.width; height: 24
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rangeSlider.setBpMode(true)
                                    
                                    Row {
                                        id: bpRow
                                        spacing: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        
                                        Text {
                                            text: "BP"
                                            font.pixelSize: 13
                                            font.bold: rangeSlider.bpMode
                                            color: rangeSlider.bpMode ? "#6A0DAD" : "#9E9E9E"
                                        }
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
                            
                            // Color utility functions for position-based handle colors
                            // Difficulty colors: PST=#00A0E9, PRS=#50C050, FTR=#A060FF, BYD=#E04040
                            // Map: Level 1 (BP 1.0) = PST, Level 5 (BP 5.0) = PRS, Level 8 (BP 8.0) = FTR, Level 12 (BP 12.0) = BYD
                            
                            function getLevelValue(idx) {
                                if (currentList.length <= 1 || idx < 0) return 1
                                var val = currentList[idx]
                                if (bpMode) {
                                    return typeof val === 'number' ? val : 1.0
                                } else {
                                    // Level mode: parse level string (e.g., "9", "9+", "10")
                                    if (typeof val === 'string') {
                                        var numStr = val.replace('+', '')
                                        var num = parseFloat(numStr)
                                        // Add 0.5 for "+" levels
                                        if (val.indexOf('+') >= 0) num += 0.5
                                        return isNaN(num) ? 1 : num
                                    }
                                    return typeof val === 'number' ? val : 1
                                }
                            }
                            
                            function getColorForLevel(level) {
                                // Key color points with smooth interpolation:
                                // Level 1: PST blue
                                // Level 5: PRS green (pure)
                                // Level 7: Dark PRS (darker green)
                                // Level 8: Light FTR (lighter purple)
                                // Level 10: FTR purple (pure)
                                // Level 12: BYD red
                                
                                var pst = {r: 0x00, g: 0xA0, b: 0xE9}       // Level 1
                                var prs = {r: 0x50, g: 0xC0, b: 0x50}       // Level 5
                                var prsDark = {r: 0x40, g: 0x9A, b: 0x40}   // Level 7 (darker PRS)
                                var ftrLight = {r: 0xB8, g: 0x88, b: 0xFF}  // Level 8 (lighter FTR)
                                var ftr = {r: 0xA0, g: 0x60, b: 0xFF}       // Level 10
                                var byd = {r: 0xE0, g: 0x40, b: 0x40}       // Level 12
                                
                                var r, g, b, t
                                
                                if (level <= 1) {
                                    return "#00A0E9"  // PST
                                } else if (level <= 5) {
                                    // PST -> PRS gradient (Level 1-5)
                                    t = (level - 1) / 4
                                    r = Math.round(pst.r + (prs.r - pst.r) * t)
                                    g = Math.round(pst.g + (prs.g - pst.g) * t)
                                    b = Math.round(pst.b + (prs.b - pst.b) * t)
                                } else if (level <= 7) {
                                    // PRS -> Dark PRS gradient (Level 5-7)
                                    t = (level - 5) / 2
                                    r = Math.round(prs.r + (prsDark.r - prs.r) * t)
                                    g = Math.round(prs.g + (prsDark.g - prs.g) * t)
                                    b = Math.round(prs.b + (prsDark.b - prs.b) * t)
                                } else if (level <= 8) {
                                    // Dark PRS -> Light FTR gradient (Level 7-8)
                                    t = (level - 7) / 1
                                    r = Math.round(prsDark.r + (ftrLight.r - prsDark.r) * t)
                                    g = Math.round(prsDark.g + (ftrLight.g - prsDark.g) * t)
                                    b = Math.round(prsDark.b + (ftrLight.b - prsDark.b) * t)
                                } else if (level <= 10) {
                                    // Light FTR -> FTR gradient (Level 8-10)
                                    t = (level - 8) / 2
                                    r = Math.round(ftrLight.r + (ftr.r - ftrLight.r) * t)
                                    g = Math.round(ftrLight.g + (ftr.g - ftrLight.g) * t)
                                    b = Math.round(ftrLight.b + (ftr.b - ftrLight.b) * t)
                                } else if (level <= 12) {
                                    // FTR -> BYD gradient (Level 10-12)
                                    t = (level - 10) / 2
                                    r = Math.round(ftr.r + (byd.r - ftr.r) * t)
                                    g = Math.round(ftr.g + (byd.g - ftr.g) * t)
                                    b = Math.round(ftr.b + (byd.b - ftr.b) * t)
                                } else {
                                    return "#E04040"  // BYD
                                }
                                
                                return "#" + r.toString(16).padStart(2, '0') + g.toString(16).padStart(2, '0') + b.toString(16).padStart(2, '0')
                            }
                            
                            // Track with gradient
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
                                
                                // Active region with canvas-based gradient
                                Item {
                                    id: activeRegion
                                    // Position aligned with handle centers (handles are 20px wide, offset by 10)
                                    property real handleWidth: 20
                                    property real trackUsableWidth: parent.width - handleWidth
                                    property real minPos: rangeSlider.currentList.length > 1 ? 
                                        (handleWidth / 2) + (rangeSlider.minIndex / (rangeSlider.currentList.length - 1)) * trackUsableWidth : 0
                                    property real maxPos: rangeSlider.currentList.length > 1 ? 
                                        (handleWidth / 2) + (rangeSlider.maxIndex / (rangeSlider.currentList.length - 1)) * trackUsableWidth : parent.width
                                    
                                    x: minPos
                                    width: maxPos - minPos
                                    height: parent.height
                                    clip: true
                                    
                                    Canvas {
                                        id: gradientCanvas
                                        // Position canvas to align with handle centers
                                        property real handleWidth: 20
                                        property real trackUsableWidth: track.width - handleWidth
                                        
                                        x: (handleWidth / 2) - activeRegion.x
                                        width: trackUsableWidth
                                        height: parent.height
                                        
                                        // Trigger repaint when data changes
                                        property var dataList: rangeSlider.currentList
                                        property bool isBpMode: rangeSlider.bpMode
                                        onDataListChanged: requestPaint()
                                        onIsBpModeChanged: requestPaint()
                                        onWidthChanged: requestPaint()
                                        
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            
                                            var n = rangeSlider.currentList.length
                                            if (n <= 1) {
                                                // Single item: fill entire width with its color
                                                var singleColor = rangeSlider.getColorForLevel(rangeSlider.getLevelValue(0))
                                                ctx.fillStyle = singleColor
                                                ctx.beginPath()
                                                ctx.roundedRect(0, 0, width, height, 3)
                                                ctx.fill()
                                                return
                                            }
                                            
                                            // Draw gradient segments between each pair of indices
                                            for (var i = 0; i < n - 1; i++) {
                                                var x0 = (i / (n - 1)) * width
                                                var x1 = ((i + 1) / (n - 1)) * width
                                                
                                                var level0 = rangeSlider.getLevelValue(i)
                                                var level1 = rangeSlider.getLevelValue(i + 1)
                                                var color0 = rangeSlider.getColorForLevel(level0)
                                                var color1 = rangeSlider.getColorForLevel(level1)
                                                
                                                // Create linear gradient for this segment
                                                var grad = ctx.createLinearGradient(x0, 0, x1, 0)
                                                grad.addColorStop(0, color0)
                                                grad.addColorStop(1, color1)
                                                
                                                ctx.fillStyle = grad
                                                ctx.fillRect(x0, 0, x1 - x0 + 1, height)  // +1 to avoid gaps
                                            }
                                            
                                            // Round the corners by clipping
                                            ctx.globalCompositeOperation = "destination-in"
                                            ctx.fillStyle = "black"
                                            ctx.beginPath()
                                            ctx.roundedRect(0, 0, width, height, 3)
                                            ctx.fill()
                                        }
                                    }
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
                                property string baseColor: rangeSlider.getColorForLevel(rangeSlider.getLevelValue(rangeSlider.handleAIndex))
                                color: handleAMouse.pressed ? Qt.darker(baseColor, 1.15) : baseColor
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
                                property string baseColor: rangeSlider.getColorForLevel(rangeSlider.getLevelValue(rangeSlider.handleBIndex))
                                color: handleBMouse.pressed ? Qt.darker(baseColor, 1.15) : baseColor
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
                    
                    // Score Range Filter
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Score Range"; font.pixelSize: 14; font.bold: true; color: "#333" }
                        
                        // Score Range Slider
                        Item {
                            id: scoreRangeSlider
                            width: parent.width
                            height: 60
                            
                            // Score grades: -, D, C, B, A, AA, EX, EX+, 99.5%, 99.8%, PM
                            property var scoreGrades: statisticsHandler ? statisticsHandler.scoreRanks : ["-", "D", "C", "B", "A", "AA", "EX", "EX+", "99.5%", "99.8%", "PM"]
                            
                            // Independent handle indices
                            property int handleAIndex: 0
                            property int handleBIndex: scoreGrades.length > 0 ? scoreGrades.length - 1 : 0
                            
                            // Computed min/max based on handle values
                            property int minIndex: Math.min(handleAIndex, handleBIndex)
                            property int maxIndex: Math.max(handleAIndex, handleBIndex)
                            
                            function getDisplayValue(idx) {
                                if (idx >= 0 && idx < scoreGrades.length) {
                                    return scoreGrades[idx]
                                }
                                return ""
                            }
                            
                            // Color mapping for Score Range gradient
                            // D (0/10) = burgundy #80354A
                            // A (4/10) = brighter purple #9B6BB5
                            // EX (6/10) = brighter blue-gray #6A8CAA
                            // PM (10/10) = brighter teal #4AA8A8
                            function getColorForScoreIndex(idx) {
                                if (scoreGrades.length <= 1) return "#80354A"
                                
                                var ratio = idx / (scoreGrades.length - 1)  // 0.0 to 1.0
                                
                                // Key color points (positions on 0-1 scale)
                                // D at 0 (idx 1, but we start from 0)
                                // A at 0.4 (idx 4)
                                // EX at 0.6 (idx 6)
                                // PM at 1.0 (idx 10)
                                var dColor = {r: 0x80, g: 0x35, b: 0x4A}      // D - burgundy
                                var aColor = {r: 0x9B, g: 0x6B, b: 0xB5}      // A - brighter purple
                                var exColor = {r: 0x6A, g: 0x8C, b: 0xAA}     // EX - brighter blue-gray
                                var pmColor = {r: 0x4A, g: 0xA8, b: 0xA8}     // PM - brighter teal
                                
                                var r, g, b, t
                                
                                if (ratio <= 0.4) {
                                    // D -> A gradient (0 to 0.4)
                                    t = ratio / 0.4
                                    r = Math.round(dColor.r + (aColor.r - dColor.r) * t)
                                    g = Math.round(dColor.g + (aColor.g - dColor.g) * t)
                                    b = Math.round(dColor.b + (aColor.b - dColor.b) * t)
                                } else if (ratio <= 0.6) {
                                    // A -> EX gradient (0.4 to 0.6)
                                    t = (ratio - 0.4) / 0.2
                                    r = Math.round(aColor.r + (exColor.r - aColor.r) * t)
                                    g = Math.round(aColor.g + (exColor.g - aColor.g) * t)
                                    b = Math.round(aColor.b + (exColor.b - aColor.b) * t)
                                } else {
                                    // EX -> PM gradient (0.6 to 1.0)
                                    t = (ratio - 0.6) / 0.4
                                    r = Math.round(exColor.r + (pmColor.r - exColor.r) * t)
                                    g = Math.round(exColor.g + (pmColor.g - exColor.g) * t)
                                    b = Math.round(exColor.b + (pmColor.b - exColor.b) * t)
                                }
                                
                                return "#" + r.toString(16).padStart(2, '0') + g.toString(16).padStart(2, '0') + b.toString(16).padStart(2, '0')
                            }
                            
                            // Track with gradient
                            Rectangle {
                                id: scoreTrack
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -10
                                height: 6; radius: 3
                                color: "#E0E0E0"
                                
                                // Tick marks for each grade
                                Repeater {
                                    model: scoreRangeSlider.scoreGrades.length
                                    
                                    Rectangle {
                                        x: scoreRangeSlider.scoreGrades.length > 1 ? 
                                            10 + (index / (scoreRangeSlider.scoreGrades.length - 1)) * (parent.width - 20) - 1 : 0
                                        y: -3
                                        width: 2; height: 12
                                        radius: 1
                                        color: "#C0C0C0"
                                    }
                                }
                                
                                // Active region with canvas-based gradient
                                Item {
                                    id: scoreActiveRegion
                                    property real handleWidth: 20
                                    property real trackUsableWidth: parent.width - handleWidth
                                    property real minPos: scoreRangeSlider.scoreGrades.length > 1 ? 
                                        (handleWidth / 2) + (scoreRangeSlider.minIndex / (scoreRangeSlider.scoreGrades.length - 1)) * trackUsableWidth : 0
                                    property real maxPos: scoreRangeSlider.scoreGrades.length > 1 ? 
                                        (handleWidth / 2) + (scoreRangeSlider.maxIndex / (scoreRangeSlider.scoreGrades.length - 1)) * trackUsableWidth : parent.width
                                    
                                    x: minPos
                                    width: maxPos - minPos
                                    height: parent.height
                                    clip: true
                                    
                                    Canvas {
                                        id: scoreGradientCanvas
                                        property real handleWidth: 20
                                        property real trackUsableWidth: scoreTrack.width - handleWidth
                                        
                                        x: (handleWidth / 2) - scoreActiveRegion.x
                                        width: trackUsableWidth
                                        height: parent.height
                                        
                                        property var dataList: scoreRangeSlider.scoreGrades
                                        onDataListChanged: requestPaint()
                                        onWidthChanged: requestPaint()
                                        
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            
                                            var n = scoreRangeSlider.scoreGrades.length
                                            if (n <= 1) {
                                                var singleColor = scoreRangeSlider.getColorForScoreIndex(0)
                                                ctx.fillStyle = singleColor
                                                ctx.beginPath()
                                                ctx.roundedRect(0, 0, width, height, 3)
                                                ctx.fill()
                                                return
                                            }
                                            
                                            // Draw gradient segments
                                            for (var i = 0; i < n - 1; i++) {
                                                var x0 = (i / (n - 1)) * width
                                                var x1 = ((i + 1) / (n - 1)) * width
                                                
                                                var color0 = scoreRangeSlider.getColorForScoreIndex(i)
                                                var color1 = scoreRangeSlider.getColorForScoreIndex(i + 1)
                                                
                                                var grad = ctx.createLinearGradient(x0, 0, x1, 0)
                                                grad.addColorStop(0, color0)
                                                grad.addColorStop(1, color1)
                                                
                                                ctx.fillStyle = grad
                                                ctx.fillRect(x0, 0, x1 - x0 + 1, height)
                                            }
                                            
                                            // Round corners
                                            ctx.globalCompositeOperation = "destination-in"
                                            ctx.fillStyle = "black"
                                            ctx.beginPath()
                                            ctx.roundedRect(0, 0, width, height, 3)
                                            ctx.fill()
                                        }
                                    }
                                }
                            }
                            
                            // Handle A
                            Rectangle {
                                id: scoreHandleA
                                width: 20; height: 20; radius: 10
                                property string baseColor: scoreRangeSlider.getColorForScoreIndex(scoreRangeSlider.handleAIndex)
                                color: scoreHandleAMouse.pressed ? Qt.darker(baseColor, 1.15) : baseColor
                                border.color: "white"; border.width: 2
                                x: scoreRangeSlider.scoreGrades.length > 1 ? 
                                    (scoreRangeSlider.handleAIndex / (scoreRangeSlider.scoreGrades.length - 1)) * (scoreTrack.width - width) : 0
                                anchors.verticalCenter: scoreTrack.verticalCenter
                                
                                Text {
                                    id: scoreHandleALabel
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    property bool tooClose: Math.abs(scoreHandleA.x - scoreHandleB.x) < 25
                                    property bool isRightHandle: scoreHandleA.x > scoreHandleB.x
                                    property bool showAbove: tooClose && isRightHandle
                                    y: showAbove ? -height - 4 : parent.height + 4
                                    text: scoreRangeSlider.getDisplayValue(scoreRangeSlider.handleAIndex)
                                    font.pixelSize: 10; font.bold: true; color: "#333"
                                }
                                
                                MouseArea {
                                    id: scoreHandleAMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -20; anchors.bottomMargin: -20
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    property int startIndex: 0
                                    property real pressGlobalX: 0
                                    
                                    onPressed: (mouse) => {
                                        startIndex = scoreRangeSlider.handleAIndex
                                        var mapped = mapToItem(scoreTrack, mouse.x, mouse.y)
                                        pressGlobalX = mapped.x
                                    }
                                    
                                    onPositionChanged: (mouse) => {
                                        if (pressed && scoreRangeSlider.scoreGrades.length > 1) {
                                            var mapped = mapToItem(scoreTrack, mouse.x, mouse.y)
                                            var deltaX = mapped.x - pressGlobalX
                                            
                                            var stepWidth = (scoreTrack.width - parent.width) / (scoreRangeSlider.scoreGrades.length - 1)
                                            var indexDelta = Math.round(deltaX / stepWidth)
                                            
                                            var newIdx = Math.max(0, Math.min(startIndex + indexDelta, scoreRangeSlider.scoreGrades.length - 1))
                                            scoreRangeSlider.handleAIndex = newIdx
                                        }
                                    }
                                    
                                    onReleased: {
                                        filterPopup.updateScoreRangeFilter()
                                    }
                                }
                            }
                            
                            // Handle B
                            Rectangle {
                                id: scoreHandleB
                                width: 20; height: 20; radius: 10
                                property string baseColor: scoreRangeSlider.getColorForScoreIndex(scoreRangeSlider.handleBIndex)
                                color: scoreHandleBMouse.pressed ? Qt.darker(baseColor, 1.15) : baseColor
                                border.color: "white"; border.width: 2
                                x: scoreRangeSlider.scoreGrades.length > 1 ? 
                                    (scoreRangeSlider.handleBIndex / (scoreRangeSlider.scoreGrades.length - 1)) * (scoreTrack.width - width) : scoreTrack.width - width
                                anchors.verticalCenter: scoreTrack.verticalCenter
                                
                                Text {
                                    id: scoreHandleBLabel
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    property bool tooClose: Math.abs(scoreHandleA.x - scoreHandleB.x) < 30
                                    property bool isRightHandle: scoreHandleB.x > scoreHandleA.x
                                    property bool showAbove: tooClose && isRightHandle
                                    y: showAbove ? -height - 4 : parent.height + 4
                                    text: scoreRangeSlider.getDisplayValue(scoreRangeSlider.handleBIndex)
                                    font.pixelSize: 10; font.bold: true; color: "#333"
                                }
                                
                                MouseArea {
                                    id: scoreHandleBMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -20; anchors.bottomMargin: -20
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    property int startIndex: 0
                                    property real pressGlobalX: 0
                                    
                                    onPressed: (mouse) => {
                                        startIndex = scoreRangeSlider.handleBIndex
                                        var mapped = mapToItem(scoreTrack, mouse.x, mouse.y)
                                        pressGlobalX = mapped.x
                                    }
                                    
                                    onPositionChanged: (mouse) => {
                                        if (pressed && scoreRangeSlider.scoreGrades.length > 1) {
                                            var mapped = mapToItem(scoreTrack, mouse.x, mouse.y)
                                            var deltaX = mapped.x - pressGlobalX
                                            
                                            var stepWidth = (scoreTrack.width - parent.width) / (scoreRangeSlider.scoreGrades.length - 1)
                                            var indexDelta = Math.round(deltaX / stepWidth)
                                            
                                            var newIdx = Math.max(0, Math.min(startIndex + indexDelta, scoreRangeSlider.scoreGrades.length - 1))
                                            scoreRangeSlider.handleBIndex = newIdx
                                        }
                                    }
                                    
                                    onReleased: {
                                        filterPopup.updateScoreRangeFilter()
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
            if (clearType4.checked) types.push(4)
            if (clearType5.checked) types.push(5)
            
            if (statisticsHandler) {
                statisticsHandler.setFilter("clear_types", types)
            }
        }
        
        function updateScoreRangeFilter() {
            if (!initialized) return
            
            if (statisticsHandler && scoreRangeSlider.scoreGrades.length > 0) {
                statisticsHandler.setFilter("score_min_rank", scoreRangeSlider.minIndex)
                statisticsHandler.setFilter("score_max_rank", scoreRangeSlider.maxIndex)
            }
        }
    }
}