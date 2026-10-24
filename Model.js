.pragma library

// Player selection adapted from LainsMain's Spotify Mini (MIT):
// match the desktop app, not web browsers or KDE Connect's remote-player proxy.
function isSpotify(player) {
  return !!player && /^org\.mpris\.MediaPlayer2\.spotify(?:[._-]|$)/i.test(String(player.dbusName || ""))
}

function selectPlayer(players) {
  var paused = null
  for (var i = 0; i < players.length; i++) {
    var player = players[i]
    if (!isSpotify(player)) continue
    if (player.isPlaying) return player
    if (!paused) paused = player
  }
  return paused
}

function timestamp(seconds) {
  var value = Number(seconds)
  var total = isFinite(value) ? Math.max(0, Math.floor(value)) : 0
  return Math.floor(total / 60) + ":" + (total % 60 < 10 ? "0" : "") + total % 60
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// Parse LRC text ("[01:02.34] line") into [{ t: seconds, text }], sorted.
// Lines with several timestamps are expanded; empty lines become "♪".
function parseLrc(lrc) {
  var out = []
  var lines = String(lrc || "").split(/\r?\n/)
  var stamp = /\[(\d+):(\d+(?:\.\d+)?)\]/g
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var times = []
    var m
    stamp.lastIndex = 0
    while ((m = stamp.exec(line)) !== null) times.push(parseInt(m[1], 10) * 60 + parseFloat(m[2]))
    if (times.length === 0) continue
    var text = line.replace(/\[[^\]]*\]/g, "").trim()
    for (var j = 0; j < times.length; j++) out.push({ t: times[j], text: text || "♪" })
  }
  out.sort(function(a, b) { return a.t - b.t })
  return out
}

// Index of the lyric line playing at `position` (binary search), or -1.
function lyricIndex(lines, position) {
  var lo = 0, hi = lines.length - 1, found = -1
  while (lo <= hi) {
    var mid = (lo + hi) >> 1
    if (lines[mid].t <= position + 0.15) { found = mid; lo = mid + 1 }
    else hi = mid - 1
  }
  return found
}

// Pick the most characterful color from a quantized palette and lift it to a
// readable accent: vivid, mid-light on dark themes, mid-dark on light ones.
// Returns null when nothing in the palette is colorful enough.
function accentFrom(colors, darkTheme, QtRef) {
  var best = null, bestScore = -1
  for (var i = 0; i < colors.length; i++) {
    var c = colors[i]
    var s = c.hslSaturation, l = c.hslLightness
    if (l < 0.08 || l > 0.95) continue
    var score = s * (1 - Math.abs(l - 0.5) * 1.2)
    if (score > bestScore) { bestScore = score; best = c }
  }
  if (!best || best.hslSaturation < 0.12) return null
  var h = Math.max(0, best.hslHue)
  var sat = clamp(best.hslSaturation * 1.15, 0.45, 0.85)
  var light = darkTheme ? clamp(best.hslLightness, 0.62, 0.74) : clamp(best.hslLightness, 0.34, 0.45)
  return QtRef.hsla(h, sat, light, 1)
}

function encodeQuery(params) {
  var parts = []
  for (var k in params) {
    if (params[k] === undefined || params[k] === null || params[k] === "") continue
    parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(params[k]))
  }
  return parts.join("&")
}
