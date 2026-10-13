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
    property int thumbnailVersion: statsHandler ? statsHandler.thumbnailVersion : (statisticsHandler ? statisticsHandler.thumbnailVersion : 0)
    readonly property bool isPackMode: Boolean(statisticsHandler && statisticsHandler.displayMode === "pack")
    readonly property bool isPackDashboardTarget: Boolean(statisticsHandler && statisticsHandler.displayMode === "pack" && statisticsHandler.isPackDetailView)
    property bool isDetailedViewCrossfading: false
    property bool isDeselectingPack: false
    property bool wasPackSelectedBeforeTransition: false
    property var cachedLastPack: null
    readonly property bool isPackSelected: Boolean((isPackMode && statisticsHandler && statisticsHandler.expandedPackIds && statisticsHandler.expandedPackIds.length > 0) || (statsRoot.isDetailedViewCrossfading && !statsRoot.isPackDashboardTarget && statsRoot.wasPackSelectedBeforeTransition && statsRoot.cachedLastPack))
    property var currentSong: statisticsHandler ? statisticsHandler.getSelectedItem() : null
    property int currentSongIndex: statisticsHandler ? statisticsHandler.selectedIndex : -1
    property string searchText: ""  // Search text managed at root level
    property real savedPackContentY: 0
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

    Connections {
        target: statisticsHandler
        function onCurrentPackChanged() {
            if (statsRoot.isDetailedViewCrossfading) return
            if (statisticsHandler && statisticsHandler.currentPack && statisticsHandler.currentPack.id) {
                statsRoot.cachedLastPack = statisticsHandler.currentPack
            }
        }
    }

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

                            readonly property var activeListView: {
                                if (statisticsHandler && statisticsHandler.displayMode === "pack") {
                                    if (statisticsHandler.currentPack && typeof packSongListView !== "undefined" && packSongListView.visible) {
                                        return packSongListView
                                    }
                                    return (typeof packListView !== "undefined") ? packListView : songListView
                                }
                                return songListView
                            }

                            policy: ScrollBar.AlwaysOn
                            size: activeListView ? activeListView.visibleArea.heightRatio : 1
                            position: activeListView ? activeListView.visibleArea.yPosition : 0

                            onPositionChanged: {
                                if (pressed && activeListView) activeListView.contentY = position * activeListView.contentHeight
                            }

                            property bool showScrollbar: (activeListView && activeListView.moving) || hideTimer.running || listVerticalBar.hovered || listVerticalBar.pressed
                            hoverEnabled: true
                            active: true

                            Timer { id: hideTimer; interval: 1000 }
                            Connections {
                                target: listVerticalBar.activeListView
                                function onMovingChanged() {
                                    if (listVerticalBar.activeListView && !listVerticalBar.activeListView.moving) hideTimer.restart()
                                }
                            }
                            onPressedChanged: {
                                if (!pressed && listVerticalBar.activeListView && !listVerticalBar.activeListView.moving) hideTimer.restart()
                            }

                            opacity: showScrollbar ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            background: Rectangle { color: "transparent" }
                            contentItem: Rectangle {
                                implicitWidth: 6; implicitHeight: 100; radius: 3
                                color: Theme.scrollbar
                                opacity: listVerticalBar.pressed ? 1.0 : (listVerticalBar.hovered ? 1.0 : 0.6)
                            }
                        }
                        
                        // Floating INS Mark: positioned in the card's right padding area (like listVerticalBar),
                        // centered horizontally in the 20px padding space (width - 20 to width)
                        // and vertically centered on the filterCountRow.
                        Item {
                            id: insMarkArea
                            z: 5
                            anchors.right: parent.right
                            width: 20
                            y: songListContentLayout.y + filterCountRow.y
                            height: filterCountRow.height

                            property var diffInfo: {
                                if (!statisticsHandler || !statisticsHandler.activeFiltersModel) return null
                                var m = statisticsHandler.activeFiltersModel
                                for (var i = 0; i < m.length; i++) {
                                    if (m[i].type === "difficulties") return m[i]
                                }
                                return null
                            }
                            visible: diffInfo ? Boolean(diffInfo.showInsMark) : false

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -0.5
                                text: (insMarkArea.diffInfo && insMarkArea.diffInfo.insActive) ? "◆" : "◇"
                                color: Theme.diffIns
                                font.pixelSize: 9
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
                            
                            // Controls Row: Mode Switcher + Integrated Sort
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                
                                // Song/Chart/Pack Mode Switcher (Pack / Song / Chart)
                                Rectangle {
                                    Layout.preferredWidth: 165
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
                                            color: statisticsHandler && statisticsHandler.displayMode === "pack" ? Theme.accent : (packMouse.containsMouse ? Theme.bgHover : "transparent")

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Pack"
                                                font.pixelSize: 12
                                                font.bold: statisticsHandler && statisticsHandler.displayMode === "pack"
                                                color: statisticsHandler && statisticsHandler.displayMode === "pack" ? "white" : Theme.textSecondary
                                            }

                                            MouseArea {
                                                id: packMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (statisticsHandler) statisticsHandler.setDisplayMode("pack")
                                            }
                                        }

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
                                
                                // Integrated Sort Dropdown & Direction Toggle
                                Basic.ComboBox {
                                    id: sortCombo
                                    Layout.preferredWidth: 120
                                    Layout.preferredHeight: 32
                                    model: ["Title", "Score", "Potential", "MAX", "Total Play", "This Year Play", "Recent", "Level (BP)", "S-BP", "P-BP", "Notes", "BPM", "Length", "Version"]

                                    property var sortModes: ["title", "score", "potential", "max", "total_play_count", "this_year_play_count", "recent_played", "level", "s_bp", "perceived_bp", "note_count", "bpm", "length", "version"]
                                    
                                    function syncIndexFromHandler() {
                                        if (!statisticsHandler) return
                                        var idx = sortModes.indexOf(statisticsHandler.sortMode)
                                        if (idx !== -1) {
                                            currentIndex = idx
                                        } else {
                                            currentIndex = 0
                                            statisticsHandler.setSortMode(sortModes[0])
                                        }
                                    }

                                    Connections {
                                        target: statisticsHandler
                                        function onDataChanged() { sortCombo.syncIndexFromHandler() }
                                        function onDisplayModeChanged() { sortCombo.syncIndexFromHandler() }
                                    }

                                    Component.onCompleted: syncIndexFromHandler()

                                    onActivated: (index) => {
                                        if (statisticsHandler && index >= 0 && index < sortModes.length) {
                                            statisticsHandler.setSortMode(sortModes[index])
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
                                        elide: Text.ElideNone
                                        leftPadding: 10
                                        rightPadding: 32
                                    }
                                    
                                    indicator: Rectangle {
                                        id: sortArrowContainer
                                        x: sortCombo.width - width - 4
                                        y: (sortCombo.height - height) / 2
                                        width: 24
                                        height: 24
                                        radius: 4
                                        color: sortArrowMouse.containsMouse ? Theme.bgSelected : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: statisticsHandler && statisticsHandler.sortAscending ? "↑" : "↓"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: sortArrowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (sortCombo.popup.visible) {
                                                    sortCombo.popup.close()
                                                }
                                                if (statisticsHandler) {
                                                    statisticsHandler.toggleSortOrder()
                                                }
                                            }
                                        }
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
                            }
                            
                            // Item count and Active Filters
                            RowLayout {
                                id: filterCountRow
                                Layout.fillWidth: true

                                Text {
                                    text: {
                                        var mode = statisticsHandler ? statisticsHandler.displayMode : "song"
                                        if (mode === "pack") {
                                            return packListView.count + (packListView.count === 1 ? " pack" : " packs")
                                        } else if (mode === "chart") {
                                            return songListView.count + (songListView.count === 1 ? " chart" : " charts")
                                        } else {
                                            return songListView.count + (songListView.count === 1 ? " song" : " songs")
                                        }
                                    }
                                    font.pixelSize: 11
                                    color: Theme.textLight
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Item { Layout.fillWidth: true }

                                // Interactive Active Filters Area (opens filterPopup on click)
                                Rectangle {
                                    id: activeFiltersArea
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: filterContentRow.implicitWidth + 12
                                    implicitHeight: 22
                                    radius: 4
                                    color: activeFiltersMouse.containsMouse ? Theme.bgHover : "transparent"
                                    border.width: 0

                                    readonly property bool hasActiveFilters: Boolean(statisticsHandler && statisticsHandler.activeFiltersModel && statisticsHandler.activeFiltersModel.length > 0)

                                    Row {
                                        id: filterContentRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        // Fallback clickable label when no filters are active
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Filters"
                                            font.pixelSize: 11
                                            color: activeFiltersMouse.containsMouse ? Theme.textPrimary : Theme.textLight
                                            visible: !activeFiltersArea.hasActiveFilters
                                        }

                                        Row {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6
                                            visible: activeFiltersArea.hasActiveFilters

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

                                    MouseArea {
                                        id: activeFiltersMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: filterPopup.open()
                                    }
                                }
                            }
                            
                            // Formatting Components for Filters
                            Component {
                                id: diffComp
                                Item {
                                    implicitWidth: diffRow.implicitWidth
                                    implicitHeight: diffRow.implicitHeight
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        id: diffRow
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
                                    visible: !(statisticsHandler && statisticsHandler.displayMode === "pack")
                                    model: statisticsHandler ? statisticsHandler.listModel : null
                                    spacing: 8
                                    
                                    delegate: listDelegate
                                    
                                    opacity: 1.0
                                    NumberAnimation on opacity {
                                        id: songListFadeIn
                                        running: false
                                        from: 0.0
                                        to: 1.0
                                        duration: 60
                                    }
                                    // No attached ScrollBar to avoid layout conflicts
                                }

                                // 1. Pack Mode: Pack List View (hidden & non-interactive when pack is selected to prevent gap bleed-through and scroll jitter)
                                ListView {
                                    id: packListView
                                    anchors.fill: parent
                                    clip: true
                                    visible: statsRoot.isPackMode && !statsRoot.isPackSelected
                                    interactive: !statsRoot.isPackSelected
                                    model: statisticsHandler ? statisticsHandler.packItems : (statsHandler ? statsHandler.packItems : null)
                                    spacing: 8

                                    delegate: packDelegate

                                    opacity: 1.0
                                    NumberAnimation on opacity {
                                        id: packListFadeIn
                                        running: false
                                        from: 0.0
                                        to: 1.0
                                        duration: 60
                                    }
                                }

                                // 1.1 Pack Mode: Informational notice when songs.db is missing or damaged
                                Item {
                                    id: packListDbMissingNotice
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: 120
                                    anchors.bottom: parent.bottom
                                    visible: statsRoot.isPackMode && !statsRoot.isPackSelected && (statisticsHandler ? !statisticsHandler.isSongsDbAvailable : false)
                                    enabled: false

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Song database is missing or damaged.\nPlease rebuild it in the Settings tab."
                                        color: Theme.textMuted
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        lineHeight: 1.4
                                    }
                                }

                                // 2. Pack Mode: Selected Pack Drill-Down Stack View (Overlays pack list when selected)
                                Item {
                                    id: packDetailStackContainer
                                    anchors.fill: parent
                                    z: 2
                                    clip: true
                                    visible: statsRoot.isPackMode && statsRoot.isPackSelected

                                    opacity: 1.0
                                    NumberAnimation on opacity {
                                        id: packStackFadeIn
                                        running: false
                                        from: 0.0
                                        to: 1.0
                                        duration: 60
                                    }

                                    // Opaque background layer matching parent bounds
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Theme.bgCard
                                    }

                                    // Fixed Top Pack Header Card (Click to return to pack list)
                                    Rectangle {
                                        id: selectedPackHeaderCard
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 84
                                        radius: 10
                                        color: selectedPackHeaderMouse.containsMouse ? Theme.bgItemHover : Theme.bgSelected
                                        border.width: 1
                                        border.color: Theme.borderSelected


                                        property var pItem: {
                                            if (!statisticsHandler) return null
                                            var cur = statisticsHandler.currentPack
                                            var expIds = statisticsHandler.expandedPackIds
                                            var targetId = (expIds && expIds.length > 0) ? expIds[0] : null
                                            if (cur && cur.id && (!targetId || cur.id === targetId)) {
                                                return cur
                                            }
                                            if (targetId) {
                                                var items = statisticsHandler.packItems
                                                if (items) {
                                                    for (var i = 0; i < items.length; i++) {
                                                        if (items[i] && items[i].id === targetId) return items[i]
                                                    }
                                                }
                                            }
                                            return (cur && cur.id) ? cur : null
                                        }

                                        // 1. Bottom Mini 7-stage clear lamp bar (Absolute bottom-pinned)
                                        Item {
                                            id: selectedPackMiniBarItem
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.bottomMargin: 7
                                            height: 5
                                            clip: true

                                            Rectangle {
                                                id: selectedPackMiniBarBg
                                                anchors.fill: parent
                                                radius: 2.5
                                                color: Theme.isDarkMode ? "#35353E" : "#E2E2E8"
                                                clip: true

                                                Row {
                                                    anchors.fill: parent
                                                    spacing: 0

                                                    property var lamps: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.lamp_counts) ? selectedPackHeaderCard.pItem.lamp_counts : ({})
                                                    property int totalC: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.all_count && selectedPackHeaderCard.pItem.all_count > 0) ? selectedPackHeaderCard.pItem.all_count : 1
                                                    property real w: selectedPackMiniBarBg.width

                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.pm ? (parent.lamps.pm / parent.totalC) * parent.w : 0
                                                        color: Theme.clearPureMemory
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.fr ? (parent.lamps.fr / parent.totalC) * parent.w : 0
                                                        color: Theme.clearFullRecall
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.hard ? (parent.lamps.hard / parent.totalC) * parent.w : 0
                                                        color: Theme.clearHard
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.complete ? (parent.lamps.complete / parent.totalC) * parent.w : 0
                                                        color: Theme.clearComplete
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.easy ? (parent.lamps.easy / parent.totalC) * parent.w : 0
                                                        color: Theme.clearEasy
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.lost ? (parent.lamps.lost / parent.totalC) * parent.w : 0
                                                        color: Theme.clearLost
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.unplayed ? (parent.lamps.unplayed / parent.totalC) * parent.w : 0
                                                        color: Theme.scoreRankNone
                                                    }
                                                }
                                            }
                                        }

                                        // 2. Main Content Area (Independent from mini bar, fills between card top and mini bar)
                                        Item {
                                            id: selectedPackContentArea
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: selectedPackMiniBarItem.top
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 7
                                            anchors.bottomMargin: 6

                                            // Left Area: Pack Name / Songs Count (Independent vertical centering)
                                            RowLayout {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.right: selectedPackRightArea.left
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                // Expansion indicator / Back action
                                                Text {
                                                    text: "▼"
                                                    font.pixelSize: 11
                                                    color: Theme.accent
                                                    Layout.preferredWidth: 22
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 2

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.name) ? selectedPackHeaderCard.pItem.name : ""
                                                        font.family: statsRoot.titleFontFamily
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: Theme.textPrimary
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: selectedPackHeaderCard.pItem ? ((selectedPackHeaderCard.pItem.song_count || 0) + " songs • " + (selectedPackHeaderCard.pItem.chart_count || 0) + " charts") : ""
                                                        font.pixelSize: 11
                                                        color: Theme.textMuted
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            // Right Area: 3-Tier Branch Layout (Case 1: Rep Song Option 2, Case 2: Display Value Grid, Case 3: Standalone Counts)
                                            Item {
                                                id: selectedPackRightArea
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: Math.max(
                                                    hasRepSong ? selectedPackRepCapsule.implicitWidth : (hasDisplayVal ? selectedPackDisplayValCol.implicitWidth : 0),
                                                    hasRepSong ? selectedPackCountsText.implicitWidth : (hasDisplayVal ? 0 : selectedPackStandaloneCountsText.implicitWidth)
                                                )

                                                readonly property bool hasRepSong: Boolean(selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.top_representative && selectedPackHeaderCard.pItem.top_representative.has_song)
                                                readonly property bool hasDisplayVal: Boolean(selectedPackHeaderCard.pItem && !hasRepSong && selectedPackHeaderCard.pItem.displayValue && selectedPackHeaderCard.pItem.displayValue !== "")

                                                // ==========================================
                                                // Case 1: Representative Song with Capsule Box (Option 2: 30x30 Thumb, 34px Capsule, ~9.5px Gap)
                                                // ==========================================
                                                Rectangle {
                                                    id: selectedPackRepCapsule
                                                    visible: selectedPackRightArea.hasRepSong
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 1
                                                    implicitWidth: selectedRepSongRow.implicitWidth + 10
                                                    implicitHeight: selectedRepSongRow.implicitHeight + 4
                                                    radius: 5
                                                    color: Theme.bgCapsule
                                                    border.width: 1
                                                    border.color: Theme.borderSubtle

                                                    RowLayout {
                                                        id: selectedRepSongRow
                                                        anchors.centerIn: parent
                                                        spacing: 5

                                                        // Song stats (right-aligned, 2 lines without title)
                                                        ColumnLayout {
                                                            spacing: 0
                                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                                                            Text {
                                                                Layout.alignment: Qt.AlignRight
                                                                text: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.top_representative) ? (selectedPackHeaderCard.pItem.top_representative.value_str || "") : ""
                                                                font.bold: true
                                                                font.pixelSize: 12
                                                                color: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.top_representative && selectedPackHeaderCard.pItem.top_representative.is_max) ? Theme.maxHighlight : Theme.listValue
                                                            }

                                                            Text {
                                                                Layout.alignment: Qt.AlignRight
                                                                visible: text !== ""
                                                                text: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.top_representative) ? (selectedPackHeaderCard.pItem.top_representative.diff_with_level || "") : ""
                                                                font.bold: true
                                                                font.pixelSize: 10
                                                                color: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.top_representative) ? Theme.getDiffColor(selectedPackHeaderCard.pItem.top_representative.diff_color_tag) : Theme.textMuted
                                                            }
                                                        }

                                                        // Thumbnail (30x30) on right
                                                        Rectangle {
                                                            width: 30
                                                            height: 30
                                                            radius: 4
                                                            clip: true
                                                            color: "transparent"

                                                            Image {
                                                                id: selectedPackTopThumb
                                                                anchors.fill: parent
                                                                source: {
                                                                    var _v = statsRoot.thumbnailVersion
                                                                    return ((statsHandler || statisticsHandler) && selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.top_representative && selectedPackHeaderCard.pItem.top_representative.song_id) ? (statsHandler || statisticsHandler).getThumbnailPathForDifficulty(selectedPackHeaderCard.pItem.top_representative.song_id, selectedPackHeaderCard.pItem.top_representative.diff_index >= 0 ? selectedPackHeaderCard.pItem.top_representative.diff_index : 2) : ""
                                                                }
                                                                fillMode: Image.PreserveAspectCrop
                                                                asynchronous: true
                                                                cache: true
                                                                smooth: true
                                                                antialiasing: true
                                                                visible: status === Image.Ready
                                                            }
                                                        }
                                                    }
                                                }

                                                // Case 1 Counts Container: Vertically centered in remaining space between capsule and mini bar
                                                Item {
                                                    id: selectedPackCountsContainer
                                                    visible: selectedPackRightArea.hasRepSong
                                                    anchors.right: parent.right
                                                    anchors.left: parent.left
                                                    anchors.top: selectedPackRepCapsule.bottom
                                                    anchors.bottom: parent.bottom

                                                    Text {
                                                        id: selectedPackCountsText
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.verticalCenterOffset: 2.5
                                                        textFormat: Text.StyledText
                                                        font.bold: true
                                                        font.pixelSize: 11
                                                        text: selectedPackHeaderCard.pItem ? ("<font color='" + Theme.clearFullRecall + "'>" + (selectedPackHeaderCard.pItem.frpm_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.clearComplete + "'>" + (selectedPackHeaderCard.pItem.clr_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.textMuted + "'>" + (selectedPackHeaderCard.pItem.all_count || 0) + "</font>") : ""
                                                    }
                                                }

                                                // ==========================================
                                                // Case 2: Other Display Value (Line 1 = displayValue 13px bold, Line 2 = counts 11px bold)
                                                // 1:1 Horizontal Alignment with Left Area (Pack Name & Songs Count)
                                                // ==========================================
                                                ColumnLayout {
                                                    id: selectedPackDisplayValCol
                                                    visible: selectedPackRightArea.hasDisplayVal
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2

                                                    Text {
                                                        Layout.alignment: Qt.AlignRight
                                                        text: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.displayValue) ? selectedPackHeaderCard.pItem.displayValue : ""
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: Theme.listValue
                                                    }

                                                    Text {
                                                        Layout.alignment: Qt.AlignRight
                                                        textFormat: Text.StyledText
                                                        font.bold: true
                                                        font.pixelSize: 11
                                                        text: selectedPackHeaderCard.pItem ? ("<font color='" + Theme.clearFullRecall + "'>" + (selectedPackHeaderCard.pItem.frpm_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.clearComplete + "'>" + (selectedPackHeaderCard.pItem.clr_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.textMuted + "'>" + (selectedPackHeaderCard.pItem.all_count || 0) + "</font>") : ""
                                                    }
                                                }

                                                // ==========================================
                                                // Case 3: Title Mode (Standalone centered counts 13px bold)
                                                // ==========================================
                                                Text {
                                                    id: selectedPackStandaloneCountsText
                                                    visible: !selectedPackRightArea.hasRepSong && !selectedPackRightArea.hasDisplayVal
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    textFormat: Text.StyledText
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                    text: selectedPackHeaderCard.pItem ? ("<font color='" + Theme.clearFullRecall + "'>" + (selectedPackHeaderCard.pItem.frpm_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.clearComplete + "'>" + (selectedPackHeaderCard.pItem.clr_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.textMuted + "'>" + (selectedPackHeaderCard.pItem.all_count || 0) + "</font>") : ""
                                                }
                                            }
                                        }

                                        function getAnchoredPackContentY(targetPackId) {
                                            var items = (statisticsHandler ? statisticsHandler.packItems : null) || packListView.model || []
                                            var targetIndex = -1
                                            for (var i = 0; i < items.length; i++) {
                                                if (items[i] && items[i].id === targetPackId) {
                                                    targetIndex = i
                                                    break
                                                }
                                            }
                                            if (targetIndex < 0) return 0

                                            var itemPitch = 92 // 84px card + 8px spacing
                                            var desiredY = targetIndex * itemPitch
                                            var totalContentHeight = Math.max(0, items.length * itemPitch - 8)
                                            var maxScrollY = Math.max(0, totalContentHeight - packListView.height)
                                            return Math.max(0, Math.min(desiredY, maxScrollY))
                                        }

                                        MouseArea {
                                            id: selectedPackHeaderMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (statisticsHandler) {
                                                    var currentPackId = selectedPackHeaderCard.pItem ? selectedPackHeaderCard.pItem.id : null
                                                    if (currentPackId) {
                                                        packListView.contentY = selectedPackHeaderCard.getAnchoredPackContentY(currentPackId)
                                                    }
                                                    packListFadeIn.stop()
                                                    packListView.opacity = 0.0
                                                    statisticsHandler.clearPackSelection()
                                                }
                                            }
                                        }
                                    }

                                    // Bottom Scrollable Song List
                                    ListView {
                                        id: packSongListView
                                        anchors.top: selectedPackHeaderCard.bottom
                                        anchors.topMargin: 5
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        clip: true
                                        topMargin: 3
                                        model: (selectedPackHeaderCard.pItem && selectedPackHeaderCard.pItem.songs) ? selectedPackHeaderCard.pItem.songs : []
                                        spacing: 6
                                        delegate: packSongDelegate

                                        function scrollToSelectedSong() {
                                            if (!statsRoot.currentSong || !model || model.length === 0) return
                                            var targetDbId = statsRoot.currentSong.songDbId
                                            var targetArcaeaId = statsRoot.currentSong.arcaeaId
                                            for (var i = 0; i < model.length; i++) {
                                                var s = model[i]
                                                if ((targetDbId !== undefined && s.songDbId === targetDbId) || (targetArcaeaId && (s.arcaeaId === targetArcaeaId || s.id === targetArcaeaId))) {
                                                    var songIdx = i
                                                    Qt.callLater(function() {
                                                        if (packSongListView.visible) {
                                                            packSongListView.positionViewAtIndex(songIdx, ListView.Contain)
                                                            Qt.callLater(function() {
                                                                if (packSongListView.visible) {
                                                                    packSongListView.positionViewAtIndex(songIdx, ListView.Contain)
                                                                }
                                                            })
                                                        }
                                                    })
                                                    break
                                                }
                                            }
                                        }

                                        onModelChanged: scrollToSelectedSong()
                                    }
                                }
                                
                                Connections {
                                    target: statsRoot

                                    function onIsPackModeChanged() {
                                        if (statsRoot.isPackMode) {
                                            if (!statsRoot.isPackSelected) {
                                                packListFadeIn.stop()
                                                packListView.opacity = 0.0
                                                Qt.callLater(function() {
                                                    if (packListView.visible) {
                                                        packListFadeIn.restart()
                                                    } else {
                                                        packListView.opacity = 1.0
                                                    }
                                                })
                                            } else {
                                                packStackFadeIn.stop()
                                                packDetailStackContainer.opacity = 0.0
                                                if (typeof packSongListView !== "undefined") {
                                                    packSongListView.scrollToSelectedSong()
                                                }
                                                Qt.callLater(function() {
                                                    if (packDetailStackContainer.visible) {
                                                        packStackFadeIn.restart()
                                                    } else {
                                                        packDetailStackContainer.opacity = 1.0
                                                    }
                                                })
                                            }
                                        }
                                    }

                                    function onIsPackSelectedChanged() {
                                        if (statsRoot.isPackSelected) {
                                            packStackFadeIn.stop()
                                            packDetailStackContainer.opacity = 0.0
                                            if (typeof packSongListView !== "undefined") {
                                                packSongListView.scrollToSelectedSong()
                                            }
                                            Qt.callLater(function() {
                                                if (packDetailStackContainer.visible) {
                                                    packStackFadeIn.restart()
                                                } else {
                                                    packDetailStackContainer.opacity = 1.0
                                                }
                                            })
                                        } else {
                                            packListFadeIn.stop()
                                            packListView.opacity = 0.0
                                            var currentPackId = selectedPackHeaderCard.pItem ? selectedPackHeaderCard.pItem.id : null
                                            var targetIndex = -1
                                            var items = (statisticsHandler ? statisticsHandler.packItems : null) || []
                                            for (var i = 0; i < items.length; i++) {
                                                if (items[i] && items[i].id === currentPackId) {
                                                    targetIndex = i
                                                    break
                                                }
                                            }
                                            if (targetIndex < 0) {
                                                packListView.contentY = 0
                                            }
                                            Qt.callLater(function() {
                                                if (packListView.visible) {
                                                    packListFadeIn.restart()
                                                } else {
                                                    packListView.opacity = 1.0
                                                }
                                            })
                                        }
                                    }
                                }
                                
                                // Auto-scroll to selected item when list data changes (sort/filter/mode)
                                Connections {
                                    id: listScrollConnections
                                    target: statisticsHandler
                                    property bool isScrollPending: false

                                    function triggerScroll(mode, isReset) {
                                        if (isReset) {
                                            if (songListView.visible) {
                                                songListFadeIn.stop()
                                                songListView.opacity = 0.0
                                            } else if (packListView.visible) {
                                                packListFadeIn.stop()
                                                packListView.opacity = 0.0
                                            } else if (packDetailStackContainer.visible) {
                                                packStackFadeIn.stop()
                                                packDetailStackContainer.opacity = 0.0
                                            }
                                        }
                                        if (isScrollPending) return
                                        isScrollPending = true

                                        // Pass 1: 뷰포트 인덱스 1차 이동
                                        Qt.callLater(function() {
                                            if (statisticsHandler && songListView.visible) {
                                                var idx = statisticsHandler.selectedIndex
                                                if (idx >= 0 && idx < songListView.count) {
                                                    songListView.positionViewAtIndex(idx, mode)
                                                }
                                            } else if (packDetailStackContainer.visible) {
                                                if (typeof packSongListView !== "undefined") {
                                                    packSongListView.scrollToSelectedSong()
                                                }
                                            }

                                            // Pass 2: delegate 지오메트리 측정 완료 후 정밀 재포지셔닝 & 페이드인
                                            Qt.callLater(function() {
                                                isScrollPending = false
                                                if (statisticsHandler && songListView.visible) {
                                                    var idx2 = statisticsHandler.selectedIndex
                                                    if (idx2 >= 0 && idx2 < songListView.count) {
                                                        songListView.positionViewAtIndex(idx2, mode)
                                                    }
                                                }
                                                if (songListView.visible) {
                                                    if (songListView.opacity < 1.0) {
                                                        songListFadeIn.restart()
                                                    } else {
                                                        songListView.opacity = 1.0
                                                    }
                                                } else if (packListView.visible) {
                                                    if (packListView.opacity < 1.0) {
                                                        packListFadeIn.restart()
                                                    } else {
                                                        packListView.opacity = 1.0
                                                    }
                                                } else if (packDetailStackContainer.visible) {
                                                    if (packDetailStackContainer.opacity < 1.0) {
                                                        packStackFadeIn.restart()
                                                    } else {
                                                        packDetailStackContainer.opacity = 1.0
                                                    }
                                                }
                                            })
                                        })
                                    }

                                    function onDataChanged() {
                                        // Song <-> Chart 모드 전환 등 리셋 시 Contain 우선: 뷰포트 흔들림 0% 보장
                                        triggerScroll(ListView.Contain, true)
                                    }
                                    function onSelectedItemChanged() {
                                        triggerScroll(ListView.Contain, false)
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
                                                color: "transparent"
                                                clip: true
                                                
                                                Image {
                                                    id: thumbImage
                                                    anchors.fill: parent
                                                    anchors.margins: -1 // Slight negative margin to avoid edge artifacts
                                                    source: {
                                                        var _v = statsRoot.thumbnailVersion
                                                        return statsHandler ? statsHandler.getThumbnailPathForDifficulty(rowModel.arcaeaId || "", rowModel.thumbnailDifficulty !== undefined ? rowModel.thumbnailDifficulty : rowModel.difficulty) : ""
                                                    }
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    cache: true
                                                    smooth: true
                                                    antialiasing: true
                                                    sourceSize: Qt.size(width * 2, height * 2)
                                                    visible: status === Image.Ready
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
                                                        if ((mode === "notes" || mode === "note_count") && rowModel.bestDiffForNoteCount >= 0) return rowModel.bestDiffForNoteCount
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
                                                                    color: isHighlighted ? Theme.getDiffColor(modelData.diffColorTag || modelData.difficulty) : Theme.textDimmed
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
                                                                    anchors.topMargin: isValueAbove ? -3 : 0
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
                                                                color: Theme.getDiffColor(rowModel.diffColorTag || rowModel.difficulty)
                                                            }
                                                            Text {
                                                                id: chartLevelNumText
                                                                text: String(rowModel.level || "")
                                                                font.bold: true
                                                                font.pixelSize: parent.parent.isStandaloneMode ? 13 : 11
                                                                color: Theme.getDiffColor(rowModel.diffColorTag || rowModel.difficulty)
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
                                                            anchors.topMargin: isValueAbove ? -3 : 0
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

                                // Delegate Component for Pack ListView
                                Component {
                                    id: packDelegate

                                    Rectangle {
                                        id: packDelegateRoot
                                        width: ListView.view ? ListView.view.width : parent.width
                                        height: 84
                                        Layout.preferredHeight: 84
                                        radius: 10
                                        color: packHeaderMouse.containsMouse ? Theme.bgItemHover : Theme.bgCard
                                        border.width: 0
                                        clip: true
                                        property var packItem: modelData

                                        // 1. Bottom Mini 7-stage clear lamp bar (Absolute bottom-pinned)
                                        Item {
                                            id: packMiniBarItem
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.bottomMargin: 7
                                            height: 5
                                            clip: true

                                            Rectangle {
                                                id: miniBarBg
                                                anchors.fill: parent
                                                radius: 2.5
                                                color: Theme.isDarkMode ? "#35353E" : "#E2E2E8"
                                                clip: true

                                                Row {
                                                    anchors.fill: parent
                                                    spacing: 0

                                                    property var lamps: packItem.lamp_counts || ({})
                                                    property int totalC: (packItem.all_count && packItem.all_count > 0) ? packItem.all_count : 1
                                                    property real w: miniBarBg.width

                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.pm ? (parent.lamps.pm / parent.totalC) * parent.w : 0
                                                        color: Theme.clearPureMemory
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.fr ? (parent.lamps.fr / parent.totalC) * parent.w : 0
                                                        color: Theme.clearFullRecall
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.hard ? (parent.lamps.hard / parent.totalC) * parent.w : 0
                                                        color: Theme.clearHard
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.complete ? (parent.lamps.complete / parent.totalC) * parent.w : 0
                                                        color: Theme.clearComplete
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.easy ? (parent.lamps.easy / parent.totalC) * parent.w : 0
                                                        color: Theme.clearEasy
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.lost ? (parent.lamps.lost / parent.totalC) * parent.w : 0
                                                        color: Theme.clearLost
                                                    }
                                                    Rectangle {
                                                        height: parent.height
                                                        width: parent.lamps.unplayed ? (parent.lamps.unplayed / parent.totalC) * parent.w : 0
                                                        color: Theme.scoreRankNone
                                                    }
                                                }
                                            }
                                        }

                                        // 2. Main Content Area (Independent from mini bar, fills between card top and mini bar)
                                        Item {
                                            id: packContentArea
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: packMiniBarItem.top
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 7
                                            anchors.bottomMargin: 6

                                            // Left Area: Pack Name / Songs Count (Independent vertical centering)
                                            RowLayout {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.right: packRightArea.left
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                // Pack Index
                                                Text {
                                                    text: index + 1
                                                    font.pixelSize: 11
                                                    color: Theme.textMuted
                                                    Layout.preferredWidth: 22
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 2

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: packItem.name || ""
                                                        font.family: statsRoot.titleFontFamily
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: Theme.textPrimary
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: (packItem.song_count || 0) + " songs • " + (packItem.chart_count || 0) + " charts"
                                                        font.pixelSize: 11
                                                        color: Theme.textMuted
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            // Right Area: 3-Tier Branch Layout (Case 1: Rep Song Option 2, Case 2: Display Value Grid, Case 3: Standalone Counts)
                                            Item {
                                                id: packRightArea
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: Math.max(
                                                    hasRepSong ? packRepCapsule.implicitWidth : (hasDisplayVal ? packDisplayValCol.implicitWidth : 0),
                                                    hasRepSong ? packCountsText.implicitWidth : (hasDisplayVal ? 0 : packStandaloneCountsText.implicitWidth)
                                                )

                                                readonly property bool hasRepSong: Boolean(packItem.top_representative && packItem.top_representative.has_song)
                                                readonly property bool hasDisplayVal: Boolean(!hasRepSong && packItem.displayValue && packItem.displayValue !== "")

                                                // ==========================================
                                                // Case 1: Representative Song with Capsule Box (Option 2: 30x30 Thumb, 34px Capsule, ~9.5px Gap)
                                                // ==========================================
                                                Rectangle {
                                                    id: packRepCapsule
                                                    visible: packRightArea.hasRepSong
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 1
                                                    implicitWidth: packRepSongRow.implicitWidth + 10
                                                    implicitHeight: packRepSongRow.implicitHeight + 4
                                                    radius: 5
                                                    color: Theme.bgCapsule
                                                    border.width: 1
                                                    border.color: Theme.borderSubtle

                                                    RowLayout {
                                                        id: packRepSongRow
                                                        anchors.centerIn: parent
                                                        spacing: 5

                                                        // Song stats (right-aligned, 2 lines without title)
                                                        ColumnLayout {
                                                            spacing: 0
                                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                                                            Text {
                                                                Layout.alignment: Qt.AlignRight
                                                                text: packItem.top_representative ? (packItem.top_representative.value_str || "") : ""
                                                                font.bold: true
                                                                font.pixelSize: 12
                                                                color: (packItem.top_representative && packItem.top_representative.is_max) ? Theme.maxHighlight : Theme.listValue
                                                            }

                                                            Text {
                                                                Layout.alignment: Qt.AlignRight
                                                                visible: text !== ""
                                                                text: packItem.top_representative ? (packItem.top_representative.diff_with_level || "") : ""
                                                                font.bold: true
                                                                font.pixelSize: 10
                                                                color: packItem.top_representative ? Theme.getDiffColor(packItem.top_representative.diff_color_tag) : Theme.textMuted
                                                            }
                                                        }

                                                        // Thumbnail (30x30) on right
                                                        Rectangle {
                                                            width: 30
                                                            height: 30
                                                            radius: 4
                                                            clip: true
                                                            color: "transparent"

                                                            Image {
                                                                id: packTopThumb
                                                                anchors.fill: parent
                                                                source: {
                                                                    var _v = statsRoot.thumbnailVersion
                                                                    return ((statsHandler || statisticsHandler) && packItem.top_representative && packItem.top_representative.song_id) ? (statsHandler || statisticsHandler).getThumbnailPathForDifficulty(packItem.top_representative.song_id, packItem.top_representative.diff_index >= 0 ? packItem.top_representative.diff_index : 2) : ""
                                                                }
                                                                fillMode: Image.PreserveAspectCrop
                                                                asynchronous: true
                                                                cache: true
                                                                smooth: true
                                                                antialiasing: true
                                                                visible: status === Image.Ready
                                                            }


                                                        }
                                                    }
                                                }

                                                // Case 1 Counts Container: Vertically centered in remaining space between capsule and mini bar
                                                Item {
                                                    id: packCountsContainer
                                                    visible: packRightArea.hasRepSong
                                                    anchors.right: parent.right
                                                    anchors.left: parent.left
                                                    anchors.top: packRepCapsule.bottom
                                                    anchors.bottom: parent.bottom

                                                    Text {
                                                        id: packCountsText
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.verticalCenterOffset: 2.5
                                                        textFormat: Text.StyledText
                                                        font.bold: true
                                                        font.pixelSize: 11
                                                        text: "<font color='" + Theme.clearFullRecall + "'>" + (packItem.frpm_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.clearComplete + "'>" + (packItem.clr_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.textMuted + "'>" + (packItem.all_count || 0) + "</font>"
                                                    }
                                                }

                                                // ==========================================
                                                // Case 2: Other Display Value (Line 1 = displayValue 13px bold, Line 2 = counts 11px bold)
                                                // 1:1 Horizontal Alignment with Left Area (Pack Name & Songs Count)
                                                // ==========================================
                                                ColumnLayout {
                                                    id: packDisplayValCol
                                                    visible: packRightArea.hasDisplayVal
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2

                                                    Text {
                                                        Layout.alignment: Qt.AlignRight
                                                        text: packItem.displayValue || ""
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: Theme.listValue
                                                    }

                                                    Text {
                                                        Layout.alignment: Qt.AlignRight
                                                        textFormat: Text.StyledText
                                                        font.bold: true
                                                        font.pixelSize: 11
                                                        text: "<font color='" + Theme.clearFullRecall + "'>" + (packItem.frpm_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.clearComplete + "'>" + (packItem.clr_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.textMuted + "'>" + (packItem.all_count || 0) + "</font>"
                                                    }
                                                }

                                                // ==========================================
                                                // Case 3: Title Mode (Standalone centered counts 13px bold)
                                                // ==========================================
                                                Text {
                                                    id: packStandaloneCountsText
                                                    visible: !packRightArea.hasRepSong && !packRightArea.hasDisplayVal
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    textFormat: Text.StyledText
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                    text: "<font color='" + Theme.clearFullRecall + "'>" + (packItem.frpm_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.clearComplete + "'>" + (packItem.clr_count || 0) + "</font><font color='" + Theme.textMuted + "'> - </font><font color='" + Theme.textMuted + "'>" + (packItem.all_count || 0) + "</font>"
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: packHeaderMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                statsRoot.savedPackContentY = packListView.contentY
                                                packStackFadeIn.stop()
                                                packDetailStackContainer.opacity = 0.0
                                                if (statisticsHandler) {
                                                    statisticsHandler.togglePackExpansion(packItem.id)
                                                }
                                                var narrow = (typeof statsRoot !== "undefined") ? Boolean(statsRoot.isNarrow) : false
                                                if (narrow) {
                                                    mobileStack.push(detailPageComponent)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Delegate Component for Pack's Sub-Songs in Stack View
                                Component {
                                    id: packSongDelegate

                                    Rectangle {
                                        id: songItemRect
                                        width: ListView.view ? ListView.view.width : parent.width
                                        height: 70
                                        radius: 10

                                        property var songItemData: modelData
                                        readonly property bool isSelected: (typeof statsRoot !== "undefined" && !statsRoot.isNarrow) && Boolean(
                                            statisticsHandler && !statisticsHandler.isPackDetailView && statsRoot.currentSong &&
                                            (statsRoot.currentSong.songDbId !== undefined && songItemData.songDbId !== undefined ?
                                                statsRoot.currentSong.songDbId === songItemData.songDbId :
                                                (statsRoot.currentSong.arcaeaId && statsRoot.currentSong.arcaeaId === (songItemData.arcaeaId || songItemData.id)))
                                        )

                                        color: isSelected ? Theme.bgSelected : (songItemHover.containsMouse ? Theme.bgItemHover : "transparent")
                                        border.width: isSelected ? 1 : 0
                                        border.color: Theme.borderSelected

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
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

                                            // Thumbnail (jacket image with fallback)
                                            Rectangle {
                                                id: thumbRect
                                                width: 48
                                                height: 48
                                                radius: 6
                                                color: "transparent"
                                                clip: true

                                                Image {
                                                    id: thumbImage
                                                    anchors.fill: parent
                                                    anchors.margins: -1
                                                    asynchronous: true
                                                    cache: true
                                                    source: {
                                                        var _v = statsRoot.thumbnailVersion
                                                        return (statsHandler || statisticsHandler) ? (statsHandler || statisticsHandler).getThumbnailPathForDifficulty(songItemData.arcaeaId || songItemData.id || "", songItemData.thumbnailDifficulty !== undefined ? songItemData.thumbnailDifficulty : 2) : ""
                                                    }
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    antialiasing: true
                                                    sourceSize: Qt.size(width * 2, height * 2)
                                                    visible: status === Image.Ready
                                                }


                                            }

                                            // Title & Artist
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: songItemData.title || ""
                                                    font.family: statsRoot.titleFontFamily
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                    color: Theme.textPrimary
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: songItemData.artist || ""
                                                    font.family: statsRoot.titleFontFamily
                                                    font.pixelSize: 11
                                                    color: Theme.textMuted
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            // Right: Difficulties Slash Bar
                                            ColumnLayout {
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                                spacing: 2

                                                readonly property bool isTitleSort: Boolean(statisticsHandler && statisticsHandler.sortMode === "title")
                                                readonly property bool isVersionSort: Boolean(statisticsHandler && statisticsHandler.sortMode === "version")
                                                readonly property bool isLevelSort: Boolean(statisticsHandler && statisticsHandler.sortMode === "level")
                                                readonly property bool isStandaloneMode: isTitleSort || isVersionSort || isLevelSort

                                                // Highlighted diff computed from songItemData
                                                property int highlightedDiff: {
                                                    if (!statisticsHandler) return -1
                                                    var mode = statisticsHandler.sortMode
                                                    if (mode === "max") return songItemData.bestDiffForMax >= 0 ? songItemData.bestDiffForMax : -1
                                                    if (mode === "recent_played") return songItemData.bestDiffForRecent >= 0 ? songItemData.bestDiffForRecent : -1
                                                    if (mode === "level") return songItemData.bestDiffForLevel >= 0 ? songItemData.bestDiffForLevel : -1
                                                    if (mode === "s_bp") return songItemData.bestDiffForSBp >= 0 ? songItemData.bestDiffForSBp : -1
                                                    if (mode === "perceived_bp") return songItemData.bestDiffForPerceivedBp >= 0 ? songItemData.bestDiffForPerceivedBp : -1
                                                    if (mode === "potential") return songItemData.bestDiffForPotential >= 0 ? songItemData.bestDiffForPotential : -1
                                                    if ((mode === "notes" || mode === "note_count") && songItemData.bestDiffForNoteCount >= 0) return songItemData.bestDiffForNoteCount
                                                    return -1
                                                }

                                                // Display Value (score, MAX, play count, BPM, etc.)
                                                Text {
                                                    Layout.alignment: Qt.AlignRight
                                                    text: songItemData.displayValue || ""
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                    color: (text === "MAX") ? Theme.maxHighlight : Theme.listValue
                                                    visible: !parent.isStandaloneMode && text !== ""
                                                }

                                                // Score of the highlighted difficulty (shown when not in score sort)
                                                Text {
                                                    id: packSongHighlightedScoreText
                                                    Layout.alignment: Qt.AlignRight
                                                    property bool isLevelSort: statisticsHandler && statisticsHandler.sortMode === "level"
                                                    font.pixelSize: 11
                                                    font.bold: isLevelSort
                                                    color: Theme.listValue
                                                    property int highlightedDiff: parent.highlightedDiff
                                                    property int songScore: {
                                                        if (highlightedDiff < 0) return 0
                                                        var diffs = songItemData.filteredDifficulties || []
                                                        for (var i = 0; i < diffs.length; i++) {
                                                            if (diffs[i].difficulty === highlightedDiff) return diffs[i].score || 0
                                                        }
                                                        return 0
                                                    }
                                                    property bool songHasScore: {
                                                        if (highlightedDiff < 0) return false
                                                        var diffs = songItemData.filteredDifficulties || []
                                                        for (var i = 0; i < diffs.length; i++) {
                                                            if (diffs[i].difficulty === highlightedDiff) return diffs[i].hasScore || false
                                                        }
                                                        return false
                                                    }
                                                    text: songHasScore ? songScore.toLocaleString(Qt.locale("en_US"), 'f', 0) : "-"
                                                    visible: Boolean(statisticsHandler && statisticsHandler.sortMode !== "score" && statisticsHandler.sortMode !== "notes" && statisticsHandler.sortMode !== "note_count" && !parent.isStandaloneMode && highlightedDiff >= 0)
                                                }

                                                // Difficulties Slash Bar
                                                Row {
                                                    id: packSongDifficultyRow
                                                    Layout.alignment: Qt.AlignRight
                                                    spacing: 0
                                                    visible: Boolean(songItemData.filteredDifficulties && songItemData.filteredDifficulties.length > 0)

                                                    function getBestDiffForSort() {
                                                        if (!statisticsHandler) return -1
                                                        var mode = statisticsHandler.sortMode
                                                        if (mode === "score" && songItemData.bestDiffForScore >= 0) return songItemData.bestDiffForScore
                                                        if (mode === "max" && songItemData.bestDiffForMax >= 0) return songItemData.bestDiffForMax
                                                        if (mode === "recent_played" && songItemData.bestDiffForRecent >= 0) return songItemData.bestDiffForRecent
                                                        if (mode === "level" && songItemData.bestDiffForLevel >= 0) return songItemData.bestDiffForLevel
                                                        if (mode === "s_bp" && songItemData.bestDiffForSBp >= 0) return songItemData.bestDiffForSBp
                                                        if (mode === "perceived_bp" && songItemData.bestDiffForPerceivedBp >= 0) return songItemData.bestDiffForPerceivedBp
                                                        if (mode === "potential" && songItemData.bestDiffForPotential >= 0) return songItemData.bestDiffForPotential
                                                        if ((mode === "notes" || mode === "note_count") && songItemData.bestDiffForNoteCount >= 0) return songItemData.bestDiffForNoteCount
                                                        return -1
                                                    }
                                                    property int bestDiff: getBestDiffForSort()

                                                    Repeater {
                                                        model: songItemData.filteredDifficulties || []

                                                        Row {
                                                            property bool isHighlighted: {
                                                                if (packSongDifficultyRow.bestDiff < 0) return true
                                                                return modelData.difficulty === packSongDifficultyRow.bestDiff
                                                            }
                                                            spacing: 0

                                                            Text {
                                                                text: " / "
                                                                font.pixelSize: parent.parent.parent.isStandaloneMode ? 13 : 11
                                                                color: Theme.textFaint
                                                                visible: index > 0
                                                            }

                                                            Item {
                                                                width: levelText.width
                                                                height: levelText.height

                                                                Text {
                                                                    id: levelText
                                                                    text: String(modelData.level || "")
                                                                    font.bold: true
                                                                    font.pixelSize: parent.parent.parent.parent.isStandaloneMode ? 13 : 11
                                                                    color: isHighlighted ? Theme.getDiffColor(modelData.diffColorTag || modelData.difficulty) : Theme.textDimmed
                                                                }

                                                                Row {
                                                                    property bool isValueAbove: Boolean((packSongHighlightedScoreText && packSongHighlightedScoreText.visible) || (!parent.parent.parent.parent.isStandaloneMode && songItemData.displayValue && songItemData.displayValue !== ""))
                                                                    property string lvlStr: String(modelData.level || "")
                                                                    z: 10
                                                                    spacing: -2
                                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                                    anchors.horizontalCenterOffset: (lvlStr === "10" || lvlStr === "11") ? 1 : 0
                                                                    anchors.top: isValueAbove ? parent.bottom : undefined
                                                                    anchors.bottom: isValueAbove ? undefined : parent.top
                                                                    anchors.topMargin: isValueAbove ? -3 : 0
                                                                    anchors.bottomMargin: isValueAbove ? 0 : -2
                                                                    visible: Boolean((modelData.ignoreChart || false) || (modelData.skillIssues || false) || (modelData.hardBpm || false))

                                                                    Text {
                                                                        text: "⛔"
                                                                        font.pixelSize: 6
                                                                        visible: Boolean(modelData.ignoreChart)
                                                                    }
                                                                    Text {
                                                                        text: "⚠️"
                                                                        font.pixelSize: 6
                                                                        visible: Boolean(modelData.skillIssues)
                                                                    }
                                                                    Text {
                                                                        text: "⏪"
                                                                        font.pixelSize: 6
                                                                        visible: Boolean(modelData.hardBpm)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // BP value in parentheses for level sort
                                                    Text {
                                                        text: " (" + (songItemData.bp ? songItemData.bp.toFixed(1) : "0.0") + ")"
                                                        font.bold: true
                                                        font.pixelSize: 13
                                                        color: Theme.listValue
                                                        visible: parent.parent.isLevelSort
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: songItemHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (statisticsHandler && statisticsHandler.currentPack) {
                                                    statisticsHandler.selectPackSong(statisticsHandler.currentPack.id, songItemData.songDbId || songItemData.id)
                                                }
                                                var narrow = (typeof statsRoot !== "undefined") ? Boolean(statsRoot.isNarrow) : false
                                                if (narrow) {
                                                    mobileStack.push(detailPageComponent)
                                                }
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
                                    visible: !statsRoot.isPackMode && songListView.count === 0
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "No packs found"
                                    color: Theme.textLight
                                    font.pixelSize: 14
                                    visible: statsRoot.isPackMode && !statsRoot.isPackSelected && packListView.count === 0
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "No songs found in this pack"
                                    color: Theme.textLight
                                    font.pixelSize: 14
                                    visible: statsRoot.isPackMode && statsRoot.isPackSelected && packSongListView.count === 0
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
            
            // 트랜지션 중에는 캐시된 직전 곡을 공급하여 difficultiesToShow 및 하위 카드 전체 증발 차단
            property var currentSong: (typeof detailedViewStackContainer !== "undefined" && ((detailedViewStackContainer.isCrossfading && detailedViewStackContainer.isPackDashboardTarget && detailedViewStackContainer.wasSongSelectedBeforeTransition) || detailedViewStackContainer.isDeselectingPack) && detailedViewStackContainer.cachedLastSong)
                ? detailedViewStackContainer.cachedLastSong
                : statsRoot.currentSong

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
                        Text {
                            text: (statisticsHandler && statisticsHandler.displayMode === "pack" && statisticsHandler.isPackDetailView) ? "Pack Detail" : "Song Detail"
                            font.bold: true
                            color: Theme.textPrimary
                            font.pixelSize: 16
                        }
                        Item { Layout.fillWidth: true }
                        Item { width: 40 }
                    }
                }

                // [Detailed View Stack Container (Fade-Over Overlay)]
                Item {
                    id: detailedViewStackContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    readonly property bool isPackDashboardTarget: Boolean(statisticsHandler && statisticsHandler.displayMode === "pack" && statisticsHandler.isPackDetailView)
                    property bool isCrossfading: false
                    onIsCrossfadingChanged: {
                        statsRoot.isDetailedViewCrossfading = isCrossfading
                    }
                    property bool isDeselectingPack: false
                    onIsDeselectingPackChanged: {
                        statsRoot.isDeselectingPack = isDeselectingPack
                    }
                    property bool wasInPackDetailViewBeforeDeselect: true
                    property bool wasPackSelected: false
                    property bool wasSongSelected: false
                    property bool wasPackSelectedBeforeTransition: false
                    property bool wasSongSelectedBeforeTransition: false
                    property var cachedLastSong: null
                    property var cachedLastPack: null
                    property bool wasInPackSubSong: false
                    property bool isReturningFromPackSubSong: false

                    function startPackSubSongDeselectTransition() {
                        isDeselectingPack = true;
                        wasInPackDetailViewBeforeDeselect = false;
                        isReturningFromPackSubSong = true;
                        statsRoot.isDetailedViewCrossfading = true;

                        if (typeof packDashboardContentFadeOut !== "undefined" && packDashboardContentFadeOut) packDashboardContentFadeOut.stop();
                        if (typeof songDetailFadeIn !== "undefined" && songDetailFadeIn) songDetailFadeIn.stop();

                        songDetailScrollView.opacity = 1.0;
                        songDetailScrollView.z = 1;
                        packDashboardScrollView.z = 0;
                        songDetailScrollView.visible = true;
                        packDashboardScrollView.visible = true;

                        songDetailFadeOut.restart();
                    }

                    function startPackDashboardDeselectTransition() {
                        isDeselectingPack = true;
                        wasInPackDetailViewBeforeDeselect = true;
                        isReturningFromPackSubSong = false;
                        statsRoot.isDetailedViewCrossfading = true;

                        if (typeof songDetailFadeIn !== "undefined" && songDetailFadeIn) songDetailFadeIn.stop();
                        if (typeof songDetailFadeOut !== "undefined" && songDetailFadeOut) songDetailFadeOut.stop();

                        songDetailScrollView.visible = false;
                        songDetailScrollView.opacity = 0.0;
                        packDashboardScrollView.visible = true;
                        packDashboardScrollView.opacity = 1.0;

                        if (typeof packDashboardContentColumn !== "undefined" && packDashboardContentColumn) {
                            packDashboardContentColumn.opacity = 1.0;
                        }
                        if (typeof packDashboardContentFadeOut !== "undefined" && packDashboardContentFadeOut) {
                            packDashboardContentFadeOut.restart();
                        }
                    }

                    Connections {
                        target: statsRoot
                        function onCurrentSongChanged() {
                            detailedViewStackContainer.wasSongSelected = Boolean(statsRoot.currentSong)
                            if (statsRoot.currentSong) {
                                detailedViewStackContainer.cachedLastSong = statsRoot.currentSong
                            }
                        }
                    }

                    Connections {
                        target: statisticsHandler
                        function onCurrentPackChanged() {
                            if (detailedViewStackContainer.isDeselectingPack) return
                            if (statisticsHandler && statisticsHandler.currentPack && statisticsHandler.currentPack.id) {
                                detailedViewStackContainer.cachedLastPack = statisticsHandler.currentPack
                                statsRoot.cachedLastPack = statisticsHandler.currentPack
                            }
                        }
                        function onIsPackDetailViewChanged() {
                            if (statisticsHandler && statisticsHandler.displayMode === "pack" && !statisticsHandler.isPackDetailView) {
                                detailedViewStackContainer.wasInPackSubSong = true
                            }
                        }
                        function onExpandedPackIdsChanged() {
                            var isSelectedNow = Boolean(statisticsHandler && statisticsHandler.expandedPackIds && statisticsHandler.expandedPackIds.length > 0)
                            if (detailedViewStackContainer.wasPackSelected && !isSelectedNow && statisticsHandler && statisticsHandler.displayMode === "pack" && !detailedViewStackContainer.isDeselectingPack) {
                                detailedViewStackContainer.startPackDashboardDeselectTransition()
                            }
                            detailedViewStackContainer.wasPackSelected = isSelectedNow
                        }
                        function onDisplayModeChanged() {
                            if (statisticsHandler && statisticsHandler.displayMode !== "pack") {
                                detailedViewStackContainer.wasInPackSubSong = false
                            }
                        }
                    }

                    onIsPackDashboardTargetChanged: {
                        wasPackSelectedBeforeTransition = wasPackSelected
                        wasSongSelectedBeforeTransition = wasSongSelected
                        statsRoot.wasPackSelectedBeforeTransition = wasPackSelected

                        var isPackDeselectingNow = Boolean(wasInPackSubSong && statisticsHandler && statisticsHandler.displayMode === "pack" && statisticsHandler.expandedPackIds && statisticsHandler.expandedPackIds.length === 0)
                        if (isPackDeselectingNow) {
                            startPackSubSongDeselectTransition()
                            return
                        }

                        if (isPackDashboardTarget && wasInPackSubSong) {
                            isReturningFromPackSubSong = true
                        } else {
                            isReturningFromPackSubSong = false
                        }
                        isCrossfading = true
                        statsRoot.isDetailedViewCrossfading = true
                        if (isPackDashboardTarget) {
                            songDetailFadeIn.stop()
                            packDashboardFadeOut.stop()
                            packDashboardScrollView.opacity = 0.0
                            songDetailScrollView.opacity = 1.0
                            packDashboardScrollView.z = 1
                            songDetailScrollView.z = 0
                            packDashboardScrollView.visible = true
                            songDetailScrollView.visible = true
                            packDashboardFadeIn.restart()
                            songDetailFadeOut.restart()
                        } else {
                            packDashboardFadeIn.stop()
                            songDetailFadeOut.stop()
                            if (typeof packDashboardContentFadeIn !== "undefined" && packDashboardContentFadeIn) {
                                packDashboardContentFadeIn.stop()
                            }
                            if (typeof packDashboardContentColumn !== "undefined" && packDashboardContentColumn && wasPackSelectedBeforeTransition) {
                                packDashboardContentColumn.opacity = 1.0
                            }
                            songDetailScrollView.opacity = 0.0
                            packDashboardScrollView.opacity = 1.0
                            songDetailScrollView.z = 1
                            packDashboardScrollView.z = 0
                            songDetailScrollView.visible = true
                            packDashboardScrollView.visible = true
                            songDetailFadeIn.restart()
                            packDashboardFadeOut.restart()
                            if (typeof bgImage !== "undefined" && bgImage) bgImage.ensureLoaded()
                            if (typeof mainThumbImage !== "undefined" && mainThumbImage) mainThumbImage.ensureLoaded()
                        }
                    }

                    Component.onCompleted: {
                        if (statsRoot.currentSong) {
                            cachedLastSong = statsRoot.currentSong
                        }
                        if (statisticsHandler && statisticsHandler.currentPack && statisticsHandler.currentPack.id) {
                            cachedLastPack = statisticsHandler.currentPack
                            statsRoot.cachedLastPack = statisticsHandler.currentPack
                        }
                        wasPackSelected = Boolean(statisticsHandler && statisticsHandler.expandedPackIds && statisticsHandler.expandedPackIds.length > 0)
                        wasSongSelected = Boolean(statsRoot.currentSong)
                        wasPackSelectedBeforeTransition = wasPackSelected
                        wasSongSelectedBeforeTransition = wasSongSelected
                        statsRoot.wasPackSelectedBeforeTransition = wasPackSelected
                        if (isPackDashboardTarget) {
                            packDashboardScrollView.visible = true
                            packDashboardScrollView.opacity = 1.0
                            songDetailScrollView.visible = false
                            songDetailScrollView.opacity = 0.0
                        } else {
                            songDetailScrollView.visible = true
                            songDetailScrollView.opacity = 1.0
                            packDashboardScrollView.visible = false
                            packDashboardScrollView.opacity = 0.0
                        }
                    }

                    // [Pack Dashboard View]
                    ScrollView {
                        id: packDashboardScrollView
                        anchors.fill: parent
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        clip: true
                        visible: detailedViewStackContainer.isPackDashboardTarget || detailedViewStackContainer.isCrossfading

                        opacity: 1.0

                        NumberAnimation {
                            id: packDashboardFadeIn
                            target: packDashboardScrollView
                            property: "opacity"
                            running: false
                            from: 0.0
                            to: 1.0
                            duration: 140
                            easing.type: Easing.OutQuad
                            onFinished: {
                                if (detailedViewStackContainer.isPackDashboardTarget) {
                                    detailedViewStackContainer.isCrossfading = false
                                    detailedViewStackContainer.isReturningFromPackSubSong = false
                                    detailedViewStackContainer.wasInPackSubSong = false
                                    detailedViewStackContainer.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                    detailedViewStackContainer.wasSongSelectedBeforeTransition = detailedViewStackContainer.wasSongSelected
                                    statsRoot.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                    songDetailScrollView.visible = false
                                    songDetailScrollView.opacity = 0.0
                                    if (typeof bgImage !== "undefined" && bgImage) bgImage.reset()
                                    if (typeof mainThumbImage !== "undefined" && mainThumbImage) mainThumbImage.reset()
                                }
                            }
                        }

                        NumberAnimation {
                            id: packDashboardFadeOut
                            target: packDashboardScrollView
                            property: "opacity"
                            running: false
                            from: 1.0
                            to: 0.0
                            duration: 140
                            easing.type: Easing.OutQuad
                            onFinished: {
                                if (!detailedViewStackContainer.isPackDashboardTarget) {
                                    detailedViewStackContainer.isCrossfading = false
                                    detailedViewStackContainer.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                    detailedViewStackContainer.wasSongSelectedBeforeTransition = detailedViewStackContainer.wasSongSelected
                                    statsRoot.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                    packDashboardScrollView.visible = false
                                    packDashboardScrollView.opacity = 0.0
                                }
                            }
                        }

                        onVisibleChanged: {
                            if (visible) {
                                if (!detailedViewStackContainer.isCrossfading) {
                                    packDashboardFadeIn.restart()
                                }
                            }
                        }

                        property var currentPack: ((detailedViewStackContainer.isCrossfading || statsRoot.isDetailedViewCrossfading || detailedViewStackContainer.isDeselectingPack) && (detailedViewStackContainer.isDeselectingPack || (!detailedViewStackContainer.isPackDashboardTarget && detailedViewStackContainer.wasPackSelectedBeforeTransition)) && (detailedViewStackContainer.cachedLastPack || statsRoot.cachedLastPack))
                            ? (detailedViewStackContainer.cachedLastPack || statsRoot.cachedLastPack)
                            : (statisticsHandler ? statisticsHandler.currentPack : null)

                        ColumnLayout {
                            width: parent.width
                            spacing: 16

                            // Empty State if no pack is selected
                            Text {
                                id: packEmptyStateText
                                visible: (!statsRoot.isPackSelected || !packDashboardScrollView.currentPack || !packDashboardScrollView.currentPack.id) && !detailedViewStackContainer.isDeselectingPack
                                text: "Select a pack from the list to view details"
                                color: Theme.textLight
                                font.pixelSize: 16
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 40
                                opacity: 1.0
                                onVisibleChanged: {
                                    if (visible) {
                                        packEmptyStateFadeIn.restart()
                                    }
                                }
                            }

                            NumberAnimation {
                                id: packEmptyStateFadeIn
                                target: packEmptyStateText
                                property: "opacity"
                                running: false
                                from: 0.0
                                to: 1.0
                                duration: 140
                                easing.type: Easing.OutQuad
                            }

                            // Content Column when currentPack is valid
                            ColumnLayout {
                                id: packDashboardContentColumn
                                Layout.fillWidth: true
                                Layout.margins: isNarrow ? 12 : 20
                                spacing: 16
                                visible: Boolean((statsRoot.isPackSelected || (detailedViewStackContainer.isCrossfading && !detailedViewStackContainer.isPackDashboardTarget && detailedViewStackContainer.wasPackSelectedBeforeTransition) || (detailedViewStackContainer.isDeselectingPack && detailedViewStackContainer.wasInPackDetailViewBeforeDeselect)) && packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.id)

                                opacity: 1.0
                                NumberAnimation on opacity {
                                    id: packDashboardContentFadeIn
                                    running: false
                                    from: 0.0
                                    to: 1.0
                                    duration: 140
                                }

                                NumberAnimation {
                                    id: packDashboardContentFadeOut
                                    target: packDashboardContentColumn
                                    property: "opacity"
                                    running: false
                                    from: 1.0
                                    to: 0.0
                                    duration: 140
                                    easing.type: Easing.OutQuad
                                    onFinished: {
                                        if (detailedViewStackContainer.isDeselectingPack) {
                                            detailedViewStackContainer.isDeselectingPack = false
                                            detailedViewStackContainer.wasInPackSubSong = false
                                            statsRoot.isDetailedViewCrossfading = false
                                            packDashboardContentColumn.opacity = 1.0
                                        }
                                    }
                                }

                                onVisibleChanged: {
                                    if (visible) {
                                        if (!detailedViewStackContainer.isCrossfading && !statsRoot.isDetailedViewCrossfading && !detailedViewStackContainer.isDeselectingPack) {
                                            packDashboardContentFadeIn.restart()
                                        } else {
                                            packDashboardContentColumn.opacity = 1.0
                                        }
                                    }
                                }

                            // 1. Pack Hero Card
                            Rectangle {
                                id: packHeroCard
                                Layout.fillWidth: true
                                implicitHeight: heroCardColLayout.implicitHeight + (isNarrow ? 24 : 40)
                                Layout.preferredHeight: implicitHeight
                                radius: 16
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.borderDivider
                                clip: true

                                // 1. Fallback Background
                                Rectangle {
                                    anchors.fill: parent
                                    color: Theme.bannerFallback
                                }

                                // 2. Blurred Background Image (Most Played Song Thumbnail)
                                Image {
                                    id: packHeroBgImage
                                    anchors.fill: parent
                                    anchors.margins: -20
                                    asynchronous: true
                                    cache: true
                                    source: {
                                        var _v = statsRoot.thumbnailVersion
                                        if (!packDashboardScrollView.currentPack) return ""
                                        var p = packDashboardScrollView.currentPack
                                        if (p.most_played_jacket_path) {
                                            return "file:///" + p.most_played_jacket_path.replace(/\\/g, "/")
                                        }
                                        if (statsHandler && p.most_played_song_id) {
                                            return statsHandler.getThumbnailPathForDifficulty(p.most_played_song_id, p.most_played_thumb_diff !== undefined ? p.most_played_thumb_diff : 2)
                                        }
                                        return ""
                                    }
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

                                // 3. Dimming Overlay
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    color: Theme.overlay
                                }

                                ColumnLayout {
                                    id: heroCardColLayout
                                    z: 1
                                    anchors.fill: parent
                                    anchors.margins: isNarrow ? 12 : 20
                                    spacing: 14

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 16

                                        // Left: Title, Badges, Total Plays
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                text: (packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.name : "") || ""
                                                font.family: statsRoot.titleFontFamily
                                                font.pixelSize: 22
                                                font.bold: true
                                                color: Theme.detailHeaderTitle
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            RowLayout {
                                                spacing: 8

                                                // Song & chart count
                                                Text {
                                                    text: ((packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.song_count) ? packDashboardScrollView.currentPack.song_count : 0) + " songs • " +
                                                          ((packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.chart_count) ? packDashboardScrollView.currentPack.chart_count : 0) + " charts"
                                                    font.pixelSize: 13
                                                    color: Theme.detailHeaderArtist
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                // Version
                                                Rectangle {
                                                    visible: Boolean(packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.version)
                                                    implicitWidth: heroVerText.implicitWidth + 18
                                                    implicitHeight: 24
                                                    radius: 12
                                                    color: Theme.alpha(Theme.badgeVerBg, 0.65)
                                                    border.color: Theme.alpha(Theme.badgeVerBorder, 0.80)
                                                    border.width: 1
                                                    Layout.alignment: Qt.AlignVCenter

                                                    Text {
                                                        id: heroVerText
                                                        anchors.centerIn: parent
                                                        text: "v" + (packDashboardScrollView.currentPack ? (packDashboardScrollView.currentPack.version || "") : "")
                                                        color: Theme.badgeVerText
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                    }
                                                }
                                            }

                                            // Total Plays
                                            Text {
                                                id: totalPlaysText
                                                text: "Total " + ((packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.total_plays !== undefined) ? packDashboardScrollView.currentPack.total_plays : 0).toLocaleString(Qt.locale("en_US"), 'f', 0) + " Plays"
                                                font.pixelSize: 14
                                                font.bold: true
                                                color: Theme.detailHeaderTitle
                                            }
                                        }

                                        // Right: Progress Card
                                        Rectangle {
                                            id: heroProgressCard
                                            Layout.preferredWidth: 200
                                            Layout.preferredHeight: 80
                                            radius: 12
                                            color: {
                                                var p = packDashboardScrollView.currentPack
                                                if (p && (p.color || p.pack_color)) {
                                                    var c = p.color || p.pack_color
                                                    if (Theme.isDarkMode) {
                                                        return Theme.alpha(c, 0.22)
                                                    }
                                                    return heroProgressCard.getLightModePackBgColor(c, false)
                                                }
                                                return Theme.bgCard
                                            }
                                            border.width: Theme.isDarkMode ? 1 : 1.5
                                            border.color: {
                                                var p = packDashboardScrollView.currentPack
                                                if (p && (p.color || p.pack_color)) {
                                                    return Theme.alpha(p.color || p.pack_color, 0.80)
                                                }
                                                return Theme.borderDivider
                                            }

                                            // Helper to convert hex pack color to accessible pastel tone (Dark mode: L=0.88)
                                            function getPastelColor(hexColor, isDark) {
                                                if (!hexColor) return Theme.textMuted
                                                try {
                                                    var c = Qt.color(hexColor)
                                                    var r = c.r, g = c.g, b = c.b
                                                    var max = Math.max(r, g, b), min = Math.min(r, g, b)
                                                    var h = 0, s = 0, l = (max + min) / 2
                                                    if (max === min) {
                                                        h = s = 0
                                                    } else {
                                                        var d = max - min
                                                        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
                                                        switch (max) {
                                                            case r: h = (g - b) / d + (g < b ? 6 : 0); break
                                                            case g: h = (b - r) / d + 2; break
                                                            case b: h = (r - g) / d + 4; break
                                                        }
                                                        h /= 6
                                                    }
                                                    var targetL = 0.88
                                                    if (s < 0.08) {
                                                        return Qt.hsla(0, 0, targetL, 1.0)
                                                    }
                                                    var targetS = Math.min(s, 0.65)
                                                    targetS = Math.max(targetS, 0.40)
                                                    return Qt.hsla(h, targetS, targetL, 1.0)
                                                } catch (e) {
                                                    return Theme.textMuted
                                                }
                                            }

                                            // Helper to get dark pastel text color for light mode (black mixed with pastel tone: L=0.18)
                                            function getDarkPastelColor(hexColor) {
                                                if (!hexColor) return Theme.textMuted
                                                try {
                                                    var c = Qt.color(hexColor)
                                                    var r = c.r, g = c.g, b = c.b
                                                    var max = Math.max(r, g, b), min = Math.min(r, g, b)
                                                    var h = 0, s = 0, l = (max + min) / 2
                                                    if (max !== min) {
                                                        var d = max - min
                                                        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
                                                        switch (max) {
                                                            case r: h = (g - b) / d + (g < b ? 6 : 0); break
                                                            case g: h = (b - r) / d + 2; break
                                                            case b: h = (r - g) / d + 4; break
                                                        }
                                                        h /= 6
                                                    }
                                                    var targetL = 0.18 // Dark base (tinted black)
                                                    if (s < 0.08) {
                                                        return Qt.hsla(0, 0, targetL, 1.0)
                                                    }
                                                    var targetS = Math.min(Math.max(s, 0.40), 0.65)
                                                    return Qt.hsla(h, targetS, targetL, 1.0)
                                                } catch (e) {
                                                    return "#1A1A20"
                                                }
                                            }

                                            // Helper to get light mode pack background (increased brightness and white-mix: L=0.88, S<=0.20, Alpha=0.85)
                                            function getLightModePackBgColor(hexColor, containsMouse) {
                                                if (!hexColor) return containsMouse ? Theme.alpha(Theme.bgCard, 0.94) : Theme.alpha(Theme.bgCard, 0.85)
                                                try {
                                                    var c = Qt.color(hexColor)
                                                    var r = c.r, g = c.g, b = c.b
                                                    var max = Math.max(r, g, b), min = Math.min(r, g, b)
                                                    var h = 0, s = 0, l = (max + min) / 2
                                                    if (max !== min) {
                                                        var d = max - min
                                                        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
                                                        switch (max) {
                                                            case r: h = (g - b) / d + (g < b ? 6 : 0); break
                                                            case g: h = (b - r) / d + 2; break
                                                            case b: h = (r - g) / d + 4; break
                                                        }
                                                        h /= 6
                                                    }
                                                    var targetL = Math.max(l + (1.0 - l) * 0.60, 0.88)
                                                    var targetS = Math.min(s * 0.50, 0.20)
                                                    var brightColor = (s < 0.08) ? Qt.hsla(0, 0, targetL, 1.0) : Qt.hsla(h, targetS, targetL, 1.0)
                                                    var alphaVal = containsMouse ? 0.94 : 0.85
                                                    return Theme.alpha(brightColor, alphaVal)
                                                } catch (e) {
                                                    return Theme.alpha(hexColor, containsMouse ? 0.94 : 0.85)
                                                }
                                            }

                                            // Helper to tint a base color towards a tint color by weight (0.0: pure base, 1.0: pure tint)
                                            function tintColor(baseColorHex, tintColorHex, weight) {
                                                if (!tintColorHex) return baseColorHex
                                                try {
                                                    var c1 = Qt.color(baseColorHex)
                                                    var c2 = Qt.color(tintColorHex)
                                                    var w = (weight !== undefined) ? weight : 0.30
                                                    var r = c1.r * (1.0 - w) + c2.r * w
                                                    var g = c1.g * (1.0 - w) + c2.g * w
                                                    var b = c1.b * (1.0 - w) + c2.b * w
                                                    return Qt.rgba(r, g, b, 1.0)
                                                } catch (e) {
                                                    return baseColorHex
                                                }
                                            }

                                            readonly property color labelColor: {
                                                var p = packDashboardScrollView.currentPack
                                                if (p && (p.color || p.pack_color)) {
                                                    var c = p.color || p.pack_color
                                                    return Theme.isDarkMode ? heroProgressCard.getPastelColor(c, true) : heroProgressCard.getDarkPastelColor(c)
                                                }
                                                return Theme.textMuted
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 4

                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    textFormat: Text.StyledText
                                                    font.pixelSize: 22
                                                    font.bold: true

                                                    readonly property var currentPack: packDashboardScrollView.currentPack
                                                    readonly property int allCount: currentPack ? (currentPack.all_count || 0) : 0
                                                    readonly property int frpmCount: currentPack ? (currentPack.frpm_count || 0) : 0
                                                    readonly property int pmCount: {
                                                        if (!currentPack) return 0
                                                        if (typeof currentPack.pm_count !== "undefined") return currentPack.pm_count
                                                        if (currentPack.lamp_counts && typeof currentPack.lamp_counts.pm !== "undefined") return currentPack.lamp_counts.pm
                                                        return 0
                                                    }

                                                    readonly property bool isAllPm: allCount > 0 && pmCount === allCount
                                                    readonly property bool isAllFr: !isAllPm && allCount > 0 && frpmCount === allCount

                                                    // 기본 FR.PM 대표색
                                                    readonly property color baseFrpmColor: {
                                                        var hasPack = currentPack && (currentPack.color || currentPack.pack_color)
                                                        if (Theme.isDarkMode) {
                                                            return hasPack ? heroProgressCard.tintColor(Theme.clearFullRecall, heroProgressCard.labelColor, 0.30) : Theme.clearFullRecall
                                                        }
                                                        return "#F06595"
                                                    }

                                                    // 기본 CLR 대표색
                                                    readonly property color baseClrColor: {
                                                        var hasPack = currentPack && (currentPack.color || currentPack.pack_color)
                                                        if (Theme.isDarkMode) {
                                                            return hasPack ? heroProgressCard.tintColor(Theme.clearComplete, heroProgressCard.labelColor, 0.30) : Theme.clearComplete
                                                        }
                                                        return "#8C7594"
                                                    }

                                                    // 기본 ALL 대표색
                                                    readonly property color baseAllColor: {
                                                        var hasPack = currentPack && (currentPack.color || currentPack.pack_color)
                                                        if (Theme.isDarkMode) {
                                                            return hasPack ? heroProgressCard.tintColor(Theme.textMuted, heroProgressCard.labelColor, 0.30) : Theme.textMuted
                                                        }
                                                        return "#4B5563"
                                                    }

                                                    // 기본 슬래시 색상
                                                    readonly property color defaultSlashColor: Theme.isDarkMode ? Theme.textMuted : "#6B7280"

                                                    // 조건부 일원화 적용 최종 색상 프로퍼티 (외부 및 마크업 참조)
                                                    property color frpmColor: isAllPm ? heroProgressCard.labelColor : baseFrpmColor
                                                    property color clrColor: isAllPm ? heroProgressCard.labelColor : (isAllFr ? baseFrpmColor : baseClrColor)
                                                    property color allColor: isAllPm ? heroProgressCard.labelColor : (isAllFr ? baseFrpmColor : baseAllColor)
                                                    property color slashColor: isAllPm ? heroProgressCard.labelColor : (isAllFr ? baseFrpmColor : defaultSlashColor)

                                                    text: "<font color='" + frpmColor + "'>" + frpmCount + "</font>" +
                                                          "<font color='" + slashColor + "'> / </font>" +
                                                          "<font color='" + clrColor + "'>" + (currentPack ? currentPack.clr_count : 0) + "</font>" +
                                                          "<font color='" + slashColor + "'> / </font>" +
                                                          "<font color='" + allColor + "'>" + allCount + "</font>"
                                                }

                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "FR.PM / CLR / ALL"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: heroProgressCard.labelColor
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Song-Based Statistics 3-Card Row (Best Potential, Best Score, Most Played)
                            GridLayout {
                                id: songStatsRow
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                columns: (typeof statsRoot !== "undefined" && statsRoot.isNarrow) ? 1 : 3
                                columnSpacing: 10
                                rowSpacing: 10

                                // Card 1: Best Potential
                                Rectangle {
                                    id: bestPotCard
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: potCardMouse.containsMouse ? Theme.bgItemHover : Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    property var potRecord: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.top_potential) ? packDashboardScrollView.currentPack.top_potential : null

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        Text {
                                            text: "Best Potential"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.textSecondary
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 10

                                            // Thumbnail
                                            Rectangle {
                                                Layout.preferredWidth: 56
                                                Layout.preferredHeight: 56
                                                radius: 8
                                                clip: true
                                                color: "transparent"

                                                Image {
                                                    id: potThumbImage
                                                    anchors.fill: parent
                                                    asynchronous: true
                                                    cache: true
                                                    source: {
                                                        var _v = statsRoot.thumbnailVersion
                                                        return (statsHandler && bestPotCard.potRecord && (bestPotCard.potRecord.potential > 0 || bestPotCard.potRecord.value > 0) && bestPotCard.potRecord.song_id) ? statsHandler.getThumbnailPathForDifficulty(bestPotCard.potRecord.song_id, bestPotCard.potRecord.diff_index) : ""
                                                    }
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    antialiasing: true
                                                    visible: status === Image.Ready
                                                }


                                            }

                                            // Right details
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                Text {
                                                    text: bestPotCard.potRecord && (bestPotCard.potRecord.potential > 0 || bestPotCard.potRecord.value > 0) ? Number(bestPotCard.potRecord.potential !== undefined ? bestPotCard.potRecord.potential : bestPotCard.potRecord.value).toFixed(2) : "-"
                                                    font.pixelSize: 16
                                                    font.bold: true
                                                    color: Theme.textPrimary
                                                }

                                                Text {
                                                    text: bestPotCard.potRecord && (bestPotCard.potRecord.potential > 0 || bestPotCard.potRecord.value > 0) ? (bestPotCard.potRecord.song_title || "-") : "-"
                                                    font.pixelSize: 11
                                                    color: Theme.textPrimary
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                Text {
                                                    text: bestPotCard.potRecord && (bestPotCard.potRecord.potential > 0 || bestPotCard.potRecord.value > 0) ? (bestPotCard.potRecord.diff_with_level || (bestPotCard.potRecord.diff_name + (bestPotCard.potRecord.level_str ? (" " + bestPotCard.potRecord.level_str) : ""))) : "-"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: (bestPotCard.potRecord && (bestPotCard.potRecord.potential > 0 || bestPotCard.potRecord.value > 0)) ? Theme.getDiffColor(bestPotCard.potRecord.diff_color_tag) : Theme.textMuted
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: potCardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: (bestPotCard.potRecord && bestPotCard.potRecord.song_id) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            var packId = packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.id : ""
                                            var diff = (bestPotCard.potRecord && bestPotCard.potRecord.diff_index !== undefined) ? bestPotCard.potRecord.diff_index : -1
                                            if (statisticsHandler && packId && bestPotCard.potRecord && bestPotCard.potRecord.song_id) {
                                                statisticsHandler.selectPackSong(packId, bestPotCard.potRecord.song_id, diff)
                                                if (typeof statsRoot !== "undefined" && statsRoot.isNarrow) {
                                                    mobileStack.push(detailPageComponent)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Card 2: Best Score
                                Rectangle {
                                    id: bestScoreCard
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: scoreCardMouse.containsMouse ? Theme.bgItemHover : Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    property var scoreRecord: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.top_score) ? packDashboardScrollView.currentPack.top_score : null

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        Text {
                                            text: "Best Score"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.textSecondary
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 10

                                            // Thumbnail
                                            Rectangle {
                                                Layout.preferredWidth: 56
                                                Layout.preferredHeight: 56
                                                radius: 8
                                                clip: true
                                                color: "transparent"

                                                Image {
                                                    id: scoreThumbImage
                                                    anchors.fill: parent
                                                    asynchronous: true
                                                    cache: true
                                                    source: {
                                                        var _v = statsRoot.thumbnailVersion;
                                                        return (statsHandler && bestScoreCard.scoreRecord && ((bestScoreCard.scoreRecord.score !== undefined && bestScoreCard.scoreRecord.score > 0) || (bestScoreCard.scoreRecord.value !== undefined && bestScoreCard.scoreRecord.value > 0)) && bestScoreCard.scoreRecord.song_id) ? statsHandler.getThumbnailPathForDifficulty(bestScoreCard.scoreRecord.song_id, bestScoreCard.scoreRecord.diff_index) : ""
                                                    }
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    antialiasing: true
                                                    visible: status === Image.Ready
                                                }


                                            }

                                            // Right details
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                Text {
                                                    text: (bestScoreCard.scoreRecord && ((bestScoreCard.scoreRecord.score !== undefined && bestScoreCard.scoreRecord.score > 0) || (bestScoreCard.scoreRecord.value !== undefined && bestScoreCard.scoreRecord.value > 0))) ? Number(bestScoreCard.scoreRecord.score !== undefined ? bestScoreCard.scoreRecord.score : bestScoreCard.scoreRecord.value).toLocaleString(Qt.locale("en_US"), 'f', 0) : "-"
                                                    font.pixelSize: 16
                                                    font.bold: true
                                                    color: (bestScoreCard.scoreRecord && bestScoreCard.scoreRecord.is_max) ? Theme.maxHighlight : Theme.textPrimary
                                                }

                                                Text {
                                                    text: (bestScoreCard.scoreRecord && ((bestScoreCard.scoreRecord.score !== undefined && bestScoreCard.scoreRecord.score > 0) || (bestScoreCard.scoreRecord.value !== undefined && bestScoreCard.scoreRecord.value > 0))) ? (bestScoreCard.scoreRecord.song_title || "-") : "-"
                                                    font.pixelSize: 11
                                                    color: Theme.textPrimary
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                Text {
                                                    text: (bestScoreCard.scoreRecord && ((bestScoreCard.scoreRecord.score !== undefined && bestScoreCard.scoreRecord.score > 0) || (bestScoreCard.scoreRecord.value !== undefined && bestScoreCard.scoreRecord.value > 0))) ? (bestScoreCard.scoreRecord.diff_with_level || (bestScoreCard.scoreRecord.diff_name + (bestScoreCard.scoreRecord.level_str ? (" " + bestScoreCard.scoreRecord.level_str) : ""))) : "-"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: (bestScoreCard.scoreRecord && ((bestScoreCard.scoreRecord.score !== undefined && bestScoreCard.scoreRecord.score > 0) || (bestScoreCard.scoreRecord.value !== undefined && bestScoreCard.scoreRecord.value > 0))) ? Theme.getDiffColor(bestScoreCard.scoreRecord.diff_color_tag) : Theme.textMuted
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: scoreCardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: (bestScoreCard.scoreRecord && bestScoreCard.scoreRecord.song_id) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            var packId = packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.id : ""
                                            var diff = (bestScoreCard.scoreRecord && bestScoreCard.scoreRecord.diff_index !== undefined) ? bestScoreCard.scoreRecord.diff_index : -1
                                            if (statisticsHandler && packId && bestScoreCard.scoreRecord && bestScoreCard.scoreRecord.song_id) {
                                                statisticsHandler.selectPackSong(packId, bestScoreCard.scoreRecord.song_id, diff)
                                                if (typeof statsRoot !== "undefined" && statsRoot.isNarrow) {
                                                    mobileStack.push(detailPageComponent)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Card 3: Most Played
                                Rectangle {
                                    id: mostPlayedCard
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: mostCardMouse.containsMouse ? Theme.bgItemHover : Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        Text {
                                            text: "Most Played"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.textSecondary
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 10

                                            // Thumbnail (56x56)
                                            Rectangle {
                                                Layout.preferredWidth: 56
                                                Layout.preferredHeight: 56
                                                radius: 8
                                                clip: true
                                                color: "transparent"

                                                Image {
                                                    id: mostPlayedThumbImage
                                                    anchors.fill: parent
                                                    asynchronous: true
                                                    cache: true
                                                    source: {
                                                        var _v = statsRoot.thumbnailVersion;
                                                        if (!packDashboardScrollView.currentPack) return ""
                                                        var p = packDashboardScrollView.currentPack
                                                        if (p.most_played_jacket_path) {
                                                            return "file:///" + p.most_played_jacket_path.replace(/\\/g, "/")
                                                        }
                                                        if (statsHandler && p.most_played_song_id) {
                                                            return statsHandler.getThumbnailPathForDifficulty(p.most_played_song_id, p.most_played_thumb_diff !== undefined ? p.most_played_thumb_diff : 2)
                                                        }
                                                        return ""
                                                    }
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    antialiasing: true
                                                    visible: status === Image.Ready
                                                }


                                            }

                                            // Right details (곡명 + 플레이수)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Layout.alignment: Qt.AlignVCenter

                                                Text {
                                                    text: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.most_played_song_title) ? packDashboardScrollView.currentPack.most_played_song_title : "-"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    color: Theme.textPrimary
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                Text {
                                                    property int playCnt: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.most_played_song_count !== undefined) ? packDashboardScrollView.currentPack.most_played_song_count : 0
                                                    text: playCnt + (playCnt === 1 ? " play" : " plays")
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    color: Theme.textSecondary
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: mostCardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.most_played_song_id) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            var p = packDashboardScrollView.currentPack
                                            var diff = (p && p.most_played_thumb_diff !== undefined) ? p.most_played_thumb_diff : -1
                                            if (statisticsHandler && p && p.id && p.most_played_song_id) {
                                                statisticsHandler.selectPackSong(p.id, p.most_played_song_id, diff)
                                                if (typeof statsRoot !== "undefined" && statsRoot.isNarrow) {
                                                    mobileStack.push(detailPageComponent)
                                                }
                                            }
                                        }
                                    }
                                }
                            }


                            // 3. Dual Symmetrical Graphs: Clear Status (Left) & Score Grade (Right)
                            GridLayout {
                                id: dualGraphLayout
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                columns: (typeof statsRoot !== "undefined" && statsRoot.isNarrow) ? 1 : 2
                                columnSpacing: 10
                                rowSpacing: 10

                                function calcLegendTextWidth(str) {
                                    var w = 0;
                                    for (var i = 0; i < str.length; i++) {
                                        var ch = str.charAt(i);
                                        if (ch === ' ') w += 3;
                                        else if (ch === '-' || ch === 'I' || ch === 'l') w += 4;
                                        else if (ch === 'M' || ch === 'W') w += 8;
                                        else if (ch >= 'A' && ch <= 'Z') w += 7;
                                        else if (ch === '+' || (ch >= '0' && ch <= '9')) w += 6;
                                        else w += 5;
                                    }
                                    return w;
                                }

                                function calcFirstLineCount(items, availW) {
                                    if (!items || items.length === 0) return 0;
                                    var N = items.length;
                                    var minGap = 8;
                                    var wLimit = (availW && availW > 0) ? availW : 320;

                                    // 1. 전체가 1줄에 들어가는지 검사
                                    var totalW = 0;
                                    for (var i = 0; i < N; i++) totalW += (items[i].itemWidth || 30);
                                    if (totalW + (N - 1) * minGap <= wLimit) {
                                        return N;
                                    }

                                    // 2. 가용 폭 내에서 1줄에 들어갈 수 있는 최대 개수 K 탐색 (Greedy Packing)
                                    var curW = 0;
                                    var K = 0;
                                    for (var j = 0; j < N; j++) {
                                        var nextW = curW + (items[j].itemWidth || 30) + (j > 0 ? minGap : 0);
                                        if (nextW <= wLimit) {
                                            curW = nextW;
                                            K = j + 1;
                                        } else {
                                            break;
                                        }
                                    }
                                    // 최소 1개는 1행에, 최소 1개는 2행에 분배
                                    return Math.max(1, Math.min(K, N - 1));
                                }

                                function isLegendTwoLines(segments, availW) {
                                    if (!segments || segments.length <= 1) return false;
                                    var K = calcFirstLineCount(segments, availW);
                                    return K < segments.length;
                                }

                                function getLegendItemX(items, index, availW, isTwo) {
                                    if (!items || items.length === 0 || index < 0 || index >= items.length) return 0;
                                    var N = items.length;
                                    var wLimit = (availW && availW > 0) ? availW : 320;
                                    var K = isTwo ? calcFirstLineCount(items, wLimit) : N;
                                    if (K <= 1) return Math.max(0, Math.round((wLimit - (items[0].itemWidth || 30)) / 2));

                                    // Calculate maximum width for each column to ensure vertical alignment
                                    var colWidths = [];
                                    var sumColW = 0;
                                    for (var c = 0; c < K; c++) {
                                        var w = items[c] ? (items[c].itemWidth || 30) : 0;
                                        if (isTwo && (K + c < N)) {
                                            var w2 = items[K + c].itemWidth || 30;
                                            if (w2 > w) w = w2;
                                        }
                                        colWidths.push(w);
                                        sumColW += w;
                                    }

                                    var col = (isTwo && index >= K) ? (index - K) : index;
                                    if (col === 0) return 0;
                                    if (col === K - 1) return Math.max(0, wLimit - colWidths[K - 1]);

                                    var gap = (wLimit - sumColW) / (K - 1);
                                    var prevW = 0;
                                    for (var j = 0; j < col; j++) prevW += colWidths[j];
                                    return Math.max(0, Math.round(prevW + col * gap));
                                }

                                function getLegendItemY(items, index, availW, isTwo) {
                                    var isT = (typeof availW === "boolean") ? availW : isTwo;
                                    var wLim = (typeof availW === "number" && availW > 0) ? availW : 320;
                                    if (!isT || !items) return 0;
                                    var K = calcFirstLineCount(items, wLim);
                                    return (index >= K) ? 15 : 0;
                                }

                                // Left Card: Clear Status
                                Rectangle {
                                    id: clearLampCard
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    property var lamps: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.lamp_counts) ? packDashboardScrollView.currentPack.lamp_counts : ({})
                                    property int totalCount: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.all_count > 0) ? packDashboardScrollView.currentPack.all_count : 0

                                    property var clearSegments: {
                                        var stages = [
                                            { name: "PM", count: lamps.pm || 0, col: Theme.clearPureMemory },
                                            { name: "FR", count: lamps.fr || 0, col: Theme.clearFullRecall },
                                            { name: "Hard", count: lamps.hard || 0, col: Theme.clearHard },
                                            { name: "Clear", count: lamps.complete || 0, col: Theme.clearComplete },
                                            { name: "Easy", count: lamps.easy || 0, col: Theme.clearEasy },
                                            { name: "Lost", count: lamps.lost || 0, col: Theme.clearLost },
                                            { name: "-", count: lamps.unplayed || 0, col: Theme.scoreRankNone }
                                        ]
                                        var active = stages.filter(function(s) { return s.count > 0 })
                                        var tot = 0
                                        for (var i = 0; i < active.length; i++) tot += active[i].count
                                        if (tot <= 0) tot = totalCount > 0 ? totalCount : 1
                                        for (var j = 0; j < active.length; j++) {
                                            active[j].widthFrac = active[j].count / tot
                                            active[j].itemWidth = 8 + dualGraphLayout.calcLegendTextWidth(active[j].name + " " + active[j].count)
                                        }
                                        return active
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 10
                                        anchors.bottomMargin: 10
                                        spacing: 5

                                        // Header Row
                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: "Clear Status"
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: Theme.textSecondary
                                            }

                                            Item { Layout.fillWidth: true }

                                            RowLayout {
                                                spacing: 2
                                                Text {
                                                    text: String(packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.clear_count : 0)
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    color: Theme.clearComplete
                                                    Layout.alignment: Qt.AlignBaseline
                                                }
                                                Text {
                                                    text: "/" + String(packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.all_count : 0)
                                                    font.pixelSize: 11
                                                    font.bold: false
                                                    color: Theme.textMuted
                                                    Layout.alignment: Qt.AlignBaseline
                                                }
                                                Text {
                                                    text: " (" + (packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.clear_rate : 0) + "%)"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Theme.textSecondary
                                                    Layout.alignment: Qt.AlignBaseline
                                                }
                                            }
                                        }

                                        // 14px Multi-segment Gauge Bar (Pill-in-Pill)
                                        Rectangle {
                                            id: clearGaugeBar
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 14
                                            radius: 6
                                            color: Theme.isDarkMode ? "#252530" : "#E2E2E8"
                                            border.width: 1
                                            border.color: Theme.borderDivider
                                            clip: true

                                            Row {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                spacing: 2

                                                Repeater {
                                                    model: clearLampCard.clearSegments

                                                    Rectangle {
                                                        height: parent.height
                                                        width: Math.max(0, modelData.widthFrac * (parent.width - Math.max(0, clearLampCard.clearSegments.length - 1) * 2))
                                                        radius: 3
                                                        color: modelData.col
                                                    }
                                                }
                                            }
                                        }

                                        // Dynamic Space-Between Legend (Auto 1-line or 2-line layout)
                                        Item {
                                            id: clearLegendArea
                                            Layout.fillWidth: true
                                            Layout.topMargin: 2
                                            property bool isTwoLines: dualGraphLayout.isLegendTwoLines(clearLampCard.clearSegments, width)
                                            Layout.preferredHeight: isTwoLines ? 29 : 14

                                            Repeater {
                                                model: clearLampCard.clearSegments

                                                Item {
                                                    x: dualGraphLayout.getLegendItemX(clearLampCard.clearSegments, index, clearLegendArea.width, clearLegendArea.isTwoLines)
                                                    y: dualGraphLayout.getLegendItemY(clearLampCard.clearSegments, index, clearLegendArea.width, clearLegendArea.isTwoLines)
                                                    width: modelData.itemWidth
                                                    height: 14

                                                    Row {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 3

                                                        Rectangle {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 5
                                                            height: 5
                                                            radius: 2.5
                                                            color: modelData.col
                                                        }

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: modelData.name + " " + modelData.count
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                            color: (modelData.name === "-" || modelData.name === "Unplayed") ? Theme.textMuted : modelData.col
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Right Card: Score Grade
                                Rectangle {
                                    id: scoreGradeCard
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    property var grades: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.score_grade_counts) ? packDashboardScrollView.currentPack.score_grade_counts : ({})
                                    property int totalCount: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.all_count > 0) ? packDashboardScrollView.currentPack.all_count : 0

                                    property var gradeSegments: {
                                        var stages = [
                                            { name: "PM", count: grades.pm || 0, col: Theme.scoreRankPm },
                                            { name: "EX+", count: grades.ex_plus || 0, col: Theme.scoreRankExPlus },
                                            { name: "EX", count: grades.ex || 0, col: Theme.scoreRankEx },
                                            { name: "AA", count: grades.aa || 0, col: Theme.scoreRankAa },
                                            { name: "A", count: grades.a || 0, col: Theme.scoreRankA },
                                            { name: "B", count: grades.b || 0, col: Theme.scoreRankB },
                                            { name: "C", count: grades.c || 0, col: Theme.scoreRankC },
                                            { name: "D", count: grades.d || 0, col: Theme.scoreRankD },
                                            { name: "-", count: grades.unplayed || 0, col: Theme.scoreRankNone }
                                        ]
                                        var active = stages.filter(function(s) { return s.count > 0 })
                                        var tot = 0
                                        for (var i = 0; i < active.length; i++) tot += active[i].count
                                        if (tot <= 0) tot = totalCount > 0 ? totalCount : 1
                                        for (var j = 0; j < active.length; j++) {
                                            active[j].widthFrac = active[j].count / tot
                                            active[j].itemWidth = 8 + dualGraphLayout.calcLegendTextWidth(active[j].name + " " + active[j].count)
                                        }
                                        return active
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 10
                                        anchors.bottomMargin: 10
                                        spacing: 5

                                        // Header Row
                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: "Score Grade"
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: Theme.textSecondary
                                            }

                                            Item { Layout.fillWidth: true }

                                            RowLayout {
                                                spacing: 2
                                                Text {
                                                    text: String(packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.ex_plus_count : 0)
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    color: Theme.scoreRankExPlus
                                                    Layout.alignment: Qt.AlignBaseline
                                                }
                                                Text {
                                                    text: "/" + String(packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.all_count : 0)
                                                    font.pixelSize: 11
                                                    font.bold: false
                                                    color: Theme.textMuted
                                                    Layout.alignment: Qt.AlignBaseline
                                                }
                                                Text {
                                                    text: " (" + (packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.ex_plus_rate : 0) + "%)"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Theme.textSecondary
                                                    Layout.alignment: Qt.AlignBaseline
                                                }
                                            }
                                        }

                                        // 14px Multi-segment Gauge Bar (Pill-in-Pill)
                                        Rectangle {
                                            id: gradeGaugeBar
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 14
                                            radius: 6
                                            color: Theme.isDarkMode ? "#252530" : "#E2E2E8"
                                            border.width: 1
                                            border.color: Theme.borderDivider
                                            clip: true

                                            Row {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                spacing: 2

                                                Repeater {
                                                    model: scoreGradeCard.gradeSegments

                                                    Rectangle {
                                                        height: parent.height
                                                        width: Math.max(0, modelData.widthFrac * (parent.width - Math.max(0, scoreGradeCard.gradeSegments.length - 1) * 2))
                                                        radius: 3
                                                        color: modelData.col
                                                    }
                                                }
                                            }
                                        }

                                        // Dynamic Space-Between Legend (Auto 1-line or 2-line layout)
                                        Item {
                                            id: gradeLegendArea
                                            Layout.fillWidth: true
                                            Layout.topMargin: 2
                                            property bool isTwoLines: dualGraphLayout.isLegendTwoLines(scoreGradeCard.gradeSegments, width)
                                            Layout.preferredHeight: isTwoLines ? 29 : 14

                                            Repeater {
                                                model: scoreGradeCard.gradeSegments

                                                Item {
                                                    x: dualGraphLayout.getLegendItemX(scoreGradeCard.gradeSegments, index, gradeLegendArea.width, gradeLegendArea.isTwoLines)
                                                    y: dualGraphLayout.getLegendItemY(scoreGradeCard.gradeSegments, index, gradeLegendArea.width, gradeLegendArea.isTwoLines)
                                                    width: modelData.itemWidth
                                                    height: 14

                                                    Row {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 3

                                                        Rectangle {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 5
                                                            height: 5
                                                            radius: 2.5
                                                            color: modelData.col
                                                        }

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: modelData.name + " " + modelData.count
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                            color: (modelData.name === "-" || modelData.name === "Unplayed") ? Theme.textMuted : modelData.col
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 4. 4-Column Stats Grid (Average Score, FRAME, Play Time, This Year)
                            GridLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                Layout.bottomMargin: 16
                                columns: isDiffCramped ? 2 : 4
                                columnSpacing: 12
                                rowSpacing: 12

                                // Column 1: Average Score
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        Text {
                                            text: "Average Score"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.textSecondary
                                        }

                                        Text {
                                            text: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.avg_score > 0) ? Math.round(packDashboardScrollView.currentPack.avg_score).toLocaleString(Qt.locale("en_US"), 'f', 0) : "-"
                                            font.pixelSize: 20
                                            font.bold: true
                                            color: Theme.textPrimary
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                }

                                // Column 2: FRAME
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        Text {
                                            text: "FRAME"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.textSecondary
                                        }

                                        RowLayout {
                                            spacing: 2
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                text: String((packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.frame_count !== undefined) ? packDashboardScrollView.currentPack.frame_count : 0)
                                                font.pixelSize: 20
                                                font.bold: true
                                                color: Theme.frameHighlight
                                                Layout.alignment: Qt.AlignBaseline
                                            }
                                            Text {
                                                text: " / " + String((packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.all_count !== undefined) ? packDashboardScrollView.currentPack.all_count : (packDashboardScrollView.currentPack ? (packDashboardScrollView.currentPack.chart_count || 0) : 0))
                                                font.pixelSize: 13
                                                font.bold: false
                                                color: Theme.textMuted
                                                Layout.alignment: Qt.AlignBaseline
                                            }
                                        }
                                    }
                                }

                                // Column 3: Play Time
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        Text {
                                            text: "Play Time"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.textSecondary
                                        }

                                        Text {
                                            text: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.play_time_str) ? packDashboardScrollView.currentPack.play_time_str : "0m"
                                            font.pixelSize: 20
                                            font.bold: true
                                            color: Theme.textPrimary
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                }

                                // Column 4: This Year
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    radius: 12
                                    color: Theme.bgButton
                                    border.width: 1
                                    border.color: Theme.borderDivider

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        Text {
                                            text: "This Year"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.textSecondary
                                        }

                                        RowLayout {
                                            spacing: 6
                                            Layout.alignment: Qt.AlignVCenter

                                            Text {
                                                text: (packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.this_year_play_time_str) ? packDashboardScrollView.currentPack.this_year_play_time_str : "0m"
                                                font.pixelSize: 20
                                                font.bold: true
                                                color: Theme.textPrimary
                                            }

                                            Text {
                                                text: "(" + ((packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.this_year_play_time_share !== undefined) ? packDashboardScrollView.currentPack.this_year_play_time_share : 0) + "%)"
                                                font.pixelSize: 13
                                                font.bold: true
                                                color: Theme.textSecondary
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // [Song Detail View]
                ScrollView {
                    id: songDetailScrollView
                    anchors.fill: parent
                    contentWidth: availableWidth; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff; clip: true
                    visible: !detailedViewStackContainer.isPackDashboardTarget || detailedViewStackContainer.isCrossfading || (detailedViewStackContainer.isDeselectingPack && !detailedViewStackContainer.wasInPackDetailViewBeforeDeselect)

                    property var currentSong: (typeof detailedViewStackContainer !== "undefined" && ((detailedViewStackContainer.isCrossfading && detailedViewStackContainer.isPackDashboardTarget && detailedViewStackContainer.wasSongSelectedBeforeTransition) || detailedViewStackContainer.isDeselectingPack) && detailedViewStackContainer.cachedLastSong)
                        ? detailedViewStackContainer.cachedLastSong
                        : statsRoot.currentSong

                    opacity: 1.0

                    NumberAnimation {
                        id: songDetailFadeIn
                        target: songDetailScrollView
                        property: "opacity"
                        running: false
                        from: 0.0
                        to: 1.0
                        duration: 140
                        easing.type: Easing.OutQuad
                        onFinished: {
                            if (!detailedViewStackContainer.isPackDashboardTarget) {
                                detailedViewStackContainer.isCrossfading = false
                                detailedViewStackContainer.wasInPackSubSong = Boolean(statisticsHandler && statisticsHandler.displayMode === "pack" && !statisticsHandler.isPackDetailView)
                                detailedViewStackContainer.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                detailedViewStackContainer.wasSongSelectedBeforeTransition = detailedViewStackContainer.wasSongSelected
                                statsRoot.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                packDashboardScrollView.visible = false
                                packDashboardScrollView.opacity = 0.0
                            }
                        }
                    }

                    NumberAnimation {
                        id: songDetailFadeOut
                        target: songDetailScrollView
                        property: "opacity"
                        running: false
                        from: 1.0
                        to: 0.0
                        duration: 140
                        easing.type: Easing.OutQuad
                        onFinished: {
                            if (detailedViewStackContainer.isPackDashboardTarget) {
                                detailedViewStackContainer.isCrossfading = false
                                detailedViewStackContainer.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                detailedViewStackContainer.wasSongSelectedBeforeTransition = detailedViewStackContainer.wasSongSelected
                                statsRoot.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                songDetailScrollView.visible = false
                                songDetailScrollView.opacity = 0.0
                                if (typeof bgImage !== "undefined" && bgImage) bgImage.reset()
                                if (typeof mainThumbImage !== "undefined" && mainThumbImage) mainThumbImage.reset()
                            }
                            if (detailedViewStackContainer.isDeselectingPack) {
                                detailedViewStackContainer.isDeselectingPack = false
                                detailedViewStackContainer.isReturningFromPackSubSong = false
                                detailedViewStackContainer.wasInPackSubSong = false
                                detailedViewStackContainer.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                detailedViewStackContainer.wasSongSelectedBeforeTransition = detailedViewStackContainer.wasSongSelected
                                statsRoot.wasPackSelectedBeforeTransition = detailedViewStackContainer.wasPackSelected
                                statsRoot.isDetailedViewCrossfading = false
                                songDetailScrollView.visible = false
                                songDetailScrollView.opacity = 0.0
                                if (typeof bgImage !== "undefined" && bgImage) bgImage.reset()
                                if (typeof mainThumbImage !== "undefined" && mainThumbImage) mainThumbImage.reset()
                            }
                        }
                    }

                    onVisibleChanged: {
                        if (visible) {
                            if (!detailedViewStackContainer.isCrossfading) {
                                songDetailFadeIn.restart()
                            }
                            if (typeof bgImage !== "undefined" && bgImage) bgImage.ensureLoaded()
                            if (typeof mainThumbImage !== "undefined" && mainThumbImage) mainThumbImage.ensureLoaded()
                        }
                    }

                    ColumnLayout {
                        width: parent.width; spacing: 16

                        // 1. Empty state when no song selected (Pack placeholder 규격과 100% 통일)
                        Text {
                            visible: !currentSong
                            text: (statisticsHandler && statisticsHandler.displayMode === "chart") ?
                                  "Select a chart from the list to view details" :
                                  "Select a song from the list to view details"
                            color: Theme.textLight
                            font.pixelSize: 16
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 40
                        }

                        // 2. Content Column when currentSong is valid
                        ColumnLayout {
                            id: songDetailContentColumn
                            Layout.fillWidth: true
                            spacing: 0
                            visible: Boolean(currentSong)

                            opacity: 1.0
                            NumberAnimation on opacity {
                                id: songDetailContentFadeIn
                                running: false
                                from: 0.0
                                to: 1.0
                                duration: 140
                            }
                            onVisibleChanged: {
                                if (visible) {
                                    if (!songDetailFadeIn.running) {
                                        songDetailContentFadeIn.restart()
                                    } else {
                                        songDetailContentColumn.opacity = 1.0
                                    }
                                }
                            }

                            // Song info header
                            Item {
                                id: headerContainer
                                property bool showBackToPack: Boolean(
                                    (statisticsHandler && statisticsHandler.displayMode === "pack" && !statisticsHandler.isPackDetailView) ||
                                    (typeof detailedViewStackContainer !== "undefined" && (detailedViewStackContainer.isCrossfading || detailedViewStackContainer.isDeselectingPack) && detailedViewStackContainer.isReturningFromPackSubSong)
                                )
                            Layout.fillWidth: true
                            Layout.preferredHeight: showBackToPack ? (isNarrow ? 236 : 240) : (isNarrow ? 180 : 200)
                            implicitHeight: Layout.preferredHeight

                            readonly property int effectiveHeaderDiff: {
                                if (!currentSong) return 2
                                if (statisticsHandler && statisticsHandler.selectedDifficulty >= 0) {
                                    return statisticsHandler.selectedDifficulty
                                }
                                return (currentSong.thumbnailDifficulty !== undefined) ? currentSong.thumbnailDifficulty : (currentSong.difficulty !== undefined ? currentSong.difficulty : 2)
                            }

                            readonly property string effectiveHeaderVersion: {
                                if (!currentSong) return ""
                                var diff = effectiveHeaderDiff
                                var allDiffs = currentSong.allDifficulties || currentSong.filteredDifficulties || []
                                for (var i = 0; i < allDiffs.length; i++) {
                                    if (allDiffs[i].difficulty === diff && allDiffs[i].version) {
                                        return allDiffs[i].version
                                    }
                                }
                                return currentSong.version || ""
                            }

                            // 1. Return Bar to Pack Dashboard (Semi-transparent overlay at top of header)
                            Item {
                                id: backToPackBarContainer
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 38
                                z: 30
                                visible: headerContainer.showBackToPack
                                clip: true

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: parent.height + (isNarrow ? 0 : 20)
                                    radius: isNarrow ? 0 : 20
                                    gradient: Gradient {
                                        GradientStop {
                                            position: 0.0
                                            color: Theme.isDarkMode ? Qt.rgba(0.05, 0.05, 0.12, 0.45) : Qt.rgba(1, 1, 1, 0.50)
                                        }
                                        GradientStop {
                                            position: isNarrow ? 1.0 : (parent.height / height)
                                            color: "transparent"
                                        }
                                        GradientStop {
                                            position: 1.0
                                            color: "transparent"
                                        }
                                    }
                                    border.width: 0

                                    RowLayout {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 38
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        spacing: 8

                                        Text {
                                            text: "← Back to Pack Dashboard"
                                            color: backToPackMouse.containsMouse ? Theme.accentHover : Theme.accent
                                            font.bold: true
                                            font.pixelSize: 13
                                        }

                                        Item { Layout.fillWidth: true }
                                    }

                                    MouseArea {
                                        id: backToPackMouse
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 38
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (statisticsHandler) {
                                                statisticsHandler.returnToPackDashboard()
                                            }
                                        }
                                    }
                                }
                            }

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
                                    CrossfadeImage {
                                        id: bgImage
                                        anchors.fill: parent
                                        anchors.margins: -20
                                        targetSource: {
                                            var _v = statsRoot.thumbnailVersion;
                                            return statsHandler && currentSong ? statsHandler.getThumbnailPathForDifficulty(currentSong.arcaeaId || "", headerContainer.effectiveHeaderDiff) : ""
                                        }
                                        fillMode: Image.PreserveAspectCrop
                                        antialiasing: true
                                        
                                        layer.enabled: true
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
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.top: parent.top
                                anchors.topMargin: headerContainer.showBackToPack ? (isNarrow ? 48 : 54) : (isNarrow ? 15 : 24)
                                anchors.bottomMargin: isNarrow ? 15 : 24
                                anchors.leftMargin: isNarrow ? 15 : 24
                                anchors.rightMargin: isNarrow ? 15 : 24
                                spacing: isNarrow ? 15 : 24
                                
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
                                        opacity: (typeof mainThumbImage !== "undefined" && mainThumbImage) ? mainThumbImage.activeOpacity : 0.0
                                        
                                        // Properties for efficient shadow updates
                                        property int diff: headerContainer.effectiveHeaderDiff
                                        property var arcaeaId: statsHandler && currentSong ? (currentSong.arcaeaId || "") : ""
                                        property string shadowColorString: {
                                            var _v = statsRoot.thumbnailVersion;
                                            return statsHandler ? statsHandler.getThumbnailColor(arcaeaId, diff) : Theme.bgCard
                                        }
                                        property color shadowColor: shadowColorString
                                        Behavior on shadowColor {
                                            ColorAnimation { duration: 140; easing.type: Easing.OutQuad }
                                        }
                                        
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
                                        color: "transparent"
                                        border.color: Qt.rgba(Theme.bgCard.r, Theme.bgCard.g, Theme.bgCard.b, (typeof mainThumbImage !== "undefined" && mainThumbImage) ? mainThumbImage.activeOpacity : 0.0)
                                        border.width: 2
                                        clip: true
                                        
                                        CrossfadeImage {
                                            id: mainThumbImage
                                            anchors.fill: parent
                                            anchors.margins: -1 // Slight negative margin to avoid edge artifacts
                                            targetSource: {
                                                var _v = statsRoot.thumbnailVersion;
                                                return statsHandler && currentSong ? statsHandler.getThumbnailPathForDifficulty(currentSong.arcaeaId || "", headerContainer.effectiveHeaderDiff) : ""
                                            }
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                        }
                                    }
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    
                                    // Top All-in-One Glass Chip Bar
                                    Flow {
                                        id: headerChipBar
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: Boolean(currentSong)

                                        property string displayPackName: {
                                            if (!currentSong) return ""
                                            if (isNarrow && (currentSong.strictPackAbbr || currentSong.packAbbr)) return currentSong.strictPackAbbr || currentSong.packAbbr
                                            return currentSong.strictPack || currentSong.pack || currentSong.packAbbr || ""
                                        }

                                        // 1. Pack Chip (Clickable -> Pack Dashboard)
                                        Rectangle {
                                            id: packChip
                                            visible: Boolean(currentSong) && Boolean(headerChipBar.displayPackName)
                                            width: packText.implicitWidth + 20
                                            height: 24
                                            radius: 12
                                            color: {
                                                if (currentSong && currentSong.packColor) {
                                                    if (Theme.isDarkMode) {
                                                        return Theme.alpha(currentSong.packColor, packMouseArea.containsMouse ? 0.50 : 0.35)
                                                    }
                                                    return packChip.getLightModePackBgColor(currentSong.packColor, packMouseArea.containsMouse)
                                                }
                                                return packMouseArea.containsMouse ? Theme.alpha(Theme.badgePackBg, 0.85) : Theme.alpha(Theme.badgePackBg, 0.60)
                                            }
                                            border.color: {
                                                if (currentSong && currentSong.packColor) {
                                                    return Theme.alpha(currentSong.packColor, packMouseArea.containsMouse ? 0.95 : 0.80)
                                                }
                                                return Theme.alpha(Theme.badgePackBorder, 0.80)
                                            }
                                            border.width: 1

                                            // Helper to convert hex pack color to accessible pastel tone (Dark mode: L=0.88)
                                            function getPastelColor(hexColor, isDark) {
                                                if (!hexColor) return Theme.badgePackText
                                                try {
                                                    var c = Qt.color(hexColor)
                                                    var r = c.r, g = c.g, b = c.b
                                                    var max = Math.max(r, g, b), min = Math.min(r, g, b)
                                                    var h, s, l = (max + min) / 2
                                                    if (max === min) {
                                                        h = s = 0
                                                    } else {
                                                        var d = max - min
                                                        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
                                                        switch (max) {
                                                            case r: h = (g - b) / d + (g < b ? 6 : 0); break
                                                            case g: h = (b - r) / d + 2; break
                                                            case b: h = (r - g) / d + 4; break
                                                        }
                                                        h /= 6
                                                    }
                                                    var targetL = 0.88 // Header always has dark blur overlay
                                                    if (s < 0.08) {
                                                        return Qt.hsla(0, 0, targetL, 1.0)
                                                    }
                                                    var targetS = Math.min(s, 0.65)
                                                    targetS = Math.max(targetS, 0.40)
                                                    return Qt.hsla(h, targetS, targetL, 1.0)
                                                } catch (e) {
                                                    return Theme.badgePackText
                                                }
                                            }

                                            // Helper to get dark pastel text color for light mode (black mixed with pastel tone: L=0.18)
                                            function getDarkPastelColor(hexColor) {
                                                if (!hexColor) return Theme.badgePackText
                                                try {
                                                    var c = Qt.color(hexColor)
                                                    var r = c.r, g = c.g, b = c.b
                                                    var max = Math.max(r, g, b), min = Math.min(r, g, b)
                                                    var h = 0, s = 0, l = (max + min) / 2
                                                    if (max !== min) {
                                                        var d = max - min
                                                        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
                                                        switch (max) {
                                                            case r: h = (g - b) / d + (g < b ? 6 : 0); break
                                                            case g: h = (b - r) / d + 2; break
                                                            case b: h = (r - g) / d + 4; break
                                                        }
                                                        h /= 6
                                                    }
                                                    var targetL = 0.18 // Dark base (tinted black)
                                                    if (s < 0.08) {
                                                        return Qt.hsla(0, 0, targetL, 1.0)
                                                    }
                                                    var targetS = Math.min(Math.max(s, 0.40), 0.65)
                                                    return Qt.hsla(h, targetS, targetL, 1.0)
                                                } catch (e) {
                                                    return "#1A1A20"
                                                }
                                            }

                                            // Helper to get light mode pack background (increased brightness and white-mix: L=0.84, S<=0.32, Alpha=0.82)
                                            function getLightModePackBgColor(hexColor, containsMouse) {
                                                if (!hexColor) return containsMouse ? Theme.alpha(Theme.badgePackBg, 0.92) : Theme.alpha(Theme.badgePackBg, 0.82)
                                                try {
                                                    var c = Qt.color(hexColor)
                                                    var r = c.r, g = c.g, b = c.b
                                                    var max = Math.max(r, g, b), min = Math.min(r, g, b)
                                                    var h = 0, s = 0, l = (max + min) / 2
                                                    if (max !== min) {
                                                        var d = max - min
                                                        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
                                                        switch (max) {
                                                            case r: h = (g - b) / d + (g < b ? 6 : 0); break
                                                            case g: h = (b - r) / d + 2; break
                                                            case b: h = (r - g) / d + 4; break
                                                        }
                                                        h /= 6
                                                    }
                                                    var targetL = Math.max(l + (1.0 - l) * 0.45, 0.84)
                                                    var targetS = Math.min(s * 0.65, 0.32)
                                                    var brightColor = (s < 0.08) ? Qt.hsla(0, 0, targetL, 1.0) : Qt.hsla(h, targetS, targetL, 1.0)
                                                    var alphaVal = containsMouse ? 0.92 : 0.82
                                                    return Theme.alpha(brightColor, alphaVal)
                                                } catch (e) {
                                                    return Theme.alpha(hexColor, containsMouse ? 0.92 : 0.82)
                                                }
                                            }

                                            Text {
                                                id: packText
                                                anchors.centerIn: parent
                                                text: headerChipBar.displayPackName
                                                color: {
                                                    if (currentSong && currentSong.packColor) {
                                                        return Theme.isDarkMode ? packChip.getPastelColor(currentSong.packColor, true) : packChip.getDarkPastelColor(currentSong.packColor)
                                                    }
                                                    return Theme.badgePackText
                                                }
                                                font.pixelSize: 11
                                                font.bold: true
                                            }

                                            MouseArea {
                                                id: packMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (statisticsHandler && currentSong && (currentSong.strictPack || currentSong.pack)) {
                                                        statisticsHandler.selectPackByName(currentSong.strictPack || currentSong.pack)
                                                    }
                                                }
                                            }
                                        }

                                        // 2. Version Chip
                                        Rectangle {
                                            visible: Boolean(currentSong) && Boolean(headerContainer.effectiveHeaderVersion || (currentSong && currentSong.version))
                                            width: verText.implicitWidth + 18
                                            height: 24
                                            radius: 12
                                            color: Theme.alpha(Theme.badgeVerBg, 0.65)
                                            border.color: Theme.alpha(Theme.badgeVerBorder, 0.80)
                                            border.width: 1
                                            Text {
                                                id: verText
                                                anchors.centerIn: parent
                                                text: "v" + (headerContainer.effectiveHeaderVersion || (currentSong ? currentSong.version : ""))
                                                color: Theme.badgeVerText
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                        }

                                        // Divider between Provenance and Specs
                                        Item {
                                            visible: Boolean((Boolean(headerChipBar.displayPackName) || Boolean(currentSong && currentSong.version)) &&
                                                             (Boolean(currentSong && currentSong.bpm) || Boolean(currentSong && Number(currentSong.length) > 0)))
                                            width: 7
                                            height: 24
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 1
                                                height: 14
                                                color: Theme.badgePillSep
                                            }
                                        }

                                        // 3. BPM Chip
                                        Rectangle {
                                            visible: Boolean(currentSong) && Boolean(currentSong.bpm)
                                            width: bpmText.implicitWidth + 18
                                            height: 24
                                            radius: 12
                                            color: Theme.alpha(Theme.badgeBpmBg, 0.65)
                                            border.color: Theme.alpha(Theme.badgeBpmBorder, 0.80)
                                            border.width: 1
                                            Text {
                                                id: bpmText
                                                anchors.centerIn: parent
                                                text: Boolean(currentSong) && Boolean(currentSong.bpm) ? ("BPM " + currentSong.bpm) : ""
                                                color: Theme.badgeBpmText
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                        }

                                        // 4. Length Chip
                                        Rectangle {
                                            visible: Boolean(currentSong) && Number(currentSong.length) > 0
                                            width: lengthText.implicitWidth + 18
                                            height: 24
                                            radius: 12
                                            color: Theme.alpha(Theme.badgeLenBg, 0.65)
                                            border.color: Theme.alpha(Theme.badgeLenBorder, 0.80)
                                            border.width: 1
                                            Text {
                                                id: lengthText
                                                anchors.centerIn: parent
                                                text: {
                                                    if (!currentSong || !currentSong.length) return ""
                                                    var len = currentSong.length
                                                    return Math.floor(len / 60) + ":" + (len % 60).toString().padStart(2, '0')
                                                }
                                                color: Theme.badgeLenText
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                        }
                                    }
                                    
                                    Text { 
                                        text: currentSong ? currentSong.title : "Select a song"
                                        font.family: statsRoot.titleFontFamily
                                        color: Theme.detailHeaderTitle; font.bold: true
                                        font.pixelSize: isNarrow ? 24 : 36
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    Text { 
                                        text: currentSong ? currentSong.artist : ""
                                        font.family: statsRoot.titleFontFamily
                                        color: Theme.detailHeaderArtist; font.pixelSize: 16
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
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

                            // Consultant Sheet search link (top-right, below Pack back-bar overlay when shown)
                            Rectangle {
                                id: sheetSearchButton
                                property bool sheetAvailable: false
                                property bool showShortcut: settingsHandler ? settingsHandler.getShowSongHeaderShortcut() : true
                                property bool searching: false
                                // Active chart = the chart the header currently represents (Song/Chart/Pack-song views)
                                readonly property var activeChart: {
                                    if (!currentSong) return null
                                    var list = difficultiesToShow || []
                                    for (var i = 0; i < list.length; i++) {
                                        if (list[i].difficulty === headerContainer.effectiveHeaderDiff) return list[i]
                                    }
                                    if (currentSong.difficultyName) return currentSong
                                    return list.length > 0 ? list[list.length - 1] : null
                                }
                                readonly property string sheetDiffName: {
                                    if (!activeChart) return ""
                                    return activeChart.isInscribed ? "INS" : (activeChart.difficultyName || "")
                                }
                                readonly property string sheetTitle: {
                                    if (!currentSong) return ""
                                    var t = currentSong.canonical_title || currentSong.title || ""
                                    return settingsHandler ? settingsHandler.toSheetTitle(t) : t
                                }

                                function refresh() {
                                    sheetAvailable = !!settingsHandler
                                                     && settingsHandler.isGoogleSheetConnected()
                                                     && settingsHandler.hasBoundSheet()
                                    searching = !!settingsHandler && settingsHandler.isSearchingSheet()
                                    showShortcut = settingsHandler ? settingsHandler.getShowSongHeaderShortcut() : true
                                }

                                Component.onCompleted: refresh()

                                Connections {
                                    target: settingsHandler
                                    function onGoogleSheetConnectionChanged() { sheetSearchButton.refresh() }
                                    function onSheetBindingChanged() { sheetSearchButton.refresh() }
                                    function onIsSearchingSheetChanged(searching) { sheetSearchButton.searching = searching }
                                    function onShowSongHeaderShortcutChanged(show) { sheetSearchButton.showShortcut = show }
                                }

                                visible: currentSong !== null && sheetAvailable && sheetDiffName !== ""
                                         && showShortcut
                                         && !Boolean(statisticsHandler && statisticsHandler.displayMode === "pack" && statisticsHandler.isPackDetailView)
                                z: 40
                                anchors.top: parent.top
                                anchors.topMargin: headerContainer.showBackToPack ? (isNarrow ? 44 : 48) : (isNarrow ? 12 : 18)
                                anchors.right: parent.right
                                anchors.rightMargin: isNarrow ? 15 : 24
                                width: sheetSearchRow.implicitWidth + 16
                                height: 28
                                radius: 8
                                border.width: 0
                                color: {
                                    var isHovered = sheetSearchMouse.containsMouse && !searching
                                    if (Theme.isDarkMode) {
                                        return isHovered ? Theme.alpha("#FFFFFF", 0.30) : Theme.alpha("#FFFFFF", 0.15)
                                    } else {
                                        return isHovered ? Theme.alpha("#000000", 0.30) : Theme.alpha("#000000", 0.15)
                                    }
                                }

                                Behavior on color { ColorAnimation { duration: 150 } }

                                Row {
                                    id: sheetSearchRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Image {
                                        width: 16
                                        height: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: (typeof consultantFaviconSource === "string" && consultantFaviconSource !== "") ? consultantFaviconSource : Qt.resolvedUrl("../resources/consultant_favicon.png")
                                        sourceSize.width: 32
                                        sourceSize.height: 32
                                        fillMode: Image.PreserveAspectFit
                                        mipmap: true
                                        smooth: true
                                    }
                                    Item {
                                        width: 14
                                        height: 14
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !sheetSearchButton.searching
                                            text: "\u2197"
                                            color: Theme.detailHeaderArtist
                                            font.bold: true
                                            font.pixelSize: 14
                                        }
                                        SpinnerIndicator {
                                            anchors.fill: parent
                                            lineWidth: 2
                                            radiusOffset: 1.5
                                            strokeColor: Theme.detailHeaderArtist
                                            running: sheetSearchButton.searching
                                        }
                                    }
                                }

                                MouseArea {
                                    id: sheetSearchMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !sheetSearchButton.searching
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (settingsHandler && sheetSearchButton.sheetTitle !== "") {
                                            settingsHandler.searchInConsultantSheet(
                                                currentSong.canonical_title || currentSong.title || "",
                                                sheetSearchButton.sheetDiffName)
                                        }
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
                                                diffColorTag: modelData.diffColorTag || ""
                                                isInscribed: modelData.isInscribed || false
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
                                                isBest10: (statsRoot.bestPotentialMarkLimit > 0 && Boolean(modelData.isBest10) && bestPotentialRank > 0)

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
                                            diffColorTag: modelData.diffColorTag || ""
                                            isInscribed: modelData.isInscribed || false
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
                                            isBest10: (statsRoot.bestPotentialMarkLimit > 0 && Boolean(modelData.isBest10) && bestPotentialRank > 0)

                                            onClicked: function(diff) {
                                                if (statisticsHandler) {
                                                    statisticsHandler.setSelectedDifficulty(diff)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
        property bool syncingBydIns: false
        
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
                                statisticsHandler.setFilter("include_inscribed", true)
                                statisticsHandler.setFilter("clear_types", [0, 1, 2, 3, 4, 5])
                            }
                            pstCheck.checked = true
                            prsCheck.checked = true
                            ftrCheck.checked = true
                            etrCheck.checked = true
                            bydCheck.checked = true
                            insCheck.checked = true
                            
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
                            RowLayout {
                                spacing: 15
                                DiffFilterCheckbox {
                                    id: bydCheck
                                    text: "BYD"
                                    diffColor: Theme.diffByd
                                    checked: true
                                    onCheckedChanged: {
                                        if (insCheck.visible && !filterPopup.syncingBydIns) {
                                            filterPopup.syncingBydIns = true
                                            insCheck.checked = bydCheck.checked
                                            filterPopup.syncingBydIns = false
                                        }
                                        filterPopup.updateDifficultyFilter()
                                    }
                                }
                                DiffFilterCheckbox {
                                    id: insCheck
                                    visible: statisticsHandler ? statisticsHandler.hasInscribedScore : false
                                    text: (statisticsHandler && statisticsHandler.isInscribedUnlocked) ? "INS" : "???"
                                    diffColor: Theme.diffIns
                                    diamondScale: 0.72
                                    checked: true
                                    onCheckedChanged: {
                                        if (!filterPopup.syncingBydIns) {
                                            filterPopup.updateDifficultyFilter()
                                        }
                                    }
                                }
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

                    Rectangle { height: 1; Layout.fillWidth: true; color: Theme.borderCard }

                    // Excluded Packs Management Shortcut Button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 8
                        color: manageExcludedMouse.containsMouse ? Theme.bgHover : Theme.bgButton
                        border.color: Theme.borderDivider
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "⚙️"
                                font.pixelSize: 13
                            }

                            Text {
                                text: "Manage Excluded Packs in Settings"
                                font.pixelSize: 12
                                font.bold: true
                                color: manageExcludedMouse.containsMouse ? Theme.accent : Theme.textPrimary
                            }
                        }

                        MouseArea {
                            id: manageExcludedMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                filterPopup.close()
                                if (typeof window !== "undefined" && typeof window.openSettingsWindow === "function") {
                                    window.openSettingsWindow("excludedPacks")
                                }
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
                statisticsHandler.setFilter("include_inscribed", insCheck.checked)
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
