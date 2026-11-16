// The card's hero: the album cover, glowing in its own two colors. It
// crossfades on track change, sinks back while paused, breathes with the bass
// when the visualizer runs, and can be a slowly spinning record instead.
import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: c

  property string source: ""
  property bool playing: false
  property bool live: false          // card open: allowed to spin
  property bool vinyl: false
  property color accent: "white"
  property color accent2: "white"
  property color fg: "white"
  property color hole: "black"
  property string fontFamily: Style.font.family
  property real energy: 0            // 0..1 bass level, 0 without a visualizer

  signal doubleClicked()

  readonly property real coverSize: Math.min(width, height) - Style.space(16)
  readonly property real coverRadius: vinyl ? coverSize / 2 : Math.max(Style.cornerRadius, Style.space(14))

  property real pulse: energy
  Behavior on pulse { NumberAnimation { duration: Style.duration(90) } }
  property real glowBase: playing ? 0.45 : 0.2
  Behavior on glowBase { NumberAnimation { duration: Style.duration(500) } }

  // Two-tone glow under the cover.
  Rectangle {
    id: glowSrc
    anchors.centerIn: cover
    anchors.verticalCenterOffset: Style.space(10)
    width: cover.width * 0.86
    height: cover.height * 0.86
    radius: c.vinyl ? width / 2 : c.coverRadius
    visible: false
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: c.accent }
      GradientStop { position: 1.0; color: c.accent2 }
    }
  }
  MultiEffect {
    anchors.fill: glowSrc
    anchors.margins: -Style.space(30)
    source: glowSrc
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1.0
    blurMax: 48
    opacity: c.glowBase + (c.playing ? 0.4 * c.pulse : 0)
    scale: cover.scale * (1 + 0.07 * c.pulse)
  }

  Item {
    id: cover
    anchors.centerIn: parent
    width: c.coverSize
    height: width
    scale: c.playing ? 1 : 0.88
    Behavior on scale { NumberAnimation { duration: Style.duration(520); easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: coverMask
    }

    // Crossfade between two images: load the new cover into the hidden one,
    // then swap once it's ready.
    property bool showA: true
    property string wanted: c.source
    onWantedChanged: {
      var next = showA ? imgB : imgA
      if (wanted === "" || next.source.toString() === wanted) return
      next.source = wanted
    }
    function settle(img) {
      if (img.status !== Image.Ready || img.source.toString() !== wanted) return
      showA = img === imgA
    }

    Item {
      id: spinner
      anchors.fill: parent

      NumberAnimation on rotation {
        from: 0; to: 360
        duration: 9000
        loops: Animation.Infinite
        running: c.vinyl && c.live && !Style.reduceMotion
        paused: running && !c.playing
        onRunningChanged: if (!running) spinner.rotation = 0
      }

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(c.fg, 0.08)
        Text {
          anchors.centerIn: parent
          text: "󰝚"
          color: Util.alpha(c.fg, 0.4)
          font.family: c.fontFamily
          font.pixelSize: Style.font.displayLarge * 2
        }
      }
      Image {
        id: imgA
        anchors.fill: parent
        sourceSize: Qt.size(512, 512)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: cover.showA && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(450); easing.type: Easing.InOutQuad } }
        onStatusChanged: cover.settle(imgA)
      }
      Image {
        id: imgB
        anchors.fill: parent
        sourceSize: Qt.size(512, 512)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: !cover.showA && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(450); easing.type: Easing.InOutQuad } }
        onStatusChanged: cover.settle(imgB)
      }

      // Record grooves.
      Repeater {
        model: c.vinyl ? [0.94, 0.84, 0.74, 0.64, 0.5] : []
        Rectangle {
          required property real modelData
          anchors.centerIn: parent
          width: parent.width * modelData
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(0, 0, 0, modelData === 0.5 ? 0.35 : 0.16)
        }
      }
    }

    // Fixed light across the record, so the spin reads as a spin.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 1.5
      height: parent.height * 0.5
      rotation: -35
      visible: c.vinyl
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.10) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    // Spindle hole.
    Rectangle {
      anchors.centerIn: parent
      visible: c.vinyl
      width: parent.width * 0.07
      height: width
      radius: width / 2
      color: c.hole
      border.width: Math.max(1, Style.space(2))
      border.color: Util.alpha(c.fg, 0.25)
    }
  }
  Item {
    id: coverMask
    anchors.fill: cover
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: c.coverRadius }
  }

  MouseArea {
    anchors.fill: cover
    cursorShape: Qt.PointingHandCursor
    onDoubleClicked: c.doubleClicked()
  }
}
