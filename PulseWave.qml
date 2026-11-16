// A small flowing wave, used in place of equalizer bars. It flows while
// music plays, follows the audio when the visualizer runs (louder bands make
// that part of the wave taller), and settles into a near-flat line on pause.
// The ends taper to the middle so it sits neatly inside a ring.
import QtQuick
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

Item {
  id: w

  property bool playing: false
  property bool live: true            // on screen: allowed to animate
  property var levels: []             // 0..1 per band from the visualizer, or empty
  property color color: "white"
  property real lineWidth: Math.max(1.5, Style.space(1.5))
  property int samples: 24

  readonly property bool hasLevels: !!levels && levels.length > 0

  property real phase: 0
  NumberAnimation on phase {
    from: 0; to: 1
    duration: 1600
    loops: Animation.Infinite
    running: w.playing && w.live && !Style.reduceMotion
  }

  // Overall height: steady while playing, the music's loudness with the
  // visualizer, almost flat on pause.
  property real energy: !playing ? 0.1
    : (hasLevels ? Model.clamp(0.3 + Model.band(levels, 0, 1) * 1.4, 0.3, 1) : 0.8)
  Behavior on energy { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutQuad } }

  readonly property var points: {
    var pts = []
    var mid = height / 2
    var amp = Math.max(0, mid - lineWidth / 2) * energy
    var p = phase * 2 * Math.PI
    for (var i = 0; i <= samples; i++) {
      var t = i / samples
      // A main swell plus a faint faster ripple: liquid rather than mechanical,
      // and still a clean "~" at icon size.
      var shape = 0.85 * Math.sin(2 * Math.PI * 1.25 * t - p) + 0.15 * Math.sin(2 * Math.PI * 2.5 * t - 2 * p)
      var taper = Math.sin(Math.PI * t)
      var local = hasLevels ? 0.35 + 0.65 * Model.band(levels, Math.max(0, t - 0.12), Math.min(1, t + 0.12)) : 1
      pts.push(Qt.point(t * width, mid - amp * taper * local * shape))
    }
    return pts
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: w.color
      strokeWidth: w.lineWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: w.points }
    }
  }
}
