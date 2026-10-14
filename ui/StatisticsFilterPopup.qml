import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Basic as Basic
import QtQuick.Window
import QtQuick.Effects

Popup {
        id: filterPopup
    parent: typeof statsRoot !== "undefined" ? statsRoot : Overlay.overlay
    width: 400
    height: 500
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    property bool initialized: false  // Prevent filter updates during initialization
    property bool syncingBydIns: false
    
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    
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
