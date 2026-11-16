// Unit tests for Model.js (pure logic, no QML). Run: node tests/model.test.js
const fs = require('fs')
const path = require('path')
const assert = require('assert')

// Model.js is a QML `.pragma library`; drop that line and evaluate the rest.
const src = fs.readFileSync(path.join(__dirname, '..', 'Model.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
eval(src)

// pickLyrics
const lrc = "[00:01.00] a\n[00:03.00] b";
let r = pickLyrics({duration: 200, syncedLyrics: lrc, plainLyrics: "a\nb"}, 200); assert.equal(r.synced, lrc);
r = pickLyrics({duration: 230, syncedLyrics: lrc, plainLyrics: "a\nb"}, 200); assert.equal(r.synced, ""); assert.equal(r.plain, "a\nb");
r = pickLyrics([{duration: 260, syncedLyrics: lrc, plainLyrics: "x"}, {duration: 201, syncedLyrics: lrc}], 200); assert.equal(r.synced, lrc);
r = pickLyrics([{duration: 200, instrumental: true}], 200); assert.equal(r.instrumental, true);
r = pickLyrics(null, 200); assert.deepEqual(r, {synced: "", plain: "", instrumental: false});
r = pickLyrics([], 0); assert.equal(r.synced, "");
// plainLines
assert.deepEqual(plainLines("\n\nA\n\n\nB\n\n").map(l => l.text), ["A", "", "B"]);
// sweep
assert.deepEqual(sweepGeometry([100, 50], 0.5), {full: 0, partial: 75});
assert.deepEqual(sweepGeometry([100, 50], 0.8), {full: 1, partial: 20});
assert.deepEqual(sweepGeometry([100], 1), {full: 1, partial: 0});
assert.deepEqual(sweepGeometry([], 0.5), {full: 0, partial: 0});
assert.ok(sweepSpan("hello", 0.5) === 0.5 && sweepSpan("hi", 10) === 1.0);
// spotifyUri
assert.equal(spotifyUri("https://open.spotify.com/track/55KZcq4bhEOKv7UMBb6P5l", ""), "spotify:track:55KZcq4bhEOKv7UMBb6P5l");
assert.equal(spotifyUri("", "/com/spotify/track/abc123"), "spotify:track:abc123");
assert.equal(spotifyUri("https://x.com", "/com/spotify/ad/1"), "");
// history
let h = pushHistory([{uri: "a"}, {uri: "b"}, {uri: "c"}], {uri: "b"}, 3); assert.deepEqual(h.map(e => e.uri), ["b", "a", "c"]);
h = pushHistory([{uri: "a"}, {uri: "b"}, {uri: "c"}], {uri: "d"}, 3); assert.deepEqual(h.map(e => e.uri), ["d", "a", "b"]);
assert.deepEqual(parseHistory("garbage"), []); assert.equal(parseHistory('[{"uri":"x"},{"nope":1}]').length, 1);
// levels
assert.deepEqual(parseLevels("0;500;1000;2000;", 1000), [0, 0.5, 1, 1]);
assert.equal(band([1, 0, 0, 0], 0, 0.25), 1); assert.equal(band([], 0, 1), 0);
assert.ok(Math.abs(band([0.2, 0.4, 0.6], 0, 1/3) - 0.2) < 1e-9);
// accentPair with fake Qt colors
const Q = { hsla: (h, s, l, a) => ({h, s, l}) };
const c = (h, s, l) => ({hslHue: h, hslSaturation: s, hslLightness: l});
let p = accentPair([c(0.05, 0.8, 0.5), c(0.55, 0.7, 0.45)], true, Q); assert.ok(Math.abs(p.a.h - 0.05) < 1e-9 && Math.abs(p.b.h - 0.55) < 1e-9);
p = accentPair([c(0.05, 0.8, 0.5), c(0.06, 0.6, 0.4)], true, Q); assert.ok(Math.abs(p.b.h - 0.12) < 1e-9, 'analogous shift');
assert.equal(accentPair([c(-1, 0, 0.5)], true, Q), null);
// outlinePoints: 20×20 box, radius 4, no inset
const P = { point: (x, y) => ({x, y}) };
const near = (a, b) => Math.abs(a - b) < 1e-6;
let o = outlinePoints(20, 20, 4, 0, 0, P); assert.equal(o.length, 1); assert.ok(near(o[0].x, 10) && near(o[0].y, 0), 'starts top middle');
o = outlinePoints(20, 20, 4, 0, 1, P); let last = o[o.length - 1]; assert.ok(near(last.x, 10) && near(last.y, 0), 'full loop ends where it began');
const per = 4 * 12 + 2 * Math.PI * 4;  // straight sides + corners
o = outlinePoints(20, 20, 4, 0, (6 + Math.PI * 2 + 6) / per, P); last = o[o.length - 1];
assert.ok(near(last.x, 20) && near(last.y, 10), 'quarter way is the right-side middle: ' + JSON.stringify(last));
o = outlinePoints(20, 20, 4, 0, 0.5, P); last = o[o.length - 1]; assert.ok(near(last.x, 10) && near(last.y, 20), 'half way is the bottom middle');
o = outlinePoints(20, 20, 4, 2, 1, P); assert.ok(o.every(p => p.x >= 2 - 1e-9 && p.x <= 18 + 1e-9 && p.y >= 2 - 1e-9 && p.y <= 18 + 1e-9), 'inset respected');
o = outlinePoints(20, 20, 50, 0, 0.25, P); assert.ok(o.every(p => isFinite(p.x) && isFinite(p.y)), 'oversized radius clamps');
// formatListening
assert.equal(formatListening(0), "<1 m"); assert.equal(formatListening(59), "<1 m");
assert.equal(formatListening(14 * 60 + 5), "14 m"); assert.equal(formatListening(72 * 60), "1 h 12 m");
assert.equal(formatListening(7200), "2 h"); assert.equal(formatListening(NaN), "<1 m");
console.log("all Model.js tests passed");
