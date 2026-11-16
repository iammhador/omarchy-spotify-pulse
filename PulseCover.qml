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
  // Swiped off: 1 = next (swiped left), -1 = previous (swiped right).
  signal skip(int dir)

  // Horizontal swipe offset of the cover (and its glow).
  property real dragX: 0
  readonly property real dragAmount: Math.min(1, Math.abs(dragX) / (coverSize * 0.28))
  onLiveChanged: if (!live) { fly.stop(); spring.stop(); dragX = 0 }

  function springBack() {
    if (Style.reduceMotion) { dragX = 0; return }
    spring.restart()
  }
  function flyOff(dir) {
    if (Style.reduceMotion) { dragX = 0; skip(dir); return }
    fly.dir = dir
    fly.restart()
  }

  NumberAnimation {
    id: spring
    target: c; property: "dragX"; to: 0
    duration: 380
    easing.type: Easing.OutBack; easing.overshoot: 1.6
  }
  // Off one side, skip, then the next cover glides in from the other.
  SequentialAnimation {
    id: fly
    property int dir: 1
    NumberAnimation { target: c; property: "dragX"; to: -fly.dir * c.width * 1.1; duration: 200; easing.type: Easing.InCubic }
    ScriptAction { script: { c.skip(fly.dir); c.dragX = fly.dir * c.width * 0.7 } }
    NumberAnimation { target: c; property: "dragX"; to: 0; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
  }

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
    opacity: (c.glowBase + (c.playing ? 0.4 * c.pulse : 0)) * cover.opacity
    scale: cover.scale * (1 + 0.07 * c.pulse)
  }

  Item {
    id: cover
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: c.dragX
    width: c.coverSize
    height: width
    rotation: c.dragX * 0.03
    opacity: 1 - Math.min(0.6, Math.abs(c.dragX) / (c.width * 1.2))
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

  // Hints at the edges while swiping: where the swipe will take you.
  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: "󰒮"
    color: c.fg
    font.family: c.fontFamily
    font.pixelSize: Style.font.iconLarge + Style.space(6)
    opacity: c.dragX > 0 ? c.dragAmount * 0.9 : 0
    scale: 0.7 + 0.3 * (c.dragX > 0 ? c.dragAmount : 0)
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: "󰒭"
    color: c.fg
    font.family: c.fontFamily
    font.pixelSize: Style.font.iconLarge + Style.space(6)
    opacity: c.dragX < 0 ? c.dragAmount * 0.9 : 0
    scale: 0.7 + 0.3 * (c.dragX < 0 ? c.dragAmount : 0)
  }

  // Swipe the cover to skip; double-click it for lyrics. The area stays where
  // the cover rests, so it doesn't slide away under the pointer.
  MouseArea {
    id: swipe
    anchors.centerIn: parent
    width: c.coverSize
    height: c.coverSize
    preventStealing: true
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

    property bool dragging: false
    property real startX: 0
    property real lastX: 0
    property double lastT: 0
    property real velocity: 0          // px per ms

    onPressed: function(m) {
      if (fly.running) return
      spring.stop()
      startX = m.x - c.dragX
      lastX = m.x
      lastT = Date.now()
      velocity = 0
      dragging = false
    }
    onPositionChanged: function(m) {
      if (!pressed || fly.running) return
      var dx = m.x - startX
      if (!dragging && Math.abs(dx) > 6) dragging = true
      if (!dragging) return
      c.dragX = dx
      var now = Date.now()
      if (now > lastT) velocity = (m.x - lastX) / (now - lastT)
      lastX = m.x
      lastT = now
    }
    onReleased: {
      if (!dragging) return
      dragging = false
      var far = Math.abs(c.dragX) > c.coverSize * 0.28
      var flick = Math.abs(velocity) > 0.8 && Math.abs(c.dragX) > 20 && (velocity < 0) === (c.dragX < 0)
      if (far || flick) c.flyOff(c.dragX < 0 ? 1 : -1)
      else c.springBack()
    }
    onCanceled: { dragging = false; c.springBack() }
    onDoubleClicked: if (!dragging) c.doubleClicked()
  }
}
