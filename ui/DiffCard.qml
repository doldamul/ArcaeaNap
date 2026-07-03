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
    property var potential: null   // float 또는 null; null이면 "-" 표시
    property bool ignoreChart: false  // Consultant Sheet: trap flag
    property bool skillIssues: false  // Consultant Sheet: individual flag
    property string rankColor: ""  // Pre-computed rank color from Python
    property string clearTypeText: ""  // Pre-computed clear type full text from Python
    property string clearTypeAbbr: ""  // Pre-computed clear type abbreviation from Python
    property int bestPotentialRank: 0

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
    
    // Helper function for rank color (applies filter blending)
    function getRankColor(baseColor) {
        if (isFiltered) return blendWithGray(baseColor, 0.4)
        return baseColor
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
        onClicked: diffCardRoot.clicked(diffCardRoot.difficulty)
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
                        text: shinyBp > 0 ? (Math.round(shinyBp * 100) % 10 === 0 ? shinyBp.toFixed(1) : shinyBp.toFixed(2)) : "-"
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
                        text: perceivedBp > 0 ? (Math.round(perceivedBp * 100) % 10 === 0 ? perceivedBp.toFixed(1) : perceivedBp.toFixed(2)) : "-"
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
        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: Math.min(parent.width * 0.9, parent.width * 0.5 + 50)
            spacing: 0

            Text {
                text: rank !== "" ? rank : "PM"
                font.bold: true; font.pixelSize: 14
                color: getRankColor(rankColor)
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
                    color: getRankColor("#6A6A8A")
                    anchors.baseline: rankNum.baseline
                    anchors.right: rankNum.left
                }
                Text {
                    id: rankNum
                    text: bestPotentialRank.toString()
                    font.bold: true
                    font.pixelSize: 14
                    color: getRankColor("#6A6A8A")
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
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
            
            // Potential Value
            Text { text: "Potential"; color: effectiveSubTextColor; font.pixelSize: 12 }
            Text {
                text: (potential !== null && hasScore)
                      ? (Math.floor(potential * 10000) / 10000).toFixed(4)
                      : "-"
                color: isFiltered ? effectiveSubTextColor : "#666"
                font.bold: true
                font.pixelSize: 12
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
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
        
        // Bottom row: Consultant Sheet badges (left) + Play Count (right)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            
            // Consultant Sheet flag badges
            Row {
                spacing: 4
                visible: ignoreChart || skillIssues
                
                // ⛔ Trap badge
                Text {
                    text: "⛔"
                    font.pixelSize: 13
                    visible: ignoreChart
                    opacity: isFiltered ? 0.4 : 1.0
                    
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
                            Text { text: "Trap"; color: "#FFF"; font.bold: true; font.pixelSize: 12 }
                            Text { text: "Flagged in Consultant Sheet"; color: "#BBB"; font.pixelSize: 10 }
                        }
                        background: Rectangle { color: "#333"; radius: 6 }
                    }
                }
                
                // ⚠️ Individual badge
                Text {
                    text: "⚠️"
                    font.pixelSize: 13
                    visible: skillIssues
                    opacity: isFiltered ? 0.4 : 1.0
                    
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
                            Text { text: "Individual"; color: "#FFF"; font.bold: true; font.pixelSize: 12 }
                            Text { text: "Flagged in Consultant Sheet"; color: "#BBB"; font.pixelSize: 10 }
                        }
                        background: Rectangle { color: "#333"; radius: 6 }
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
                color: isFiltered ? effectiveSubTextColor : "#666"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }
}
