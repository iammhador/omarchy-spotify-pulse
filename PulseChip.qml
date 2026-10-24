// Small pill button with an icon and label; tinted with the accent while active.
import QtQuick
import qs.Commons

Rectangle {
  id: c

  property string icon: ""
  property string label: ""
  property color fg: "white"
  property color accent: "white"
  property string fontFamily: Style.font.family
  property bool active: false

  signal clicked()

  implicitWidth: row.implicitWidth + Style.space(24)
  implicitHeight: row.implicitHeight + Style.space(12)
  radius: height / 2
  color: c.active ? Util.alpha(c.accent, 0.22) : Util.alpha(c.fg, area.containsMouse ? 0.12 : 0.06)
  border.width: 1
  border.color: c.active ? Util.alpha(c.accent, 0.5) : Util.alpha(c.fg, 0.10)
  scale: area.pressed ? 0.94 : 1
  Behavior on color { ColorAnimation { duration: 200 } }
  Behavior on border.color { ColorAnimation { duration: 200 } }
  Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 3 } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(7)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: c.icon
      textFormat: Text.PlainText
      font.family: c.fontFamily
      font.pixelSize: Style.font.body
      color: c.active ? c.accent : c.fg
      Behavior on color { ColorAnimation { duration: 200 } }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: c.label
      textFormat: Text.PlainText
      font.family: c.fontFamily
      font.pixelSize: Style.font.bodySmall
      color: c.active ? c.accent : Util.alpha(c.fg, 0.85)
      Behavior on color { ColorAnimation { duration: 200 } }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: c.clicked()
  }
}
