// Borderless glyph button: springs up on hover, squishes on press, and shows
// an accent dot underneath while `active` (shuffle / repeat on).
import QtQuick
import qs.Commons

Item {
  id: b

  property string icon: ""
  property real size: Style.font.iconLarge
  property color color: "white"
  property color accent: "white"
  property string fontFamily: Style.font.family
  property bool active: false

  signal clicked()

  implicitWidth: Style.space(38)
  implicitHeight: Style.space(38)
  opacity: enabled ? 1 : 0.3
  Behavior on opacity { NumberAnimation { duration: 200 } }

  Text {
    id: glyph
    anchors.centerIn: parent
    text: b.icon
    textFormat: Text.PlainText
    font.family: b.fontFamily
    font.pixelSize: b.size
    color: b.active ? b.accent : b.color
    opacity: b.active || area.containsMouse ? 1 : 0.78
    scale: area.pressed ? 0.82 : (area.containsMouse ? 1.16 : 1)
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 } }
    Behavior on color { ColorAnimation { duration: 220 } }
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: glyph.bottom
    anchors.topMargin: Style.space(1)
    width: Style.space(4)
    height: width
    radius: width / 2
    color: b.accent
    scale: b.active ? 1 : 0
    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 } }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: b.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: b.clicked()
  }
}
