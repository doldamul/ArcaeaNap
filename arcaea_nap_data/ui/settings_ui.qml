// settings_ui.qml
// Separate window for Settings
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs

Window {
    id: settingsWindow
    width: 600
    height: 800
    minimumWidth: 600
    maximumWidth: 600
    minimumHeight: 600
    title: "Settings"
    color: "#F3F4F8"
    
    // 메인 윈도우 위에 고정되지 않도록 부모 관계 해제
    transientParent: null

    ScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        padding: 40

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: 30

            // --- 1. General Section ---
            Rectangle {
                Layout.fillWidth: true
                height: generalLayout.implicitHeight + 60
                color: "#FFFFFF"
                radius: 20
                border.color: "#E0E0E0"; border.width: 1

                ColumnLayout {
                    id: generalLayout
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 24

                    // Header
                    Text { text: "General"; font.bold: true; font.pixelSize: 18; color: "#333" }

                    // Cache Path
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "Cache Path"; font.bold: true; color: "#333" }
                        Text { text: "Location where scores and images are stored"; font.pixelSize: 12; color: "#888" }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            
                            Basic.TextField {
                                id: cachePathField
                                Layout.fillWidth: true
                                text: settingsHandler ? settingsHandler.getCachePath() : ""
                                readOnly: true
                                background: Rectangle {
                                    color: "#F5F5F5"; radius: 8; border.width: 0
                                }
                            }
                            
                            Basic.Button {
                                text: "📁"
                                background: Rectangle { color: "#F0F0F0"; radius: 8 }
                                onClicked: folderDialog.open()
                            }
                        }
                    }

                    FolderDialog {
                        id: folderDialog
                        title: "Select Cache Directory"
                        onAccepted: if (settingsHandler) settingsHandler.setCachePath(folderDialog.selectedFolder)
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Analyze Mode Toggle
                    RowLayout {
                        Layout.fillWidth: true
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            
                            RowLayout {
                                spacing: 6
                                Text { 
                                    text: "Play Count Analyze Mode"
                                    font.bold: true
                                    color: "#333" 
                                }
                                
                                Text {
                                    text: "🛈"
                                    font.pixelSize: 14
                                    color: helpMouse.containsMouse ? "#6A0DAD" : "#999"
                                    
                                    MouseArea {
                                        id: helpMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }
                                    
                                    Basic.ToolTip {
                                        visible: helpMouse.containsMouse
                                        delay: 100
                                        timeout: -1 // 무기한 표시 (마우스가 떠나면 visible에 의해 사라짐)
                                        x: parent.width + 10
                                        y: -10
                                        
                                        contentItem: Text {
                                            text: "Arcaea Online resets 'Yearly Play Count' data annually on Jan 1st (00:00 GMT).\n\n" +
                                                  "Normally, the analyzer updates play count of a record only when a new score is found, for ensuring record consistency and preventing server strain. Enable this mode to temporarily bypass limits and update play counts for ALL songs.\n" +
                                                  "This is useful for archiving your complete yearly statistics before the reset."
                                            font.pixelSize: 12
                                            color: "#FFFFFF"
                                            wrapMode: Text.WordWrap
                                        }
                                        
                                        background: Rectangle {
                                            color: "#333333"
                                            radius: 6
                                            opacity: 0.95
                                        }
                                        
                                        width: 350
                                    }
                                }
                            }
                            
                            
                        }
                        
                        Basic.Switch {
                            checked: settingsHandler ? settingsHandler.getAnalyzeModeEnabled() : false
                            onToggled: if (settingsHandler) settingsHandler.setAnalyzeModeEnabled(checked)
                            
                            indicator: Rectangle {
                                implicitWidth: 48; implicitHeight: 26
                                x: parent.leftPadding; y: parent.height / 2 - height / 2
                                radius: 13
                                color: parent.checked ? "#6A0DAD" : "#E0E0E0"
                                border.color: parent.checked ? "#6A0DAD" : "#CCCCCC"

                                Rectangle {
                                    x: parent.checked ? parent.width - width - 2 : 2
                                    width: 22; height: 22
                                    radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "white"
                                    Behavior on x { NumberAnimation { duration: 100 } }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Account Connections
                    Text { text: "Account Connections"; font.bold: true; color: "#333" }
                    RowLayout {
                        spacing: 20
                        
                        // Arcaea Online
                        Rectangle {
                            width: 200; height: 50
                            radius: 10
                            color: "#F8F9FA"
                            border.color: "#E0E0E0"; border.width: 1
                            
                            Text { 
                                anchors.centerIn: parent
                                text: "Arcaea Online"
                                font.bold: true
                                color: (settingsHandler && settingsHandler.isArcaeaOnlineConnected()) ? "#4CAF50" : "#555"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: console.log("Bind Arcaea Online clicked")
                            }
                        }
                        
                        // Google Sheet
                        Rectangle {
                            width: 200; height: 50
                            radius: 10
                            color: "#F8F9FA"
                            border.color: "#E0E0E0"; border.width: 1
                            
                            Text { 
                                anchors.centerIn: parent
                                text: "Google Sheet"
                                font.bold: true
                                color: (settingsHandler && settingsHandler.isGoogleSheetConnected()) ? "#4CAF50" : "#555"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: console.log("Bind Google Sheet clicked")
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Database Management
                    // Arcaea Consultant Sheet Section
                    Text { text: "Arcaea Consultant Sheet"; font.bold: true; color: "#333" }
                    
                    // 1. Sheet Management Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: sheetMgmtLayout.implicitHeight + 30
                        color: "#FFFFFF"
                        radius: 12
                        border.color: "#E0E0E0"; border.width: 1
                        
                        ColumnLayout {
                            id: sheetMgmtLayout
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 12
                            
                            // Header: Title & Shortcut
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Sheet Management"; font.bold: true; color: "#2E7D32"; font.pixelSize: 13 }
                                Item { Layout.fillWidth: true }
                                Basic.Button {
                                    text: "🔗 Open Sheet"
                                    font.pixelSize: 11
                                    background: Rectangle { color: "#F1F8E9"; radius: 4; border.color: "#C5E1A5" }
                                    contentItem: Text { text: parent.text; color: "#33691E"; font.pixelSize: 11; anchors.centerIn: parent }
                                    onClicked: Qt.openUrlExternally("https://docs.google.com/spreadsheets/...") // TODO: Add link
                                    implicitHeight: 24
                                }
                            }
                            
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }
                            
                            // Status Message
                            Text { 
                                text: "Update Available!" 
                                color: "#E53935" 
                                font.bold: true 
                                font.pixelSize: 12 
                            }
                            
                            // Version Info Grid
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 20
                                rowSpacing: 8
                                
                                // Headers
                                Text { text: "Current Version"; color: "#757575"; font.pixelSize: 11 }
                                Text { text: "Latest Version"; color: "#757575"; font.pixelSize: 11 }
                                
                                // Values
                                Text { text: "v7.5.3 (Arc v6.11.0)"; font.bold: true; color: "#333" }
                                Text { text: "v7.5.7 (Arc v6.12.0)"; font.bold: true; color: "#2E7D32" }
                            }
                            
                            // Changelog Box
                            Rectangle {
                                Layout.fillWidth: true
                                height: changelogCol.implicitHeight + 16
                                color: "#FAFAFA"
                                radius: 6
                                
                                ColumnLayout {
                                    id: changelogCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4
                                    
                                    Text { text: "Changelog"; font.pixelSize: 10; font.bold: true; color: "#555" }
                                    Text { 
                                        text: "• Added 1 new song (Arcaea v6.11.8)"
                                        font.pixelSize: 11
                                        color: "#333"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                            
                            // Update Button
                            Basic.Button {
                                Layout.fillWidth: true
                                Layout.topMargin: 5
                                text: "Update Sheet to v7.5.7"
                                onClicked: console.log("Update sheet clicked")
                                background: Rectangle {
                                    color: parent.down ? "#43A047" : "#4CAF50" // Green for update
                                    radius: 8
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                    
                    // 2. Data Sync Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 60
                        color: "#FFFFFF"
                        radius: 12
                        border.color: "#E0E0E0"; border.width: 1
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20; anchors.rightMargin: 20
                            spacing: 15
                            
                            Rectangle {
                                width: 32; height: 32; radius: 16; color: "#E8EAF6"
                                Text { text: "🔄"; anchors.centerIn: parent }
                            }
                            
                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Text { text: "Sync Play Data"; font.bold: true; color: "#333" }
                                Text { text: "Send your latest records to the sheet"; font.pixelSize: 11; color: "#757575" }
                            }
                            
                            Basic.Button {
                                text: "Send Data"
                                onClicked: console.log("Send data clicked")
                                background: Rectangle {
                                    color: parent.down ? "#5E35B1" : "#673AB7" // Deep Purple
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Database Management
                    Text { text: "Song Database Management"; font.bold: true; color: "#333" }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: 50
                        radius: 10
                        color: "#E3F2FD"
                        border.color: "#90CAF9"
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20; anchors.rightMargin: 20
                            
                            Column {
                                spacing: 2
                                Text { text: "Update Song Database"; font.bold: true; color: "#1976D2" }
                                Text { text: "Rebuild song database from online sources"; font.pixelSize: 11; color: "#1976D2" }
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Basic.Button {
                                text: "Update"
                                onClicked: settingsHandler.updateSongDatabase()
                                background: Rectangle {
                                    color: parent.down ? "#42A5F5" : "#64B5F6"
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            // --- 2. Profile Section ---
            Rectangle {
                Layout.fillWidth: true
                height: profileLayout.implicitHeight + 60
                color: "#FFFFFF"
                radius: 20
                border.color: "#E0E0E0"; border.width: 1

                ColumnLayout {
                    id: profileLayout
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 24

                    Text { text: "Profile"; font.bold: true; font.pixelSize: 18; color: "#333" }

                    // Profile Actions & Image (Moved)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        
                        Rectangle {
                            width: 80; height: 80
                            radius: 40
                            color: "#F0F0F0"
                            border.color: "#E0E0E0"
                            clip: true
                            
                            Image {
                                anchors.fill: parent
                                source: (settingsHandler && settingsHandler.getProfileImage()) ? "file:///" + settingsHandler.getProfileImage() : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: source != ""
                            }
                            
                            Text {
                                anchors.centerIn: parent
                                text: "No\nImg"
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter
                                visible: parent.children[0].status !== Image.Ready
                            }
                        }
                        
                        ColumnLayout {
                            Button {
                                text: "Set Profile Image"
                                onClicked: fileDialog.open()
                            }
                            Button {
                                text: "Scan Profile from Arcaea Online"
                                onClicked: console.log("Scan profile clicked")
                            }
                        }
                        
                        FileDialog {
                            id: fileDialog
                            title: "Select Profile Image"
                            nameFilters: ["Image files (*.png *.jpg *.jpeg)"]
                            onAccepted: if (settingsHandler) settingsHandler.setProfileImage(fileDialog.selectedFile)
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }

                    // Privacy Options
                    Text { text: "Privacy"; font.bold: true; color: "#333" }
                    RowLayout {
                        spacing: 30
                        CheckBox {
                            text: "Show Friend Code"
                            checked: settingsHandler ? settingsHandler.getShowFriendCode() : false
                            onCheckedChanged: if (settingsHandler) settingsHandler.setShowFriendCode(checked)
                        }
                        CheckBox {
                            text: "Show Potential"
                            checked: settingsHandler ? settingsHandler.getShowPotential() : false
                            onCheckedChanged: if (settingsHandler) settingsHandler.setShowPotential(checked)
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#EEEEEE" }
                    
                    // Most Played Order
                    Text { text: "Most Played Order"; font.bold: true; color: "#333" }
                    
                    ColumnLayout {
                        spacing: 15
                        
                        // Grouping Criteria
                        RowLayout {
                            spacing: 10
                            Text { text: "Grouping Criteria:" }
                            RadioButton {
                                text: "By Song"
                                checked: settingsHandler ? settingsHandler.getGroupingCriteria() === 'song' : true
                                onToggled: if(checked && settingsHandler) settingsHandler.setGroupingCriteria('song')
                            }
                            RadioButton {
                                text: "By Chart"
                                checked: settingsHandler ? settingsHandler.getGroupingCriteria() === 'chart' : false
                                onToggled: if(checked && settingsHandler) settingsHandler.setGroupingCriteria('chart')
                            }
                        }
                        
                        // Difficulty Filter
                        RowLayout {
                            spacing: 10
                            Text { text: "Difficulty Filter:" }
                            
                            property string currentFilters: settingsHandler ? settingsHandler.getDifficultyFilter() : 'all'
                            
                            CheckBox {
                                text: "All"
                                checked: parent.currentFilters === 'all'
                                onToggled: if(checked && settingsHandler) settingsHandler.setDifficultyFilter('all')
                            }
                            
                            // Helper to toggle specific diff
                            function toggleDiff(diffCode) {
                                if (!settingsHandler) return
                                if (currentFilters === 'all') {
                                    settingsHandler.setDifficultyFilter(diffCode)
                                } else {
                                    var parts = currentFilters.split(',')
                                    var idx = parts.indexOf(diffCode)
                                    if (idx >= 0) parts.splice(idx, 1)
                                    else parts.push(diffCode)
                                    
                                    if (parts.length === 0) settingsHandler.setDifficultyFilter('all')
                                    else settingsHandler.setDifficultyFilter(parts.join(','))
                                }
                            }
                            
                            function isDiffChecked(diffCode) {
                                return currentFilters !== 'all' && currentFilters.split(',').includes(diffCode)
                            }
                            
                            CheckBox { text: "PST"; checked: parent.isDiffChecked('pst'); onToggled: parent.toggleDiff('pst') }
                            CheckBox { text: "PRS"; checked: parent.isDiffChecked('prs'); onToggled: parent.toggleDiff('prs') }
                            CheckBox { text: "FTR"; checked: parent.isDiffChecked('ftr'); onToggled: parent.toggleDiff('ftr') }
                            CheckBox { text: "ETR"; checked: parent.isDiffChecked('etr'); onToggled: parent.toggleDiff('etr') }
                            CheckBox { text: "BYD"; checked: parent.isDiffChecked('byd'); onToggled: parent.toggleDiff('byd') }
                        }
                    }


                }
            }


            
            // Bottom Spacer
            Item { height: 40 }
        }
    }
}
