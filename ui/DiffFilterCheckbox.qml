import QtQuick
import QtQuick.Shapes 1.15

/**
 * DiffFilterCheckbox — 다이아몬드 형태의 난이도 필터 체크박스.
 */
Column {
    id: diffCheckRoot
    property bool checked: true
    property string text: ""
    property color diffColor: "#000000"
    
    spacing: 8
    
    // Diamond Indicator using Shape for proper anti-aliasing
    Item {
        width: 32; height: 32
        anchors.horizontalCenter: parent.horizontalCenter
        
        Shape {
            anchors.fill: parent
            antialiasing: true
            
            ShapePath {
                strokeWidth: 2
                strokeColor: diffCheckRoot.diffColor
                fillColor: diffCheckRoot.checked ? diffCheckRoot.diffColor : "transparent"
                joinStyle: ShapePath.MiterJoin
                
                // Diamond: top -> right -> bottom -> left -> top
                startX: 16; startY: 4
                PathLine { x: 28; y: 16 }
                PathLine { x: 16; y: 28 }
                PathLine { x: 4; y: 16 }
                PathLine { x: 16; y: 4 }
            }
        }
        
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                diffCheckRoot.checked = !diffCheckRoot.checked
            }
        }
    }
    
    // Label
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: diffCheckRoot.text
        font.bold: true
        font.pixelSize: 12
        color: diffCheckRoot.checked ? diffCheckRoot.diffColor : "#AAA"
    }
}
