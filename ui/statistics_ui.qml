import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Basic as Basic
import QtQuick.Window
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
    property var currentSong: statisticsHandler ? statisticsHandler.getSelectedItem() : null
    property int currentSongIndex: statisticsHandler ? statisticsHandler.selectedIndex : -1
    property string searchText: ""  // Search text managed at root level
    property bool suppressResponsivePopAnimation: false
    property int bestPotentialMarkLimit: {
        if (!settingsHandler) return 0
        var v = settingsHandler.getBestPotentialMark()
        if (v === "none") return 0
        if (v === "all") return 999999
        return parseInt(v) || 0
    }
    readonly property var appWindow: ApplicationWindow.window
    readonly property string titleFontFamily: (appWindow && appWindow.titleFontFamily)
        ? appWindow.titleFontFamily
        : (appWindow ? appWindow.font.family : "")

    onIsNarrowChanged: {
        if (!isNarrow) {
            // 모바일 -> 데스크탑 반응형 전환 시에는 스택 정리를 즉시 수행해 pop 애니메이션 노출을 막습니다.
            suppressResponsivePopAnimation = true
            while (mobileStack.depth > 1) {
                mobileStack.pop()
            }
            Qt.callLater(function() {
                suppressResponsivePopAnimation = false
            })
        }
    }
    
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
            statsRoot.currentSong = statisticsHandler.getSelectedItem()
        }
        function onSelectedItemChanged() {
            statsRoot.currentSong = statisticsHandler.getSelectedItem()
        }
    }

    Connections {
        target: settingsHandler
        function onBestPotentialMarkChanged() {
            var v = settingsHandler ? settingsHandler.getBestPotentialMark() : "none"
            if (v === "none") statsRoot.bestPotentialMarkLimit = 0
            else if (v === "all") statsRoot.bestPotentialMarkLimit = 999999
            else statsRoot.bestPotentialMarkLimit = parseInt(v) || 0
        }
    }

    // =========================================================================
    // [2] 메인 뷰 (Root View)
    // =========================================================================
    StackView {
        id: mobileStack
        anchors.fill: parent
        initialItem: mainContentComponent
        pushEnter: Transition { PropertyAnimation { property: "x"; from: mobileStack.width; to: 0; duration: 250; easing.type: Easing.OutQuad } }
        pushExit: Transition { PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 250 } }
        popEnter: Transition { PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: statsRoot.suppressResponsivePopAnimation ? 0 : 250 } }
        popExit: Transition { PropertyAnimation { property: "x"; from: 0; to: mobileStack.width; duration: statsRoot.suppressResponsivePopAnimation ? 0 : 250; easing.type: Easing.InQuad } }
    }

    // =========================================================================
    // [3] 메인 컨텐츠 컴포넌트
    // =========================================================================
    Component {
        id: mainContentComponent

        ScrollView {
            id: mainScroll // [1] 높이 참조를 위해 ID 부여
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
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
                        color: Theme.bgCard; radius: 20

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
                                color: Theme.scrollbar
                                opacity: listVerticalBar.pressed ? 1.0 : (listVerticalBar.hovered ? 1.0 : 0.6)
                            }
                        }
                        
                        ColumnLayout {
                            id: songListContentLayout
                            anchors.fill: parent; anchors.margins: 20; spacing: 12
                            
                            // Search Bar
                            Rectangle {
                                Layout.fillWidth: true; height: 40; radius: 10; color: Theme.bgInput
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10
                                    Text { text: "🔍"; color: Theme.textFaint }
                                    TextInput { 
                                        id: searchInput
                                        text: statsRoot.searchText
                                        color: Theme.textPrimary; font.pixelSize: 14
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
                                            color: Theme.textLight
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
                                    color: Theme.bgButton
                                    
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                        
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 6
                                            color: statisticsHandler && statisticsHandler.displayMode === "song" ? Theme.accent : (songMouse.containsMouse ? Theme.bgHover : "transparent")
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Song"
                                                font.pixelSize: 12
                                                font.bold: statisticsHandler && statisticsHandler.displayMode === "song"
                                                color: statisticsHandler && statisticsHandler.displayMode === "song" ? "white" : Theme.textSecondary
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
                                            color: statisticsHandler && statisticsHandler.displayMode === "chart" ? Theme.accent : (chartMouse.containsMouse ? Theme.bgHover : "transparent")
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Chart"
                                                font.pixelSize: 12
                                                font.bold: statisticsHandler && statisticsHandler.displayMode === "chart"
                                                color: statisticsHandler && statisticsHandler.displayMode === "chart" ? "white" : Theme.textSecondary
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
                                    color: filterMouse.containsMouse ? Theme.bgHover : Theme.bgButton
                                    
                                    Text { anchors.centerIn: parent; text: "Filters"; font.pixelSize: 12; color: Theme.textSecondary; font.bold: true }
                                    
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
                                    model: ["Title", "Score", "Potential", "MAX", "Total Play", "This Year Play", "Recent", "Level (BP)", "S-BP", "P-BP", "Notes", "BPM", "Length"]

                                    property var sortModes: ["title", "score", "potential", "max", "total_play_count", "this_year_play_count", "recent_played", "level", "s_bp", "perceived_bp", "note_count", "bpm", "length"]
                                    
                                    onCurrentIndexChanged: {
                                        if (statisticsHandler && currentIndex >= 0) {
                                            statisticsHandler.setSortMode(sortModes[currentIndex])
                                        }
                                    }

                                    // Custom Styling
                                    background: Rectangle {
                                        color: parent.hovered ? Theme.bgHover : Theme.bgButton
                                        radius: 6
                                    }
                                    
                                    contentItem: Text {
                                        text: parent.displayText
                                        font.pixelSize: 12
                                        color: Theme.textSecondary
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        leftPadding: 10
                                        rightPadding: 20
                                    }
                                    
                                    indicator: Text {
                                        x: parent.width - width - 8
                                        y: (parent.height - height) / 2
                                        text: "▼"
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                    }

                                    delegate: ItemDelegate {
                                        width: sortCombo.width
                                        height: 32 // Fixed height for consistency
                                        
                                        contentItem: Text {
                                            text: modelData
                                            color: Theme.textPrimary
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
                                            color: parent.hovered || parent.highlighted ? Theme.bgSelected : "transparent" // Soft purple tint
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
                                            color: Theme.bgCard
                                            border.color: Theme.borderCard
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
                                    color: sortOrderMouse.containsMouse ? Theme.bgHover : Theme.bgButton
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: statisticsHandler && statisticsHandler.sortAscending ? "↑" : "↓"
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: Theme.accent
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
                            
                            // Item count and Active Filters
                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: songListView.count + " items"
                                    font.pixelSize: 11
                                    color: Theme.textLight
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Item { Layout.fillWidth: true }

                                Row {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 6

                                    Repeater {
                                        model: statisticsHandler ? statisticsHandler.activeFiltersModel : null

                                        Row {
                                            spacing: 6
                                            
                                            Text {
                                                text: "/"
                                                font.pixelSize: 11
                                                color: Theme.textLight
                                                visible: index > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            
                                            Loader {
                                                anchors.verticalCenter: parent.verticalCenter
                                                property var filterData: modelData
                                                sourceComponent: {
                                                    if (!modelData) return null;
                                                    switch(modelData.type) {
                                                        case "difficulties": return diffComp;
                                                        case "level": return levelComp;
                                                        case "bp": return bpComp;
                                                        case "score": return scoreComp;
                                                        case "clear": return clearComp;
                                                        case "flags": return flagsComp;
                                                        default: return null;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Formatting Components for Filters
                            Component {
                                id: diffComp
                                Row {
                                    spacing: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: filterData ? filterData.data : []
                                        Text {
                                            text: modelData.active ? "◆" : "◇"
                                            color: Theme.getDiffColor(modelData.diff)
                                            font.pixelSize: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }

                            Component {
                                id: levelComp
                                Text {
                                    textFormat: Text.StyledText
                                    font.pixelSize: 11
                                    font.bold: true
                                    text: {
                                        if (!filterData) return "";
                                        function getLevelVal(lstr) {
                                            var str = String(lstr);
                                            if (str.indexOf("⁺") !== -1 || str.indexOf("+") !== -1) return parseFloat(str) + 0.5;
                                            return parseFloat(str);
                                        }
                                        var cMin = rangeSlider.getColorForLevel(getLevelVal(filterData.min))
                                        if (filterData.min === filterData.max) {
                                            return "<font color='" + cMin + "'>" + filterData.min + "</font>"
                                        }
                                        var cMax = rangeSlider.getColorForLevel(getLevelVal(filterData.max))
                                        return "<font color='" + cMin + "'>" + filterData.min + "</font>" +
                                               "<font color='" + Theme.textLight + "'>-</font>" +
                                               "<font color='" + cMax + "'>" + filterData.max + "</font>"
                                    }
                                }
                            }

                            Component {
                                id: bpComp
                                Text {
                                    textFormat: Text.StyledText
                                    font.pixelSize: 11
                                    font.bold: true
                                    text: {
                                        if (!filterData) return "";
                                        var cMin = rangeSlider.getColorForLevel(parseFloat(filterData.min))
                                        var minStr = Number(filterData.min).toFixed(1)
                                        var maxStr = Number(filterData.max).toFixed(1)
                                        if (minStr === maxStr || Math.abs(Number(filterData.min) - Number(filterData.max)) < 1e-4) {
                                            return "<font color='" + cMin + "'>" + minStr + "</font>"
                                        }
                                        var cMax = rangeSlider.getColorForLevel(parseFloat(filterData.max))
                                        return "<font color='" + cMin + "'>" + minStr + "</font>" +
                                               "<font color='" + Theme.textLight + "'>-</font>" +
                                               "<font color='" + cMax + "'>" + maxStr + "</font>"
                                    }
                                }
                            }

                            Component {
                                id: scoreComp
                                Text {
                                    textFormat: Text.StyledText
                                    font.pixelSize: 11
                                    font.bold: true
                                    text: {
                                        if (!filterData) return "";
                                        var cMin = scoreRangeSlider.getColorForScoreIndex(filterData.minIdx)
                                        if (filterData.minIdx === filterData.maxIdx || filterData.minStr === filterData.maxStr) {
                                            return "<font color='" + cMin + "'>" + filterData.minStr + "</font>"
                                        }
                                        var cMax = scoreRangeSlider.getColorForScoreIndex(filterData.maxIdx)
                                        return "<font color='" + cMin + "'>" + filterData.minStr + "</font>" +
                                               "<font color='" + Theme.textLight + "'>-</font>" +
                                               "<font color='" + cMax + "'>" + filterData.maxStr + "</font>"
                                    }
                                }
                            }

                            Component {
                                id: clearComp
                                Text {
                                    textFormat: Text.StyledText
                                    font.pixelSize: 11
                                    font.bold: true
                                    text: {
                                        if (!filterData) return "";
                                        var cMin = clearRangeSlider.getColorForIndex(filterData.minIdx)
                                        if (filterData.isSingle || filterData.minIdx === filterData.maxIdx || filterData.minStr === filterData.maxStr) {
                                            return "<font color='" + cMin + "'>" + filterData.minStr + "</font>"
                                        }
                                        var cMax = clearRangeSlider.getColorForIndex(filterData.maxIdx)
                                        return "<font color='" + cMin + "'>" + filterData.minStr + "</font>" +
                                               "<font color='" + Theme.textLight + "'>-</font>" +
                                               "<font color='" + cMax + "'>" + filterData.maxStr + "</font>"
                                    }
                                }
                            }

                            Component {
                                id: flagsComp
                                Row {
                                    spacing: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: filterData ? filterData.data : []
                                        Text {
                                            text: modelData.icon
                                            font.pixelSize: 10
                                            opacity: modelData.state === "off" ? 0.3 : 1.0
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
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
                                    model: statisticsHandler ? statisticsHandler.listModel : null
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
                                        color: (!isNarrow && index === currentSongIndex) ? Theme.bgSelected : (delegateMouse.containsMouse ? Theme.bgItemHover : "transparent")
                                        radius: 10
                                        border.width: (!isNarrow && index === currentSongIndex) ? 1 : 0
                                        border.color: Theme.borderSelected
                                        property var rowModel: model
                                        
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
                                                color: Theme.textMuted
                                                Layout.preferredWidth: 22
                                                horizontalAlignment: Text.AlignRight
                                            }
                                            
                                            // Thumbnail (uses real image with fallback to colored rectangle)
                                            Rectangle { 
                                                id: thumbRect
                                                width: 48; height: 48; radius: 6
                                                color: Theme.getDiffColor(rowModel.thumbnailDifficulty !== undefined ? rowModel.thumbnailDifficulty : rowModel.difficulty)
                                                clip: true
                                                
                                                Image {
                                                    id: thumbImage
                                                    anchors.fill: parent
                                                    anchors.margins: -1 // Slight negative margin to avoid edge artifacts
                                                    source: statsHandler ? statsHandler.getThumbnailPathForDifficulty(rowModel.arcaeaId || "", rowModel.thumbnailDifficulty !== undefined ? rowModel.thumbnailDifficulty : rowModel.difficulty) : ""
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
                                                    text: rowModel.difficultyName || ""
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    color: Theme.bgCard
                                                    visible: thumbImage.status !== Image.Ready
                                                }
                                            }
                                            
                                            Column {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text { 
                                                    text: rowModel.title || ""
                                                    font.family: statsRoot.titleFontFamily
                                                    font.bold: true
                                                    color: Theme.textPrimary
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                                Text { 
                                                    text: rowModel.artist || ""
                                                    font.family: statsRoot.titleFontFamily
                                                    font.pixelSize: 11
                                                    color: Theme.textMuted
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
                                                    text: rowModel.displayValue || ""
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                    color: Theme.listValue
                                                    visible: !parent.isStandaloneMode && rowModel.displayValue && rowModel.displayValue !== ""
                                                }

                                                // Score of the highlighted difficulty (shown when not in score sort)
                                                Text {
                                                    id: highlightedScoreText
                                                    anchors.right: parent.right
                                                    property bool isLevelSort: statisticsHandler && statisticsHandler.sortMode === "level"
                                                    font.pixelSize: 11
                                                    font.bold: isLevelSort
                                                    color: Theme.listValue

                                                    property bool isSongMode: statisticsHandler && statisticsHandler.displayMode === "song"
                                                    property bool isChartMode: statisticsHandler && statisticsHandler.displayMode === "chart"

                                                    // Highlighted diff computed from rowModel directly (avoids forward ref to difficultyRow)
                                                    property int highlightedDiff: {
                                                        if (!statisticsHandler) return -1
                                                        var mode = statisticsHandler.sortMode
                                                        if (mode === "max") return rowModel.bestDiffForMax >= 0 ? rowModel.bestDiffForMax : -1
                                                        if (mode === "recent_played") return rowModel.bestDiffForRecent >= 0 ? rowModel.bestDiffForRecent : -1
                                                        if (mode === "level") return rowModel.bestDiffForLevel >= 0 ? rowModel.bestDiffForLevel : -1
                                                        if (mode === "s_bp") return rowModel.bestDiffForSBp >= 0 ? rowModel.bestDiffForSBp : -1
                                                        if (mode === "perceived_bp") return rowModel.bestDiffForPerceivedBp >= 0 ? rowModel.bestDiffForPerceivedBp : -1
                                                        if (mode === "potential") return rowModel.bestDiffForPotential >= 0 ? rowModel.bestDiffForPotential : -1
                                                        if (mode === "note_count") return rowModel.bestDiffForNoteCount >= 0 ? rowModel.bestDiffForNoteCount : -1
                                                        return -1
                                                    }

                                                    property int songModeScore: {
                                                        if (!isSongMode || highlightedDiff < 0) return 0
                                                        var diffs = rowModel.filteredDifficulties || []
                                                        for (var i = 0; i < diffs.length; i++) {
                                                            if (diffs[i].difficulty === highlightedDiff) return diffs[i].score || 0
                                                        }
                                                        return 0
                                                    }
                                                    property bool songModeHasScore: {
                                                        if (!isSongMode || highlightedDiff < 0) return false
                                                        var diffs = rowModel.filteredDifficulties || []
                                                        for (var i = 0; i < diffs.length; i++) {
                                                            if (diffs[i].difficulty === highlightedDiff) return diffs[i].hasScore || false
                                                        }
                                                        return false
                                                    }

                                                    text: {
                                                        if (isSongMode) return songModeHasScore ? songModeScore.toLocaleString(Qt.locale("en_US"), 'f', 0) : "-"
                                                        if (isChartMode) return rowModel.hasScore ? (rowModel.bestScore || 0).toLocaleString(Qt.locale("en_US"), 'f', 0) : "-"
                                                        return ""
                                                    }

                                                    visible: {
                                                        if (!statisticsHandler || statisticsHandler.sortMode === "score") return false
                                                        if (isSongMode) return highlightedDiff >= 0
                                                        return !!isChartMode
                                                    }
                                                }

                                                // Song mode: show all difficulty levels with colors
                                                // In standalone modes: main display (font 13), otherwise secondary info (font 11)
                                                // In specific sort modes, only highlight the "best" difficulty
                                                Row {
                                                    id: difficultyRow
                                                    anchors.right: parent.right
                                                    spacing: 0
                                                    visible: statisticsHandler && statisticsHandler.displayMode === "song" && rowModel.filteredDifficulties
                                                    
                                                    // Helper function to get the best difficulty for current sort mode
                                                    // Returns -1 for modes that should highlight all difficulties
                                                    function getBestDiffForSort() {
                                                        if (!statisticsHandler) return -1
                                                        var mode = statisticsHandler.sortMode
                                                        // Check if value is a valid difficulty (>=0), -1 means no data
                                                        if (mode === "score" && rowModel.bestDiffForScore >= 0) return rowModel.bestDiffForScore
                                                        if (mode === "max" && rowModel.bestDiffForMax >= 0) return rowModel.bestDiffForMax
                                                        if (mode === "recent_played" && rowModel.bestDiffForRecent >= 0) return rowModel.bestDiffForRecent
                                                        if (mode === "level" && rowModel.bestDiffForLevel >= 0) return rowModel.bestDiffForLevel
                                                        if (mode === "s_bp" && rowModel.bestDiffForSBp >= 0) return rowModel.bestDiffForSBp
                                                        if (mode === "perceived_bp" && rowModel.bestDiffForPerceivedBp >= 0) return rowModel.bestDiffForPerceivedBp
                                                        if (mode === "potential" && rowModel.bestDiffForPotential >= 0) return rowModel.bestDiffForPotential
                                                        if (mode === "note_count" && rowModel.bestDiffForNoteCount >= 0) return rowModel.bestDiffForNoteCount
                                                        return -1  // No highlighting for other modes (title, total_play_count, length)
                                                    }
                                                    
                                                    property int bestDiff: getBestDiffForSort()
                                                    property bool isStandaloneMode: statisticsHandler && (statisticsHandler.sortMode === "title" || statisticsHandler.sortMode === "level")
                                                    property bool isLevelSort: statisticsHandler && statisticsHandler.sortMode === "level"
                                                    
                                                    Repeater {
                                                        model: rowModel.filteredDifficulties || []
                                                        
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
                                                                color: Theme.textFaint
                                                                visible: index > 0
                                                            }
                                                            // Level with difficulty color (or gray if not highlighted)
                                                            Item {
                                                                width: levelText.width
                                                                height: levelText.height
                                                                Text {
                                                                    id: levelText
                                                                    text: String(modelData.level || "")
                                                                    font.bold: true
                                                                    font.pixelSize: difficultyRow.isStandaloneMode ? 13 : 11
                                                                    color: isHighlighted ? Theme.getDiffColor(modelData.difficulty) : Theme.textDimmed
                                                                }
                                                                // Floating badge overlay
                                                                Row {
                                                                    property bool isValueAbove: Boolean((highlightedScoreText && highlightedScoreText.visible) || (!difficultyRow.isStandaloneMode && rowModel.displayValue && rowModel.displayValue !== ""))
                                                                    property string lvlStr: String(modelData.level || "")
                                                                    z: 10
                                                                    spacing: -2
                                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                                    anchors.horizontalCenterOffset: (lvlStr === "10" || lvlStr === "11") ? 1 : 0
                                                                    anchors.top: isValueAbove ? parent.bottom : undefined
                                                                    anchors.bottom: isValueAbove ? undefined : parent.top
                                                                    anchors.topMargin: 0
                                                                    anchors.bottomMargin: isValueAbove ? 0 : -2
                                                                    visible: (modelData.ignoreChart || false) || (modelData.skillIssues || false) || (modelData.hardBpm || false)
                                                                    Text {
                                                                        text: "⛔"
                                                                        font.pixelSize: 6
                                                                        visible: modelData.ignoreChart || false
                                                                        opacity: isHighlighted ? 1.0 : 0.4
                                                                    }
                                                                    Text {
                                                                        text: "⚠️"
                                                                        font.pixelSize: 6
                                                                        visible: modelData.skillIssues || false
                                                                        opacity: isHighlighted ? 1.0 : 0.4
                                                                    }
                                                                    Text {
                                                                        text: "⏪"
                                                                        font.pixelSize: 6
                                                                        visible: modelData.hardBpm || false
                                                                        opacity: isHighlighted ? 1.0 : 0.4
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                    
                                                    // BP value in parentheses for level sort (song mode)
                                                    Text {
                                                        text: " (" + (rowModel.bp ? rowModel.bp.toFixed(1) : "0.0") + ")"
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: Theme.listValue
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
                                                    
                                                    // Difficulty name + level with floating badge
                                                    Item {
                                                        property bool isStandaloneMode: parent.isStandaloneMode
                                                        width: chartLevelRow.width
                                                        height: chartLevelRow.height
                                                        
                                                        Row {
                                                            id: chartLevelRow
                                                            spacing: 0
                                                            Text {
                                                                text: (rowModel.difficultyName ? rowModel.difficultyName + " " : "")
                                                                font.bold: true
                                                                font.pixelSize: parent.parent.isStandaloneMode ? 13 : 11
                                                                color: Theme.getDiffColor(rowModel.difficulty)
                                                            }
                                                            Text {
                                                                id: chartLevelNumText
                                                                text: String(rowModel.level || "")
                                                                font.bold: true
                                                                font.pixelSize: parent.parent.isStandaloneMode ? 13 : 11
                                                                color: Theme.getDiffColor(rowModel.difficulty)
                                                            }
                                                        }

                                                        // Floating badge overlay
                                                        Row {
                                                            property bool isValueAbove: Boolean((highlightedScoreText && highlightedScoreText.visible) || (!(statisticsHandler && (statisticsHandler.sortMode === "title" || statisticsHandler.sortMode === "level")) && rowModel.displayValue && rowModel.displayValue !== ""))
                                                            property string lvlStr: String(rowModel.level || "")
                                                            z: 10
                                                            spacing: -2
                                                            anchors.horizontalCenter: parent.left
                                                            anchors.horizontalCenterOffset: chartLevelRow.x + chartLevelNumText.x + chartLevelNumText.width / 2 + ((lvlStr === "10" || lvlStr === "11") ? 1 : 0)
                                                            anchors.top: isValueAbove ? parent.bottom : undefined
                                                            anchors.bottom: isValueAbove ? undefined : parent.top
                                                            anchors.topMargin: isValueAbove ? 2 : 0
                                                            anchors.bottomMargin: isValueAbove ? 0 : -2
                                                            visible: (rowModel.ignoreChart || false) || (rowModel.skillIssues || false) || (rowModel.hardBpm || false)
                                                            Text {
                                                                text: "⛔"
                                                                font.pixelSize: 6
                                                                visible: rowModel.ignoreChart || false
                                                            }
                                                            Text {
                                                                text: "⚠️"
                                                                font.pixelSize: 6
                                                                visible: rowModel.skillIssues || false
                                                            }
                                                            Text {
                                                                text: "⏪"
                                                                font.pixelSize: 6
                                                                visible: rowModel.hardBpm || false
                                                            }
                                                        }
                                                    }
                                                    
                                                    // BP value in parentheses for level sort (chart mode)
                                                    Text {
                                                        text: " (" + (rowModel.bp ? rowModel.bp.toFixed(1) : "0.0") + ")"
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: Theme.listValue
                                                        visible: parent.isLevelSort
                                                        anchors.bottom: parent.bottom
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
                                    color: Theme.textLight
                                    font.pixelSize: 14
                                    visible: songListView.count === 0
                                }
                            }
                        }
                    }

                    // (B-2) 곡 상세 정보
                    Loader {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        active: !isNarrow
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
            color: isNarrow ? Theme.bgWindow : Theme.bgCard 
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
                    Layout.fillWidth: true; height: 60; visible: isNarrow; color: Theme.bgCard
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "❮ Back"; font.bold: true; color: Theme.accent; font.pixelSize: 16 
                            MouseArea { anchors.fill: parent; onClicked: mobileStack.pop() }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: "Song Detail"; font.bold: true; color: Theme.textPrimary; font.pixelSize: 16 }
                        Item { Layout.fillWidth: true }
                        Item { width: 40 }
                    }
                }

                // [Song Header]
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentWidth: availableWidth; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff; clip: true
                    
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
                                        color: Theme.textTitle
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
                                        color: Theme.bannerFallback
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
                                        color: Theme.overlay
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
                                        property int diff: statsHandler && currentSong ? (currentSong.thumbnailDifficulty !== undefined ? currentSong.thumbnailDifficulty : currentSong.difficulty) : 0
                                        property var arcaeaId: statsHandler && currentSong ? (currentSong.arcaeaId || "") : ""
                                        property string shadowColorString: statsHandler ? statsHandler.getThumbnailColor(arcaeaId, diff) : Theme.bgCard
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
                                        color: currentSong ? Theme.getDiffColor(currentSong.thumbnailDifficulty !== undefined ? currentSong.thumbnailDifficulty : currentSong.difficulty) : Theme.accent
                                        border.color: Theme.bgCard; border.width: 2
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
                                            color: Theme.accent
                                            Text {
                                                id: bpmText
                                                anchors.centerIn: parent
                                                text: Boolean(currentSong) && Boolean(currentSong.bpm) ? ("BPM: " + currentSong.bpm) : ""
                                                color: Theme.bgCard; font.pixelSize: 11
                                            }
                                        }
                                        
                                        Rectangle {
                                            visible: Boolean(currentSong) && Number(currentSong.length) > 0
                                            Layout.preferredWidth: lengthText.width + 16
                                            Layout.preferredHeight: 24
                                            radius: 12
                                            color: Theme.badgeLen
                                            Text {
                                                id: lengthText
                                                anchors.centerIn: parent
                                                text: {
                                                    if (!currentSong || !currentSong.length) return ""
                                                    var len = currentSong.length
                                                    return "Length: " + Math.floor(len / 60) + ":" + (len % 60).toString().padStart(2, '0')
                                                }
                                                color: Theme.bgCard; font.pixelSize: 11
                                            }
                                        }
                                    }
                                    
                                    Text { 
                                        text: currentSong ? currentSong.title : "Select a song"
                                        font.family: statsRoot.titleFontFamily
                                        color: Theme.detailHeaderTitle; font.bold: true
                                        font.pixelSize: isNarrow ? 24 : 36
                                        elide: Text.ElideRight
                                        width: parent.width 
                                    }
                                    Text { 
                                        text: currentSong ? currentSong.artist : ""
                                        font.family: statsRoot.titleFontFamily
                                        color: Theme.detailHeaderArtist; font.pixelSize: 16
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
                                color: Theme.detailHeaderPlayCount
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
                                // FRAME/MAX 라인(PM 이상 성적)이 표시되는 경우, 두 라인 높이만큼 카드 영역을 더 확보해
                                // 하단 콘텐츠(PlayDate·배지·플레이카운트)가 잘리지 않게 한다. mobile(base 360)은 여유가
                                // 있어 소폭만, desktop(base 330)은 넉넉히 확보한다.
                                property bool anyFrameLine: {
                                    for (var i = 0; i < difficultiesToShow.length; i++) {
                                        var m = difficultiesToShow[i]
                                        if (m && m.hasScore && (m.bestScore || 0) >= 10000000) return true
                                    }
                                    return false
                                }
                                Layout.preferredHeight: ((isNarrow || isDiffCramped) ? 360 : 330)
                                                        + (anyFrameLine ? 36 : 0)
                                Layout.minimumHeight: ((isNarrow || isDiffCramped) ? 360 : 330)
                                                       + (anyFrameLine ? 36 : 0)
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
                                                score: modelData.bestScore || 0
                                                rank: modelData.rank || ""
                                                clearTypeText: modelData.clearTypeText || ""
                                                clearTypeAbbr: modelData.clearTypeAbbr || ""
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
                                                ignoreChart: modelData.ignoreChart || false
                                                skillIssues: modelData.skillIssues || false
                                                hardBpm: modelData.hardBpm || false
                                                isSelected: statisticsHandler && modelData.difficulty === statisticsHandler.selectedDifficulty
                                                isFiltered: modelData.isFiltered || false
                                                potential: modelData.potential !== undefined ? modelData.potential : null
                                                scoreBelowMax: modelData.scoreBelowMax || 0
                                                cut200: modelData.cut200 || 0
                                                bestPotentialRank: {
                                                    var r = modelData.potentialRank || 0
                                                    return (statsRoot.bestPotentialMarkLimit > 0 && r > 0 && r <= statsRoot.bestPotentialMarkLimit) ? r : 0
                                                }

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
                                    delegate: Rectangle { width: 8; height: 8; radius: 4; color: index === diffSwipe.currentIndex ? Theme.accent : Theme.borderDivider }
                                }

                                // [Desktop] RowLayout
                                RowLayout {
                                    id: desktopRow
                                    anchors.fill: parent
                                    visible: !isNarrow && !isDiffCramped
                                    
                                    property int numCards: Math.max(1, difficultiesToShow.length)
                                    property real cardMaxWidth: 220
                                    property real baseSpacing: 15
                                    property real totalBaseRequired: (numCards * cardMaxWidth) + (Math.max(0, numCards - 1) * baseSpacing)
                                    
                                    property real extraWidth: Math.max(0, width - totalBaseRequired)
                                    property real sExtra: extraWidth / (numCards + 3)
                                    
                                    spacing: baseSpacing + sExtra
                                    
                                    Repeater {
                                        model: difficultiesToShow
                                        
                                        DiffCard {
                                            Layout.leftMargin: index === 0 ? 2 * desktopRow.sExtra : 0
                                            Layout.rightMargin: index === desktopRow.numCards - 1 ? 2 * desktopRow.sExtra : 0
                                            Layout.maximumWidth: desktopRow.cardMaxWidth
                                            diffName: modelData.difficultyName || ""
                                            diffLevel: modelData.level || ""
                                            score: modelData.bestScore || 0
                                            rank: modelData.rank || ""
                                            clearTypeText: modelData.clearTypeText || ""
                                            clearTypeAbbr: modelData.clearTypeAbbr || ""
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
                                            ignoreChart: modelData.ignoreChart || false
                                            skillIssues: modelData.skillIssues || false
                                            hardBpm: modelData.hardBpm || false
                                            isSelected: statisticsHandler && modelData.difficulty === statisticsHandler.selectedDifficulty
                                            isFiltered: modelData.isFiltered || false
                                            potential: modelData.potential !== undefined ? modelData.potential : null
                                            scoreBelowMax: modelData.scoreBelowMax || 0
                                            cut200: modelData.cut200 || 0
                                            bestPotentialRank: {
                                                var r = modelData.potentialRank || 0
                                                return (statsRoot.bestPotentialMarkLimit > 0 && r > 0 && r <= statsRoot.bestPotentialMarkLimit) ? r : 0
                                            }

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
                                color: Theme.textLight
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
            color: Theme.bgCard
            radius: 15
            border.color: Theme.borderCard
            border.width: 1
            
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 4
                shadowBlur: 1.0 // Normalized value roughly corresponding to radius
                shadowColor: Theme.shadowLight
            }
        }
        
        // X Close Button (positioned at top-right corner)
        Rectangle {
            id: closeButton
            width: 40; height: 40; radius: 20
            color: closeButtonMouse.containsMouse ? Theme.bgButton : Theme.bgHover
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
                color: Theme.textSecondary
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
                Text { text: "Filters"; font.pixelSize: 20; font.bold: true; color: Theme.textPrimary }
                Item { Layout.fillWidth: true }
                Text { 
                    text: "↺"
                    font.pixelSize: 26
                    font.bold: true
                    color: Theme.accent
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
                            hardBpmFlagSegment.selectedIndex = 1 // Show
                            filterPopup.updateFlagFilter()  // Apply consultant sheet flags reset to backend
                            
                            clearRangeSlider.handleAIndex = 0
                            clearRangeSlider.handleBIndex = clearRangeSlider.clearTypeItems.length > 0 ? clearRangeSlider.clearTypeItems.length - 1 : 0
                            filterPopup.updateClearTypeFilter()  // Apply the reset to backend
                        }
                    }
                }
            }
            
            Item {
                id: filterScrollArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                ScrollView {
                    id: filterScrollView
                    anchors.fill: parent
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                    clip: true
                
                ColumnLayout {
                    width: parent.width - 24  // Right padding for scroll indicator
                    spacing: 20
                    
                    // Difficulty Filter
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Difficulties"; font.pixelSize: 14; font.bold: true; color: Theme.textPrimary }
                        
                        RowLayout {
                            spacing: 20
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            
                            DiffFilterCheckbox {
                                id: pstCheck
                                text: "PST"
                                diffColor: Theme.diffPst
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: prsCheck
                                text: "PRS"
                                diffColor: Theme.diffPrs
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: ftrCheck
                                text: "FTR"
                                diffColor: Theme.diffFtr
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: etrCheck
                                text: "ETR"
                                diffColor: Theme.diffEtr  // Gray for ETR
                                checked: true
                                onCheckedChanged: filterPopup.updateDifficultyFilter()
                            }
                            DiffFilterCheckbox {
                                id: bydCheck
                                text: "BYD"
                                diffColor: Theme.diffByd
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
                            
                            Text { text: rangeSlider.bpMode ? "BP Range" : "Level Range"; font.pixelSize: 14; font.bold: true; color: Theme.textPrimary }
                            
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
                                            color: !rangeSlider.bpMode ? Theme.accent : Theme.textMuted
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
                                            color: rangeSlider.bpMode ? Theme.accent : Theme.textMuted
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
                                    return Theme.diffPst  // PST
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
                                    return Theme.diffByd  // BYD
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
                                color: Theme.borderCard
                                
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
                                        color: Theme.textDisabled
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
                                border.color: Theme.bgCard; border.width: 2
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
                                    font.pixelSize: 10; font.bold: true; color: Theme.textPrimary
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
                                border.color: Theme.bgCard; border.width: 2
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
                                    font.pixelSize: 10; font.bold: true; color: Theme.textPrimary
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
                    
                    Rectangle { height: 1; Layout.fillWidth: true; color: Theme.borderCard }
                    
                    // Score Range Filter
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Score Range"; font.pixelSize: 14; font.bold: true; color: Theme.textPrimary }
                        
                        // Score Range Slider
                        Item {
                            id: scoreRangeSlider
                            width: parent.width
                            height: 60
                            
                            // Score grades: -, D, C, B, A, AA, EX, EX+, 99.5%, 99.8%, PM, FRAME, MAX
                            property var scoreGrades: statisticsHandler ? statisticsHandler.scoreRanks : ["-", "D", "C", "B", "A", "AA", "EX", "EX+", "99.5%", "99.8%", "PM", "FRAME", "MAX"]
                            
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
                            
                            // Color mapping for Score Range gradient (index-based anchors)
                            // D (idx 0) = burgundy #80354A
                            // A (idx 4) = brighter purple #9B6BB5
                            // EX (idx 6) = brighter blue-gray #6A8CAA
                            // PM (idx 10) = brighter teal #4AA8A8
                            // FRAME (idx 11) = sky blue #5AB8E0 (기존 MAX 색)
                            // MAX (idx 12) = brighter sky blue #85D5F5
                            function getColorForScoreIndex(idx) {
                                if (scoreGrades.length <= 1) return Theme.scoreLost

                                var anchors = [
                                    {i: 0,  r: 0x80, g: 0x35, b: 0x4A},   // D     - burgundy
                                    {i: 4,  r: 0x9B, g: 0x6B, b: 0xB5},   // A     - brighter purple
                                    {i: 6,  r: 0x6A, g: 0x8C, b: 0xAA},   // EX    - brighter blue-gray
                                    {i: 10, r: 0x4A, g: 0xA8, b: 0xA8},   // PM    - brighter teal
                                    {i: 11, r: 0x5A, g: 0xB8, b: 0xE0},   // FRAME - sky blue
                                    {i: 12, r: 0x85, g: 0xD5, b: 0xF5}    // MAX   - brighter sky blue
                                ]
                                var last = anchors.length - 1
                                if (idx <= anchors[0].i) idx = anchors[0].i
                                if (idx >= anchors[last].i) idx = anchors[last].i

                                for (var k = 0; k < last; k++) {
                                    var a = anchors[k], b2 = anchors[k + 1]
                                    if (idx >= a.i && idx <= b2.i) {
                                        var t = (b2.i === a.i) ? 0 : (idx - a.i) / (b2.i - a.i)
                                        var r = Math.round(a.r + (b2.r - a.r) * t)
                                        var g = Math.round(a.g + (b2.g - a.g) * t)
                                        var b = Math.round(a.b + (b2.b - a.b) * t)
                                        return "#" + r.toString(16).padStart(2, '0') + g.toString(16).padStart(2, '0') + b.toString(16).padStart(2, '0')
                                    }
                                }
                                return Theme.scoreLost
                            }
                            
                            // Track with gradient
                            Rectangle {
                                id: scoreTrack
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -10
                                height: 6; radius: 3
                                color: Theme.borderCard
                                
                                // Tick marks for each grade
                                Repeater {
                                    model: scoreRangeSlider.scoreGrades.length
                                    
                                    Rectangle {
                                        x: scoreRangeSlider.scoreGrades.length > 1 ? 
                                            10 + (index / (scoreRangeSlider.scoreGrades.length - 1)) * (parent.width - 20) - 1 : 0
                                        y: -3
                                        width: 2; height: 12
                                        radius: 1
                                        color: Theme.textDisabled
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
                                border.color: Theme.bgCard; border.width: 2
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
                                    font.pixelSize: 10; font.bold: true; color: Theme.textPrimary
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
                                border.color: Theme.bgCard; border.width: 2
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
                                    font.pixelSize: 10; font.bold: true; color: Theme.textPrimary
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
                    
                    Rectangle { height: 1; Layout.fillWidth: true; color: Theme.borderCard }
                    
                    // Clear Type Filter
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Clear Range"; font.pixelSize: 14; font.bold: true; color: Theme.textPrimary }
                        
                        Item {
                            id: clearRangeSlider
                            width: parent.width
                            height: 60
                            
                            // Display order: Track Lost -> Easy Clear -> Track Complete -> Hard Clear -> Full Recall -> Pure Memory
                            property var clearTypeItems: [
                                { id: 0, label: "Track Lost", color: Theme.clearLost },
                                { id: 4, label: "Easy Clear", color: Theme.clearEasy },
                                { id: 1, label: "Track Complete", color: Theme.clearComplete },
                                { id: 5, label: "Hard Clear", color: Theme.clearHard },
                                { id: 2, label: "Full Recall", color: Theme.clearFullRecall },
                                { id: 3, label: "Pure Memory", color: Theme.clearPureMemory }
                            ]
                            
                            property int handleAIndex: 0
                            property int handleBIndex: clearTypeItems.length > 0 ? clearTypeItems.length - 1 : 0
                            property int minIndex: Math.min(handleAIndex, handleBIndex)
                            property int maxIndex: Math.max(handleAIndex, handleBIndex)
                            
                            function getDisplayLabel(idx) {
                                if (idx >= 0 && idx < clearTypeItems.length) return clearTypeItems[idx].label
                                return ""
                            }
                            
                            function getHandleLabel(idx) {
                                var label = getDisplayLabel(idx)
                                if (label === "Track Lost") return "Track\nLost"
                                if (label === "Pure Memory") return "Pure\nMemory"
                                return label
                            }
                            
                            function colorToRgb(value) {
                                // QML color properties arrive as QColor-like objects,
                                // not JavaScript strings. Keep a string fallback for
                                // any future data source that supplies a hex value.
                                if (value && typeof value.r === "number") {
                                    return {
                                        r: Math.round(value.r * 255),
                                        g: Math.round(value.g * 255),
                                        b: Math.round(value.b * 255)
                                    }
                                }

                                var clean = String(value).replace("#", "")
                                return {
                                    r: parseInt(clean.substring(0, 2), 16),
                                    g: parseInt(clean.substring(2, 4), 16),
                                    b: parseInt(clean.substring(4, 6), 16)
                                }
                            }
                            
                            function rgbToHex(r, g, b) {
                                return "#" + r.toString(16).padStart(2, "0") + g.toString(16).padStart(2, "0") + b.toString(16).padStart(2, "0")
                            }
                            
                            function interpolateColor(colorA, colorB, t) {
                                var a = colorToRgb(colorA)
                                var b = colorToRgb(colorB)
                                var r = Math.round(a.r + (b.r - a.r) * t)
                                var g = Math.round(a.g + (b.g - a.g) * t)
                                var bl = Math.round(a.b + (b.b - a.b) * t)
                                return rgbToHex(r, g, bl)
                            }
                            
                            function getColorForClearIndex(idx) {
                                var n = clearTypeItems.length
                                if (n <= 1) return Theme.rankSilver

                                var bounded = Math.max(0, Math.min(idx, n - 1))
                                var i0 = Math.floor(bounded)
                                var i1 = Math.min(i0 + 1, n - 1)
                                var t = bounded - i0
                                return interpolateColor(clearTypeItems[i0].color, clearTypeItems[i1].color, t)
                            }
                            
                            function getColorForIndex(idx) {
                                if (idx >= 0 && idx < clearTypeItems.length) return getColorForClearIndex(idx)
                                return Theme.rankSilver
                            }
                            
                            function getSelectedTypes() {
                                var selected = []
                                for (var i = minIndex; i <= maxIndex; i++) {
                                    selected.push(clearTypeItems[i].id)
                                }
                                return selected
                            }
                            
                            Rectangle {
                                id: clearTrack
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -10
                                height: 6
                                radius: 3
                                color: Theme.borderCard
                                
                                Repeater {
                                    model: clearRangeSlider.clearTypeItems.length
                                    
                                    Rectangle {
                                        x: clearRangeSlider.clearTypeItems.length > 1 ?
                                            10 + (index / (clearRangeSlider.clearTypeItems.length - 1)) * (parent.width - 20) - 1 : 0
                                        y: -3
                                        width: 2
                                        height: 12
                                        radius: 1
                                        color: Theme.textDisabled
                                    }
                                }
                                
                                Rectangle {
                                    id: clearActiveRegion
                                    property real handleWidth: 20
                                    property real trackUsableWidth: parent.width - handleWidth
                                    property real minPos: clearRangeSlider.clearTypeItems.length > 1 ?
                                        (handleWidth / 2) + (clearRangeSlider.minIndex / (clearRangeSlider.clearTypeItems.length - 1)) * trackUsableWidth : 0
                                    property real maxPos: clearRangeSlider.clearTypeItems.length > 1 ?
                                        (handleWidth / 2) + (clearRangeSlider.maxIndex / (clearRangeSlider.clearTypeItems.length - 1)) * trackUsableWidth : parent.width
                                    
                                    x: minPos
                                    width: maxPos - minPos
                                    height: parent.height
                                    clip: true
                                    
                                    Canvas {
                                        id: clearGradientCanvas
                                        property real handleWidth: 20
                                        property real trackUsableWidth: clearTrack.width - handleWidth
                                        
                                        x: (handleWidth / 2) - clearActiveRegion.x
                                        width: trackUsableWidth
                                        height: parent.height
                                        
                                        property var dataList: clearRangeSlider.clearTypeItems
                                        onDataListChanged: requestPaint()
                                        onWidthChanged: requestPaint()
                                        
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            
                                            var n = clearRangeSlider.clearTypeItems.length
                                            if (n <= 1) {
                                                var singleColor = clearRangeSlider.getColorForClearIndex(0)
                                                ctx.fillStyle = singleColor
                                                ctx.beginPath()
                                                ctx.roundedRect(0, 0, width, height, 3)
                                                ctx.fill()
                                                return
                                            }
                                            
                                            for (var i = 0; i < n - 1; i++) {
                                                var x0 = (i / (n - 1)) * width
                                                var x1 = ((i + 1) / (n - 1)) * width
                                                var color0 = clearRangeSlider.getColorForClearIndex(i)
                                                var color1 = clearRangeSlider.getColorForClearIndex(i + 1)
                                                var grad = ctx.createLinearGradient(x0, 0, x1, 0)
                                                grad.addColorStop(0, color0)
                                                grad.addColorStop(1, color1)
                                                ctx.fillStyle = grad
                                                ctx.fillRect(x0, 0, x1 - x0 + 1, height)
                                            }
                                            
                                            ctx.globalCompositeOperation = "destination-in"
                                            ctx.fillStyle = "black"
                                            ctx.beginPath()
                                            ctx.roundedRect(0, 0, width, height, 3)
                                            ctx.fill()
                                        }
                                    }
                                }
                            }
                            
                            Rectangle {
                                id: clearHandleA
                                width: 20
                                height: 20
                                radius: 10
                                property string baseColor: clearRangeSlider.getColorForIndex(clearRangeSlider.handleAIndex)
                                color: clearHandleAMouse.pressed ? Qt.darker(baseColor, 1.15) : baseColor
                                border.color: Theme.bgCard
                                border.width: 2
                                x: clearRangeSlider.clearTypeItems.length > 1 ?
                                    (clearRangeSlider.handleAIndex / (clearRangeSlider.clearTypeItems.length - 1)) * (clearTrack.width - width) : 0
                                anchors.verticalCenter: clearTrack.verticalCenter
                                
                                Text {
                                    property bool tooClose: Math.abs(clearRangeSlider.handleAIndex - clearRangeSlider.handleBIndex) <= 1
                                    property bool isRightHandle: clearHandleA.x > clearHandleB.x
                                    property bool showAbove: tooClose && isRightHandle
                                    y: showAbove ? -height - 4 : parent.height + 4
                                    x: clearRangeSlider.handleAIndex === 0 ? Math.max(-parent.x, (parent.width - width) / 2) : (parent.width - width) / 2
                                    text: clearRangeSlider.getHandleLabel(clearRangeSlider.handleAIndex)
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Theme.textPrimary
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                
                                MouseArea {
                                    id: clearHandleAMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -20
                                    anchors.bottomMargin: -20
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    property int startIndex: 0
                                    property real pressGlobalX: 0
                                    
                                    onPressed: (mouse) => {
                                        startIndex = clearRangeSlider.handleAIndex
                                        var mapped = mapToItem(clearTrack, mouse.x, mouse.y)
                                        pressGlobalX = mapped.x
                                    }
                                    
                                    onPositionChanged: (mouse) => {
                                        if (pressed && clearRangeSlider.clearTypeItems.length > 1) {
                                            var mapped = mapToItem(clearTrack, mouse.x, mouse.y)
                                            var deltaX = mapped.x - pressGlobalX
                                            var stepWidth = (clearTrack.width - parent.width) / (clearRangeSlider.clearTypeItems.length - 1)
                                            var indexDelta = Math.round(deltaX / stepWidth)
                                            var newIdx = Math.max(0, Math.min(startIndex + indexDelta, clearRangeSlider.clearTypeItems.length - 1))
                                            clearRangeSlider.handleAIndex = newIdx
                                        }
                                    }
                                    
                                    onReleased: {
                                        filterPopup.updateClearTypeFilter()
                                    }
                                }
                            }
                            
                            Rectangle {
                                id: clearHandleB
                                width: 20
                                height: 20
                                radius: 10
                                property string baseColor: clearRangeSlider.getColorForIndex(clearRangeSlider.handleBIndex)
                                color: clearHandleBMouse.pressed ? Qt.darker(baseColor, 1.15) : baseColor
                                border.color: Theme.bgCard
                                border.width: 2
                                x: clearRangeSlider.clearTypeItems.length > 1 ?
                                    (clearRangeSlider.handleBIndex / (clearRangeSlider.clearTypeItems.length - 1)) * (clearTrack.width - width) : clearTrack.width - width
                                anchors.verticalCenter: clearTrack.verticalCenter
                                
                                Text {
                                    property bool tooClose: Math.abs(clearRangeSlider.handleAIndex - clearRangeSlider.handleBIndex) <= 1
                                    property bool isRightHandle: clearHandleB.x > clearHandleA.x
                                    property bool showAbove: tooClose && isRightHandle
                                    y: showAbove ? -height - 4 : parent.height + 4
                                    x: clearRangeSlider.handleBIndex === 0 ? Math.max(-parent.x, (parent.width - width) / 2) : (parent.width - width) / 2
                                    text: clearRangeSlider.getHandleLabel(clearRangeSlider.handleBIndex)
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Theme.textPrimary
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                
                                MouseArea {
                                    id: clearHandleBMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -20
                                    anchors.bottomMargin: -20
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    property int startIndex: 0
                                    property real pressGlobalX: 0
                                    
                                    onPressed: (mouse) => {
                                        startIndex = clearRangeSlider.handleBIndex
                                        var mapped = mapToItem(clearTrack, mouse.x, mouse.y)
                                        pressGlobalX = mapped.x
                                    }
                                    
                                    onPositionChanged: (mouse) => {
                                        if (pressed && clearRangeSlider.clearTypeItems.length > 1) {
                                            var mapped = mapToItem(clearTrack, mouse.x, mouse.y)
                                            var deltaX = mapped.x - pressGlobalX
                                            var stepWidth = (clearTrack.width - parent.width) / (clearRangeSlider.clearTypeItems.length - 1)
                                            var indexDelta = Math.round(deltaX / stepWidth)
                                            var newIdx = Math.max(0, Math.min(startIndex + indexDelta, clearRangeSlider.clearTypeItems.length - 1))
                                            clearRangeSlider.handleBIndex = newIdx
                                        }
                                    }
                                    
                                    onReleased: {
                                        filterPopup.updateClearTypeFilter()
                                    }
                                }
                            }
                        }
                    }
                    
                    Rectangle { height: 1; Layout.fillWidth: true; color: Theme.borderCard }
                    
                    // Chart Flags
                    Column {
                        spacing: 10
                        Layout.fillWidth: true
                        
                        Text { text: "Consultant Sheet Flags"; font.pixelSize: 14; font.bold: true; color: Theme.textPrimary }
                        
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
                                id: hardBpmFlagSegment
                                flagName: "⏪ hard speed"
                                selectedIndex: 1  // Default: Show
                                onIndexChanged: filterPopup.updateFlagFilter()
                            }

                        }
                    }
                }
            }

                Basic.ScrollBar {
                    id: filterVerticalBar
                    z: 10
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    width: 10

                    policy: ScrollBar.AlwaysOn
                    size: filterScrollView.contentItem ? filterScrollView.contentItem.visibleArea.heightRatio : 1
                    position: filterScrollView.contentItem ? filterScrollView.contentItem.visibleArea.yPosition : 0

                    onPositionChanged: {
                        if (pressed && filterScrollView.contentItem)
                            filterScrollView.contentItem.contentY = position * filterScrollView.contentItem.contentHeight
                    }

                    property bool showScrollbar: (filterScrollView.contentItem && filterScrollView.contentItem.moving)
                                                  || filterHideTimer.running
                                                  || filterVerticalBar.hovered
                                                  || filterVerticalBar.pressed
                    hoverEnabled: true
                    active: true

                    Timer { id: filterHideTimer; interval: 1000 }
                    Connections {
                        target: filterScrollView.contentItem
                        function onMovingChanged() {
                            if (!filterScrollView.contentItem.moving)
                                filterHideTimer.restart()
                        }
                    }
                    onPressedChanged: {
                        if (!pressed && filterScrollView.contentItem && !filterScrollView.contentItem.moving)
                            filterHideTimer.restart()
                    }

                    opacity: showScrollbar ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    background: Rectangle { color: "transparent" }
                    contentItem: Rectangle {
                        implicitWidth: 6
                        implicitHeight: 100
                        radius: 3
                        color: Theme.scrollbar
                        opacity: filterVerticalBar.pressed ? 1.0 : (filterVerticalBar.hovered ? 1.0 : 0.6)
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
                statisticsHandler.setFilter("hard_bpm", map[hardBpmFlagSegment.selectedIndex])
            }
        }

        function updateClearTypeFilter() {
            if (!initialized) return  // Skip during initialization
            
            var types = clearRangeSlider.getSelectedTypes()
            
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
