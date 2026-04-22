import QtQuick
import QtQuick.Controls

/**
 * ArrowNav — SwipeView 양옆에 화살표 버튼을 배치하는 래퍼.
 *
 * Usage:
 *   ArrowNav {
 *       targetView: mySwipeView
 *       SwipeView { id: mySwipeView; ... }
 *   }
 */
Item {
    id: arrowNavRoot
    default property alias content: container.data
    property SwipeView targetView: null

    anchors.fill: parent

    Item { id: container; anchors.fill: parent }

    // 왼쪽 화살표 버튼
    Rectangle {
        width: 30; height: 30; radius: 15
        color: "#FFFFFF"; border.color: "#E0E0E0"
        anchors.left: parent.left; anchors.leftMargin: -10
        anchors.verticalCenter: parent.verticalCenter
        z: 10
        visible: targetView && targetView.currentIndex > 0

        Text { text: "❮"; anchors.centerIn: parent; color: "#6A0DAD"; font.bold: true }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.color = "#F0F0F0"
            onExited: parent.color = "#FFFFFF"
            onClicked: targetView.decrementCurrentIndex()
        }
    }

    // 오른쪽 화살표 버튼
    Rectangle {
        width: 30; height: 30; radius: 15
        color: "#FFFFFF"; border.color: "#E0E0E0"
        anchors.right: parent.right; anchors.rightMargin: -10
        anchors.verticalCenter: parent.verticalCenter
        z: 10
        visible: targetView && targetView.currentIndex < targetView.count - 1

        Text { text: "❯"; anchors.centerIn: parent; color: "#6A0DAD"; font.bold: true }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.color = "#F0F0F0"
            onExited: parent.color = "#FFFFFF"
            onClicked: targetView.incrementCurrentIndex()
        }
    }
}
