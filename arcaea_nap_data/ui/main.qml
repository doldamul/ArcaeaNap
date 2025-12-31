// main.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: window
    width: 1280
    height: 900
    visible: true
    title: "ArcaeaNap"
    color: "#F3F4F8"
    
    minimumWidth: 400
    minimumHeight: 800

    // 현재 선택된 탭 인덱스 (0: Home, 1: Analyze, 2: Statistics)
    property int currentTab: 0

    font.family: "Segoe UI, Roboto, Helvetica, Arial, sans-serif"

    // --- 통합 상단 네비게이션 바 ---
    Rectangle {
        id: navBar
        width: parent.width
        height: 70
        color: "#FFFFFF"
        z: 10

        // [수정] RowLayout 제거 -> 앵커(Anchors) 기반의 독립 배치로 변경

        // 1. 로고 (왼쪽 고정)
        Text {
            id: logoText
            text: "Arcaea Stats"
            font.pixelSize: 20
            font.bold: true
            color: "#1A1A1A"
            
            anchors.left: parent.left
            anchors.leftMargin: 40
            anchors.verticalCenter: parent.verticalCenter
            
            // [핵심] 창 너비가 좁아지면(예: 800px 미만) 로고를 숨겨서 탭 공간 확보
            visible: window.width > 800
        }

        // 2. 탭 메뉴 컨테이너 (정중앙 고정)
        Item {
            id: menuContainer
            width: 400 
            height: parent.height
            
            // [핵심] 부모의 정중앙에 강제로 위치시킴
            anchors.centerIn: parent

            // --- (이하 탭 메뉴 내부 코드는 기존과 동일) ---
            Item {
                id: centerWrapper
                anchors.centerIn: parent
                width: buttonRow.width
                height: 70

                Row {
                    id: buttonRow
                    
                    // [수정됨] 반응형 간격 (Dynamic Spacing)
                    // 너비 800px 이상일 땐 40px 유지
                    // 너비 800px ~ 400px 구간에선 40px -> 15px로 점차 좁아짐
                    spacing: {
                        var minSp = 15
                        var maxSp = 40
                        var titleHiddenWidth = 800
                        var minWinWidth = 400
                        
                        // 현재 창 너비에 따른 비율 계산
                        var ratio = (window.width - minWinWidth) / (titleHiddenWidth - minWinWidth)
                        
                        // 15 ~ 40 사이로 값 제한 (Clamp)
                        var dynamicSpacing = minSp + (maxSp - minSp) * ratio
                        return Math.max(minSp, Math.min(maxSp, dynamicSpacing))
                    }
                    
                    Repeater {
                        id: tabRepeater
                        model: ListModel {
                            ListElement { name: "Home" }
                            ListElement { name: "Analyze" }
                            ListElement { name: "Statistics" }
                        }
                        
                        delegate: Item {
                            id: tabBtn
                            width: tabText.implicitWidth
                            height: 70
                            property bool isActive: window.currentTab === index

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.currentTab = index
                            }

                            Text {
                                id: tabText
                                text: name
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: parent.isActive ? -2 : 0
                                scale: parent.isActive ? 1.15 : 1.0
                                color: parent.isActive ? "#6A0DAD" : (tabMouse.containsMouse ? "#9D70C9" : "#888888")
                                font.bold: true 
                                font.pixelSize: 16

                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 200 } }
                            }
                        }
                    }
                }

                Rectangle {
                    id: slidingBar
                    height: 3
                    width: 40
                    radius: 2
                    color: "#6A0DAD"
                    y: 50 
                    
                    property Item activeItem: tabRepeater.itemAt(window.currentTab)
                    x: activeItem ? (activeItem.x + (activeItem.width - width) / 2) : 0

                    Behavior on x {
                        enabled: slidingBar.activeItem !== null
                        NumberAnimation { duration: 350; easing.type: Easing.OutQuad }
                    }
                }
            }
        }

        // 3. 설정 아이콘 버튼 (오른쪽 고정)
        Item {
            id: settingsBtn
            width: 40
            height: 40
            
            // [핵심] 오른쪽 끝에 강제로 고정
            anchors.right: parent.right
            anchors.rightMargin: 40
            anchors.verticalCenter: parent.verticalCenter
            
            Rectangle {
                anchors.fill: parent
                radius: 8 
                color: "#E0E0E0" 
                opacity: settingsMouse.containsMouse ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Text {
                id: settingsIcon
                text: "⚙️"
                font.pixelSize: 22
                anchors.centerIn: parent
                color: settingsMouse.containsMouse ? "#333333" : "#888888"
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            MouseArea {
                id: settingsMouse
                anchors.fill: parent
                hoverEnabled: true 
                cursorShape: Qt.PointingHandCursor
                onClicked: console.log("Settings Clicked!")
            }
        }
    }

    // --- 페이지 컨테이너 (StackLayout) ---
    // 현재 currentTab 값에 따라 보여주는 페이지가 바뀝니다.
    Item {
        id: contentArea
        anchors.top: navBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        // 탭 전환 애니메이션 컴포넌트 정의
        component TabPage: Loader {
            property int tabIndex: 0 // 이 탭의 고유 번호
            
            anchors.fill: parent
            
            // 현재 탭이면 불투명(1), 아니면 투명(0)
            opacity: window.currentTab === tabIndex ? 1 : 0
            
            // 투명해지면 클릭 안 되게 비활성화 (성능 최적화)
            visible: opacity > 0
            
            // [핵심] opacity 값이 변할 때 0.2초 동안 부드럽게 애니메이션
            Behavior on opacity {
                NumberAnimation { 
                    duration: 200 
                    easing.type: Easing.InOutQuad 
                }
            }
        }

        // 1. Home 페이지
        TabPage {
            source: "home_ui.qml"
            tabIndex: 0
        }

        // 2. Analyze 페이지
        TabPage {
            source: "analyze_ui.qml"
            tabIndex: 1
        }

        // 3. Statistics 페이지
        TabPage {
            source: "statistics_ui.qml"
            tabIndex: 2
        }
    }

    // --- Loading Overlay ---
    property bool isLoading: false

    Connections {
        target: startupHandler
        function onLoadingStarted() {
            window.isLoading = true
        }
        function onLoadingFinished() {
            window.isLoading = false
        }
        function onErrorOccurred(msg) {
            console.log("Loading error: " + msg)
            window.isLoading = false
        }
    }

    Component.onCompleted: {
        if (startupHandler) {
            startupHandler.checkAndLoad()
        }
    }

    Rectangle {
        id: loadingOverlay
        anchors.fill: parent
        color: "#80000000" // Semi-transparent black
        z: 999
        visible: window.isLoading
        
        // Block input
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 20
            
            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: loadingOverlay.visible
                
                contentItem: Rectangle {
                    implicitWidth: 64
                    implicitHeight: 64
                    color: "transparent"
                    border.color: "#FFFFFF"
                    border.width: 4
                    radius: 32
                    
                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: "#FFFFFF"
                        x: 26
                        y: 4
                        
                        transform: Rotation {
                            origin.x: 6
                            origin.y: 28
                            angle: 0
                            
                            NumberAnimation on angle {
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                running: loadingOverlay.visible
                            }
                        }
                    }
                }
            }
            
            Text {
                text: "Loading song data..."
                color: "#FFFFFF"
                font.pixelSize: 24
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
                style: Text.Outline
                styleColor: "#000000"
            }
        }
    }
}