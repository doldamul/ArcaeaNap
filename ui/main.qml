// main.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: window
    width: 1280
    height: 900
    visible: true
    title: "ArcaeaNap"
    color: "#F3F4F8"
    
    minimumWidth: 1280
    minimumHeight: 900

    // 현재 선택된 탭 인덱스 (0: Home, 1: Analyze, 2: Statistics)
    // Settings는 별도 윈도우로 분리됨
    property int currentTab: 0

    readonly property string baseUiFontFamily: {
        if (typeof embeddedBaseUiFontFamily === "string" && embeddedBaseUiFontFamily.length > 0) {
            return embeddedBaseUiFontFamily
        }
        return "Segoe UI, Roboto, Helvetica, Arial, sans-serif"
    }
    readonly property string titleFontFamily: {
        if (typeof embeddedTitleFontFamily === "string" && embeddedTitleFontFamily.length > 0) {
            return embeddedTitleFontFamily
        }
        return baseUiFontFamily
    }

    font.family: baseUiFontFamily

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
            text: "ArcaeaNap"
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
                onClicked: {
                    // Show settings window or bring it to focus
                    if (settingsWindow.visible) {
                        settingsWindow.raise()
                        settingsWindow.requestActivate()
                    } else {
                        settingsWindow.show()
                    }
                }
            }
        }
    }

    // --- Settings Window (별도 윈도우) ---
    Loader {
        id: settingsWindowLoader
        source: "settings_ui.qml"
        asynchronous: true
    }
    
    property Window settingsWindow: settingsWindowLoader.item

    onClosing: {
        if (settingsWindow && settingsWindow.visible) {
            settingsWindow.close()
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
    
    // --- Cache Migration State ---
    property bool isCacheMigrating: false
    
    Connections {
        target: settingsHandler
        function onCacheMigrationStarting() {
            window.isCacheMigrating = true
        }
        function onCacheMigrationFinished(error) {
            window.isCacheMigrating = false
            // Refresh all handlers to use new thumbnail paths
            if (error === "") {
                if (statsHandler) {
                    statsHandler.refreshStats()
                }
                if (statisticsHandler) {
                    statisticsHandler.refreshData()
                }
            }
        }
        function onSongDatabaseUpdateStarting() {
            songDbUpdateModal.show()
        }
        function onSongDatabaseUpdateFinished(success, message) {
            songDbUpdateModal.close()
            if (success) {
                if (statsHandler) statsHandler.refreshStats()
                if (statisticsHandler) statisticsHandler.refreshData()
            } else {
                songDbErrorText.text = message
                songDbErrorPopup.open()
            }
        }
        function onSongTitleLanguageChanged() {
            if (statisticsHandler) {
                statisticsHandler.refreshData()
            }
        }
    }

    // --- Song Database Update Modal (ApplicationModal blocks all windows) ---
    Window {
        id: songDbUpdateModal
        modality: Qt.ApplicationModal
        flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint
        title: "Updating Song Database"
        width: 350
        height: 160
        minimumWidth: 350
        maximumWidth: 350
        minimumHeight: 160
        maximumHeight: 160
        color: "#F3F4F8"
        visible: false

        Column {
            anchors.centerIn: parent
            spacing: 16

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: songDbUpdateModal.visible
            }

            Text {
                text: "Updating song database..."
                font.pixelSize: 15
                font.bold: true
                color: "#333"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "This may take a minute."
                font.pixelSize: 12
                color: "#888"
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- Song Database Update Error Popup ---
    Popup {
        id: songDbErrorPopup
        anchors.centerIn: parent
        width: 380
        height: songDbErrorContent.implicitHeight + 40
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        z: 1001

        background: Rectangle {
            color: "#FFFFFF"
            radius: 12
            border.color: "#E53935"
            border.width: 2
        }

        Column {
            id: songDbErrorContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: "Update Failed"
                font.bold: true
                font.pixelSize: 16
                color: "#E53935"
            }

            Text {
                id: songDbErrorText
                wrapMode: Text.WordWrap
                width: parent.width
                color: "#333"
            }

            Basic.Button {
                text: "OK"
                anchors.right: parent.right
                onClicked: songDbErrorPopup.close()
                background: Rectangle { color: "#F0F0F0"; radius: 6 }
            }
        }
    }

    Connections {
        target: startupHandler
        function onLoadingStarted() {
            window.isLoading = true
        }
        function onLoadingFinished() {
            window.isLoading = false
            // Refresh all handlers after database is created
            if (statsHandler) {
                statsHandler.refreshStats()
            }
            if (statisticsHandler) {
                statisticsHandler.refreshData()
            }
        }
        function onErrorOccurred(msg) {
            console.log("Loading error: " + msg)
            window.isLoading = false
        }
    }
    
    // Refresh Home/Statistics tabs when Arcaea Online data is saved
    Connections {
        target: analysisHandler
        function onDataUpdated() {
            if (statsHandler) {
                statsHandler.refreshStats()
            }
            if (statisticsHandler) {
                statisticsHandler.refreshData()
            }
        }
        function onSessionReset(message) {
            toastText.text = message
            toastAnimation.restart()
        }
    }

    Component.onCompleted: {
        if (startupHandler) {
            startupHandler.checkAndLoad()
        }
    }

    // --- Toast Notification ---
    Rectangle {
        id: toastContainer
        width: toastText.implicitWidth + 40
        height: toastText.implicitHeight + 24
        radius: 20
        color: "#E0333333"

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40

        opacity: 0
        scale: 0.85
        z: 100
        visible: opacity > 0

        Text {
            id: toastText
            anchors.centerIn: parent
            color: "#FFFFFF"
            font.pixelSize: 14
            font.bold: true
            text: ""
        }

        // 말풍선 꼬리 (하단 중앙 삼각형)
        Canvas {
            width: 16; height: 8
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            onPaint: {
                var ctx = getContext("2d")
                ctx.fillStyle = "#E0333333"
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(8, 8)
                ctx.lineTo(16, 0)
                ctx.closePath()
                ctx.fill()
            }
        }

        SequentialAnimation {
            id: toastAnimation

            // 등장: 아래에서 위로 슬라이드 + 페이드인
            ParallelAnimation {
                NumberAnimation {
                    target: toastContainer; property: "opacity"
                    from: 0; to: 1; duration: 300
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: toastContainer; property: "scale"
                    from: 0.85; to: 1.0; duration: 300
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: toastContainer; property: "anchors.bottomMargin"
                    from: 20; to: 40; duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            // 3초 대기
            PauseAnimation { duration: 3000 }

            // 퇴장: 페이드아웃 + 축소
            ParallelAnimation {
                NumberAnimation {
                    target: toastContainer; property: "opacity"
                    from: 1; to: 0; duration: 400
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: toastContainer; property: "scale"
                    from: 1.0; to: 0.85; duration: 400
                    easing.type: Easing.InCubic
                }
            }
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