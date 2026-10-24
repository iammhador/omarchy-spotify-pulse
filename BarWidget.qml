// Spotify Pulse — an animated Spotify player for the Omarchy bar.
//
// Bar:  "Song — Artist" with a live equalizer, a slide transition on track
//       change and a ping-pong marquee for long titles. Left click opens the
//       card, middle click plays/pauses, scroll changes Spotify's volume.
// Card: cover-first player tinted by the album art: glowing cover, seek,
//       shuffle / previous / play / next / repeat, Spotify volume, and
//       synced lyrics (lrclib.net) that flip in on the back of the cover.
//
// Everything is driven by Spotify's MPRIS interface, so it stays in sync with
// the desktop app, media keys and Spotify Connect. No account or API key.
//
// Nothing ticks while the card is closed; the bar only animates while music
// plays.

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

  // ---------------------------------------------------------------- player

  readonly property var player: Model.selectPlayer(Mpris.players.values)
  readonly property bool running: player !== null
  readonly property bool playing: running && player.isPlaying
  readonly property string title: running ? String(player.trackTitle || "") : ""
  readonly property string artist: running ? String(player.trackArtist || "") : ""
  readonly property string album: running ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: running ? String(player.trackArtUrl || "") : ""
  readonly property string trackKey: title + "\u0001" + artist + "\u0001" + album
  readonly property real duration: running && player.lengthSupported ? Math.max(0, player.length) : 0
  readonly property real position: running && player.positionSupported ? Model.clamp(player.position, 0, duration || 1e9) : 0
  readonly property real progress: duration > 0 ? position / duration : 0

  // ---------------------------------------------------------------- settings

  // `omarchy bar set` stores plain strings, so accept "false" / "0" too.
  function flag(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "string") return !/^(false|0|no|off)$/i.test(v.trim())
    return !!v
  }

  readonly property int maxWidth: Number(setting("maxWidth", 260)) > 0 ? Number(setting("maxWidth", 260)) : 260
  readonly property bool showArtist: flag("showArtist", true)
  readonly property bool marquee: flag("marquee", true)
  readonly property bool showWhenClosed: flag("showWhenClosed", false)
  readonly property bool albumColors: flag("albumColors", true)
  readonly property bool blurBackdrop: flag("blurBackdrop", true)
  readonly property string scrollAction: String(setting("scrollAction", "volume"))

  // ---------------------------------------------------------------- colors

  readonly property color barFg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color panelFg: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool darkTheme: Commons.Color.background.hslLightness < 0.5
  readonly property color spotifyGreen: "#1ed760"

  // Album accent, sampled once per track from a small copy of the cover.
  property color albumAccent: Commons.Color.accent
  readonly property color accent: albumColors ? albumAccent : Commons.Color.accent
  property color animatedAccent: accent
  Behavior on animatedAccent { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }

  // ColorQuantizer only reads local files, and Spotify serves covers over
  // https, so fetch each cover once into a small cache (pruned after a week).
  readonly property string artCacheDir: Quickshell.env("HOME") + "/.cache/spotify-pulse"
  property string artFile: ""

  function fetchArt() {
    if (!albumColors || artUrl === "") { artFile = ""; return }
    if (artUrl.indexOf("file://") === 0) { artFile = artUrl.substring(7); return }
    var name = artUrl.split("/").pop().replace(/[^A-Za-z0-9_-]/g, "")
    if (name === "") return
    artFetch.running = false
    artFetch.target = artCacheDir + "/" + name + ".jpg"
    artFetch.command = ["sh", "-c",
      'mkdir -p "$1" && find "$1" -name "*.jpg" -mtime +7 -delete; [ -s "$2" ] || curl -sfL --max-time 10 -o "$2" "$3"',
      "sh", artCacheDir, artFetch.target, artUrl]
    artFetch.running = true
  }

  Process {
    id: artFetch
    property string target: ""
    onExited: function(code) { if (code === 0) root.artFile = target }
  }

  onArtUrlChanged: fetchArt()
  onAlbumColorsChanged: fetchArt()
  Component.onCompleted: fetchArt()

  ColorQuantizer {
    id: quantizer
    source: root.artFile !== "" ? "file://" + root.artFile : ""
    depth: 3
    rescaleSize: 64
    onColorsChanged: {
      var c = Model.accentFrom(quantizer.colors, root.darkTheme, Qt)
      root.albumAccent = c ? c : Commons.Color.accent
    }
  }

  // ---------------------------------------------------------------- state

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property bool lyricsOn: false
  property real volumeFlash: 0

  function open() { if (running) popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { if (running) popupOpen = !popupOpen; else launch() }
  onRunningChanged: if (!running) close()

  function launch() {
    if (running && player.canRaise) player.raise()
    else Quickshell.execDetached(["spotify"])
  }
  function playPause() { if (running && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (running && player.canGoNext) player.next() }
  function previous() {
    if (!running) return
    // Like the app: restart the song unless we're at its very start.
    if (position > 4 && player.canSeek) seekTo(0)
    else if (player.canGoPrevious) player.previous()
  }
  function seekTo(seconds) {
    if (running && player.canSeek && duration > 0) player.position = Model.clamp(seconds, 0, duration - 0.5)
  }
  function setVolume(v) {
    if (!running || !player.volumeSupported) return
    player.volume = Model.clamp(v, 0, 1)
    volumeFlash = 1
    volumeFlashTimer.restart()
  }
  function toggleShuffle() { if (running && player.shuffleSupported) player.shuffle = !player.shuffle }
  function cycleRepeat() {
    if (!running || !player.loopSupported) return
    if (player.loopState === MprisLoopState.None) player.loopState = MprisLoopState.Playlist
    else if (player.loopState === MprisLoopState.Playlist) player.loopState = MprisLoopState.Track
    else player.loopState = MprisLoopState.None
  }

  // MPRIS position is interpolated on read; nudging the signal refreshes
  // bindings. Only while someone is looking at a moving playhead.
  Timer {
    interval: 250
    repeat: true
    running: root.popupOpen && root.playing
    onTriggered: root.player.positionChanged()
  }

  Timer {
    id: volumeFlashTimer
    interval: 1100
    onTriggered: root.volumeFlash = 0
  }

  // ---------------------------------------------------------------- lyrics

  property var lyricLines: []
  property string lyricsStatus: ""   // "", "loading", "none", "error"
  property string lyricsKey: ""
  property var lyricsCache: ({})
  readonly property int lyricIdx: lyricLines.length ? Model.lyricIndex(lyricLines, position) : -1

  function loadLyrics() {
    if (!lyricsOn || !running || title === "") return
    if (lyricsKey === trackKey) return
    var key = trackKey
    lyricsKey = key
    if (lyricsCache[key] !== undefined) {
      lyricLines = lyricsCache[key]
      lyricsStatus = lyricLines.length ? "" : "none"
      return
    }
    lyricLines = []
    lyricsStatus = "loading"
    var q = Model.encodeQuery({
      track_name: title, artist_name: artist, album_name: album,
      duration: duration > 0 ? Math.round(duration) : ""
    })
    fetchLyrics("https://lrclib.net/api/get?" + q, key, function() {
      // Exact match failed: fall back to a looser search.
      fetchLyrics("https://lrclib.net/api/search?" + Model.encodeQuery({ track_name: title, artist_name: artist }), key, null)
    })
  }

  function fetchLyrics(url, key, onMiss) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (key !== root.lyricsKey) return   // track changed meanwhile
      var synced = ""
      if (xhr.status === 200) {
        try {
          var data = JSON.parse(xhr.responseText)
          if (Array.isArray(data)) {
            for (var i = 0; i < data.length && !synced; i++) synced = data[i].syncedLyrics || ""
          } else {
            synced = data.syncedLyrics || ""
          }
        } catch (e) {}
      }
      if (!synced && onMiss && (xhr.status === 200 || xhr.status === 404)) { onMiss(); return }
      var lines = Model.parseLrc(synced)
      var cache = root.lyricsCache
      cache[key] = lines
      root.lyricsCache = cache
      root.lyricLines = lines
      root.lyricsStatus = lines.length ? "" : (xhr.status === 0 ? "error" : "none")
    }
    xhr.open("GET", url)
    xhr.send()
  }

  onLyricsOnChanged: loadLyrics()
  onPillTextChanged: pill.swapTrack()
  onTrackKeyChanged: {
    if (popupOpen) trackAnim.restart()
    loadLyrics()
  }

  // ---------------------------------------------------------------- ipc

  IpcHandler {
    target: "spotify-pulse"
    function toggle(): void { root.toggle() }
    function close(): void { root.close() }
    function playPause(): void { root.playPause() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function lyrics(): void { root.lyricsOn = !root.lyricsOn }
    function shuffle(): void { root.toggleShuffle() }
    function repeat(): void { root.cycleRepeat() }
    function volume(percent: int): void { root.setVolume(percent / 100) }
    function status(): string {
      return JSON.stringify({
        running: root.running, playing: root.playing, popupOpen: root.popupOpen,
        title: root.title, artist: root.artist, album: root.album,
        position: Math.round(root.position * 10) / 10, duration: root.duration,
        shuffle: root.running ? root.player.shuffle : false,
        loop: root.running ? root.player.loopState : 0,
        volume: root.running ? root.player.volume : 0,
        accent: String(root.accent), lyricsOn: root.lyricsOn, lyricsLines: root.lyricLines.length
      })
    }
  }

  // ================================================================ BAR PILL

  readonly property bool shown: running ? title !== "" : showWhenClosed
  visible: shown && !vertical
  implicitWidth: shown && !vertical ? pill.width : 0
  implicitHeight: barSize

  readonly property string pillText: running
    ? title + (showArtist && artist ? "  —  " + artist : "")
    : "Open Spotify"

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    height: Math.round(root.barSize * 0.72)
    width: pillRow.width + Style.space(18)
    radius: height / 2
    color: Util.alpha(root.animatedAccent, mouse.containsMouse || root.popupOpen ? 0.16 : 0.0)
    border.width: mouse.containsMouse || root.popupOpen ? 1 : 0
    border.color: Util.alpha(root.animatedAccent, 0.35)
    opacity: root.running ? 1 : 0.55
    Behavior on color { ColorAnimation { duration: 180 } }
    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // Shown text lags `pillText` so the swap can animate out and back in.
    property string displayText: root.pillText

    function swapTrack() {
      if (displayText === root.pillText) return
      if (!root.visible) { displayText = root.pillText; return }
      swapAnim.restart()
    }

    // Spotify volume, briefly, after a scroll.
    Rectangle {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: parent.radius * 0.6
      anchors.bottomMargin: 1
      height: Math.max(2, Style.space(2))
      radius: height / 2
      width: (parent.width - parent.radius * 1.2) * (root.running ? root.player.volume : 0)
      color: root.animatedAccent
      opacity: root.volumeFlash
      Behavior on opacity { NumberAnimation { duration: 220 } }
      Behavior on width { NumberAnimation { duration: 120 } }
    }

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      // Live equalizer: three bars on one shared timeline.
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
          running: root.playing && root.visible
        }
        Repeater {
          model: 3
          Rectangle {
            readonly property real wave: Math.abs(Math.sin((eq.phase + index * 0.37) * Math.PI * (2 + index * 0.6)))
            x: index * (eq.width / 3)
            width: Math.max(2, Math.round(eq.width / 3) - 1)
            radius: width / 2
            height: root.playing ? eq.height * (0.3 + 0.7 * wave) : eq.height * 0.28
            anchors.bottom: parent.bottom
            color: root.running ? root.animatedAccent : root.barFg
            opacity: root.playing ? 1 : 0.5
            Behavior on height { enabled: !root.playing; NumberAnimation { duration: 200 } }
          }
        }
      }

      Item {
        id: clipBox
        readonly property real fullWidth: labelMetrics.advanceWidth
        readonly property bool overflow: fullWidth > root.maxWidth
        readonly property bool scrolling: overflow && root.marquee && root.playing && !root.popupOpen
        width: Math.min(fullWidth, root.maxWidth)
        height: label.implicitHeight
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        TextMetrics {
          id: labelMetrics
          font: label.font
          text: pill.displayText
        }

        Text {
          id: label
          y: 0
          text: pill.displayText
          textFormat: Text.PlainText
          width: clipBox.scrolling ? implicitWidth : clipBox.width
          elide: clipBox.scrolling ? Text.ElideNone : Text.ElideRight
          color: root.barFg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          onTextChanged: x = 0
        }

        // Ping-pong marquee with rests at each end.
        SequentialAnimation {
          running: clipBox.scrolling
          loops: Animation.Infinite
          onRunningChanged: if (!running) label.x = 0
          PauseAnimation { duration: 1600 }
          NumberAnimation {
            target: label; property: "x"; to: -(clipBox.fullWidth - clipBox.width)
            duration: Math.max(1200, (clipBox.fullWidth - clipBox.width) * 28)
            easing.type: Easing.InOutSine
          }
          PauseAnimation { duration: 1200 }
          NumberAnimation {
            target: label; property: "x"; to: 0
            duration: Math.max(1200, (clipBox.fullWidth - clipBox.width) * 28)
            easing.type: Easing.InOutSine
          }
        }
      }
    }

    SequentialAnimation {
      id: swapAnim
      ParallelAnimation {
        NumberAnimation { target: label; property: "y"; to: -label.height * 0.8; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { target: label; property: "opacity"; to: 0; duration: 150 }
      }
      ScriptAction { script: { pill.displayText = root.pillText; label.y = label.height * 0.8 } }
      ParallelAnimation {
        NumberAnimation { target: label; property: "y"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { target: label; property: "opacity"; to: 1; duration: 220 }
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
        if (root.scrollAction === "volume") root.setVolume(root.player.volume + (up ? 0.05 : -0.05))
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
  // Cover-first: the album cover is the hero, glowing in its own color over a
  // blurred copy of itself that fills the card. Lyrics flip in on the back of
  // the cover.

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
      Keys.onUpPressed: root.setVolume(root.player.volume + 0.05)
      Keys.onDownPressed: root.setVolume(root.player.volume - 0.05)
      Keys.onPressed: function(e) {
        if (e.key === Qt.Key_N) root.next()
        else if (e.key === Qt.Key_P) root.previous()
        else if (e.key === Qt.Key_S) root.toggleShuffle()
        else if (e.key === Qt.Key_R) root.cycleRepeat()
        else if (e.key === Qt.Key_L) root.lyricsOn = !root.lyricsOn
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
          running: root.popupOpen && root.playing
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

        transform: Rotation {
          origin.x: stage.width / 2
          origin.y: stage.height / 2
          axis { x: 0; y: 1; z: 0 }
          angle: stage.flipped ? 180 : 0
          Behavior on angle { NumberAnimation { duration: 620; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        }

        front: Item {
          id: front
          anchors.fill: parent

          readonly property real coverSize: Math.min(width, height) - Style.space(16)
          readonly property real coverRadius: Math.max(Style.cornerRadius, Style.space(14))

          // Colored glow under the cover.
          Rectangle {
            id: glowSrc
            anchors.centerIn: cover
            anchors.verticalCenterOffset: Style.space(10)
            width: cover.width * 0.86
            height: cover.height * 0.86
            radius: front.coverRadius
            color: root.animatedAccent
            visible: false
          }
          MultiEffect {
            anchors.fill: glowSrc
            anchors.margins: -Style.space(30)
            source: glowSrc
            autoPaddingEnabled: true
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            opacity: root.playing ? 0.55 : 0.2
            scale: cover.scale
            Behavior on opacity { NumberAnimation { duration: 500 } }
          }

          // The cover: crossfades between two images on track change, and
          // breathes back a little while paused.
          Item {
            id: cover
            anchors.centerIn: parent
            width: front.coverSize
            height: width
            scale: root.playing ? 1 : 0.88
            Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
            layer.enabled: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: coverMask
            }

            property bool showA: true
            property string wanted: root.popupOpen ? root.artUrl : ""
            onWantedChanged: {
              var next = showA ? imgB : imgA
              if (wanted === "" || next.source.toString() === wanted) return
              next.source = wanted
            }
            function settle(img) {
              if (img.status !== Image.Ready || img.source.toString() !== wanted) return
              showA = img === imgA
            }

            Rectangle {
              anchors.fill: parent
              color: Util.alpha(root.panelFg, 0.08)
              Text {
                anchors.centerIn: parent
                text: "󰝚"
                color: Util.alpha(root.panelFg, 0.4)
                font.family: root.fontFamily
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
              Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
              onStatusChanged: cover.settle(imgA)
            }
            Image {
              id: imgB
              anchors.fill: parent
              sourceSize: Qt.size(512, 512)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              opacity: !cover.showA && status === Image.Ready ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
              onStatusChanged: cover.settle(imgB)
            }
          }
          Item {
            id: coverMask
            anchors.fill: cover
            layer.enabled: true
            visible: false
            Rectangle { anchors.fill: parent; radius: front.coverRadius }
          }

          // Double-click the cover for lyrics.
          MouseArea {
            anchors.fill: cover
            cursorShape: Qt.PointingHandCursor
            onDoubleClicked: root.lyricsOn = true
          }
        }

        back: Item {
          id: back
          anchors.fill: parent

          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.space(4)
            radius: Math.max(Style.cornerRadius, Style.space(14))
            color: Util.alpha(root.animatedAccent, 0.08)
            border.width: 1
            border.color: Util.alpha(root.animatedAccent, 0.18)
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
              id: lyricsView
              anchors.fill: parent
              interactive: false
              model: stage.flipped || root.lyricsOn ? root.lyricLines : []
              currentIndex: Math.max(0, root.lyricIdx)
              preferredHighlightBegin: height * 0.36
              preferredHighlightEnd: height * 0.36 + Style.space(30)
              highlightRangeMode: ListView.StrictlyEnforceRange
              highlightMoveDuration: 520
              highlightMoveVelocity: -1
              visible: root.lyricLines.length > 0
              spacing: Style.space(4)

              delegate: Item {
                id: line
                required property var modelData
                required property int index
                readonly property bool current: index === root.lyricIdx
                readonly property int dist: Math.abs(index - Math.max(0, root.lyricIdx))
                width: lyricsView.width
                height: lineText.implicitHeight + Style.space(8)

                Text {
                  id: lineText
                  width: parent.width
                  anchors.verticalCenter: parent.verticalCenter
                  text: line.modelData.text
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title + Style.space(3)
                  font.bold: true
                  color: line.current ? root.panelFg : Util.alpha(root.panelFg, 0.9)
                  opacity: line.current ? 1 : Math.max(0.16, 0.5 - line.dist * 0.1)
                  scale: line.current ? 1 : 0.92
                  transformOrigin: Item.Left
                  Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                  Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                }

                // Click a line to jump there.
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.seekTo(line.modelData.t)
                  onEntered: if (!line.current) lineText.opacity = 0.75
                  onExited: lineText.opacity = Qt.binding(function() { return line.current ? 1 : Math.max(0.16, 0.5 - line.dist * 0.1) })
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
                GradientStop { position: 0.16; color: "white" }
                GradientStop { position: 0.8; color: "white" }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }
          }

          // Empty / loading states.
          Column {
            anchors.centerIn: parent
            spacing: Style.space(10)
            visible: root.lyricLines.length === 0

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)
              visible: root.lyricsStatus === "loading"
              Repeater {
                model: 3
                Rectangle {
                  width: Style.space(8); height: width; radius: width / 2
                  color: root.animatedAccent
                  SequentialAnimation on scale {
                    running: root.lyricsStatus === "loading" && root.popupOpen
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
              visible: root.lyricsStatus !== "loading"
              text: "󰍡"
              color: Util.alpha(root.panelFg, 0.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.lyricsStatus === "loading" ? "Finding lyrics"
                : root.lyricsStatus === "error" ? "Couldn't reach lrclib.net"
                : "No synced lyrics for this song"
              color: Util.alpha(root.panelFg, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }

      // ---- Title / artist ----------------------------------------------
      Item {
        id: info
        width: parent.width
        height: infoCol.implicitHeight

        Column {
          id: infoCol
          width: parent.width - miniEq.width - Style.space(12)
          spacing: Style.space(3)

          Text {
            id: tTitle
            width: parent.width
            text: root.title || "Nothing playing"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.panelFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title + Style.space(4)
            font.bold: true
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

        // Little live equalizer where a like button would go.
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
            running: root.playing && root.popupOpen
          }
          Repeater {
            model: 4
            Rectangle {
              readonly property real wave: Math.abs(Math.sin((miniEq.phase + index * 0.29) * Math.PI * (2 + index * 0.5)))
              x: index * (miniEq.width / 4)
              width: Math.max(2, Math.round(miniEq.width / 4) - 2)
              radius: width / 2
              anchors.bottom: parent.bottom
              height: root.playing ? miniEq.height * (0.25 + 0.75 * wave) : miniEq.height * 0.2
              color: root.animatedAccent
              Behavior on height { enabled: !root.playing; NumberAnimation { duration: 220 } }
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
          }
          Text {
            anchors.right: parent.right
            text: "-" + Model.timestamp(root.duration - root.position)
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

          // Play: accent disc that squishes on press and morphs its glyph.
          Rectangle {
            id: playBtn
            width: Style.space(58)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.animatedAccent
            scale: playMouse.pressed ? 0.86 : (playMouse.containsMouse ? 1.07 : 1)
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 3 } }

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
              border.color: root.animatedAccent
              opacity: 0
              SequentialAnimation {
                running: root.playing && root.popupOpen
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
              onTextChanged: glyphMorph.restart()
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

        readonly property real v: root.running ? root.player.volume : 0
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

      // ---- Footer ---------------------------------------------------------
      Item {
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
          onClicked: root.lyricsOn = !root.lyricsOn
        }
        PulseChip {
          anchors.right: parent.right
          icon: "󰓇"
          label: "Open Spotify"
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
    NumberAnimation { target: stage; property: "opacity"; from: 0; to: 1; duration: 260 }
    NumberAnimation { target: stage; property: "scale"; from: 0.9; to: 1; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
    SequentialAnimation {
      PauseAnimation { duration: 80 }
      ParallelAnimation {
        NumberAnimation { target: info; property: "opacity"; from: 0; to: 1; duration: 300 }
        NumberAnimation { target: info; property: "y"; from: info.y + Style.space(14); to: info.y; duration: 420; easing.type: Easing.OutCubic }
      }
    }
    SequentialAnimation {
      PauseAnimation { duration: 150 }
      NumberAnimation { target: seek; property: "opacity"; from: 0; to: root.duration > 0 ? 1 : 0.4; duration: 300 }
    }
    SequentialAnimation {
      PauseAnimation { duration: 210 }
      ParallelAnimation {
        NumberAnimation { target: transport; property: "opacity"; from: 0; to: 1; duration: 300 }
        NumberAnimation { target: transport; property: "scale"; from: 0.92; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2 }
      }
    }
  }

  // Track change: title and artist slide in one after the other.
  SequentialAnimation {
    id: trackAnim
    ParallelAnimation {
      NumberAnimation { target: tTitle; property: "opacity"; from: 0; to: 1; duration: 320 }
      NumberAnimation { target: tTitle; property: "x"; from: Style.space(18); to: 0; duration: 440; easing.type: Easing.OutCubic }
      SequentialAnimation {
        PauseAnimation { duration: 90 }
        ParallelAnimation {
          NumberAnimation { target: tArtist; property: "opacity"; from: 0; to: 1; duration: 320 }
          NumberAnimation { target: tArtist; property: "x"; from: Style.space(18); to: 0; duration: 440; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  onPopupOpenChanged: if (popupOpen) { introAnim.restart(); if (running) player.positionChanged() }
}
