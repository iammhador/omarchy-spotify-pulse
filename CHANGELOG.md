# Changelog

## 1.1.0

After updating, run `omarchy restart shell` so the new version loads.

### Bar
- **Album cover in the bar**, with the song's progress drawn around its four sides. Right after a scroll it shows the volume instead.
- **Hover preview:** cover, title, artist, album and time left.
- `barStyle wave`: a flowing wave inside a progress ring, with the new cover peeking in on track change.
- `barLyrics`: show the line being sung instead of the title.
- A moon shows while a sleep timer is set.
- No highlight or underline under the pill; the cover says it all.

### Card
- **Two-color album theme** for the glow, seek bar, play button and waves.
- **Lyrics:** karaoke sweep through the current line, depth-of-field blur, `[` / `]` timing nudge, plain lyrics when there's no synced version, an "Instrumental" state, and safer matching (synced lyrics must match the recording's length).
- **Swipe the cover** to skip to the next or previous song.
- **Seek preview:** hover the seek bar for the time and the lyric line there.
- **♡ Like** (works on free accounts), `H` key.
- **Open in Spotify:** brings the app forward, where "Add to playlist" is one click away. `O` key.
- **Share:** copy a "Now playing" image to the clipboard (also saved in `~/Pictures/Spotify Pulse/`). `C` key.
- **Recently played:** click a cover to play it again, plus today's listening time and song count.
- **Sleep timer:** 15 / 30 / 60 minutes or after this song, with a volume fade-out. `Z` key.
- **Real audio visualizer** with [cava](https://github.com/karlstav/cava) (optional).
- Progress ring around the play button; the song-title equalizer is now a wave.
- Long titles scroll instead of being cut off.
- `0`–`9` jump to 0 %–90 % of the song.
- Optional vinyl cover (`coverStyle vinyl`).

### Under the hood
- One shared service does the work for every monitor's bar (one lyrics lookup instead of one per screen, and so on).
- Settings appear in Omarchy's bar settings.
- Honors Omarchy's reduced-motion setting.
- Lyrics lookups time out after 8 seconds instead of loading forever, and failures aren't cached.
- New commands: `like`, `open`, `share`, `sleep`, `clearHistory`; `status` reports much more.

## 1.0.0

First release: Song — Artist in the bar with a live equalizer, and a cover-first player card with album colors, synced lyrics on the back of the cover, shuffle, repeat and volume.
