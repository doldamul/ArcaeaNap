import QtQuick

// ♥/♡ 글리프를 폰트 메트릭(advance/line-height)이 아닌 실제 잉크 영역(tight bounding rect) 기준으로
// 부모의 정중앙에 배치한다. 폰트 폴백에 따라 심볼 글리프가 박스 안에서 치우치는 현상 방지용.
Item {
    id: root
    property bool filled: false
    property int pixelSize: 9
    property color glyphColor: "black"

    anchors.fill: parent

    TextMetrics {
        id: metrics
        font.pixelSize: root.pixelSize
        text: root.filled ? "♥" : "♡"
    }

    Text {
        text: metrics.text
        font.pixelSize: root.pixelSize
        color: root.glyphColor
        x: (root.width - metrics.tightBoundingRect.width) / 2 - metrics.tightBoundingRect.x
        y: root.height / 2 - (metrics.tightBoundingRect.y + metrics.tightBoundingRect.height / 2) - baselineOffset
    }
}
