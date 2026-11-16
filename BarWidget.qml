// Spotify Pulse — an animated Spotify player for the Omarchy bar.
//
// Bar:  "Song — Artist" (or the line being sung) with an equalizer that
//       follows the music, a peek at the cover on track change, a thin
//       progress line and a ping-pong marquee for long titles. Left click
//       opens the card, middle click plays/pauses, right click skips, scroll
//       changes Spotify's volume.
// Card: cover-first player tinted by two colors from the album art: glowing
//       cover (or a spinning record), seek, shuffle / previous / play / next /
//       repeat, volume, recently played, a sleep timer, and synced lyrics
//       with a karaoke sweep that flip in on the back of the cover.
//
// Everything is driven by Spotify's MPRIS interface, so it stays in sync with
// the desktop app, media keys and Spotify Connect. No account or API key.
//
// Shared state and every side effect (lyrics lookups, cover sampling, the
// visualizer, history, sleep) live in Service.qml, created once by the
// shell. This file is the per-monitor UI on top of it.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.iammhador.spotify-pulse"

  // ---------------------------------------------------------------- service

  property var svc: null
  property int resolveTries: 0

  function resolveService() {
    if (svc) return
    if (bar && bar.shell && typeof bar.shell.serviceFor === "function")
      svc = bar.shell.serviceFor(moduleName) || null
  }

  // The service can finish loading after the widget; look again until it's up.
  Timer {
    interval: 250
    repeat: true
    running: root.svc === null && !localService.active
    onTriggered: {
      root.resolveService()
      // Still nothing after 5 s: the shell couldn't start it, so host one here
      // (per monitor, but better than an empty bar).
      if (!root.svc && ++root.resolveTries >= 20) localService.active = true
    }
  }
  Loader {
    id: localService
    active: false
    source: "Service.qml"
    onLoaded: if (!root.svc) root.svc = item
  }

  onBarChanged: resolveService()
  onSvcChanged: pushConfig()
  Component.onCompleted: resolveService()
  Component.onDestruction: if (popupOpen && svc) svc.cardOpened(false)

  // ---------------------------------------------------------------- player

  readonly property var player: svc ? svc.player : null
  readonly property bool running: svc ? svc.running : false
  readonly property bool playing: svc ? svc.playing : false
  readonly property string title: svc ? svc.title : ""
  readonly property string artist: svc ? svc.artist : ""
  readonly property string album: svc ? svc.album : ""
  readonly property string artUrl: svc ? svc.artUrl : ""
  readonly property string trackKey: svc ? svc.trackKey : ""
  readonly property real duration: svc ? svc.duration : 0
  readonly property real position: svc ? svc.position : 0
  readonly property real progress: svc ? svc.progress : 0
  readonly property real volume: svc ? svc.volume : 0
  readonly property bool lyricsOn: svc ? svc.lyricsOn : false

  // ---------------------------------------------------------------- settings

  // `omarchy bar set` stores plain strings, so accept "false" / "0" too.
  function flag(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "string") return !/^(false|0|no|off)$/i.test(v.trim())
    return !!v
  }
  function choice(name, fallback, options) {
    var v = String(setting(name, fallback)).trim().toLowerCase()
    return options.indexOf(v) !== -1 ? v : fallback
  }

  readonly property int maxWidth: Number(setting("maxWidth", 260)) > 0 ? Number(setting("maxWidth", 260)) : 260
  readonly property bool showArtist: flag("showArtist", true)
  readonly property bool marquee: flag("marquee", true)
  readonly property bool showWhenClosed: flag("showWhenClosed", false)
  readonly property bool albumColors: flag("albumColors", true)
  readonly property bool blurBackdrop: flag("blurBackdrop", true)
  readonly property string scrollAction: choice("scrollAction", "volume", ["volume", "track", "none"])
  readonly property bool barLyrics: flag("barLyrics", false)
  readonly property bool visualizer: flag("visualizer", true)
  readonly property bool historyOn: flag("history", true)
  readonly property bool karaoke: flag("karaoke", true)
  readonly property string pillCover: choice("pillCover", "peek", ["peek", "always", "off"])
  readonly property bool pillProgress: flag("pillProgress", true)
  readonly property bool vinyl: choice("coverStyle", "square", ["square", "vinyl"]) === "vinyl"

  readonly property var serviceConfig: ({
    albumColors: albumColors, visualizer: visualizer, history: historyOn,
    barLyrics: barLyrics, pillProgress: pillProgress
  })
  onServiceConfigChanged: pushConfig()
  function pushConfig() { if (svc) svc.configure(serviceConfig) }

  // ---------------------------------------------------------------- look

  readonly property color barFg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color panelFg: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool darkTheme: Commons.Color.background.hslLightness < 0.5
  readonly property bool motion: !Style.reduceMotion
  readonly property color spotifyGreen: "#1ed760"

  // Two album colors, crossfading between tracks.
  property color animatedAccent: svc ? svc.accent : Commons.Color.accent
  property color animatedAccent2: svc ? svc.accent2 : Commons.Color.accent
  Behavior on animatedAccent { ColorAnimation { duration: Style.duration(600); easing.type: Easing.OutCubic } }
  Behavior on animatedAccent2 { ColorAnimation { duration: Style.duration(600); easing.type: Easing.OutCubic } }

  // Audio levels from the visualizer (empty without cava).
  readonly property var levels: svc ? svc.levels : []
  readonly property bool vizLive: !!svc && svc.vizLive && levels.length > 0
  readonly property real bass: vizLive ? Model.band(levels, 0, 0.25) : 0

  // ---------------------------------------------------------------- actions

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property real volumeFlash: 0

  function open() { if (running) popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { if (running) popupOpen = !popupOpen; else launch() }
  onRunningChanged: if (!running) close()

  function launch() { if (svc) svc.launch(); else Quickshell.execDetached(["spotify"]) }
  function playPause() { if (svc) svc.playPause() }
  function next() { if (svc) svc.next() }
  function previous() { if (svc) svc.previous() }
  function seekTo(seconds) { if (svc) svc.seekTo(seconds) }
  function setVolume(v) {
    if (!running || !player.volumeSupported) return
    svc.setVolume(v)
    volumeFlash = 1
    volumeFlashTimer.restart()
  }
  function nudgeVolume(delta) { if (running) setVolume(volume + delta) }
  function toggleShuffle() { if (svc) svc.toggleShuffle() }
  function cycleRepeat() { if (svc) svc.cycleRepeat() }
  function toggleLyrics() { if (svc) svc.lyricsOn = !svc.lyricsOn }

  Timer {
    id: volumeFlashTimer
    interval: 1100
    onTriggered: root.volumeFlash = 0
  }

  onPopupOpenChanged: {
    if (svc) svc.cardOpened(popupOpen)
    if (popupOpen) introAnim.restart()
  }

  // Spotify blanks the metadata for a moment between tracks. Ride that out
  // instead of hiding the pill (and losing its text) for a frame.
  property bool bridging: false
  readonly property bool hasTitle: title !== ""
  onHasTitleChanged: {
    bridging = !hasTitle && running
    if (bridging) bridgeTimer.restart()
  }
  Timer {
    id: bridgeTimer
    interval: 1500
    onTriggered: root.bridging = false
  }

  // Peek: on track change, briefly show the new cover in the bar.
  property bool peeking: false
  property string lastTrack: ""
  Timer {
    id: peekTimer
    interval: 4000
    onTriggered: root.peeking = false
  }
  onTrackKeyChanged: {
    if (popupOpen) trackAnim.restart()
    if (title === "") return
    if (lastTrack !== "" && lastTrack !== trackKey && pillCover === "peek" && running && !popupOpen) {
      peeking = true
      peekTimer.restart()
    }
    lastTrack = trackKey
  }

  // ---------------------------------------------------------------- ipc

  IpcHandler {
    target: "spotify-pulse"
    function toggle(): void { root.toggle() }
    function close(): void { root.close() }
    function playPause(): void { root.playPause() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function lyrics(): void { root.toggleLyrics() }
    function shuffle(): void { root.toggleShuffle() }
    function repeat(): void { root.cycleRepeat() }
    function volume(percent: int): void { root.setVolume(percent / 100) }
    // Minutes until pause; 0 turns it off, -1 pauses when the track ends.
    function sleep(minutes: int): void { if (root.svc) root.svc.setSleep(minutes) }
    function clearHistory(): void { if (root.svc) root.svc.clearHistory() }
    function status(): string {
      var s = root.svc
      return JSON.stringify({
        running: root.running, playing: root.playing, popupOpen: root.popupOpen,
        title: root.title, artist: root.artist, album: root.album,
        uri: s ? s.trackUri : "",
        position: Math.round(root.position * 10) / 10, duration: root.duration,
        shuffle: root.running ? root.player.shuffle : false,
        loop: root.running ? root.player.loopState : 0,
        volume: root.volume,
        accent: s ? String(s.accent) : "", accent2: s ? String(s.accent2) : "",
        lyricsOn: root.lyricsOn, lyricsStatus: s ? s.lyricsStatus : "",
        lyricsSynced: s ? s.lyricsSynced : true, lyricsLines: s ? s.lyricLines.length : 0,
        lyricsOffset: s ? s.lyricsOffset : 0,
        visualizer: s ? (s.vizLive ? "live" : (s.cavaFound ? "idle" : "no-cava")) : "",
        sleep: s ? s.sleepMinutes : 0, sleepLeft: s ? s.sleepLeft : 0,
        history: s ? s.history.length : 0
      })
    }
  }

  // ================================================================ BAR PILL

  readonly property bool shown: svc !== null && (running ? (title !== "" || bridging) : showWhenClosed)
  visible: shown && !vertical
  implicitWidth: shown && !vertical ? pill.width : 0
  implicitHeight: barSize

  readonly property string trackText: title + (showArtist && artist ? "  —  " + artist : "")
  readonly property string lyricText: svc ? svc.currentLine : ""
  readonly property bool showingLyric: running && barLyrics && playing && lyricText !== ""
  readonly property string pillText: !running ? "Open Spotify" : (showingLyric ? lyricText : trackText)
  onPillTextChanged: pill.swapTrack()

  readonly property bool showThumb: running && (pillCover === "always" || (pillCover === "peek" && peeking))

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    height: Math.round(root.barSize * 0.72)
    width: pillRow.width + Style.space(18)
    radius: height / 2
    color: Util.alpha(root.animatedAccent, mouse.containsMouse || root.popupOpen ? 0.16 : (root.peeking ? 0.10 : 0.0))
    border.width: mouse.containsMouse || root.popupOpen ? 1 : 0
    border.color: Util.alpha(root.animatedAccent, 0.35)
    opacity: root.running ? 1 : 0.55
    Behavior on color { ColorAnimation { duration: Style.duration(180) } }
    Behavior on width { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }

    // Shown text lags `pillText` so the swap can animate out and back in.
    property string displayText: root.pillText

    function swapTrack() {
      if (displayText === root.pillText) return
      if (root.running && root.title === "") return   // between tracks: keep the old text
      if (!root.visible || !root.motion) { displayText = root.pillText; return }
      swapAnim.restart()
    }

    // Progress through the song, as a hairline along the bottom.
    Rectangle {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: parent.radius * 0.6
      anchors.bottomMargin: 1
      visible: root.pillProgress && root.running && root.duration > 0
      height: Math.max(1, Style.space(2))
      radius: height / 2
      width: (parent.width - parent.radius * 1.2) * root.progress
      opacity: root.volumeFlash > 0 ? 0 : (root.playing ? 0.75 : 0.35)
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: root.animatedAccent }
        GradientStop { position: 1.0; color: root.animatedAccent2 }
      }
      Behavior on opacity { NumberAnimation { duration: Style.duration(220) } }
    }

    // Spotify volume, briefly, after a scroll.
    Rectangle {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: parent.radius * 0.6
      anchors.bottomMargin: 1
      height: Math.max(2, Style.space(2))
      radius: height / 2
      width: (parent.width - parent.radius * 1.2) * root.volume
      color: root.animatedAccent
      opacity: root.volumeFlash
      Behavior on opacity { NumberAnimation { duration: Style.duration(220) } }
      Behavior on width { NumberAnimation { duration: Style.duration(120) } }
    }

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      // Tiny cover: on track change (peek) or always, per `pillCover`.
      Item {
        id: thumb
        readonly property real size: pill.height - Style.space(6)
        width: root.showThumb ? size : 0
        height: size
        visible: width > 0.5
        anchors.verticalCenter: parent.verticalCenter
        Behavior on width { NumberAnimation { duration: Style.duration(340); easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

        Item {
          id: thumbArt
          anchors.centerIn: parent
          width: thumb.width
          height: thumb.width
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: thumbMask
          }
          Rectangle { anchors.fill: parent; color: Util.alpha(root.barFg, 0.15) }
          Image {
            anchors.fill: parent
            source: thumb.visible && root.svc
              ? (root.svc.artFile !== "" ? "file://" + root.svc.artFile : root.artUrl) : ""
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
        }
        Item {
          id: thumbMask
          anchors.fill: thumbArt
          layer.enabled: true
          visible: false
          Rectangle { anchors.fill: parent; radius: width * 0.28 }
        }
      }

      // Equalizer: real levels from the visualizer, or a gentle stand-in.
      Item {
        id: eq
        width: Style.space(13)
        height: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        property real phase: 0
        NumberAnimation on phase {
          from: 0; to: 1
          duration: 1100
          loops: Animation.Infinite
          running: root.playing && root.visible && !root.vizLive && root.motion
        }
        Repeater {
          model: 3
          Rectangle {
            required property int index
            readonly property real wave: root.vizLive
              ? Model.band(root.levels, index / 3, (index + 1) / 3)
              : (root.motion ? Math.abs(Math.sin((eq.phase + index * 0.37) * Math.PI * (2 + index * 0.6))) : 0.55)
            x: index * (eq.width / 3)
            width: Math.max(2, Math.round(eq.width / 3) - 1)
            radius: width / 2
            height: root.playing ? eq.height * (0.3 + 0.7 * wave) : eq.height * 0.28
            anchors.bottom: parent.bottom
            // Each bar runs from one accent at the base to the other at the tip.
            gradient: Gradient {
              GradientStop { position: 0.0; color: root.running ? root.animatedAccent2 : root.barFg }
              GradientStop { position: 1.0; color: root.running ? root.animatedAccent : root.barFg }
            }
            opacity: root.playing ? 1 : 0.5
            Behavior on height { enabled: !root.playing; NumberAnimation { duration: Style.duration(200) } }
          }
        }
      }

      PulseMarquee {
        id: barLabel
        width: Math.min(implicitWidth, root.maxWidth)
        anchors.verticalCenter: parent.verticalCenter
        text: pill.displayText
        color: root.barFg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.italic: root.showingLyric
        active: root.marquee && root.playing && !root.popupOpen
      }

      // Sleep timer set.
      Text {
        visible: !!root.svc && root.svc.sleepActive
        anchors.verticalCenter: parent.verticalCenter
        text: "󰒲"
        color: Util.alpha(root.barFg, 0.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    SequentialAnimation {
      id: swapAnim
      readonly property Item label: barLabel.content
      ParallelAnimation {
        NumberAnimation { target: swapAnim.label; property: "y"; to: -swapAnim.label.height * 0.8; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { target: swapAnim.label; property: "opacity"; to: 0; duration: 150 }
      }
      ScriptAction { script: { pill.displayText = root.pillText; swapAnim.label.y = swapAnim.label.height * 0.8 } }
      ParallelAnimation {
        NumberAnimation { target: swapAnim.label; property: "y"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { target: swapAnim.label; property: "opacity"; to: 1; duration: 220 }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      onClicked: function(m) {
        if (m.button === Qt.MiddleButton) root.playPause()
        else if (m.button === Qt.RightButton) root.next()
        else root.toggle()
      }
      onWheel: function(w) {
        if (!root.running) return
        var up = w.angleDelta.y > 0
        if (root.scrollAction === "volume") root.nudgeVolume(up ? 0.05 : -0.05)
        else if (root.scrollAction === "track") { if (up) root.previous(); else root.next() }
      }
      onEntered: if (root.bar && !root.popupOpen) root.bar.showTooltip(root, root.running
        ? root.title + (root.artist ? "\n" + root.artist : "") + (root.album ? " · " + root.album : "")
        : "Open Spotify")
      onExited: if (root.bar) root.bar.hideTooltip(root)
      onPressed: if (root.bar) root.bar.hideTooltip(root)
    }
  }

  // ================================================================ CARD
  //
  // Cover-first: the album cover is the hero, glowing in its own colors over
  // a blurred copy of itself that fills the card. Lyrics flip in on the back
  // of the cover.

  KeyboardPanel {
    id: card
    anchorItem: pill
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keys
    contentWidth: card.fittedContentWidth(Style.space(340))
    contentHeight: card.fittedContentHeight(content.implicitHeight)

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
      Keys.onSpacePressed: root.playPause()
      Keys.onLeftPressed: root.seekTo(root.position - 5)
      Keys.onRightPressed: root.seekTo(root.position + 5)
      Keys.onUpPressed: root.nudgeVolume(0.05)
      Keys.onDownPressed: root.nudgeVolume(-0.05)
      Keys.onPressed: function(e) {
        if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) root.seekTo(root.duration * (e.key - Qt.Key_0) / 10)
        else if (e.key === Qt.Key_N) root.next()
        else if (e.key === Qt.Key_P) root.previous()
        else if (e.key === Qt.Key_S) root.toggleShuffle()
        else if (e.key === Qt.Key_R) root.cycleRepeat()
        else if (e.key === Qt.Key_L) root.toggleLyrics()
        else if (e.key === Qt.Key_Z) { if (root.svc) root.svc.cycleSleep() }
        else if (e.key === Qt.Key_BracketLeft && root.lyricsOn) { if (root.svc) root.svc.nudgeLyrics(0.5) }
        else if (e.key === Qt.Key_BracketRight && root.lyricsOn) { if (root.svc) root.svc.nudgeLyrics(-0.5) }
        else return
        e.accepted = true
      }
    }

    // ---- Backdrop: the blurred cover tints the whole card ---------------
    Item {
      id: backdrop
      anchors.fill: parent
      anchors.margins: -card.padding
      visible: root.blurBackdrop && backdropSrc.status === Image.Ready
      // The popup doesn't clip, and the blur reaches well past its source.
      clip: true
      layer.enabled: Style.cornerRadius > 0
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: backdropMask
      }

      Image {
        id: backdropSrc
        anchors.fill: parent
        source: root.popupOpen && root.blurBackdrop ? root.artUrl : ""
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
      }
      MultiEffect {
        anchors.fill: parent
        anchors.margins: -Style.space(40)
        source: backdropSrc
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 0.25
        opacity: 0.9
        // Slow drift keeps the color field alive without a timer.
        NumberAnimation on scale {
          running: root.popupOpen && root.playing && root.motion
          from: 1.0; to: 1.2
          duration: 12000
          loops: Animation.Infinite
          easing.type: Easing.SineCurve
        }
      }
      // Scrim so text stays readable on any cover.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(Commons.Color.background, root.darkTheme ? 0.45 : 0.35) }
          GradientStop { position: 0.55; color: Util.alpha(Commons.Color.background, root.darkTheme ? 0.72 : 0.6) }
          GradientStop { position: 1.0; color: Util.alpha(Commons.Color.background, root.darkTheme ? 0.88 : 0.8) }
        }
      }
    }
    Item {
      id: backdropMask
      anchors.fill: backdrop
      layer.enabled: true
      visible: false
      Rectangle { anchors.fill: parent; radius: Style.cornerRadius }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.space(14)

      // ---- Stage: cover on the front, lyrics on the back ------------------
      Flipable {
        id: stage
        width: parent.width
        height: Math.round(width * 0.9)
        readonly property bool flipped: root.lyricsOn
        // Keep the lyrics populated until the back has turned away.
        readonly property bool lyricsLive: flipped || flipRot.angle > 90

        transform: Rotation {
          id: flipRot
          origin.x: stage.width / 2
          origin.y: stage.height / 2
          axis { x: 0; y: 1; z: 0 }
          angle: stage.flipped ? 180 : 0
          Behavior on angle { NumberAnimation { duration: Style.duration(620); easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        }

        front: PulseCover {
          anchors.fill: parent
          source: root.popupOpen ? root.artUrl : ""
          playing: root.playing
          live: root.popupOpen && !stage.flipped
          vinyl: root.vinyl
          accent: root.animatedAccent
          accent2: root.animatedAccent2
          fg: root.panelFg
          hole: Commons.Color.background
          fontFamily: root.fontFamily
          energy: root.popupOpen ? root.bass : 0
          onDoubleClicked: { if (root.svc) root.svc.lyricsOn = true }
        }

        back: PulseLyrics {
          anchors.fill: parent
          lines: root.svc ? root.svc.lyricLines : []
          synced: root.svc ? root.svc.lyricsSynced : true
          live: stage.lyricsLive
          index: root.svc ? root.svc.lyricIdx : -1
          position: root.svc ? root.svc.lyricsPosition : 0
          status: root.svc ? root.svc.lyricsStatus : ""
          offset: root.svc ? root.svc.lyricsOffset : 0
          karaoke: root.karaoke
          showLoading: root.popupOpen
          fg: root.panelFg
          accent: root.animatedAccent
          accent2: root.animatedAccent2
          fontFamily: root.fontFamily
          onSeek: function(t) { root.seekTo(t - (root.svc ? root.svc.lyricsOffset : 0)) }
        }
      }

      // ---- Title / artist ----------------------------------------------
      Item {
        id: info
        width: parent.width
        height: infoCol.implicitHeight
        // The Column owns `y`, so the intro slides this offset instead.
        transform: Translate { id: infoShift }

        Column {
          id: infoCol
          width: parent.width - miniEq.width - Style.space(12)
          spacing: Style.space(3)

          PulseMarquee {
            id: tTitle
            width: parent.width
            text: root.title || "Nothing playing"
            color: root.panelFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title + Style.space(4)
            font.bold: true
            active: root.popupOpen
          }
          Text {
            id: tArtist
            width: parent.width
            text: root.artist + (root.album && root.album !== root.title ? "  ·  " + root.album : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Util.alpha(root.panelFg, 0.62)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        // Little equalizer where a like button would go.
        Item {
          id: miniEq
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18)
          height: Style.space(16)
          property real phase: 0
          NumberAnimation on phase {
            from: 0; to: 1
            duration: 1100
            loops: Animation.Infinite
            running: root.playing && root.popupOpen && !root.vizLive && root.motion
          }
          Repeater {
            model: 4
            Rectangle {
              required property int index
              readonly property real wave: root.vizLive
                ? Model.band(root.levels, index / 4, (index + 1) / 4)
                : (root.motion ? Math.abs(Math.sin((miniEq.phase + index * 0.29) * Math.PI * (2 + index * 0.5))) : 0.55)
              x: index * (miniEq.width / 4)
              width: Math.max(2, Math.round(miniEq.width / 4) - 2)
              radius: width / 2
              anchors.bottom: parent.bottom
              height: root.playing ? miniEq.height * (0.25 + 0.75 * wave) : miniEq.height * 0.2
              gradient: Gradient {
                GradientStop { position: 0.0; color: root.animatedAccent2 }
                GradientStop { position: 1.0; color: root.animatedAccent }
              }
              Behavior on height { enabled: !root.playing; NumberAnimation { duration: Style.duration(220) } }
            }
          }
        }
      }

      // ---- Seek -----------------------------------------------------------
      Column {
        id: seek
        width: parent.width
        spacing: Style.space(2)
        opacity: root.duration > 0 ? 1 : 0.4

        PulseSlider {
          width: parent.width
          value: root.position
          maximum: Math.max(1, root.duration)
          fill: root.animatedAccent
          fill2: root.animatedAccent2
          track: Util.alpha(root.panelFg, 0.15)
          enabled: root.running && root.player.canSeek && root.duration > 0
          onReleased: function(v) { root.seekTo(v) }
        }
        Item {
          width: parent.width
          height: elapsed.implicitHeight
          Text {
            id: elapsed
            text: Model.timestamp(root.position)
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            text: "-" + Model.timestamp(root.duration - root.position)
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
        }
      }

      // ---- Transport ------------------------------------------------------
      Item {
        id: transport
        width: parent.width
        height: playBtn.height

        PulseIconButton {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          icon: "󰒝"
          size: Style.font.icon + Style.space(2)
          color: root.panelFg
          accent: root.animatedAccent
          fontFamily: root.fontFamily
          active: root.running && root.player.shuffle
          enabled: root.running && root.player.shuffleSupported
          onClicked: root.toggleShuffle()
        }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(18)

          PulseIconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "󰒮"
            size: Style.font.iconLarge + Style.space(4)
            color: root.panelFg
            accent: root.animatedAccent
            fontFamily: root.fontFamily
            enabled: root.running && (root.player.canGoPrevious || root.player.canSeek)
            onClicked: root.previous()
          }

          // Play: two-tone disc that squishes on press and morphs its glyph.
          Rectangle {
            id: playBtn
            width: Style.space(58)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            gradient: Gradient {
              GradientStop { position: 0.0; color: root.animatedAccent }
              GradientStop { position: 1.0; color: root.animatedAccent2 }
            }
            scale: playMouse.pressed ? 0.86 : (playMouse.containsMouse ? 1.07 : 1)
            Behavior on scale { NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutBack; easing.overshoot: 3 } }

            // Pulse ring while playing.
            Rectangle {
              id: pulseRing
              z: -1
              anchors.centerIn: parent
              width: parent.width
              height: width
              radius: width / 2
              color: "transparent"
              border.width: Style.space(2)
              border.color: root.animatedAccent2
              opacity: 0
              SequentialAnimation {
                running: root.playing && root.popupOpen && root.motion
                loops: Animation.Infinite
                onRunningChanged: if (!running) { pulseRing.opacity = 0; pulseRing.scale = 1 }
                ParallelAnimation {
                  NumberAnimation { target: pulseRing; property: "scale"; from: 1; to: 1.45; duration: 1600; easing.type: Easing.OutCubic }
                  NumberAnimation { target: pulseRing; property: "opacity"; from: 0.5; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                }
              }
            }

            Text {
              id: playGlyph
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: root.playing ? 0 : Style.space(2)
              text: root.playing ? "󰏤" : "󰐊"
              color: Commons.Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge + Style.space(8)
              onTextChanged: if (root.motion) glyphMorph.restart()
            }
            SequentialAnimation {
              id: glyphMorph
              ParallelAnimation {
                NumberAnimation { target: playGlyph; property: "scale"; from: 0.3; to: 1.15; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: playGlyph; property: "rotation"; from: -90; to: 0; duration: 260; easing.type: Easing.OutBack }
              }
              NumberAnimation { target: playGlyph; property: "scale"; to: 1; duration: 140; easing.type: Easing.OutQuad }
            }

            MouseArea {
              id: playMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.playPause()
            }
          }

          PulseIconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "󰒭"
            size: Style.font.iconLarge + Style.space(4)
            color: root.panelFg
            accent: root.animatedAccent
            fontFamily: root.fontFamily
            enabled: root.running && root.player.canGoNext
            onClicked: root.next()
          }
        }

        PulseIconButton {
          readonly property int loop: root.running ? root.player.loopState : MprisLoopState.None
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          icon: loop === MprisLoopState.Track ? "󰑘" : "󰑖"
          size: Style.font.icon + Style.space(2)
          color: root.panelFg
          accent: root.animatedAccent
          fontFamily: root.fontFamily
          active: loop !== MprisLoopState.None
          enabled: root.running && root.player.loopSupported
          onClicked: root.cycleRepeat()
        }
      }

      // ---- Volume ---------------------------------------------------------
      Item {
        width: parent.width
        height: volSlider.implicitHeight
        visible: root.running && root.player.volumeSupported

        readonly property real v: root.volume
        property real restore: 0.5

        Text {
          id: volLow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: parent.v <= 0.001 ? "󰝟" : "󰕿"
          color: Util.alpha(root.panelFg, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var item = parent.parent
              if (item.v > 0.001) { item.restore = item.v; root.setVolume(0) }
              else root.setVolume(item.restore)
            }
          }
        }
        PulseSlider {
          id: volSlider
          anchors.left: volLow.right
          anchors.right: volHigh.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          value: parent.v
          maximum: 1
          live: true
          fill: Util.alpha(root.panelFg, 0.8)
          track: Util.alpha(root.panelFg, 0.15)
          onMoved: function(v) { root.setVolume(v) }
          onReleased: function(v) { root.setVolume(v) }
        }
        Text {
          id: volHigh
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "󰕾"
          color: Util.alpha(root.panelFg, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }

      // ---- Recently played ------------------------------------------------
      PulseHistory {
        id: historyStrip
        width: parent.width
        visible: root.historyOn && items.length > 0
        items: {
          var s = root.svc
          if (!s || !root.historyOn) return []
          var out = []
          for (var i = 0; i < s.history.length; i++)
            if (s.history[i].uri !== s.trackUri) out.push(s.history[i])
          return out
        }
        live: root.popupOpen
        fg: root.panelFg
        accent: root.animatedAccent
        fontFamily: root.fontFamily
        onPlay: function(uri) { if (root.svc) root.svc.playUri(uri) }
      }

      // ---- Footer ---------------------------------------------------------
      Item {
        id: footer
        width: parent.width
        height: lyricsChip.implicitHeight

        PulseChip {
          id: lyricsChip
          anchors.left: parent.left
          icon: root.lyricsOn ? "󰐻" : "󰍡"
          label: root.lyricsOn ? "Cover" : "Lyrics"
          fg: root.panelFg
          accent: root.animatedAccent
          fontFamily: root.fontFamily
          active: root.lyricsOn
          onClicked: root.toggleLyrics()
        }
        // Sleep: off → 15 → 30 → 60 min → end of track → off.
        PulseChip {
          readonly property var s: root.svc
          anchors.horizontalCenter: parent.horizontalCenter
          icon: "󰒲"
          label: !s || !s.sleepActive ? "Sleep" : (s.sleepEndOfTrack ? "After song" : s.sleepLeft + " min")
          fg: root.panelFg
          accent: root.animatedAccent
          fontFamily: root.fontFamily
          active: !!s && s.sleepActive
          onClicked: if (s) s.cycleSleep()
        }
        PulseChip {
          anchors.right: parent.right
          icon: "󰓇"
          label: "Spotify"
          fg: root.panelFg
          accent: root.spotifyGreen
          fontFamily: root.fontFamily
          onClicked: { root.launch(); root.close() }
        }
      }
    }
  }

  // ---- Motion -----------------------------------------------------------

  // Opening: the stage pops in, then the rest cascades up.
  ParallelAnimation {
    id: introAnim
    NumberAnimation { target: stage; property: "opacity"; from: 0; to: 1; duration: Style.duration(260) }
    NumberAnimation { target: stage; property: "scale"; from: 0.9; to: 1; duration: Style.duration(560); easing.type: Easing.OutBack; easing.overshoot: 1.4 }
    SequentialAnimation {
      PauseAnimation { duration: Style.duration(80) }
      ParallelAnimation {
        NumberAnimation { target: info; property: "opacity"; from: 0; to: 1; duration: Style.duration(300) }
        NumberAnimation { target: infoShift; property: "y"; from: Style.space(14); to: 0; duration: Style.duration(420); easing.type: Easing.OutCubic }
      }
    }
    SequentialAnimation {
      PauseAnimation { duration: Style.duration(150) }
      NumberAnimation { target: seek; property: "opacity"; from: 0; to: root.duration > 0 ? 1 : 0.4; duration: Style.duration(300) }
    }
    SequentialAnimation {
      PauseAnimation { duration: Style.duration(210) }
      ParallelAnimation {
        NumberAnimation { target: transport; property: "opacity"; from: 0; to: 1; duration: Style.duration(300) }
        NumberAnimation { target: transport; property: "scale"; from: 0.92; to: 1; duration: Style.duration(420); easing.type: Easing.OutBack; easing.overshoot: 2 }
      }
    }
    SequentialAnimation {
      PauseAnimation { duration: Style.duration(270) }
      ParallelAnimation {
        NumberAnimation { target: historyStrip; property: "opacity"; from: 0; to: 1; duration: Style.duration(300) }
        NumberAnimation { target: footer; property: "opacity"; from: 0; to: 1; duration: Style.duration(300) }
      }
    }
  }

  // Track change: title and artist slide in one after the other.
  SequentialAnimation {
    id: trackAnim
    ParallelAnimation {
      NumberAnimation { target: tTitle; property: "opacity"; from: 0; to: 1; duration: Style.duration(320) }
      NumberAnimation { target: tTitle; property: "x"; from: Style.space(18); to: 0; duration: Style.duration(440); easing.type: Easing.OutCubic }
      SequentialAnimation {
        PauseAnimation { duration: Style.duration(90) }
        ParallelAnimation {
          NumberAnimation { target: tArtist; property: "opacity"; from: 0; to: 1; duration: Style.duration(320) }
          NumberAnimation { target: tArtist; property: "x"; from: Style.space(18); to: 0; duration: Style.duration(440); easing.type: Easing.OutCubic }
        }
      }
    }
  }
}
