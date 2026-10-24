// Thin slider: a hairline track that thickens and grows a knob on hover.
import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: s

  property real value: 0
  property real maximum: 1
  property color fill: "white"
  property color track: Qt.rgba(1, 1, 1, 0.15)
  // Emit `moved` continuously while dragging (volume) or only on release (seek).
  property bool live: false

  signal moved(real value)
  signal released(real value)

  property bool dragging: false
  property real dragValue: 0
  readonly property bool hot: area.containsMouse || dragging
  readonly property real fraction: Model.clamp((dragging ? dragValue : value) / Math.max(0.0001, maximum), 0, 1)

  implicitHeight: Style.space(18)
  opacity: enabled ? 1 : 0.4

  Rectangle {
    id: bed
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: s.hot ? Style.space(6) : Style.space(4)
    radius: height / 2
    color: s.track
    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Rectangle {
      height: parent.height
      radius: height / 2
      width: Math.max(height, parent.width * s.fraction)
      color: s.fill
      Behavior on width {
        enabled: !s.dragging
        NumberAnimation { duration: 260; easing.type: Easing.Linear }
      }
    }
  }

  Rectangle {
    width: s.hot ? Style.space(14) : 0
    height: width
    radius: width / 2
    x: bed.width * s.fraction - width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: s.fill
    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
    Behavior on x {
      enabled: !s.dragging
      NumberAnimation { duration: 260; easing.type: Easing.Linear }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    anchors.topMargin: -Style.space(4)
    anchors.bottomMargin: -Style.space(4)
    hoverEnabled: true
    enabled: s.enabled
    cursorShape: Qt.PointingHandCursor
    preventStealing: true

    function at(x) { return Model.clamp(x / width, 0, 1) * s.maximum }

    onPressed: function(m) {
      s.dragValue = at(m.x)
      s.dragging = true
      if (s.live) s.moved(s.dragValue)
    }
    onPositionChanged: function(m) {
      if (!pressed) return
      s.dragValue = at(m.x)
      if (s.live) s.moved(s.dragValue)
    }
    onReleased: function(m) {
      s.dragValue = at(m.x)
      s.released(s.dragValue)
      s.dragging = false
    }
    onWheel: function(w) {
      var step = s.maximum * 0.05
      s.released(Model.clamp(s.value + (w.angleDelta.y > 0 ? step : -step), 0, s.maximum))
    }
  }
}
