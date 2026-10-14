import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

ColumnLayout {
    id: songDetailPage
    Layout.fillWidth: true
    spacing: 0

    property var currentSong: null
    property var difficultiesToShow: []
    property bool showBackToPack: false
    property var statsRoot: null
    property var slotRoot: null
    property var detailedViewStackContainer: null
    property bool isNarrow: (statsRoot && statsRoot.isNarrow) ? statsRoot.isNarrow : false
    property bool isDiffCramped: (statsRoot && statsRoot.isDiffCramped) ? statsRoot.isDiffCramped : false
    property int bestPotentialMarkLimit: (statsRoot && statsRoot.bestPotentialMarkLimit !== undefined) ? statsRoot.bestPotentialMarkLimit : 0
    property string titleFontFamily: (statsRoot && statsRoot.titleFontFamily) ? statsRoot.titleFontFamily : ((typeof embeddedTitleFontFamily === "string" && embeddedTitleFontFamily.length > 0) ? embeddedTitleFontFamily : "Segoe UI")
    property int thumbnailVersion: (statsRoot && statsRoot.thumbnailVersion) ? statsRoot.thumbnailVersion : 0

    // Aliases for external reference & contract preservation
    property alias headerContainer: headerContainer
    property alias backToPackBarContainer: backToPackBarContainer
    property alias backToPackMouse: backToPackMouse
    property alias bgImage: bgImage
    property alias mainThumbRect: mainThumbRect
    property alias mainThumbImage: mainThumbImage
    property alias headerChipBar: headerChipBar
    property alias packChip: packChip

    function reset() {
        if (bgImage) bgImage.reset()
        if (mainThumbImage) mainThumbImage.reset()
    }

    function ensureLoaded() {
        if (bgImage) bgImage.ensureLoaded()
        if (mainThumbImage) mainThumbImage.ensureLoaded()
    }

                            // Song info header
                            Item {
                                id: headerContainer
                                property bool showBackToPack: Boolean(
                                    (typeof slotRoot !== "undefined" && slotRoot && slotRoot.showBackToPack) ||
                                    (typeof detailedViewStackContainer !== "undefined" && detailedViewStackContainer && (detailedViewStackContainer.isCrossfading || detailedViewStackContainer.isDeselectingPack) && detailedViewStackContainer.isReturningFromPackSubSong)
                                )
                            Layout.fillWidth: true
                            Layout.preferredHeight: showBackToPack ? (isNarrow ? 236 : 238) : (isNarrow ? 180 : 200)
                            implicitHeight: Layout.preferredHeight
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

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
                                            var _v = thumbnailVersion;
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
                                anchors.topMargin: headerContainer.showBackToPack ? (isNarrow ? 53 : 62) : (isNarrow ? 15 : 24)
                                anchors.bottomMargin: isNarrow ? 15 : 24
                                anchors.leftMargin: isNarrow ? 15 : 24
                                anchors.rightMargin: isNarrow ? 15 : 24
                                spacing: isNarrow ? 15 : 24

                                Behavior on anchors.topMargin { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                                
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
                                            var _v = thumbnailVersion;
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
                                                var _v = thumbnailVersion;
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
                                    
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Text { 
                                            text: (currentSong && currentSong.title) ? currentSong.title : "Select a song"
                                            font.family: titleFontFamily
                                            color: Theme.detailHeaderTitle; font.bold: true
                                            font.pixelSize: isNarrow ? 24 : 36
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Text { 
                                        text: (currentSong && currentSong.artist) ? currentSong.artist : ""
                                        font.family: titleFontFamily
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

                            // Song Favorite Button in Detail Header (Top-Right)
                            Rectangle {
                                id: headerSongFavButton
                                visible: Boolean(currentSong && currentSong.arcaeaId)
                                z: 40
                                anchors.top: parent.top
                                anchors.topMargin: headerContainer.showBackToPack ? (isNarrow ? 53 : 62) : (isNarrow ? 15 : 24)
                                anchors.right: parent.right
                                anchors.rightMargin: isNarrow ? 15 : 24
                                Behavior on anchors.topMargin { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                                width: 28
                                height: 28
                                radius: 8
                                border.width: 0
                                property bool isSongFav: Boolean(currentSong && currentSong.isSongFavorite)
                                property bool effectiveFav: headerSongFavMouse.pressed ? !isSongFav : isSongFav
                                color: {
                                    if (headerSongFavMouse.pressed) return "transparent"
                                    var isHovered = headerSongFavMouse.containsMouse
                                    if (Theme.isDarkMode) {
                                        return isHovered ? Theme.alpha("#FFFFFF", 0.30) : Theme.alpha("#FFFFFF", 0.15)
                                    } else {
                                        return isHovered ? Theme.alpha("#000000", 0.30) : Theme.alpha("#000000", 0.15)
                                    }
                                }
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.effectiveFav ? "♥" : "♡"
                                    font.pixelSize: 18
                                    color: parent.effectiveFav ? Theme.favoriteActive : Theme.favoriteInactive
                                }

                                MouseArea {
                                    id: headerSongFavMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        mouse.accepted = true
                                        if (statisticsHandler && currentSong && currentSong.arcaeaId) {
                                            statisticsHandler.toggleSongFavorite(currentSong.arcaeaId)
                                        }
                                    }
                                }
                            }

                            // Consultant Sheet search link (top-right, to the left of Favorite button)
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
                                anchors.topMargin: headerContainer.showBackToPack ? (isNarrow ? 53 : 62) : (isNarrow ? 15 : 24)
                                anchors.right: (headerSongFavButton.visible ? headerSongFavButton.left : parent.right)
                                anchors.rightMargin: headerSongFavButton.visible ? 8 : (isNarrow ? 15 : 24)
                                Behavior on anchors.topMargin { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
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
                                                    return (bestPotentialMarkLimit > 0 && r > 0 && r <= bestPotentialMarkLimit) ? r : 0
                                                }
                                                isBest10: (bestPotentialMarkLimit > 0 && Boolean(modelData.isBest10) && bestPotentialRank > 0)

                                                isFavorite: Boolean(modelData && (modelData.isFavorite !== undefined ? modelData.isFavorite : modelData.isChartFavorite))

                                                onFavoriteClicked: function(diff) {
                                                    if (statisticsHandler && currentSong && currentSong.arcaeaId) {
                                                        statisticsHandler.toggleChartFavorite(currentSong.arcaeaId, diff)
                                                    }
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
                                                return (bestPotentialMarkLimit > 0 && r > 0 && r <= bestPotentialMarkLimit) ? r : 0
                                            }
                                            isFavorite: Boolean(modelData && (modelData.isFavorite !== undefined ? modelData.isFavorite : modelData.isChartFavorite))

                                            onFavoriteClicked: function(diff) {
                                                if (statisticsHandler && currentSong && currentSong.arcaeaId) {
                                                    statisticsHandler.toggleChartFavorite(currentSong.arcaeaId, diff)
                                                }
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
                        }

}
