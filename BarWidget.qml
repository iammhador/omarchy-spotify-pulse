// Spotify Pulse — an animated Spotify player for the Omarchy bar.
//
// Bar:  "Song — Artist" with a live equalizer, a slide transition on track
//       change and a ping-pong marquee for long titles. Left click opens the
//       card, middle click plays/pauses, scroll changes Spotify's volume.
// Card: album art over a blurred backdrop, a progress ring, seek bar,
//       shuffle / previous / play / next / repeat, Spotify volume and
//       synced lyrics from lrclib.net. Colors follow the album art.
//
// Everything is driven by Spotify's MPRIS interface, so it stays in sync with
// the desktop app, media keys and Spotify Connect. No account or API key.
//
// Nothing ticks while the card is closed; the bar only animates while music
// plays.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
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

  readonly property int maxWidth: Number(setting("maxWidth", 260))
  readonly property bool showArtist: setting("showArtist", true) !== false
  readonly property bool marquee: setting("marquee", true) !== false
  readonly property bool showWhenClosed: setting("showWhenClosed", false) === true
  readonly property bool albumColors: setting("albumColors", true) !== false
  readonly property bool blurBackdrop: setting("blurBackdrop", true) !== false
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
    if (popupOpen) heroSwap.restart()
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
        accent: String(root.accent), lyricsLines: root.lyricLines.length
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

  KeyboardPanel {
    id: card
    anchorItem: pill
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keys
    contentWidth: card.fittedContentWidth(Style.space(400))
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

    Column {
      id: content
      width: parent.width
      spacing: Style.space(14)

      // ---- Header -----------------------------------------------------
      Item {
        width: parent.width
        implicitHeight: Math.max(headIcon.implicitHeight, headLabels.implicitHeight)

        Text {
          id: headIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰓇"
          color: root.spotifyGreen
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }
        Column {
          id: headLabels
          anchors.left: headIcon.right
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            text: "Spotify"
            color: root.panelFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Row {
            spacing: Style.space(6)
            Rectangle {
              width: Style.space(6); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.playing ? root.animatedAccent : Util.alpha(root.panelFg, 0.4)
              SequentialAnimation on opacity {
                running: root.playing && root.popupOpen
                loops: Animation.Infinite
                onRunningChanged: if (!running) parent.opacity = 1
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
              }
            }
            Text {
              text: root.playing ? "NOW PLAYING" : "PAUSED"
              color: Util.alpha(root.panelFg, 0.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.running && root.player.shuffle
          text: "󰒝  shuffle"
          color: Util.alpha(root.animatedAccent, 0.9)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // ---- Hero: art + track over a blurred cover -----------------------
      Item {
        id: hero
        width: parent.width
        height: Style.space(124)

        Rectangle {
          id: heroBg
          anchors.fill: parent
          radius: Math.max(Style.cornerRadius, Style.space(10))
          color: Util.alpha(root.animatedAccent, 0.10)
          border.width: 1
          border.color: Util.alpha(root.animatedAccent, 0.22)
          clip: true

          Image {
            id: backdropSrc
            anchors.fill: parent
            source: root.popupOpen && root.blurBackdrop ? root.artUrl : ""
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
          }
          MultiEffect {
            anchors.fill: parent
            anchors.margins: -Style.space(20)
            source: backdropSrc
            visible: backdropSrc.status === Image.Ready
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            saturation: 0.15
            brightness: root.darkTheme ? -0.42 : 0.35
            opacity: 0.85
            // Slow drift keeps the backdrop alive without a timer.
            NumberAnimation on scale {
              running: root.popupOpen && root.playing
              from: 1.0; to: 1.15
              duration: 9000
              loops: Animation.Infinite
              easing.type: Easing.SineCurve
            }
          }
        }

        Row {
          id: heroRow
          anchors.fill: parent
          anchors.margins: Style.space(14)
          spacing: Style.space(16)

          // Cover with a progress ring.
          Item {
            id: artBox
            width: hero.height - Style.space(28)
            height: width
            anchors.verticalCenter: parent.verticalCenter

            Shape {
              anchors.fill: parent
              anchors.margins: -Style.space(5)
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                strokeColor: Util.alpha(root.panelFg, 0.10)
                strokeWidth: Math.max(2, Style.space(3))
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                  centerX: artBox.width / 2 + Style.space(5); centerY: centerX
                  radiusX: artBox.width / 2 + Style.space(3); radiusY: radiusX
                  startAngle: -90; sweepAngle: 360
                }
              }
              ShapePath {
                strokeColor: root.animatedAccent
                strokeWidth: Math.max(2, Style.space(3))
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                  centerX: artBox.width / 2 + Style.space(5); centerY: centerX
                  radiusX: artBox.width / 2 + Style.space(3); radiusY: radiusX
                  startAngle: -90
                  sweepAngle: 360 * root.progress
                  Behavior on sweepAngle { NumberAnimation { duration: 250 } }
                }
              }
            }

            Rectangle {
              id: art
              anchors.fill: parent
              anchors.margins: Style.space(2)
              radius: width / 2
              color: Util.alpha(root.panelFg, 0.08)
              clip: true
              layer.enabled: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: artMask
              }

              Image {
                id: cover
                anchors.fill: parent
                source: root.popupOpen ? root.artUrl : ""
                sourceSize: Qt.size(256, 256)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
              }
              Text {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                text: "󰝚"
                color: Util.alpha(root.panelFg, 0.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              // Vinyl-style slow spin while playing.
              RotationAnimation on rotation {
                running: root.popupOpen && root.playing
                from: art.rotation; to: art.rotation + 360
                duration: 24000
                loops: Animation.Infinite
              }
            }
            Item {
              id: artMask
              anchors.fill: art
              layer.enabled: true
              visible: false
              Rectangle { anchors.fill: parent; radius: width / 2 }
            }
            // Spindle hole, for the record look.
            Rectangle {
              anchors.centerIn: parent
              width: Style.space(10); height: width; radius: width / 2
              color: Commons.Color.background
              border.width: 1
              border.color: Util.alpha(root.animatedAccent, 0.6)
            }
          }

          Column {
            id: trackInfo
            width: heroRow.width - artBox.width - heroRow.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              id: tTitle
              width: parent.width
              text: root.title || "Nothing playing"
              textFormat: Text.PlainText
              maximumLineCount: 2
              wrapMode: Text.Wrap
              elide: Text.ElideRight
              color: root.panelFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle + Style.space(2)
              font.bold: true
            }
            Text {
              id: tArtist
              width: parent.width
              text: root.artist
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.animatedAccent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: tAlbum
              width: parent.width
              text: root.album
              visible: text !== ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Util.alpha(root.panelFg, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Track change: cover pops, text cascades in.
        SequentialAnimation {
          id: heroSwap
          ParallelAnimation {
            NumberAnimation { target: artBox; property: "scale"; from: 0.86; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2 }
            NumberAnimation { target: tTitle; property: "opacity"; from: 0; to: 1; duration: 260 }
            NumberAnimation { target: tTitle; property: "x"; from: Style.space(14); to: 0; duration: 360; easing.type: Easing.OutCubic }
            SequentialAnimation {
              PauseAnimation { duration: 70 }
              ParallelAnimation {
                NumberAnimation { target: tArtist; property: "opacity"; from: 0; to: 1; duration: 260 }
                NumberAnimation { target: tArtist; property: "x"; from: Style.space(14); to: 0; duration: 360; easing.type: Easing.OutCubic }
              }
            }
            SequentialAnimation {
              PauseAnimation { duration: 140 }
              ParallelAnimation {
                NumberAnimation { target: tAlbum; property: "opacity"; from: 0; to: 1; duration: 260 }
                NumberAnimation { target: tAlbum; property: "x"; from: Style.space(14); to: 0; duration: 360; easing.type: Easing.OutCubic }
              }
            }
          }
        }
      }

      // ---- Seek ---------------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: root.duration > 0
        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: Math.max(1, root.duration)
          value: root.position
          step: 5
          enabled: root.running && root.player.canSeek
          fillColor: root.animatedAccent
          knobColor: root.animatedAccent
          onReleased: function(v) { root.seekTo(v) }
        }
        Item {
          width: parent.width
          height: elapsed.implicitHeight
          Text {
            id: elapsed
            text: Model.timestamp(root.position)
            color: Util.alpha(root.panelFg, 0.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.right: parent.right
            text: "-" + Model.timestamp(root.duration - root.position)
            color: Util.alpha(root.panelFg, 0.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---- Transport ----------------------------------------------------
      Item {
        width: parent.width
        implicitHeight: playBtn.height

        Row {
          anchors.centerIn: parent
          spacing: Style.space(14)

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒝"
            tooltipText: "Shuffle · S"
            foreground: root.running && root.player.shuffle ? root.animatedAccent : root.panelFg
            accent: root.animatedAccent
            selected: root.running && root.player.shuffle
            enabled: root.running && root.player.shuffleSupported
            opacity: enabled ? 1 : 0.35
            onClicked: root.toggleShuffle()
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒮"
            tooltipText: "Previous · P"
            foreground: root.panelFg
            accent: root.animatedAccent
            iconSize: Style.font.iconLarge
            enabled: root.running && (root.player.canGoPrevious || root.player.canSeek)
            opacity: enabled ? 1 : 0.35
            onClicked: root.previous()
          }

          // Big play button: accent disc that squishes on press.
          Rectangle {
            id: playBtn
            width: Style.space(54)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.animatedAccent
            scale: playMouse.pressed ? 0.88 : (playMouse.containsMouse ? 1.06 : 1)
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 } }

            // Soft glow ring.
            Rectangle {
              z: -1
              anchors.centerIn: parent
              width: parent.width + Style.space(12)
              height: width
              radius: width / 2
              color: "transparent"
              border.width: Style.space(6)
              border.color: Util.alpha(root.animatedAccent, root.playing ? 0.22 : 0.10)
              Behavior on border.color { ColorAnimation { duration: 300 } }
            }

            Text {
              id: playGlyph
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: root.playing ? 0 : Style.space(2)
              text: root.playing ? "󰏤" : "󰐊"
              color: Commons.Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge + Style.space(6)
              onTextChanged: glyphMorph.restart()
            }
            SequentialAnimation {
              id: glyphMorph
              NumberAnimation { target: playGlyph; property: "scale"; from: 0.4; to: 1.12; duration: 160; easing.type: Easing.OutQuad }
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

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒭"
            tooltipText: "Next · N"
            foreground: root.panelFg
            accent: root.animatedAccent
            iconSize: Style.font.iconLarge
            enabled: root.running && root.player.canGoNext
            opacity: enabled ? 1 : 0.35
            onClicked: root.next()
          }
          Button {
            readonly property int loop: root.running ? root.player.loopState : MprisLoopState.None
            anchors.verticalCenter: parent.verticalCenter
            iconText: loop === MprisLoopState.Track ? "󰑘" : "󰑖"
            tooltipText: loop === MprisLoopState.Track ? "Repeat one · R" : (loop === MprisLoopState.Playlist ? "Repeat all · R" : "Repeat off · R")
            foreground: loop !== MprisLoopState.None ? root.animatedAccent : root.panelFg
            accent: root.animatedAccent
            selected: loop !== MprisLoopState.None
            enabled: root.running && root.player.loopSupported
            opacity: enabled ? 1 : 0.35
            onClicked: root.cycleRepeat()
          }
        }
      }

      // ---- Volume -------------------------------------------------------
      Row {
        width: parent.width
        spacing: Style.space(10)
        visible: root.running && root.player.volumeSupported

        Text {
          id: volIcon
          anchors.verticalCenter: parent.verticalCenter
          readonly property real v: root.running ? root.player.volume : 0
          text: v <= 0.001 ? "󰝟" : (v < 0.34 ? "󰕿" : (v < 0.67 ? "󰖀" : "󰕾"))
          color: Util.alpha(root.panelFg, 0.75)
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            property real restore: 0.5
            onClicked: {
              if (volIcon.v > 0.001) { restore = volIcon.v; root.setVolume(0) }
              else root.setVolume(restore)
            }
          }
        }
        PanelSlider {
          width: parent.width - volIcon.width - volPct.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.running ? root.player.volume : 0
          fillColor: root.animatedAccent
          knobColor: root.animatedAccent
          onMoved: function(v) { root.setVolume(v) }
          onReleased: function(v) { root.setVolume(v) }
        }
        Text {
          id: volPct
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
          text: Math.round((root.running ? root.player.volume : 0) * 100) + "%"
          color: Util.alpha(root.panelFg, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // ---- Lyrics -------------------------------------------------------
      Item {
        id: lyricsBox
        width: parent.width
        height: root.lyricsOn ? Style.space(96) : 0
        clip: true
        visible: height > 0
        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        Rectangle {
          anchors.fill: parent
          radius: Math.max(Style.cornerRadius, Style.space(8))
          color: Util.alpha(root.animatedAccent, 0.07)
          border.width: 1
          border.color: Util.alpha(root.animatedAccent, 0.15)
        }

        ListView {
          id: lyricsView
          anchors.fill: parent
          anchors.margins: Style.space(8)
          clip: true
          interactive: false
          model: root.lyricLines
          currentIndex: Math.max(0, root.lyricIdx)
          preferredHighlightBegin: height / 2 - Style.space(12)
          preferredHighlightEnd: height / 2 + Style.space(12)
          highlightRangeMode: ListView.StrictlyEnforceRange
          highlightMoveDuration: 420
          visible: root.lyricLines.length > 0
          delegate: Text {
            required property var modelData
            required property int index
            readonly property bool current: index === root.lyricIdx
            width: lyricsView.width
            horizontalAlignment: Text.AlignHCenter
            text: modelData.text
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: current ? root.animatedAccent : Util.alpha(root.panelFg, 0.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: current
            scale: current ? 1.06 : 1
            height: Style.space(24)
            verticalAlignment: Text.AlignVCenter
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 260 } }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.lyricLines.length === 0
          text: root.lyricsStatus === "loading" ? "Finding lyrics…"
            : root.lyricsStatus === "error" ? "Couldn't reach lrclib.net"
            : "No synced lyrics for this song"
          color: Util.alpha(root.panelFg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSeparator { foreground: root.panelFg }

      // ---- Footer -------------------------------------------------------
      Item {
        width: parent.width
        implicitHeight: lyricsBtn.implicitHeight

        Button {
          id: lyricsBtn
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰍡"
          text: "Lyrics"
          tooltipText: "Synced lyrics from lrclib.net · L"
          fontSize: Style.font.bodySmall
          foreground: root.lyricsOn ? root.animatedAccent : root.panelFg
          accent: root.animatedAccent
          selected: root.lyricsOn
          focusable: true
          onClicked: root.lyricsOn = !root.lyricsOn
        }
        Button {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰓇"
          text: "Open Spotify"
          fontSize: Style.font.bodySmall
          foreground: root.panelFg
          accent: root.animatedAccent
          focusable: true
          onClicked: { root.launch(); root.close() }
        }
      }
    }
  }

  // Opening the card replays the hero entrance once.
  onPopupOpenChanged: if (popupOpen) { heroSwap.restart(); if (running) player.positionChanged() }
}
