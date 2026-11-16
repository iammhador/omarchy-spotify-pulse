// Spotify Pulse service: the one shared brain behind every bar instance.
//
// The shell creates a single service, while a bar widget exists per monitor.
// Everything with a side effect lives here so it happens once, not once per
// screen: cover color sampling, lyrics lookups, the visualizer process, the
// play history file and the sleep timer. Widgets only render this state and
// call its functions.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: svc

  // Injected by the shell.
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- config
  // Pushed by the bar widgets, which share one settings entry.

  property bool albumColors: true
  property bool visualizer: true
  property bool historyEnabled: true
  property bool barLyrics: false
  property bool pillProgress: true
  property bool sleepFade: true

  function configure(c) {
    albumColors = c.albumColors !== false
    visualizer = c.visualizer !== false
    historyEnabled = c.history !== false
    barLyrics = c.barLyrics === true
    pillProgress = c.pillProgress !== false
    sleepFade = c.sleepFade !== false
  }

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/spotify-pulse"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/spotify-pulse"

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
  readonly property real volume: running && player.volumeSupported ? player.volume : 0
  readonly property string trackUri: {
    if (!running || !player.metadata) return ""
    var md = player.metadata
    return Model.spotifyUri(md["xesam:url"], md["mpris:trackid"])
  }

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
    if (running && player.volumeSupported) player.volume = Model.clamp(v, 0, 1)
  }
  function toggleShuffle() { if (running && player.shuffleSupported) player.shuffle = !player.shuffle }
  function cycleRepeat() {
    if (!running || !player.loopSupported) return
    if (player.loopState === MprisLoopState.None) player.loopState = MprisLoopState.Playlist
    else if (player.loopState === MprisLoopState.Playlist) player.loopState = MprisLoopState.Track
    else player.loopState = MprisLoopState.None
  }
  // Play a spotify: URI through MPRIS OpenUri (Quickshell doesn't wrap it).
  function playUri(uri) {
    if (!running || !/^spotify:(track|episode):[A-Za-z0-9]+$/.test(String(uri))) return
    Quickshell.execDetached(["busctl", "--user", "call", String(player.dbusName),
      "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "OpenUri", "s", String(uri)])
  }

  // ---------------------------------------------------------------- like
  // MPRIS can't like songs, and Spotify's Web API needs Premium plus a
  // developer app. Instead, send the Spotify app its own Like shortcut
  // (Alt+Shift+B) through Hyprland, straight to its window: no focus change,
  // works for free accounts. It toggles, and the plugin can't read whether
  // the song is liked, so the UI only confirms that Spotify got the request.

  signal likeSent(bool ok)

  function toggleLike() {
    if (!running || likeProc.running) return
    likeProc.running = true
  }

  Process {
    id: likeProc
    // Hyprland's Lua dispatcher first, then the older text syntax.
    command: ["sh", "-c",
      'r=$(hyprctl dispatch \'hl.dsp.send_shortcut({ mods = "ALT SHIFT", key = "B", window = "class:^([Ss]potify)$" })\' 2>&1)\n'
      + '[ "$r" = ok ] && exit 0\n'
      + 'r=$(hyprctl dispatch sendshortcut "ALT SHIFT, B, class:^([Ss]potify)$" 2>&1)\n'
      + '[ "$r" = ok ]']
    onExited: function(code) { svc.likeSent(code === 0) }
  }

  // ---------------------------------------------------------------- open in spotify
  // Bring the Spotify window forward (Hyprland focus, falling back to MPRIS
  // Raise). Its Now Playing panel shows this song with Spotify's own
  // "Add to playlist" button, which free accounts can use too. (Handing the
  // app the song's link doesn't navigate a running Spotify, and MPRIS
  // OpenUri would restart the song.)

  function openInSpotify() {
    if (!running) { launch(); return }
    focusProc.running = false
    focusProc.running = true
  }

  Process {
    id: focusProc
    command: ["sh", "-c",
      'r=$(hyprctl dispatch \'hl.dsp.focus({ window = "class:^([Ss]potify)$" })\' 2>&1)\n'
      + '[ "$r" = ok ] && exit 0\n'
      + 'r=$(hyprctl dispatch focuswindow "class:^([Ss]potify)$" 2>&1)\n'
      + '[ "$r" = ok ]']
    onExited: function(code) { if (code !== 0 && svc.running && svc.player.canRaise) svc.player.raise() }
  }

  // ---------------------------------------------------------------- position
  // MPRIS position is interpolated on read; nudging the signal refreshes
  // bindings. Fast while a card is open or lyrics play in the bar, slow for
  // the bar's progress line, and not at all otherwise.

  property int openCards: 0
  function cardOpened(open) {
    openCards = Math.max(0, openCards + (open ? 1 : -1))
    if (open && running) player.positionChanged()
  }

  readonly property bool barLyricsLive: barLyrics && lyricsSynced && lyricLines.length > 0
  readonly property int tickInterval: openCards > 0 || barLyricsLive ? 250
    : (pillProgress || sleepEndOfTrack ? 1000 : 0)

  Timer {
    interval: Math.max(250, svc.tickInterval)
    repeat: true
    running: svc.playing && svc.tickInterval > 0
    onTriggered: svc.player.positionChanged()
  }

  // ---------------------------------------------------------------- colors
  // ColorQuantizer only reads local files, and Spotify serves covers over
  // https, so fetch each cover once into a small cache (pruned after a week).

  readonly property bool darkTheme: Commons.Color.background.hslLightness < 0.5
  property color albumA: Commons.Color.accent
  property color albumB: Commons.Color.accent
  property bool albumOk: false
  readonly property color accent: albumColors && albumOk ? albumA : Commons.Color.accent
  readonly property color accent2: albumColors && albumOk ? albumB : Commons.Color.accent
  property string artFile: ""

  function fetchArt() {
    if (!albumColors || artUrl === "") { artFile = ""; return }
    if (artUrl.indexOf("file://") === 0) { artFile = artUrl.substring(7); return }
    var name = artUrl.split("/").pop().replace(/[^A-Za-z0-9_-]/g, "")
    if (name === "") return
    artFetch.running = false
    artFetch.target = cacheDir + "/" + name + ".jpg"
    artFetch.command = ["sh", "-c",
      'mkdir -p "$1" && find "$1" -name "*.jpg" -mtime +7 -delete; [ -s "$2" ] || curl -sfL --max-time 10 -o "$2" "$3"',
      "sh", cacheDir, artFetch.target, artUrl]
    artFetch.running = true
  }

  Process {
    id: artFetch
    property string target: ""
    onExited: function(code) { if (code === 0) svc.artFile = target }
  }

  function sampleColors() {
    var p = Model.accentPair(quantizer.colors, darkTheme, Qt)
    albumOk = p !== null
    if (p) { albumA = p.a; albumB = p.b }
  }

  ColorQuantizer {
    id: quantizer
    source: svc.artFile !== "" ? "file://" + svc.artFile : ""
    depth: 3
    rescaleSize: 64
    onColorsChanged: svc.sampleColors()
  }

  onArtUrlChanged: fetchArt()
  onAlbumColorsChanged: fetchArt()
  onDarkThemeChanged: sampleColors()

  // ---------------------------------------------------------------- lyrics
  // Opt-in: nothing is sent to lrclib.net unless lyrics are shown in a card
  // or the barLyrics setting is on.

  property bool lyricsOn: false
  property var lyricLines: []
  property bool lyricsSynced: true
  property string lyricsStatus: ""   // "", "loading", "none", "instrumental", "error"
  property string lyricsKey: ""
  property var lyricsCache: ({})
  readonly property int lyricsCacheMax: 50
  // Seconds to shift lyrics by when lrclib's timing is off; positive = sooner.
  property real lyricsOffset: 0
  readonly property real lyricsPosition: position + lyricsOffset
  readonly property int lyricIdx: lyricsSynced && lyricLines.length ? Model.lyricIndex(lyricLines, lyricsPosition) : -1
  readonly property bool lyricsWanted: lyricsOn || barLyrics

  // The current line, for the bar ("" between lines and in instrumentals).
  readonly property string currentLine: {
    if (!barLyricsLive || lyricIdx < 0) return ""
    var text = lyricLines[lyricIdx].text
    return text === "♪" ? "" : text
  }

  function nudgeLyrics(delta) {
    lyricsOffset = Model.clamp(Math.round((lyricsOffset + delta) * 10) / 10, -10, 10)
  }

  // Only the newest request may report back; anything older is stale.
  property int lyricsReq: 0
  property var lyricsXhr: null

  function loadLyrics() {
    if (!lyricsWanted || !running || title === "") return
    if (lyricsKey === trackKey) return
    cancelLyricsFetch()
    var key = trackKey
    lyricsKey = key
    var cached = lyricsCache[key]
    if (cached !== undefined) {
      lyricLines = cached.lines
      lyricsSynced = cached.synced
      lyricsStatus = cached.status
      return
    }
    lyricLines = []
    lyricsSynced = true
    lyricsStatus = "loading"
    var dur = duration
    var getUrl = "https://lrclib.net/api/get?" + Model.encodeQuery({
      track_name: title, artist_name: artist, album_name: album,
      duration: dur > 0 ? Math.round(dur) : ""
    })
    var searchUrl = "https://lrclib.net/api/search?" + Model.encodeQuery({ track_name: title, artist_name: artist })

    fetchJson(getUrl, function(status, data) {
      var first = Model.pickLyrics(data, dur)
      // Unreachable: a second request would fail too.
      if (first.synced || status === 0) { finishLyrics(key, first, status); return }
      // Exact match missing or unsynced: look wider for synced lyrics.
      fetchJson(searchUrl, function(status2, data2) {
        var second = Model.pickLyrics(data2, dur)
        if (second.synced) finishLyrics(key, second, status2)
        else if (first.plain || second.plain)
          finishLyrics(key, { synced: "", plain: first.plain || second.plain, instrumental: false }, 200)
        else
          finishLyrics(key, { synced: "", plain: "", instrumental: first.instrumental || second.instrumental },
                       status === 200 || status === 404 ? status : status2)
      })
    })
  }

  function cancelLyricsFetch() {
    lyricsReq++
    lyricsTimeout.stop()
    var xhr = lyricsXhr
    lyricsXhr = null
    if (xhr) xhr.abort()
  }

  function fetchJson(url, done) {
    var req = ++lyricsReq
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || req !== svc.lyricsReq) return
      lyricsTimeout.stop()
      svc.lyricsXhr = null
      var data = null
      if (xhr.status === 200) {
        try { data = JSON.parse(xhr.responseText) } catch (e) {}
      }
      done(xhr.status, data)
    }
    lyricsXhr = xhr
    xhr.open("GET", url)
    xhr.send()
    lyricsTimeout.restart()
  }

  function finishLyrics(key, res, status) {
    if (key !== lyricsKey) return
    if (status !== 200 && status !== 404) {
      // Not cached, so turning lyrics back on (or replaying the song) retries.
      lyricLines = []
      lyricsStatus = "error"
      lyricsKey = ""
      return
    }
    var entry
    if (res.synced) entry = { lines: Model.parseLrc(res.synced), synced: true }
    else if (res.plain) entry = { lines: Model.plainLines(res.plain), synced: false }
    else entry = { lines: [], synced: true }
    entry.status = entry.lines.length ? "" : (res.instrumental ? "instrumental" : "none")

    var cache = lyricsCache
    cache[key] = entry
    var keys = Object.keys(cache)   // insertion order, oldest first
    for (var i = 0; i < keys.length - lyricsCacheMax; i++) delete cache[keys[i]]
    lyricsCache = cache

    lyricLines = entry.lines
    lyricsSynced = entry.synced
    lyricsStatus = entry.status
  }

  // An lrclib request that hangs ends as an error instead of loading forever.
  Timer {
    id: lyricsTimeout
    interval: 8000
    onTriggered: {
      var key = svc.lyricsKey
      svc.cancelLyricsFetch()
      svc.finishLyrics(key, null, 0)
    }
  }

  onLyricsWantedChanged: loadLyrics()

  // ---------------------------------------------------------------- history
  // Recently played, newest first, kept in ~/.local/state/spotify-pulse.
  // A track counts once it has played for 10 seconds.

  property var history: []
  readonly property int historyMax: 24
  property string recordedKey: ""

  Process {
    id: stateDirMaker
    command: ["mkdir", "-p", svc.stateDir]
  }

  FileView {
    id: historyFile
    path: svc.stateDir + "/history.json"
    printErrors: false
    // Load before anything can record, so a write never replaces the file
    // with a list that hasn't been read yet.
    blockLoading: true
    onLoaded: { svc.history = Model.parseHistory(historyFile.text()); svc.historyReady = true }
    onLoadFailed: svc.historyReady = true   // no file yet
  }
  property bool historyReady: false

  Timer {
    id: historyTimer
    interval: 10000
    running: svc.historyEnabled && svc.playing && svc.trackUri !== "" && svc.recordedKey !== svc.trackKey
    onTriggered: svc.recordTrack()
  }

  function recordTrack() {
    if (!historyEnabled || !historyReady || trackUri === "" || recordedKey === trackKey) return
    recordedKey = trackKey
    history = Model.pushHistory(history, {
      uri: trackUri, title: title, artist: artist, album: album, art: artUrl
    }, historyMax)
    historyFile.setText(JSON.stringify(history))
    rollDay()
    statsSongs++
    saveStats()
  }

  function clearHistory() {
    history = []
    historyFile.setText("[]")
    statsSeconds = 0
    statsSongs = 0
    playStart = playing ? Date.now() : 0
    saveStats()
  }

  // ---------------------------------------------------------------- stats
  // Today's listening time and songs, kept with the history (and off with
  // it) in ~/.local/state/spotify-pulse/stats.json. Time is counted from
  // when playback starts and banked on pause, track change or a new day.

  property string statsDay: ""
  property real statsSeconds: 0
  property int statsSongs: 0
  property double playStart: 0
  readonly property real listenedToday: statsSeconds
    + (playing && playStart > 0 ? Math.max(0, (now - playStart) / 1000) : 0)

  FileView {
    id: statsFile
    path: svc.stateDir + "/stats.json"
    printErrors: false
    // Read today's totals before anything is banked: banking first used to
    // see no date, take it for a new day and save zeros over the file.
    blockLoading: true
    onLoadFailed: { svc.statsReady = true; svc.rollDay() }   // no file yet
    onLoaded: {
      try {
        var d = JSON.parse(statsFile.text())
        svc.statsDay = String(d.day || "")
        svc.statsSeconds = Math.max(0, Number(d.seconds) || 0)
        svc.statsSongs = Math.max(0, Math.round(Number(d.songs) || 0))
      } catch (e) {}
      svc.statsReady = true
      svc.rollDay()
    }
  }
  property bool statsReady: false

  // Bank the time played every minute too, so a shell restart or crash loses
  // at most a minute of today's total.
  Timer {
    interval: 60000
    repeat: true
    running: svc.playing && svc.historyEnabled && svc.statsReady
    onTriggered: svc.bankListening()
  }

  function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
  onHistoryEnabledChanged: playStart = playing && historyEnabled ? Date.now() : 0

  function rollDay() {
    var d = today()
    if (statsDay === d) return
    statsDay = d
    statsSeconds = 0
    statsSongs = 0
  }

  // Bank the stretch played since `playStart`, and start a new one if still
  // playing.
  function bankListening() {
    var t = Date.now()
    if (playStart > 0 && historyEnabled && statsReady) {
      rollDay()
      // A stretch over 6 h means a missed pause (suspend); don't count it.
      var secs = (t - playStart) / 1000
      if (secs > 0 && secs < 6 * 3600) statsSeconds += secs
      saveStats()
    }
    playStart = playing && historyEnabled ? t : 0
    now = t
  }

  function saveStats() {
    if (!historyEnabled || !statsReady) return
    statsFile.setText(JSON.stringify({ day: statsDay || today(), seconds: Math.round(statsSeconds), songs: statsSongs }))
  }

  // ---------------------------------------------------------------- visualizer
  // Real audio levels from cava, when it's installed. It only runs while
  // music plays; without it the widgets fall back to their own animation.

  property bool cavaFound: false
  property bool cavaBroken: false
  property var levels: []
  readonly property int cavaRange: 1000
  readonly property bool vizLive: visualizer && cavaFound && !cavaBroken && playing

  Process {
    id: cavaProbe
    command: ["sh", "-c", "command -v cava >/dev/null"]
    onExited: function(code) { svc.cavaFound = code === 0 }
  }

  Process {
    id: cava
    command: ["sh", "-c",
      'mkdir -p "$1" && cat > "$1/cava.conf" <<EOF\n'
      + '[general]\nframerate = 30\nbars = 12\nautosens = 1\n'
      + '[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\n'
      + 'ascii_max_range = ' + svc.cavaRange + '\nbar_delimiter = 59\nframe_delimiter = 10\nchannels = mono\n'
      + '[smoothing]\nnoise_reduction = 70\n'
      + 'EOF\nexec cava -p "$1/cava.conf"',
      "sh", svc.cacheDir]
    stdout: SplitParser {
      onRead: function(line) { svc.levels = Model.parseLevels(line, svc.cavaRange) }
    }
    onExited: function(code) {
      // Exiting on its own (no audio backend, bad version): stop retrying
      // until playback restarts.
      if (svc.vizLive) svc.cavaBroken = true
      svc.levels = []
    }
  }

  onVizLiveChanged: {
    cava.running = vizLive
    if (!vizLive) levels = []
  }
  onPlayingChanged: {
    bankListening()
    if (!playing) restoreVolume()   // paused (by sleep or by hand) mid-fade
    if (!playing) return
    cavaBroken = false
    if (visualizer && !cavaFound && !cavaProbe.running) cavaProbe.running = true
  }
  onVisualizerChanged: if (visualizer && !cavaFound && !cavaProbe.running) cavaProbe.running = true

  // ---------------------------------------------------------------- sleep
  // Pause after a while, or when the current track ends.

  property int sleepMinutes: 0          // 0 off, -1 end of track
  property double sleepDeadline: 0
  readonly property bool sleepEndOfTrack: sleepMinutes === -1
  readonly property bool sleepActive: sleepMinutes !== 0
  property double now: Date.now()
  readonly property int sleepLeft: sleepDeadline > 0 ? Math.max(1, Math.ceil((sleepDeadline - now) / 60000)) : 0
  property real lastRemaining: 1e9

  function setSleep(minutes) {
    restoreVolume()   // turned off or changed mid-fade: back to full volume
    sleepDeadline = 0
    lastRemaining = 1e9
    sleepMinutes = minutes < 0 ? -1 : Math.max(0, Math.round(minutes))
    if (sleepMinutes > 0) sleepDeadline = Date.now() + sleepMinutes * 60000
    now = Date.now()
  }

  function cycleSleep() {
    var steps = [0, 15, 30, 60, -1]
    var i = steps.indexOf(sleepMinutes)
    setSleep(steps[(i + 1) % steps.length])
  }

  function sleepNow() {
    // The faded volume is put back once Spotify reports the pause (see
    // onPlayingChanged), so it never blips loud before stopping.
    var fading = fadeFrom
    fadeFrom = -1
    setSleep(0)
    fadeFrom = fading
    if (playing && player.canPause) player.pause()
    else restoreVolume()
  }

  // Fade-out: ease the volume down over the last 30 s (10 s for "after this
  // song") before pausing, then restore it for next time.
  property real fadeFrom: -1           // volume before fading; -1 = not fading

  function sleepSecondsLeft() {
    if (sleepEndOfTrack) return duration > 0 ? duration - position : 1e9
    if (sleepDeadline > 0) return (sleepDeadline - Date.now()) / 1000
    return 1e9
  }

  function fadeStep() {
    if (sleepEndOfTrack) player.positionChanged()
    var span = sleepEndOfTrack ? 10 : 30
    var left = sleepSecondsLeft()
    if (left > span) { restoreVolume(); return }   // seeked back out of the fade
    if (fadeFrom < 0) fadeFrom = volume
    setVolume(fadeFrom * Model.clamp(left / span, 0, 1))
  }

  function restoreVolume() {
    if (fadeFrom < 0) return
    var v = fadeFrom
    fadeFrom = -1
    setVolume(v)
  }

  Timer {
    interval: 500
    repeat: true
    running: svc.sleepFade && svc.sleepActive && svc.playing && svc.running && svc.player.volumeSupported
    onTriggered: svc.fadeStep()
  }
  onSleepFadeChanged: if (!sleepFade) restoreVolume()

  // Check the wall clock rather than trusting one long Timer: QML timers run
  // on the animation clock and drift by seconds over a minute.
  Timer {
    interval: 1000
    repeat: true
    running: svc.sleepDeadline > 0
    onTriggered: {
      if (Date.now() < svc.sleepDeadline) return
      if (svc.playing) svc.sleepNow()
      else svc.setSleep(0)   // already paused: nothing to stop
    }
  }

  // Countdown label, only while someone can see it.
  Timer {
    interval: 1000
    repeat: true
    // Also keeps today's listening time live in an open card.
    running: svc.openCards > 0 && (svc.sleepDeadline > 0 || svc.playing)
    onTriggered: svc.now = Date.now()
  }

  // End of track: pause just before it ends.
  Timer {
    interval: 500
    repeat: true
    running: svc.sleepEndOfTrack && svc.playing
    onTriggered: {
      svc.player.positionChanged()
      if (svc.duration <= 0) return
      svc.lastRemaining = svc.duration - svc.position
      if (svc.lastRemaining <= 0.8) svc.sleepNow()
    }
  }

  // ---------------------------------------------------------------- track change

  onTrackKeyChanged: {
    // Ran out between two checks: the next track has just begun.
    if (sleepEndOfTrack && lastRemaining < 3) sleepNow()
    lastRemaining = 1e9
    lyricsOffset = 0
    if (historyTimer.running) historyTimer.restart()   // skipped early: start the 10s over
    if (playing) bankListening()
    loadLyrics()
  }

  Component.onCompleted: {
    stateDirMaker.running = true
    cavaProbe.running = true
    fetchArt()
  }
}
