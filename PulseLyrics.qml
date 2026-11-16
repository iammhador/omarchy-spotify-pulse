// The back of the cover: lyrics.
//
// Synced: the current line is big and bright, filling with the accent as
// it's sung (karaoke sweep); the lines around it blur and fade with
// distance. Click a line to jump there.
// Unsynced: a plain page to scroll through.
import QtQuick
import QtQuick.Effects
import qs.Commons
import "Model.js" as Model

Item {
  id: lyr

  property var lines: []
  property bool synced: true
  property bool live: false          // populated (false while the back is hidden)
  property int index: -1             // current line
  property real position: 0          // lyric time (already offset)
  property string status: ""         // "", "loading", "none", "instrumental", "error"
  property real offset: 0
  property bool karaoke: true
  property bool showLoading: false   // animate the loading dots
  property color fg: "white"
  property color accent: "white"
  property color accent2: "white"
  property string fontFamily: Style.font.family

  signal seek(real seconds)

  readonly property bool sweepOn: karaoke && synced && !Style.reduceMotion

  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.space(4)
    radius: Math.max(Style.cornerRadius, Style.space(14))
    color: Util.alpha(lyr.accent, 0.08)
    border.width: 1
    border.color: Util.alpha(lyr.accent, 0.18)
  }

  // Lines fade out toward the top and bottom edges.
  Item {
    id: lyricsArea
    anchors.fill: parent
    anchors.margins: Style.space(18)
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: fadeMask
      maskThresholdMin: 0.0
      maskSpreadAtMin: 1.0
    }

    ListView {
      id: view
      anchors.fill: parent
      model: lyr.live ? lyr.lines : []
      visible: lyr.lines.length > 0
      spacing: Style.space(4)
      clip: !lyr.synced
      boundsBehavior: Flickable.StopAtBounds

      // Synced: the view follows the song. Unsynced: the user scrolls.
      interactive: !lyr.synced
      currentIndex: lyr.synced ? Math.max(0, lyr.index) : -1
      preferredHighlightBegin: height * 0.36
      preferredHighlightEnd: height * 0.36 + Style.space(30)
      highlightRangeMode: lyr.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
      highlightMoveDuration: Style.duration(520)
      highlightMoveVelocity: -1
      header: Item { width: 1; height: lyr.synced ? 0 : Style.space(16) }
      footer: Item { width: 1; height: lyr.synced ? 0 : Style.space(24) }

      delegate: Item {
        id: line
        required property var modelData
        required property int index
        readonly property bool current: lyr.synced && index === lyr.index
        readonly property int dist: lyr.synced ? Math.abs(index - Math.max(0, lyr.index)) : 0
        readonly property bool blank: modelData.text === ""
        readonly property real restOpacity: lyr.synced ? Math.max(0.16, 0.5 - dist * 0.1) : 0.82

        width: view.width
        height: blank ? Style.space(10) : lineText.implicitHeight + Style.space(8)

        // Depth of field: lines blur a little more the further they are.
        property real blurAmount: lyr.synced && !Style.reduceMotion ? Math.min(1, dist * 0.2) : 0
        Behavior on blurAmount { NumberAnimation { duration: Style.duration(420); easing.type: Easing.OutCubic } }
        layer.enabled: blurAmount > 0.01 && dist < 7
        layer.effect: MultiEffect {
          blurEnabled: true
          blurMax: 12
          blur: line.blurAmount
        }

        // Karaoke progress through the current line, smoothed between ticks.
        readonly property real start: modelData.t
        readonly property real gap: (index + 1 < lyr.lines.length ? lyr.lines[index + 1].t : start + 6) - start
        readonly property real target: current ? Model.clamp((lyr.position - start) / Model.sweepSpan(modelData.text, gap), 0, 1) : 0
        property real sweep: target
        Behavior on sweep {
          enabled: line.current
          NumberAnimation { duration: 260; easing.type: Easing.Linear }
        }

        Text {
          id: lineText
          visible: !line.blank
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          text: line.modelData.text
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          font.family: lyr.fontFamily
          font.pixelSize: lyr.synced ? Style.font.title + Style.space(3) : Style.font.title
          font.bold: lyr.synced
          color: line.current && lyr.sweepOn ? Util.alpha(lyr.fg, 0.5)
            : (line.current ? lyr.fg : Util.alpha(lyr.fg, 0.9))
          opacity: line.current ? 1 : line.restOpacity
          scale: line.current || !lyr.synced ? 1 : 0.92
          transformOrigin: Item.Left
          Behavior on opacity { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: Style.duration(420); easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

          // Widths of the wrapped rows, so the sweep follows the words.
          property var rowWidths: []
          property var pendingRows: []
          onLineLaidOut: function(row) {
            pendingRows[row.number] = row.implicitWidth !== undefined ? row.implicitWidth : row.width
            if (row.isLast) { rowWidths = pendingRows; pendingRows = [] }
          }
          // The sung part: rows already done, plus the row in progress.
          Item {
            id: sung
            visible: line.current && lyr.sweepOn
            anchors.fill: parent
            readonly property int rows: Math.max(1, lineText.lineCount)
            readonly property real rowHeight: lineText.contentHeight / rows
            readonly property var geo: Model.sweepGeometry(
              lineText.rowWidths.length ? lineText.rowWidths : [lineText.width], line.sweep)

            Item {
              width: parent.width
              height: sung.geo.full * sung.rowHeight
              clip: true
              Text {
                width: lineText.width
                text: lineText.text
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                font: lineText.font
                color: lyr.accent
              }
            }
            Item {
              y: sung.geo.full * sung.rowHeight
              width: sung.geo.partial
              height: sung.rowHeight
              clip: true
              Text {
                y: -sung.geo.full * sung.rowHeight
                width: lineText.width
                text: lineText.text
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                font: lineText.font
                color: lyr.accent
              }
            }
          }
        }

        // Click a line to jump there.
        MouseArea {
          anchors.fill: parent
          enabled: lyr.synced && !line.blank
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: lyr.seek(line.modelData.t)
          onEntered: if (!line.current) lineText.opacity = 0.75
          onExited: lineText.opacity = Qt.binding(function() { return line.current ? 1 : line.restOpacity })
        }
      }
    }
  }
  Item {
    id: fadeMask
    anchors.fill: lyricsArea
    layer.enabled: true
    visible: false
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: lyr.synced ? 0.16 : 0.08; color: "white" }
        GradientStop { position: lyr.synced ? 0.8 : 0.9; color: "white" }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
  }

  // Unsynced badge.
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(12)
    visible: !lyr.synced && lyr.lines.length > 0
    width: badge.implicitWidth + Style.space(16)
    height: badge.implicitHeight + Style.space(6)
    radius: height / 2
    color: Util.alpha(lyr.fg, 0.10)
    Text {
      id: badge
      anchors.centerIn: parent
      text: "Not synced · scroll to read"
      color: Util.alpha(lyr.fg, 0.6)
      font.family: lyr.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Timing nudge feedback.
  Rectangle {
    id: toast
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(12)
    width: toastText.implicitWidth + Style.space(18)
    height: toastText.implicitHeight + Style.space(8)
    radius: height / 2
    color: Util.alpha(lyr.accent, 0.22)
    border.width: 1
    border.color: Util.alpha(lyr.accent, 0.5)
    opacity: 0
    Text {
      id: toastText
      anchors.centerIn: parent
      text: lyr.offset === 0 ? "Lyrics timing reset"
        : "Lyrics " + Math.abs(lyr.offset).toFixed(1) + " s " + (lyr.offset > 0 ? "sooner" : "later")
      color: lyr.fg
      font.family: lyr.fontFamily
      font.pixelSize: Style.font.caption
    }
    SequentialAnimation {
      id: toastAnim
      NumberAnimation { target: toast; property: "opacity"; to: 1; duration: Style.duration(140) }
      PauseAnimation { duration: 1300 }
      NumberAnimation { target: toast; property: "opacity"; to: 0; duration: Style.duration(400) }
    }
  }
  onOffsetChanged: toastAnim.restart()

  // Empty / loading states.
  Column {
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    spacing: Style.space(10)
    visible: lyr.lines.length === 0

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(6)
      visible: lyr.status === "loading"
      Repeater {
        model: 3
        Rectangle {
          required property int index
          width: Style.space(8); height: width; radius: width / 2
          // Two accents alternate; blending them (often complements) goes gray.
          color: index === 1 ? lyr.accent2 : lyr.accent
          SequentialAnimation on scale {
            running: lyr.status === "loading" && lyr.showLoading && !Style.reduceMotion
            loops: Animation.Infinite
            PauseAnimation { duration: index * 140 }
            NumberAnimation { from: 0.5; to: 1.2; duration: 300; easing.type: Easing.OutQuad }
            NumberAnimation { to: 0.5; duration: 300; easing.type: Easing.InQuad }
            PauseAnimation { duration: (2 - index) * 140 }
          }
        }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: lyr.status !== "loading"
      text: lyr.status === "instrumental" ? "󰝚" : "󰍡"
      color: Util.alpha(lyr.fg, 0.35)
      font.family: lyr.fontFamily
      font.pixelSize: Style.font.displayLarge
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: lyr.status === "loading" ? "Finding lyrics"
        : lyr.status === "error" ? "Couldn't reach lrclib.net"
        : lyr.status === "instrumental" ? "Instrumental"
        : "No lyrics for this song"
      color: Util.alpha(lyr.fg, 0.55)
      font.family: lyr.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
