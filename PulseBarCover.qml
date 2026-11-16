// The bar's cover: the album art as a rounded square, with the song's
// progress drawn around its four sides (clockwise from the top middle).
// Right after a scroll the outline shows the volume instead. Until a cover
// loads, a small wave stands in for it.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

Item {
  id: b

  property string source: ""
  property bool playing: false
  property bool live: true
  property bool showOutline: true
  property real fraction: 0            // progress (or volume) 0..1
  property bool volumeMode: false
  property var levels: []
  property color fg: "white"
  property color accent: "white"

  // A fine line: present, not heavy.
  readonly property real stroke: Math.max(1, Style.space(1.2))
  readonly property real radius: width * 0.24
  // The outline hugs the art with a hairline of air between them.
  readonly property real gap: showOutline ? stroke + 1 : 0

  implicitWidth: Style.space(22)
  implicitHeight: implicitWidth

  // ---- art
  Item {
    id: art
    anchors.fill: parent
    anchors.margins: b.gap
    opacity: b.playing ? 1 : 0.6
    Behavior on opacity { NumberAnimation { duration: Style.duration(220) } }
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: artMask
    }

    Rectangle { anchors.fill: parent; color: Util.alpha(b.fg, 0.12) }

    PulseWave {
      anchors.centerIn: parent
      width: parent.width * 0.7
      height: parent.height * 0.5
      visible: img.status !== Image.Ready
      playing: b.playing
      live: b.live && visible
      levels: b.levels
      color: b.accent
      lineWidth: Math.max(1, Style.space(1.2))
    }

    Image {
      id: img
      anchors.fill: parent
      source: b.source
      sourceSize: Qt.size(64, 64)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(300) } }
    }
  }
  Item {
    id: artMask
    anchors.fill: art
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: Math.max(2, b.radius - b.gap) }
  }

  // New track: a small pop as the new cover arrives.
  property string track: ""
  onTrackChanged: if (!Style.reduceMotion && track !== "") pop.restart()
  NumberAnimation {
    id: pop
    target: art; property: "scale"
    from: 0.82; to: 1
    duration: 420
    easing.type: Easing.OutBack; easing.overshoot: 2
  }

  // ---- outline
  Shape {
    anchors.fill: parent
    visible: b.showOutline || b.volumeMode
    preferredRendererType: Shape.CurveRenderer
    opacity: b.playing || b.volumeMode ? 1 : 0.5
    Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }

    ShapePath {
      strokeWidth: b.stroke
      strokeColor: Util.alpha(b.fg, 0.18)
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: Model.outlinePoints(b.width, b.height, b.radius, b.stroke / 2, 1, Qt) }
    }
    ShapePath {
      strokeWidth: b.stroke
      strokeColor: b.volumeMode ? b.fg : b.accent
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: Model.outlinePoints(b.width, b.height, b.radius, b.stroke / 2, b.fraction, Qt) }
    }
  }
}
