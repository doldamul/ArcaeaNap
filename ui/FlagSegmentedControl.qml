import QtQuick
import QtQuick.Layouts

/**
 * FlagSegmentedControl — 3단계(Hide/Show/Only) 세그먼트 필터 컨트롤.
 */
RowLayout {
    id: flagSegmentRoot
    property string flagName: ""
    property int selectedIndex: 1  // 0=Hide, 1=Show, 2=Only
    signal indexChanged(int idx)
    
    spacing: 0
    
    Text { 
        text: flagName
        color: "#333"
        Layout.preferredWidth: 100
    }
    
    Repeater {
        model: ["Hide", "Show", "Only"]
        
        Rectangle {
            width: 50; height: 28
            radius: index === 0 ? 4 : (index === 2 ? 4 : 0)
            color: flagSegmentRoot.selectedIndex === index ? "#6A0DAD" : "#F0F0F0"
            border.color: "#D0D0D0"
            border.width: flagSegmentRoot.selectedIndex === index ? 0 : 1
            
            // Round only left/right corners based on position
            Rectangle {
                visible: index === 0
                anchors.right: parent.right; width: 4; height: parent.height
                color: parent.color
            }
            Rectangle {
                visible: index === 2
                anchors.left: parent.left; width: 4; height: parent.height
                color: parent.color
            }
            
            Text {
                anchors.centerIn: parent
                text: modelData
                font.pixelSize: 11
                color: flagSegmentRoot.selectedIndex === index ? "white" : "#666"
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    flagSegmentRoot.selectedIndex = index
                    flagSegmentRoot.indexChanged(index)
                }
            }
        }
    }
}
