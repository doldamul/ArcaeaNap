import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

ColumnLayout {
    id: packDashboardPage
    Layout.fillWidth: true
    spacing: 16

    property var currentPack: null
    property bool isNarrow: (statsRoot && statsRoot.isNarrow) ? statsRoot.isNarrow : false
    property bool isDiffCramped: (statsRoot && statsRoot.isDiffCramped) ? statsRoot.isDiffCramped : false
    property var statsRoot: null
    property string titleFontFamily: (statsRoot && statsRoot.titleFontFamily) ? statsRoot.titleFontFamily : ((typeof embeddedTitleFontFamily === "string" && embeddedTitleFontFamily.length > 0) ? embeddedTitleFontFamily : "Segoe UI")
    // NOTE: statistics_ui.qml에서 `statsRoot: statsRoot`로 전달하면 자기 자신의 프로퍼티(null)로 해석되어
    // statsRoot를 통한 thumbnailVersion은 항상 0에 고정된다. 썸네일 다운로드 완료 통지를 받으려면
    // 컨텍스트 핸들러의 thumbnailVersion(NOTIFY 시그널 보유)을 직접 바인딩해야 한다.
    property int thumbnailVersion: statsHandler ? statsHandler.thumbnailVersion : (statisticsHandler ? statisticsHandler.thumbnailVersion : 0)
    property var packDashboardScrollView: this

    // Aliases for external reference & contract preservation
    property alias packHeroCard: packHeroCard
    property alias heroCardColLayout: heroCardColLayout
    property alias clearLampCard: clearLampCard
    property alias scoreGradeCard: scoreGradeCard
    property alias bestPotCard: bestPotCard
    property alias bestScoreCard: bestScoreCard
    property alias mostPlayedCard: mostPlayedCard
    property alias dualGraphLayout: dualGraphLayout
    property alias songStatsRow: songStatsRow

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

                                // 카드를 항상 하나의 텍스처로 합성한 뒤 opacity를 적용한다.
                                // (개별 자식 opacity 적용 시 딤 오버레이가 이미지보다 먼저 옅어져 다크모드에서 썸네일이 순간적으로 밝아짐)
                                layer.enabled: true
                                layer.smooth: true

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
                                        var _v = thumbnailVersion
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

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    text: (packDashboardScrollView.currentPack ? packDashboardScrollView.currentPack.name : "") || ""
                                                    font.family: titleFontFamily
                                                    font.pixelSize: 22
                                                    font.bold: true
                                                    color: Theme.detailHeaderTitle
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: false
                                                    Layout.maximumWidth: Math.max(0, parent.width - heroPackFavButton.width - parent.spacing)
                                                }

                                                // Pack Favorite Button right next to pack name (28x28)
                                                Rectangle {
                                                    id: heroPackFavButton
                                                    visible: Boolean(packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.name)
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 28
                                                    Layout.alignment: Qt.AlignVCenter
                                                    radius: 8
                                                    border.width: 0
                                                    property bool isPackFav: Boolean(packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.isPackFavorite)
                                                    property bool effectiveFav: heroPackFavMouse.pressed ? !isPackFav : isPackFav
                                                    color: {
                                                        if (heroPackFavMouse.pressed) return "transparent"
                                                        var isHovered = heroPackFavMouse.containsMouse
                                                        if (Theme.isDarkMode) {
                                                            return isHovered ? Theme.alpha("#FFFFFF", 0.30) : Theme.alpha("#FFFFFF", 0.15)
                                                        } else {
                                                            return isHovered ? Theme.alpha("#000000", 0.30) : Theme.alpha("#000000", 0.15)
                                                        }
                                                    }
                                                    Behavior on color { ColorAnimation { duration: 150 } }

                                                    FavGlyph {
                                                        filled: parent.effectiveFav
                                                        pixelSize: 18
                                                        glyphColor: parent.effectiveFav ? Theme.favoriteActive : Theme.favoriteInactive
                                                    }

                                                    MouseArea {
                                                        id: heroPackFavMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: (mouse) => {
                                                            mouse.accepted = true
                                                            if (statisticsHandler && packDashboardScrollView.currentPack && packDashboardScrollView.currentPack.name) {
                                                                statisticsHandler.togglePackFavorite(packDashboardScrollView.currentPack.name)
                                                            }
                                                        }
                                                    }
                                                }

                                                Item { Layout.fillWidth: true }
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

                                        // Right: Progress Card (Restored to rightmost end)
                                        Rectangle {
                                            id: heroProgressCard
                                            Layout.preferredWidth: 200
                                            Layout.preferredHeight: 80
                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
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
                                columns: isNarrow ? 1 : 3
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
                                                        var _v = thumbnailVersion
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
                                                if (isNarrow && typeof mobileStack !== "undefined" && typeof detailPageComponent !== "undefined") {
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
                                                        var _v = thumbnailVersion;
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
                                                if (isNarrow && typeof mobileStack !== "undefined" && typeof detailPageComponent !== "undefined") {
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
                                                        var _v = thumbnailVersion;
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
                                                if (isNarrow && typeof mobileStack !== "undefined" && typeof detailPageComponent !== "undefined") {
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
                                columns: isNarrow ? 1 : 2
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
