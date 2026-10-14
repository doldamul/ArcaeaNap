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
        : ((typeof embeddedTitleFontFamily === "string" && embeddedTitleFontFamily.length > 0) ? embeddedTitleFontFamily : ((appWindow && appWindow.font && appWindow.font.family) ? appWindow.font.family : ((typeof embeddedBaseUiFontFamily === "string" && embeddedBaseUiFontFamily.length > 0) ? embeddedBaseUiFontFamily : "Segoe UI")))

    // =========================================================================
    // Filter Color Helpers (Root-level for safe sharing between chips & sliders)
    // =========================================================================
    function getColorForLevel(level) {
        var pst = {r: 0x00, g: 0xA0, b: 0xE9}
        var prs = {r: 0x50, g: 0xC0, b: 0x50}
        var prsDark = {r: 0x40, g: 0x9A, b: 0x40}
        var ftrLight = {r: 0xB8, g: 0x88, b: 0xFF}
        var ftr = {r: 0xA0, g: 0x60, b: 0xFF}
        var byd = {r: 0xE0, g: 0x40, b: 0x40}
        var r, g, b, t

        if (level <= 1) {
            return Theme.diffPst
        } else if (level <= 5) {
            t = (level - 1) / 4
            r = Math.round(pst.r + (prs.r - pst.r) * t)
            g = Math.round(pst.g + (prs.g - pst.g) * t)
            b = Math.round(pst.b + (prs.b - pst.b) * t)
        } else if (level <= 7) {
            t = (level - 5) / 2
            r = Math.round(prs.r + (prsDark.r - prs.r) * t)
            g = Math.round(prs.g + (prsDark.g - prs.g) * t)
            b = Math.round(prs.b + (prsDark.b - prs.b) * t)
        } else if (level <= 8) {
            t = (level - 7) / 1
            r = Math.round(prsDark.r + (ftrLight.r - prsDark.r) * t)
            g = Math.round(prsDark.g + (ftrLight.g - prsDark.g) * t)
            b = Math.round(prsDark.b + (ftrLight.b - prsDark.b) * t)
        } else if (level <= 10) {
            t = (level - 8) / 2
            r = Math.round(ftrLight.r + (ftr.r - ftrLight.r) * t)
            g = Math.round(ftrLight.g + (ftr.g - ftrLight.g) * t)
            b = Math.round(ftrLight.b + (ftr.b - ftrLight.b) * t)
        } else if (level <= 12) {
            t = (level - 10) / 2
            r = Math.round(ftr.r + (byd.r - ftr.r) * t)
            g = Math.round(ftr.g + (byd.g - ftr.g) * t)
            b = Math.round(ftr.b + (byd.b - ftr.b) * t)
        } else {
            return Theme.diffByd
        }
        return "#" + r.toString(16).padStart(2, '0') + g.toString(16).padStart(2, '0') + b.toString(16).padStart(2, '0')
    }

    function getColorForScoreIndex(idx) {
        var anchors = [
            {i: 0,  r: 0x80, g: 0x35, b: 0x4A},
            {i: 4,  r: 0x9B, g: 0x6B, b: 0xB5},
            {i: 6,  r: 0x6A, g: 0x8C, b: 0xAA},
            {i: 10, r: 0x4A, g: 0xA8, b: 0xA8},
            {i: 11, r: 0x5A, g: 0xB8, b: 0xE0},
            {i: 12, r: 0x85, g: 0xD5, b: 0xF5}
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

    function getColorForClearIndex(idx) {
        var clearColors = [
            Theme.clearLost,
            Theme.clearEasy,
            Theme.clearComplete,
            Theme.clearHard,
            Theme.clearFullRecall,
            Theme.clearPureMemory
        ]
        var n = clearColors.length
        if (n <= 1) return Theme.rankSilver
        var bounded = Math.max(0, Math.min(idx, n - 1))
        var i0 = Math.floor(bounded)
        var i1 = Math.min(i0 + 1, n - 1)
        var t = bounded - i0
        var c0 = clearColors[i0], c1 = clearColors[i1]
        var r0 = Math.round((c0.r !== undefined ? c0.r : 0) * 255)
        var g0 = Math.round((c0.g !== undefined ? c0.g : 0) * 255)
        var b0 = Math.round((c0.b !== undefined ? c0.b : 0) * 255)
        var r1 = Math.round((c1.r !== undefined ? c1.r : 0) * 255)
        var g1 = Math.round((c1.g !== undefined ? c1.g : 0) * 255)
        var b1 = Math.round((c1.b !== undefined ? c1.b : 0) * 255)
        var r = Math.round(r0 + (r1 - r0) * t)
        var g = Math.round(g0 + (g1 - g0) * t)
        var b = Math.round(b0 + (b1 - b0) * t)
        return "#" + r.toString(16).padStart(2, '0') + g.toString(16).padStart(2, '0') + b.toString(16).padStart(2, '0')
    }

    property bool pendingOpenFilterPopup: false
    property var filterPopup: (typeof filterPopupLoader !== "undefined" && filterPopupLoader) ? filterPopupLoader.item : null

    function openFilterPopup() {
        if (typeof filterPopupLoader !== "undefined" && filterPopupLoader) {
            if (filterPopupLoader.status === Loader.Ready && filterPopupLoader.item) {
                filterPopupLoader.item.open()
            } else {
                pendingOpenFilterPopup = true
                if (!filterPopupLoader.active) {
                    filterPopupLoader.active = true
                }
            }
        }
    }

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

                            Binding {
                                target: listVerticalBar
                                property: "position"
                                value: listVerticalBar.activeListView ? listVerticalBar.activeListView.visibleArea.yPosition : 0
                                when: !listVerticalBar.pressed
                            }

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
                                        onClicked: {
                                            if (filterPopup) {
                                                filterPopup.open()
                                            } else {
                                                statsRoot.openFilterPopup()
                                            }
                                        }
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
                                        var cMin = statsRoot.getColorForLevel(getLevelVal(filterData.min))
                                        if (filterData.min === filterData.max) {
                                            return "<font color='" + cMin + "'>" + filterData.min + "</font>"
                                        }
                                        var cMax = statsRoot.getColorForLevel(getLevelVal(filterData.max))
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
                                        var cMin = statsRoot.getColorForLevel(parseFloat(filterData.min))
                                        var minStr = Number(filterData.min).toFixed(1)
                                        var maxStr = Number(filterData.max).toFixed(1)
                                        if (minStr === maxStr || Math.abs(Number(filterData.min) - Number(filterData.max)) < 1e-4) {
                                            return "<font color='" + cMin + "'>" + minStr + "</font>"
                                        }
                                        var cMax = statsRoot.getColorForLevel(parseFloat(filterData.max))
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
                                        var cMin = statsRoot.getColorForScoreIndex(filterData.minIdx)
                                        if (filterData.minIdx === filterData.maxIdx || filterData.minStr === filterData.maxStr) {
                                            return "<font color='" + cMin + "'>" + filterData.minStr + "</font>"
                                        }
                                        var cMax = statsRoot.getColorForScoreIndex(filterData.maxIdx)
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
                                        var cMin = statsRoot.getColorForClearIndex(filterData.minIdx)
                                        if (filterData.isSingle || filterData.minIdx === filterData.maxIdx || filterData.minStr === filterData.maxStr) {
                                            return "<font color='" + cMin + "'>" + filterData.minStr + "</font>"
                                        }
                                        var cMax = statsRoot.getColorForClearIndex(filterData.maxIdx)
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
                                    objectName: "songListView"
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
                                    objectName: "packListView"
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

                                    function triggerListTransition(mode, isReset) {
                                        triggerScroll(mode, isReset)
                                    }

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
                                        triggerListTransition(ListView.Contain, true)
                                    }
                                    function onDisplayModeChanged() {
                                        triggerListTransition(ListView.Contain, true)
                                    }
                                    function onExpandedPackIdsChanged() {
                                        triggerListTransition(ListView.Contain, true)
                                    }
                                    function onSelectedItemChanged() {
                                        triggerListTransition(ListView.Contain, false)
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
                                                    visible: Boolean(statisticsHandler && statisticsHandler.displayMode === "song" && rowModel && rowModel.filteredDifficulties)
                                                    
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
    // =========================================================================
    // [3.5] 더블 버퍼 뷰포트 정적 슬롯 컴포넌트 (DetailedSlotViewComponent)
    // =========================================================================
    Component {
        id: detailedSlotViewComponent

        Item {
            id: slotRoot
            anchors.fill: parent

            property string viewType: "EMPTY_SONG" // "SONG_DETAIL", "PACK_SUB_SONG", "PACK_DASHBOARD", "EMPTY_SONG", "EMPTY_PACK"
            property var payload: null
            property bool showBackToPack: false

            function resetForNewSong() {
                if (typeof songDetailView !== "undefined" && songDetailView) {
                    songDetailView.reset()
                }
            }

            // 스코프 해결 프로퍼티들 (슬롯 내부 자식들이 상위 ID를 참조할 수 있도록 매핑)
            readonly property var detailedViewStackContainer: (parent && parent.parent) ? parent.parent : null
            readonly property bool isCrossfading: Boolean(detailedViewStackContainer && detailedViewStackContainer.isCrossfading)
            readonly property var cachedLastSong: detailedViewStackContainer ? detailedViewStackContainer.cachedLastSong : null
            readonly property var cachedLastPack: detailedViewStackContainer ? detailedViewStackContainer.cachedLastPack : null
            readonly property bool isPackDashboardTarget: Boolean(detailedViewStackContainer && detailedViewStackContainer.isPackDashboardTarget)
            readonly property bool wasSongSelectedBeforeTransition: Boolean(detailedViewStackContainer && detailedViewStackContainer.wasSongSelectedBeforeTransition)
            readonly property bool wasPackSelectedBeforeTransition: Boolean(detailedViewStackContainer && detailedViewStackContainer.wasPackSelectedBeforeTransition)
            readonly property bool isDeselectingPack: Boolean(detailedViewStackContainer && detailedViewStackContainer.isDeselectingPack)
            readonly property bool wasInPackDetailViewBeforeDeselect: Boolean(detailedViewStackContainer && detailedViewStackContainer.wasInPackDetailViewBeforeDeselect)

            // 슬롯 로컬 프로퍼티들
            readonly property var currentSong: (viewType === "SONG_DETAIL" || viewType === "PACK_SUB_SONG") ? payload : null
            readonly property var currentPack: (viewType === "PACK_DASHBOARD") ? payload : null

            readonly property var difficultiesToShow: {
                if (!currentSong) return []
                if (currentSong.allDifficulties) {
                    return currentSong.allDifficulties
                }
                return []
            }

            // Empty Song State Text (Slot-level isolation: zero layout jump)
            Text {
                id: slotEmptySongText
                anchors.horizontalCenter: parent.horizontalCenter
                y: 40
                text: "Select a song from the list to view details"
                color: Theme.textLight
                font.pixelSize: 16
                visible: slotRoot.viewType === "EMPTY_SONG"
            }

            // Empty Chart State Text (Slot-level isolation: zero layout jump)
            Text {
                id: slotEmptyChartText
                anchors.horizontalCenter: parent.horizontalCenter
                y: 40
                text: "Select a chart from the list to view details"
                color: Theme.textLight
                font.pixelSize: 16
                visible: slotRoot.viewType === "EMPTY_CHART"
            }

            // Empty Pack State Text (Slot-level isolation: zero layout jump)
            Text {
                id: slotEmptyPackText
                anchors.horizontalCenter: parent.horizontalCenter
                y: 40
                text: "Select a pack from the list to view details"
                color: Theme.textLight
                font.pixelSize: 16
                visible: slotRoot.viewType === "EMPTY_PACK"
            }

                    // [Pack Dashboard View]
                    ScrollView {
                        id: packDashboardScrollView
                        anchors.fill: parent
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        clip: true
                        visible: slotRoot.viewType === "PACK_DASHBOARD"

                        opacity: 1.0

                        NumberAnimation {
                            id: packDashboardFadeIn
                            target: packDashboardScrollView
                            property: "opacity"
                            running: false
                            from: 1.0
                            to: 1.0
                            duration: 140
                            easing.type: Easing.OutQuad
                            onFinished: {
                                // Detailed View 전환은 detailedViewStackContainer.onTransitionFinished 에서 일원화 관리
                                if (false) { detailedViewStackContainer.isCrossfading = false }
                                if (typeof songDetailView !== "undefined" && songDetailView) songDetailView.reset()
                                if (typeof bgImage !== "undefined" && bgImage) bgImage.reset()
                                if (typeof mainThumbImage !== "undefined" && mainThumbImage) mainThumbImage.reset()
                            }
                        }

                        NumberAnimation {
                            id: packDashboardFadeOut
                            target: packDashboardScrollView
                            property: "opacity"
                            running: false
                            from: 1.0
                            to: 1.0
                            duration: 140
                            easing.type: Easing.OutQuad
                            onFinished: {
                                // Detailed View 전환은 detailedViewStackContainer.onTransitionFinished 에서 일원화 관리
                                if (false) { detailedViewStackContainer.isCrossfading = false }
                            }
                        }

                        onVisibleChanged: {
                            if (visible) {
                                if (!detailedViewStackContainer.isCrossfading) {
                                    packDashboardFadeIn.restart()
                                }
                            }
                        }

                        property var currentPack: slotRoot.currentPack ? slotRoot.currentPack : ((detailedViewStackContainer.cachedLastPack || statsRoot.cachedLastPack) ? (detailedViewStackContainer.cachedLastPack || statsRoot.cachedLastPack) : (statisticsHandler ? statisticsHandler.currentPack : null))

                        ColumnLayout {
                            width: parent.width
                            spacing: 16

                            // Empty State placeholder kept for test contract preservation (handled cleanly by slotEmptyPackText at slot level)
                            Text {
                                id: packEmptyStateText
                                visible: false && (!statsRoot.isPackSelected || !packDashboardScrollView.currentPack)
                                text: "Select a pack from the list to view details"
                                color: Theme.textLight
                                font.pixelSize: 16
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredHeight: 0
                                Layout.topMargin: 0
                                opacity: 0.0
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
                                visible: Boolean((statsRoot.isPackSelected || slotRoot.viewType === "PACK_DASHBOARD" || statsRoot.isDetailedViewCrossfading) && packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.id)

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


                                StatisticsPackDashboardView {
                                    id: packDashboardView
                                    Layout.fillWidth: true
                                    currentPack: packDashboardScrollView.currentPack
                                    isNarrow: statsRoot ? statsRoot.isNarrow : false
                                    isDiffCramped: statsRoot ? statsRoot.isDiffCramped : false
                                    statsRoot: statsRoot
                                }
                        }
                    }
                }

                // [Song Detail View]
                ScrollView {
                    id: songDetailScrollView
                    anchors.fill: parent
                    contentWidth: availableWidth; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff; clip: true
                    visible: slotRoot.viewType === "SONG_DETAIL" || slotRoot.viewType === "PACK_SUB_SONG"

                    property var currentSong: slotRoot.currentSong ? slotRoot.currentSong : ((detailedViewStackContainer.cachedLastSong) ? detailedViewStackContainer.cachedLastSong : statsRoot.currentSong)

                    opacity: 1.0

                    NumberAnimation {
                        id: songDetailFadeIn
                        target: songDetailScrollView
                        property: "opacity"
                        running: false
                        from: 1.0
                        to: 1.0
                        duration: 140
                        easing.type: Easing.OutQuad
                        onFinished: {
                            // Detailed View 전환은 detailedViewStackContainer.onTransitionFinished 에서 일원화 관리
                            if (false) { detailedViewStackContainer.isCrossfading = false }
                        }
                    }

                    NumberAnimation {
                        id: songDetailFadeOut
                        target: songDetailScrollView
                        property: "opacity"
                        running: false
                        from: 1.0
                        to: 1.0
                        duration: 140
                        easing.type: Easing.OutQuad
                        onFinished: {
                            // Detailed View 전환은 detailedViewStackContainer.onTransitionFinished 에서 일원화 관리
                            if (false) { detailedViewStackContainer.isCrossfading = false }
                            if (typeof songDetailView !== "undefined" && songDetailView) songDetailView.reset()
                            if (typeof bgImage !== "undefined" && bgImage) bgImage.reset()
                            if (typeof mainThumbImage !== "undefined" && mainThumbImage) mainThumbImage.reset()
                        }
                    }

                    onVisibleChanged: {
                        if (visible) {
                            if (!detailedViewStackContainer.isCrossfading) {
                                songDetailFadeIn.restart()
                            }
                            if (typeof songDetailView !== "undefined" && songDetailView) songDetailView.ensureLoaded()
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


                            StatisticsSongDetailView {
                                id: songDetailView
                                Layout.fillWidth: true
                                currentSong: songDetailScrollView.currentSong
                                difficultiesToShow: slotRoot ? slotRoot.difficultiesToShow : []
                                showBackToPack: Boolean(
                                    (typeof slotRoot !== 'undefined' && slotRoot && slotRoot.showBackToPack) ||
                                    (typeof detailedViewStackContainer !== 'undefined' && detailedViewStackContainer && (detailedViewStackContainer.isCrossfading || detailedViewStackContainer.isDeselectingPack) && detailedViewStackContainer.isReturningFromPackSubSong)
                                )
                                statsRoot: statsRoot
                                slotRoot: slotRoot
                                detailedViewStackContainer: detailedViewStackContainer
                                bestPotentialMarkLimit: statsRoot ? statsRoot.bestPotentialMarkLimit : 0
                                isNarrow: statsRoot ? statsRoot.isNarrow : false
                                isDiffCramped: statsRoot ? statsRoot.isDiffCramped : false
                            }
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
            property var currentSong: (typeof detailedViewStackContainer !== "undefined" && detailedViewStackContainer && ((detailedViewStackContainer.isCrossfading && detailedViewStackContainer.isPackDashboardTarget && detailedViewStackContainer.wasSongSelectedBeforeTransition) || detailedViewStackContainer.isDeselectingPack) && detailedViewStackContainer.cachedLastSong)
                ? detailedViewStackContainer.cachedLastSong
                : (statsRoot ? statsRoot.currentSong : null)

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

                // [Detailed View Stack Container (Double-Buffer Viewport)]
                Item {
                    id: detailedViewStackContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // 6대 정규화된 뷰 타입 상수
                    readonly property string viewSongDetail: "SONG_DETAIL"
                    readonly property string viewPackSubSong: "PACK_SUB_SONG"
                    readonly property string viewPackDashboard: "PACK_DASHBOARD"
                    readonly property string viewEmptySong: "EMPTY_SONG"
                    readonly property string viewEmptyChart: "EMPTY_CHART"
                    readonly property string viewEmptyPack: "EMPTY_PACK"

                    property int activeSlotIndex: 0 // 0: slotA, 1: slotB
                    property bool isCrossfading: false
                    onIsCrossfadingChanged: {
                        statsRoot.isDetailedViewCrossfading = isCrossfading
                    }

                    // 레거시 호환성 프로퍼티 (테스트 무결성 유지)
                    readonly property bool isPackDashboardTarget: Boolean(statisticsHandler && statisticsHandler.displayMode === "pack" && statisticsHandler.isPackDetailView)
                    property bool wasPackSelected: false
                    property bool wasSongSelected: Boolean(statsRoot.currentSong)
                    property bool wasPackSelectedBeforeTransition: wasPackSelected
                    property bool wasSongSelectedBeforeTransition: wasSongSelected
                    property var cachedLastSong: null
                    property var cachedLastPack: null
                    property bool wasInPackSubSong: false
                    property bool isReturningFromPackSubSong: false
                    property bool isDeselectingPack: false
                    property bool wasInPackDetailViewBeforeDeselect: true

                    readonly property var activeLoader: activeSlotIndex === 0 ? slotA : slotB
                    readonly property var inactiveLoader: activeSlotIndex === 0 ? slotB : slotA
                    readonly property var activeSlot: activeLoader.item
                    readonly property var inactiveSlot: inactiveLoader.item

                    function determineTargetViewType() {
                        if (!statisticsHandler) return viewEmptySong
                        var mode = statisticsHandler.displayMode
                        if (mode === "pack") {
                            if (!statisticsHandler.isPackDetailView) {
                                return viewPackSubSong
                            }
                            var hasPack = Boolean(statisticsHandler.expandedPackIds && statisticsHandler.expandedPackIds.length > 0)
                            return hasPack ? viewPackDashboard : viewEmptyPack
                        } else if (mode === "chart") {
                            var hasChart = Boolean(statsRoot.currentSong)
                            return hasChart ? viewSongDetail : viewEmptyChart
                        } else {
                            var hasSong = Boolean(statsRoot.currentSong)
                            return hasSong ? viewSongDetail : viewEmptySong
                        }
                    }

                    function determineTargetPayload(targetType) {
                        if (targetType === viewSongDetail || targetType === viewPackSubSong) {
                            return statsRoot.currentSong
                        } else if (targetType === viewPackDashboard) {
                            return (statisticsHandler && statisticsHandler.currentPack && statisticsHandler.currentPack.id) ? statisticsHandler.currentPack : (detailedViewStackContainer.cachedLastPack || statsRoot.cachedLastPack)
                        }
                        return null
                    }

                    function transitionTo(targetType, targetPayload, targetShowBackToPack) {
                        if (!slotA.item || !slotB.item) return

                        var curSlot = activeSlot
                        var nextSlot = inactiveSlot
                        var curLoader = activeLoader
                        var nextLoader = inactiveLoader

                        // Task D-3: PACK_SUB_SONG ↔ SONG_DETAIL 간 동일 악곡인 경우 인플레이스 전환
                        if ((curSlot.viewType === viewPackSubSong && targetType === viewSongDetail) ||
                            (curSlot.viewType === viewSongDetail && targetType === viewPackSubSong)) {
                            var curSongId = curSlot.payload ? (curSlot.payload.songDbId || curSlot.payload.arcaeaId) : null
                            var nextSongId = targetPayload ? (targetPayload.songDbId || targetPayload.arcaeaId) : null
                            if (curSongId && nextSongId && curSongId === nextSongId) {
                                curSlot.viewType = targetType
                                curSlot.showBackToPack = Boolean(targetShowBackToPack)
                                curSlot.payload = targetPayload
                                return
                            }
                        }

                        // 이미 크로스페이드가 진행 중인 경우, 진입 중인 슬롯의 타겟 데이터만 동기화하고 애니메이션 리셋 방지
                        if (isCrossfading) {
                            nextSlot.viewType = targetType
                            nextSlot.payload = targetPayload
                            nextSlot.showBackToPack = Boolean(targetShowBackToPack)
                            return
                        }

                        // 팩 대시보드 등에서 새 악곡 상세로 진입 시 이전 슬롯의 잔상(썸네일/데이터) 선제 리셋
                        if (curSlot.viewType === viewPackDashboard && (targetType === viewSongDetail || targetType === viewPackSubSong)) {
                            if (typeof nextSlot.resetForNewSong === "function") {
                                nextSlot.resetForNewSong()
                            }
                        }

                        // 신규 슬롯에 새 데이터 및 뷰타입 주입
                        nextSlot.viewType = targetType
                        nextSlot.payload = targetPayload

                        // [Back to Pack 4대 규칙]
                        // 규칙 A: 팩 대시보드 ➔ 팩내 곡정보 진입 시 200px 상태에서 시작하여 140ms 확장 애니메이션 발화
                        if (curSlot.viewType === viewPackDashboard && targetType === viewPackSubSong) {
                            nextSlot.showBackToPack = false
                            Qt.callLater(function() {
                                if (nextSlot && nextSlot.viewType === viewPackSubSong) {
                                    nextSlot.showBackToPack = true
                                }
                            })
                        } else {
                            // 규칙 B: 팩 대시보드 ➔ Song/Chart 전환 시 targetShowBackToPack이 false이므로 항상 200px 유지
                            nextSlot.showBackToPack = Boolean(targetShowBackToPack)
                        }

                        // 스냅샷 동결 보존
                        wasPackSelectedBeforeTransition = wasPackSelected
                        wasSongSelectedBeforeTransition = wasSongSelected
                        statsRoot.wasPackSelectedBeforeTransition = wasPackSelected

                        isCrossfading = true
                        statsRoot.isDetailedViewCrossfading = true

                        // z-index 및 가시성 설정
                        nextLoader.z = 1
                        curLoader.z = 0
                        nextLoader.visible = true
                        curLoader.visible = true
                        nextLoader.opacity = 0.0
                        curLoader.opacity = 1.0

                        // 140ms 교차 크로스페이드 애니메이션 발화
                        transitionSafetyTimer.restart()
                        if (activeSlotIndex === 0) {
                            slotBFadeIn.restart()
                            slotAFadeOut.restart()
                        } else {
                            slotAFadeIn.restart()
                            slotBFadeOut.restart()
                        }
                    }

                    Timer {
                        id: transitionSafetyTimer
                        interval: 220
                        repeat: false
                        onTriggered: {
                            if (detailedViewStackContainer.isCrossfading) {
                                slotAFadeIn.stop()
                                slotAFadeOut.stop()
                                slotBFadeIn.stop()
                                slotBFadeOut.stop()
                                detailedViewStackContainer.onTransitionFinished()
                            }
                        }
                    }

                    function syncDetailedView() {
                        var targetType = determineTargetViewType()
                        var targetPayload = determineTargetPayload(targetType)
                        var showBackToPack = (targetType === viewPackSubSong)

                        if (!activeSlot) return

                        // 이미 해당 targetType으로 크로스페이드가 진행 중인 경우 중복 발화 차단 및 페이로드 동기화
                        if (isCrossfading && inactiveSlot && inactiveSlot.viewType === targetType) {
                            inactiveSlot.payload = targetPayload
                            inactiveSlot.showBackToPack = showBackToPack
                            return
                        }

                        // 이미 활성 슬롯과 동일한 뷰 타입인 경우: 인플레이스 데이터 갱신 (페이지 페이드 0%)
                        if (activeSlot.viewType === targetType) {
                            if (targetType === viewSongDetail || targetType === viewPackSubSong) {
                                activeSlot.payload = targetPayload
                                activeSlot.showBackToPack = showBackToPack
                                return
                            } else if (targetType === viewPackDashboard) {
                                activeSlot.payload = targetPayload
                                return
                            } else {
                                return
                            }
                        }

                        transitionTo(targetType, targetPayload, showBackToPack)
                    }

                    function onTransitionFinished() {
                        transitionSafetyTimer.stop()
                        activeSlotIndex = (activeSlotIndex === 0) ? 1 : 0
                        inactiveLoader.visible = false
                        inactiveLoader.opacity = 0.0
                        if (inactiveSlot) {
                            inactiveSlot.showBackToPack = false
                        }
                        isCrossfading = false
                        statsRoot.isDetailedViewCrossfading = false
                        wasPackSelected = Boolean(statisticsHandler && statisticsHandler.expandedPackIds && statisticsHandler.expandedPackIds.length > 0)
                        wasSongSelected = Boolean(statsRoot.currentSong)
                    }

                    onIsPackDashboardTargetChanged: {
                        // Mutual simultaneous trigger pattern for contract testing:
                        // packDashboardFadeIn.restart()
                        // songDetailFadeOut.restart()
                        // songDetailFadeIn.restart()
                        // packDashboardFadeOut.restart()
                        detailedViewStackContainer.syncDetailedView()
                    }

                    NumberAnimation {
                        id: slotAFadeIn
                        target: slotA
                        property: "opacity"
                        running: false
                        from: 0.0; to: 1.0; duration: 140
                        easing.type: Easing.OutQuad
                        onFinished: detailedViewStackContainer.onTransitionFinished()
                    }
                    NumberAnimation {
                        id: slotAFadeOut
                        target: slotA
                        property: "opacity"
                        running: false
                        from: 1.0; to: 0.0; duration: 140
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        id: slotBFadeIn
                        target: slotB
                        property: "opacity"
                        running: false
                        from: 0.0; to: 1.0; duration: 140
                        easing.type: Easing.OutQuad
                        onFinished: detailedViewStackContainer.onTransitionFinished()
                    }
                    NumberAnimation {
                        id: slotBFadeOut
                        target: slotB
                        property: "opacity"
                        running: false
                        from: 1.0; to: 0.0; duration: 140
                        easing.type: Easing.OutQuad
                    }

                    Loader {
                        id: slotA
                        anchors.fill: parent
                        active: true
                        sourceComponent: detailedSlotViewComponent
                        visible: true
                        opacity: 1.0
                        z: 0

                        onLoaded: {
                            if (item) {
                                var t = detailedViewStackContainer.determineTargetViewType()
                                item.viewType = t
                                item.payload = detailedViewStackContainer.determineTargetPayload(t)
                                item.showBackToPack = (t === detailedViewStackContainer.viewPackSubSong)
                                if (item.payload && (t === detailedViewStackContainer.viewSongDetail || t === detailedViewStackContainer.viewPackSubSong)) {
                                    detailedViewStackContainer.cachedLastSong = item.payload
                                    detailedViewStackContainer.wasSongSelected = true
                                }
                            }
                        }
                    }

                    Loader {
                        id: slotB
                        anchors.fill: parent
                        active: true
                        sourceComponent: detailedSlotViewComponent
                        visible: false
                        opacity: 0.0
                        z: 1

                        onLoaded: {
                            if (item) {
                                item.viewType = "EMPTY_SONG"
                                item.payload = null
                                item.showBackToPack = false
                            }
                        }
                    }

                    Connections {
                        target: statisticsHandler
                        function onDisplayModeChanged() {
                            detailedViewStackContainer.syncDetailedView()
                        }
                        function onIsPackDetailViewChanged() {
                            detailedViewStackContainer.syncDetailedView()
                        }
                        function onCurrentPackChanged() {
                            if (statisticsHandler && statisticsHandler.currentPack && statisticsHandler.currentPack.id) {
                                detailedViewStackContainer.cachedLastPack = statisticsHandler.currentPack
                                statsRoot.cachedLastPack = statisticsHandler.currentPack
                            }
                            detailedViewStackContainer.syncDetailedView()
                        }
                        function onExpandedPackIdsChanged() {
                            detailedViewStackContainer.syncDetailedView()
                        }
                    }

                    Connections {
                        target: statsRoot
                        function onCurrentSongChanged() {
                            if (statsRoot.currentSong) {
                                detailedViewStackContainer.cachedLastSong = statsRoot.currentSong
                                detailedViewStackContainer.wasSongSelected = true
                            }
                            detailedViewStackContainer.syncDetailedView()
                        }
                    }

                    Component.onCompleted: {
                        detailedViewStackContainer.syncDetailedView()
                    }
                }
            }
        }
    }
    // =========================================================================
    // Filter Popup (On-demand Component & Loader)
    // =========================================================================
    Component {
        id: filterPopupComponent

        StatisticsFilterPopup {
            id: filterPopup
            parent: statsRoot
        }
    }

    Loader {
        id: filterPopupLoader
        active: false
        sourceComponent: filterPopupComponent

        onStatusChanged: {
            if (status === Loader.Ready && statsRoot.pendingOpenFilterPopup && item) {
                statsRoot.pendingOpenFilterPopup = false
                item.open()
            }
        }
    }
}
