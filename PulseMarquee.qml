// One line of text that ping-pongs (with rests at each end) when it doesn't
// fit and `active` is set; otherwise it's cut off with an ellipsis. Size it by
// setting `width`; `implicitWidth` is the full text width.
import QtQuick
import qs.Commons

Item {
  id: m

  property string text: ""
  property color color: "white"
  property alias font: label.font
  property bool active: true
  // The moving text, for callers that animate it (the bar's track swap).
  readonly property Item content: label

  readonly property real fullWidth: metrics.advanceWidth
  readonly property bool overflow: fullWidth > width + 0.5
  readonly property bool scrolling: overflow && active && !Style.reduceMotion
  readonly property real travel: Math.max(0, fullWidth - width)

  implicitWidth: Math.ceil(fullWidth)
  implicitHeight: label.implicitHeight
  clip: true

  TextMetrics {
    id: metrics
    font: label.font
    text: m.text
  }

  Text {
    id: label
    text: m.text
    textFormat: Text.PlainText
    color: m.color
    width: m.scrolling ? implicitWidth : m.width
    elide: m.scrolling ? Text.ElideNone : Text.ElideRight
    onTextChanged: x = 0
  }

  SequentialAnimation {
    running: m.scrolling
    loops: Animation.Infinite
    onRunningChanged: if (!running) label.x = 0
    PauseAnimation { duration: 1600 }
    NumberAnimation {
      target: label; property: "x"; to: -m.travel
      duration: Math.max(1200, m.travel * 28)
      easing.type: Easing.InOutSine
    }
    PauseAnimation { duration: 1200 }
    NumberAnimation {
      target: label; property: "x"; to: 0
      duration: Math.max(1200, m.travel * 28)
      easing.type: Easing.InOutSine
    }
  }
}
