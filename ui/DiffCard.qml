import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * DiffCard — 난이도별 성적 상세 카드.
 *
 * 모든 데이터는 프로퍼티로 주입. 외부 컨텍스트 의존 없음.
 */
Rectangle {
    id: diffCardRoot

    property string diffName: "FTR"
    property string diffLevel: "11"
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
    property var potential: null   // float 또는 null; null이면 "-" 표시
    property int scoreBelowMax: 0  // 이론상 MAX 대비 점수 손실 (user_scores.db)
    property int cut200: 0         // Consultant Sheet frame-limited offset (<=0)
    property bool ignoreChart: false  // Consultant Sheet: trap flag
    property bool skillIssues: false  // Consultant Sheet: individual flag
    property bool hardBpm: false      // Consultant Sheet: hard speed change flag
    property string clearTypeText: ""  // Pre-computed clear type full text from Python
    property string clearTypeAbbr: ""  // Pre-computed clear type abbreviation from Python
    property int bestPotentialRank: 0
    // PM/MAX records render FRAME and MAX as two additional rows.
    property int frameLineCount: hasScore && score >= 10000000 ? 2 : 0

    signal clicked(int diff)
    
    Layout.fillWidth: true
    Layout.fillHeight: true
    // Keep the two PM rows inside the card even when the parent only honors
    // the preferred size. minimumHeight prevents the bottom row from being
    // compressed away by the surrounding RowLayout.
    Layout.preferredHeight: 342 + frameLineCount * 18
    Layout.minimumHeight: 342 + frameLineCount * 18
    radius: 15
    color: Theme.getDiffCardBackground(difficulty, isSelected, isFiltered)
    border.color: isFiltered ? Theme.getFilteredDiffCardBorder(difficulty) : (isSelected ? Theme.getDiffColor(difficulty) : Theme.borderCard)
    border.width: (isSelected && !isFiltered) ? 2 : 1
    clip: true  // Prevent content from overflowing card boundaries
    
    // Clickable area for radio-button behavior (disabled when filtered)
    MouseArea {
        anchors.fill: parent
        cursorShape: isFiltered ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !isFiltered
        onClicked: diffCardRoot.clicked(diffCardRoot.difficulty)
    }
    
    // Diagonal stripes overlay for filtered state (subtle disabled indicator)
    Canvas {
        id: filteredPattern
        property color stripeColor: Theme.filteredCardStripe
        anchors.fill: parent
        visible: isFiltered
        opacity: Theme.filteredCardStripeOpacity
        onStripeColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = stripeColor
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
        opacity: isFiltered ? Theme.filteredCardContentOpacity : 1.0
        
        // Header: Difficulty Name + Level
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 0
            
            Text { 
                id: diffTitleText
                text: diffName + " " + diffLevel
                color: Theme.getDiffColor(difficulty); font.bold: true; font.pixelSize: 18
                
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
                text: clearTypeText
                font.pixelSize: 10
            }

            Text { 
                id: clearTypeDisplay
                // Calculate if we need to abbreviate based on accurate metrics
                // Using implicitWidth vs width is key; titleMetrics provides unelided width
                property real safetyPadding: 25
                property bool performAbbreviation: (titleMetrics.width + safetyPadding + clearTextMeasure.width) > headerRow.width
                
                text: performAbbreviation ? clearTypeAbbr : clearTypeText
                color: Theme.textSecondary; font.pixelSize: 10
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
                        text: shinyBp > 0 ? (Math.round(shinyBp * 100) % 10 === 0 ? shinyBp.toFixed(1) : shinyBp.toFixed(2)) : "-"
                        font.bold: true; font.pixelSize: 12; color: Theme.textPrimary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text { 
                        text: shinyWrapper.width < 50 ? "S-BP" : "Shiny"
                        font.pixelSize: 10; color: Theme.textSecondary
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
                        font.bold: true; font.pixelSize: 12; color: Theme.textPrimary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text { 
                        text: "BP"
                        font.pixelSize: 10; color: Theme.textSecondary
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
                        text: perceivedBp > 0 ? (Math.round(perceivedBp * 100) % 10 === 0 ? perceivedBp.toFixed(1) : perceivedBp.toFixed(2)) : "-"
                        font.bold: true; font.pixelSize: 12; color: Theme.textPrimary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text { 
                        text: perceivedWrapper.width < 50 ? "P-BP" : "Perceived"
                        font.pixelSize: 10; color: Theme.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
        
        Item { Layout.preferredHeight: 2 }

        // Score + Rank
        Text { 
            text: hasScore ? score : "-"
            font.bold: true; font.pixelSize: 24; color: Theme.textTitle 
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: Math.min(parent.width * 0.9, parent.width * 0.5 + 50)
            spacing: 0

            Text {
                text: rank !== "" ? rank : "PM"
                font.bold: true; font.pixelSize: 14
                color: Theme.getRankColor(rank)
                opacity: rank !== "" ? 1.0 : 0.0
            }
            Item { Layout.fillWidth: true }
            Item {
                visible: bestPotentialRank > 0 && hasScore
                implicitWidth: bestLabel.width + rankNum.width
                implicitHeight: rankNum.height
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

                Text {
                    id: bestLabel
                    text: "BEST "
                    font.bold: true
                    font.pixelSize: 11
                    color: Theme.bestPotentialMark
                    anchors.baseline: rankNum.baseline
                    anchors.right: rankNum.left
                }
                Text {
                    id: rankNum
                    text: bestPotentialRank.toString()
                    font.bold: true
                    font.pixelSize: 14
                    color: Theme.bestPotentialMark
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }

        // Stats Grid: Pure, Far, Lost — 상단 고정(FRAME/MAX 유무와 무관하게 통계 값 위치 동일)
        GridLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: Math.min(parent.width * 0.9, parent.width * 0.5 + 50)
            columns: 2
            rowSpacing: 6
            columnSpacing: 10
            
            Text { text: "Pure"; color: Theme.textSecondary; font.pixelSize: 12 }
            Text { 
                text: hasScore ? pure + (shinyPure > 0 ? " (" + shinyPure + ")" : "") : "-"
                color: Theme.textPrimary; font.bold: true; font.pixelSize: 12
                Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
            }
            
            Text { text: "Far"; color: Theme.textSecondary; font.pixelSize: 12 }
            Text { 
                text: hasScore ? far.toString() : "-"
                color: Theme.scoreFar; font.bold: true; font.pixelSize: 12
                Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
            }
            
            Text { text: "Lost"; color: Theme.textSecondary; font.pixelSize: 12 }
            Text { 
                text: hasScore ? lost.toString() : "-"
                color: Theme.scoreLost; font.bold: true; font.pixelSize: 12
                Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
            }
            
            // Divider
            Rectangle {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                height: 1
                color: Theme.borderDivider
                Layout.topMargin: 4
                Layout.bottomMargin: 4
            }
            
            // Potential Value
            Text { text: "Potential"; color: Theme.textSecondary; font.pixelSize: 12 }
            Text {
                text: (potential !== null && hasScore)
                      ? (Math.floor(potential * 10000) / 10000).toFixed(4)
                      : "-"
                color: Theme.textPrimary
                font.bold: true
                font.pixelSize: 12
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
            }
            // FRAME Value (frame-limited max 기준; PM 이상 성적에서만 의미 있음)
            // FRAME 도달(FRAME-N이 아닌 FRAME)이면 필터 FRAME 색으로 bold 강조.
            Text {
                readonly property bool framePlain: (scoreBelowMax + cut200) <= 0
                Layout.columnSpan: 2
                Layout.alignment: Qt.AlignRight
                visible: frameLineCount > 0
                text: framePlain ? "FRAME" : "FRAME-" + (scoreBelowMax + cut200)
                color: framePlain ? Theme.frameHighlight : Theme.textSecondary
                font.bold: framePlain
                font.pixelSize: 11
            }
            // MAX Value (FRAME과 동일하게 PM 이상 성적에서만 표시)
            // MAX 도달(MAX-N이 아닌 MAX)이면 필터 MAX 색으로 bold 강조.
            Text {
                readonly property bool maxPlain: (pure + far + lost - shinyPure) <= 0
                Layout.columnSpan: 2
                Layout.alignment: Qt.AlignRight
                visible: frameLineCount > 0
                text: maxPlain ? "MAX" : "MAX-" + (pure + far + lost - shinyPure)
                color: maxPlain ? Theme.maxHighlight : Theme.textSecondary
                font.bold: maxPlain
                font.pixelSize: 11
            }
            // Play Date Value
            Text {
                Layout.columnSpan: 2
                Layout.alignment: Qt.AlignRight
                text: hasScore ? lastPlayedDate : "-"
                color: Theme.textSecondary
                font.pixelSize: 11
            }
        }

        // 유동 여백: FRAME/MAX가 접힐 때 PlayDate만 위로 당겨지고, 하단 배지/플레이카운트는 바닥에 고정된다.
        Item { Layout.fillHeight: true }

        // Bottom row: Consultant Sheet badges (left) + Play Count (right)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            
            // Consultant Sheet flag badges
            Row {
                spacing: 4
                visible: ignoreChart || skillIssues || hardBpm
                
                // ⛔ Trap badge
                Text {
                    text: "⛔"
                    font.pixelSize: 13
                    visible: ignoreChart
                    
                    MouseArea {
                        id: trapBadgeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                    
                    ToolTip {
                        visible: trapBadgeMouse.containsMouse
                        delay: 300
                        contentItem: Column {
                            spacing: 2
                            Text { text: "Trap"; color: Theme.textTitle; font.bold: true; font.pixelSize: 12 }
                            Text { text: "Flagged in Consultant Sheet"; color: Theme.textSecondary; font.pixelSize: 10 }
                        }
                        background: Rectangle { color: Theme.bgHover; radius: 6 }
                    }
                }
                
                // ⚠️ Individual badge
                Text {
                    text: "⚠️"
                    font.pixelSize: 13
                    visible: skillIssues

                    MouseArea {
                        id: skillBadgeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ToolTip {
                        visible: skillBadgeMouse.containsMouse
                        delay: 300
                        contentItem: Column {
                            spacing: 2
                            Text { text: "Individual"; color: Theme.textTitle; font.bold: true; font.pixelSize: 12 }
                            Text { text: "Flagged in Consultant Sheet"; color: Theme.textSecondary; font.pixelSize: 10 }
                        }
                        background: Rectangle { color: Theme.bgHover; radius: 6 }
                    }
                }

                // ⏪ Hard speed badge
                Text {
                    text: "⏪"
                    font.pixelSize: 13
                    visible: hardBpm

                    MouseArea {
                        id: hardBpmBadgeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ToolTip {
                        visible: hardBpmBadgeMouse.containsMouse
                        delay: 300
                        contentItem: Column {
                            spacing: 2
                            Text { text: "Hard Speed Change"; color: Theme.textTitle; font.bold: true; font.pixelSize: 12 }
                            Text { text: "Flagged in Consultant Sheet"; color: Theme.textSecondary; font.pixelSize: 10 }
                        }
                        background: Rectangle { color: Theme.bgHover; radius: 6 }
                    }
                }
            }
            
            Item { Layout.fillWidth: true }
            
            // Play Count Value
            Text {
                text: {
                    if (playCount <= 0) return "-"
                    return playCount + " plays"
                }
                color: Theme.textSecondary
                font.pixelSize: 12
                font.bold: true
            }
        }
    }
}
