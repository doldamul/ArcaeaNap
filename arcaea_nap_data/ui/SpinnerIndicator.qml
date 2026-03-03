import QtQuick

/**
 * SpinnerIndicator — 재사용 가능한 회전 스피너 컴포넌트.
 *
 * Properties:
 *   running (bool): 애니메이션 실행 여부 (유일한 제어 인터페이스)
 *   lineWidth (real): 호(arc)의 굵기 (default: 2)
 *   strokeColor (string): 호의 색상 (default: "white")
 *   radiusOffset (real): 반지름 = width/2 - radiusOffset (default: lineWidth)
 *
 * 사용 패턴:
 *   SpinnerIndicator {
 *       width: 64; height: 64
 *       running: someCondition
 *   }
 *
 * running이 false이면 자동으로 visible: false가 되어 표시와 애니메이션이 동시에 제어된다.
 */
Canvas {
    id: spinnerCanvas

    property bool running: false
    property real lineWidth: 2
    property string strokeColor: "white"
    property real radiusOffset: lineWidth

    visible: running
    rotation: 0

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.beginPath()
        ctx.arc(width / 2, height / 2, width / 2 - radiusOffset, 0, 1.4 * Math.PI)
        ctx.lineWidth = spinnerCanvas.lineWidth
        ctx.strokeStyle = spinnerCanvas.strokeColor
        ctx.lineCap = "round"
        ctx.stroke()
    }

    RotationAnimation on rotation {
        from: 0
        to: 360
        duration: 1000
        loops: Animation.Infinite
        running: spinnerCanvas.running
    }

    onAvailableChanged: if (available) requestPaint()
}
