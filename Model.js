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

// Plain (unsynced) lyrics as [{ t: -1, text }], keeping single blank lines
// between verses.
function plainLines(text) {
  var out = []
  var lines = String(text || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" && (out.length === 0 || out[out.length - 1].text === "")) continue
    out.push({ t: -1, text: line })
  }
  while (out.length && out[out.length - 1].text === "") out.pop()
  return out
}

// Choose lyrics from an lrclib /get object or /search array. Synced lyrics
// only count when the recording length matches (another version's timings
// would drift); a mismatched entry can still lend its plain text.
// Returns { synced, plain, instrumental }.
function pickLyrics(data, duration) {
  var list = Array.isArray(data) ? data : (data ? [data] : [])
  var best = null, bestScore = 0, instrumental = false
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d) continue
    var close = !(duration > 0) || !(d.duration > 0) || Math.abs(d.duration - duration) <= 4
    if (d.instrumental && close) instrumental = true
    var synced = close ? String(d.syncedLyrics || "") : ""
    var plain = String(d.plainLyrics || "")
    var score = synced ? 3 : (plain ? (close ? 2 : 1) : 0)
    if (score > bestScore) { bestScore = score; best = { synced: synced, plain: plain } }
  }
  if (!best) return { synced: "", plain: "", instrumental: instrumental }
  return { synced: best.synced, plain: best.plain, instrumental: false }
}

// How long a line takes to sing, for the karaoke sweep: roughly by length,
// never past the next line.
function sweepSpan(text, gap) {
  var g = gap > 0 ? gap : 6
  return Math.min(g, Math.max(1.0, String(text || "").length * 0.065 + 0.5))
}

// Where a sweep at `fraction` sits across wrapped rows of the given widths:
// { full: rows completely sung, partial: px into the next row }.
function sweepGeometry(rowWidths, fraction) {
  var total = 0
  for (var i = 0; i < rowWidths.length; i++) total += rowWidths[i]
  var covered = clamp(fraction, 0, 1) * total
  for (var r = 0; r < rowWidths.length; r++) {
    if (covered < rowWidths[r]) return { full: r, partial: covered }
    covered -= rowWidths[r]
  }
  return { full: rowWidths.length, partial: 0 }
}

// ---------------------------------------------------------------- colors

function _score(c) {
  return c.hslSaturation * (1 - Math.abs(c.hslLightness - 0.5) * 1.2)
}

function _lift(h, s, l, darkTheme, QtRef) {
  var sat = clamp(s * 1.15, 0.45, 0.85)
  var light = darkTheme ? clamp(l, 0.62, 0.74) : clamp(l, 0.34, 0.45)
  return QtRef.hsla(h, sat, light, 1)
}

function _hueDistance(a, b) {
  var d = Math.abs(a - b) % 1
  return Math.min(d, 1 - d)
}

// Two readable accents from a quantized palette: the most characterful color,
// plus the best one with a clearly different hue (or a gentle analogous shift
// of the first when the cover is all one hue). Lifted to read well: vivid,
// mid-light on dark themes, mid-dark on light ones. Null when the palette is
// too gray to theme from.
function accentPair(colors, darkTheme, QtRef) {
  var best = null, bestScore = -1
  for (var i = 0; i < colors.length; i++) {
    var c = colors[i]
    if (c.hslLightness < 0.08 || c.hslLightness > 0.95) continue
    var score = _score(c)
    if (score > bestScore) { bestScore = score; best = c }
  }
  if (!best || best.hslSaturation < 0.12) return null
  var h = Math.max(0, best.hslHue)

  var second = null, secondScore = -1
  for (var j = 0; j < colors.length; j++) {
    var o = colors[j]
    if (o === best || o.hslSaturation < 0.18 || o.hslLightness < 0.08 || o.hslLightness > 0.95) continue
    if (_hueDistance(Math.max(0, o.hslHue), h) < 0.08) continue
    var s2 = _score(o)
    if (s2 > secondScore) { secondScore = s2; second = o }
  }

  var a = _lift(h, best.hslSaturation, best.hslLightness, darkTheme, QtRef)
  var b = second
    ? _lift(Math.max(0, second.hslHue), second.hslSaturation, second.hslLightness, darkTheme, QtRef)
    : _lift((h + 0.07) % 1, best.hslSaturation, best.hslLightness, darkTheme, QtRef)
  return { a: a, b: b }
}

function mix(a, b, t, QtRef) {
  return QtRef.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                    a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
}

// ---------------------------------------------------------------- spotify

// spotify:track:<id> from the track's open.spotify.com URL (or its MPRIS
// track id), so it can be replayed later. "" for anything else.
function spotifyUri(url, trackId) {
  var m = /open\.spotify\.com\/(track|episode)\/([A-Za-z0-9]+)/.exec(String(url || ""))
  if (m) return "spotify:" + m[1] + ":" + m[2]
  m = /\/com\/spotify\/(track|episode)\/([A-Za-z0-9]+)/.exec(String(trackId || ""))
  if (m) return "spotify:" + m[1] + ":" + m[2]
  return ""
}

// ---------------------------------------------------------------- history

function parseHistory(text) {
  try {
    var data = JSON.parse(String(text || "[]"))
    if (!Array.isArray(data)) return []
    return data.filter(function(e) { return e && typeof e.uri === "string" && e.uri !== "" })
  } catch (e) {
    return []
  }
}

// Newest first, one entry per track.
function pushHistory(list, entry, max) {
  var out = [entry]
  for (var i = 0; i < list.length && out.length < max; i++)
    if (list[i].uri !== entry.uri) out.push(list[i])
  return out
}

// ---------------------------------------------------------------- visualizer

// One cava frame ("12;340;...;") as levels in 0..1.
function parseLevels(line, range) {
  var parts = String(line || "").split(";")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "") continue
    var v = Number(parts[i])
    out.push(isFinite(v) ? clamp(v / range, 0, 1) : 0)
  }
  return out
}

// Average of levels[from..to) or 0.
function band(levels, from, to) {
  if (!levels || levels.length === 0) return 0
  var a = Math.floor(from * levels.length), b = Math.max(a + 1, Math.floor(to * levels.length))
  var sum = 0, n = 0
  for (var i = a; i < b && i < levels.length; i++) { sum += levels[i]; n++ }
  return n ? sum / n : 0
}

function encodeQuery(params) {
  var parts = []
  for (var k in params) {
    if (params[k] === undefined || params[k] === null || params[k] === "") continue
    parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(params[k]))
  }
  return parts.join("&")
}
