import QtQuick
import QtQuick.Shapes

/**
 * DiamondMark — 폰트와 무관하게 그려지는 마름모 표시.
 * ◆/◇ 글리프는 플랫폼별 폰트 대체에 따라 크기·세로 위치가 달라 도형으로 대체한다.
 * filled: true 면 채운 마름모(◆), false 면 윤곽선만(◇).
 */
Item {
    id: root

    property color color: "black"
    property bool filled: true
    property real size: 10
    property real strokeWidth: 1.2

    // PathLine 은 ShapePath 의 속성을 참조할 수 없으므로 루트에 둔다.
    readonly property real _c: size / 2
    readonly property real _h: size / 2 - strokeWidth / 2

    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            strokeWidth: root.strokeWidth
            strokeColor: root.color
            fillColor: root.filled ? root.color : "transparent"
            joinStyle: ShapePath.MiterJoin

            startX: root._c; startY: root._c - root._h
            PathLine { x: root._c + root._h; y: root._c }
            PathLine { x: root._c; y: root._c + root._h }
            PathLine { x: root._c - root._h; y: root._c }
            PathLine { x: root._c; y: root._c - root._h }
        }
    }
}
