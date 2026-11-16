# Spotify Pulse

An animated Spotify player for the [Omarchy](https://omarchy.org) bar.

The album cover and **Song — Artist** live in your bar, with the song's progress drawn around the cover. Click it for a player card that takes on the colors of whatever's playing: karaoke lyrics, a real audio visualizer, swipe-to-skip, a like button, recently played, a sleep timer and a shareable "Now playing" image.

<p align="center">
  <img src="assets/demo.gif" alt="Spotify Pulse demo: the player card opens with a large glowing album cover, crossfades to the next track as the whole card shifts from orange to teal, the cover sinks back on pause, and the cover flips over to the lyrics side" width="360">
</p>

**Contents:** [Install](#install) · [Quick start](#quick-start) · [The bar](#the-bar) · [The card](#the-card) · [Controls](#controls) · [Settings](#settings) · [Commands](#commands) · [Keyboard shortcuts](#keyboard-shortcuts-for-your-desktop) · [Visualizer](#visualizer) · [Troubleshooting](#troubleshooting) · [Privacy](#privacy) · [Limitations](#limitations) · [Uninstall](#uninstall)

## Install

**Requirements**
- Omarchy 4 (Hyprland and the Quickshell-based `omarchy-shell`).
- The Spotify desktop app.
- `curl` and `wl-copy`. Both ship with every Omarchy install.
- Optional: [`cava`](https://github.com/karlstav/cava) for the real audio visualizer: `omarchy pkg add cava`.
- No Spotify Premium, account login, API key or root access.

```bash
omarchy plugin add https://github.com/iammhador/omarchy-spotify-pulse.git --enable
```

It lands in the center of the bar. To move it:

```bash
omarchy bar move io.github.iammhador.spotify-pulse --section center --index 3
```

Replacing another Spotify widget? Disable that one: `omarchy plugin disable <its id>`.

### Updating

```bash
omarchy plugin update io.github.iammhador.spotify-pulse
omarchy restart shell
```

The shell keeps the old version loaded until it restarts, so the restart matters. What's new in each version is in [CHANGELOG.md](CHANGELOG.md).

## Quick start

1. Play something in Spotify. The cover and song appear in the bar.
2. **Hover** the bar for a quick preview. **Click** it to open the card.
3. In the card: **Lyrics** flips the cover over, **♡** likes the song, **swipe** the cover to skip, **Sleep** sets a timer.
4. Press `Esc` (or click the bar again) to close it.

## The bar

| What you see | What it means |
|---|---|
| Album cover (rounded square) | The current song. A new cover pops in when the track changes. |
| Line around the cover | How much of the song has played, going clockwise from the top middle. Right after you scroll, it shows the volume instead. |
| `Song — Artist` | Slides out and back in on track change. Long titles scroll back and forth while playing. |
| Dimmed cover | Paused. |
| 🌙 moon | A sleep timer is set. |
| Hover preview | Rest the mouse on it for half a second: cover, title, artist, album and time left. |

**Mouse:** left click opens the card · middle click plays/pauses · right click skips · scroll changes Spotify's volume (or skips tracks, see `scrollAction`).

**Other looks:**
- `barStyle wave`: a little wave that flows to the music inside a progress ring, with the new cover peeking in on track change.
- `barLyrics true`: the line being sung replaces the title while it plays.

It hides itself when Spotify isn't running (or shows a dim "Open Spotify" button with `showWhenClosed true`).

## The card

### Look
- **Cover-first:** a big album cover glowing in its own colors, over a blurred copy of itself that tints the whole card. Or a spinning record with `coverStyle vinyl`.
- **Two-color album theme:** two colors are taken from each cover. The glow, seek bar, play button and wave use them, and fade smoothly between tracks.
- **Motion that means something:** the cover crossfades on track change and sinks back on pause; the glow breathes with the bass (with the visualizer); the play button wears a progress ring and pulses while playing; controls cascade in when the card opens.
- Honors Omarchy's **reduced-motion** setting: looping animations stop and transitions become instant.

### Playing
- **Seek bar:** drag or scroll it. **Hover** it to see the time at that point, and the lyric line sung there when lyrics are on.
- **Transport:** shuffle · previous · play/pause · next · repeat (off → all → one). An accent dot shows when shuffle or repeat is on. Previous restarts the song if it's past 4 seconds, like the app.
- **Volume:** drag or scroll the slider; click the speaker to mute and unmute.
- **Swipe to skip:** drag the cover **left for the next song**, **right for the previous one**. It follows the pointer, flies off and the next cover glides in. A short drag springs back.

### Lyrics
- Click **Lyrics**, press `L` or **double-click the cover**: the cover flips over to its lyrics side.
- **Synced lyrics:** the current line is big and fills with the accent color as it's sung (karaoke sweep, `karaoke` setting). Lines around it blur and fade with distance. **Click a line** to jump there.
- **Timing off?** Press `[` to show lyrics sooner or `]` for later, half a second at a time. It resets on the next song.
- **No synced version?** You still get the plain lyrics to scroll through.
- Lyrics come from [lrclib.net](https://lrclib.net), a free community lyrics database, and are only looked up when you ask (see [Privacy](#privacy)).

### ♡ Like
- Click the heart next to the title, or press `H`: the song is added to (or removed from) your **Liked Songs**. Free accounts work.
- How: the plugin sends the Spotify app its own Like shortcut (Alt+Shift+B), straight to Spotify's window, without focusing it.
- The heart fills for a moment to confirm Spotify got it. It **toggles**, and it can't show whether a song is already liked (Spotify only shares that through its Web API, which needs Premium). If the heart shakes, Spotify's window wasn't found.

### Open in Spotify
- The green Spotify icon in the corner (or `O`) brings the Spotify app forward. Its **Now Playing** panel shows this song with Spotify's own **⊕ Add to playlist** button, so adding to a playlist is one click away, on any account.

### Share a "Now playing" image
- The share icon in the corner (or `C`) makes an image of the song: cover, title, artist, album and progress, in the album's colors.
- It's **copied to your clipboard** (paste it into any chat) and **saved** in `~/Pictures/Spotify Pulse/`.

### Recently played & today's stats
- The last tracks you played (10 seconds or more) appear as small covers. **Hover** one for its name, **click** it to play it again.
- Beside them: **today's listening time and number of songs**.
- Kept on your machine only. Turn off with `history false`, clear with `omarchy-shell spotify-pulse clearHistory`.

### Sleep timer
- Click **Sleep** (or press `Z`) to step through **15 → 30 → 60 minutes → After song → off**. The chip counts down, and a moon shows in the bar.
- Before pausing, the volume **fades out** over the last 30 seconds (10 seconds for "After song") and is put back afterwards, so the next play starts at your normal volume. Turn the fade off with `sleepFade false`.

## Controls

### Mouse

| Where | Action |
|---|---|
| Bar | Left: open/close the card · Middle: play/pause · Right: next · Scroll: volume · Hover: preview |
| Card cover | Drag left/right: next/previous · Double-click: lyrics |
| Lyrics | Click a line: jump to it · Scroll: read plain lyrics |
| Seek bar | Hover: preview · Click/drag/scroll: seek |
| Recently played | Hover: name · Click: play again |

### Keyboard (with the card open)

| Key | Action | Key | Action |
|---|---|---|---|
| `Space` | Play / pause | `N` / `P` | Next / previous |
| `←` / `→` | Seek 5 s | `0`–`9` | Jump to 0 %–90 % |
| `↑` / `↓` | Volume | `S` / `R` | Shuffle / repeat |
| `L` | Lyrics | `[` / `]` | Lyrics sooner / later |
| `H` | Like / unlike | `O` | Open in Spotify |
| `C` | Copy "Now playing" image | `Z` | Sleep timer |
| `Esc` | Close | | |

## Settings

All optional. Change them in **Omarchy's bar settings**, or from a terminal:

```bash
omarchy bar set io.github.iammhador.spotify-pulse coverStyle vinyl
omarchy bar set io.github.iammhador.spotify-pulse barLyrics true
```

**Bar**

| Setting | Default | What it does |
|---|---|---|
| `barStyle` | `"cover"` | `"cover"`: album art with progress around it. `"wave"`: a flowing wave in a progress ring. |
| `pillProgress` | `true` | Show progress around the cover (or ring) |
| `maxWidth` | `260` | Max width of the bar text, in px, before it scrolls |
| `showArtist` | `true` | Show `— Artist` after the song name |
| `marquee` | `true` | Scroll long titles (otherwise cut off with `…`) |
| `scrollAction` | `"volume"` | Mouse wheel on the bar: `"volume"`, `"track"` or `"none"` |
| `barLyrics` | `false` | Show the line being sung instead of the title (looks lyrics up, see [Privacy](#privacy)) |
| `showWhenClosed` | `false` | Show a dim "Open Spotify" button when Spotify isn't running |

**Card**

| Setting | Default | What it does |
|---|---|---|
| `coverStyle` | `"square"` | `"square"` cover or `"vinyl"` spinning record |
| `albumColors` | `true` | Theme the card from the album cover (otherwise your Omarchy accent) |
| `blurBackdrop` | `true` | Blurred cover tinting the whole card |
| `karaoke` | `true` | Fill the current lyric line as it's sung |
| `visualizer` | `true` | Real audio levels when `cava` is installed |
| `history` | `true` | Recently played and today's listening stats |
| `sleepFade` | `true` | Fade the volume out before the sleep timer pauses |

## Commands

Everything the card does can be scripted:

```bash
omarchy-shell spotify-pulse toggle        # open / close the card
omarchy-shell spotify-pulse close
omarchy-shell spotify-pulse playPause
omarchy-shell spotify-pulse next
omarchy-shell spotify-pulse previous
omarchy-shell spotify-pulse shuffle       # toggle
omarchy-shell spotify-pulse repeat        # off → all → one
omarchy-shell spotify-pulse volume 60     # percent
omarchy-shell spotify-pulse lyrics        # toggle lyrics
omarchy-shell spotify-pulse like          # like / unlike the current song
omarchy-shell spotify-pulse open          # bring Spotify forward
omarchy-shell spotify-pulse share         # copy a "Now playing" image (also saved to Pictures)
omarchy-shell spotify-pulse sleep 30      # pause in 30 min; -1 = after this song, 0 = off
omarchy-shell spotify-pulse clearHistory  # forget recently played and today's stats
omarchy-shell spotify-pulse status        # JSON: track, position, lyrics, visualizer, sleep, stats…
```

## Keyboard shortcuts for your desktop

Bind any command above to a key in `~/.config/hypr/bindings.lua`, then save; Hyprland reloads it on its own. For example:

```lua
-- Spotify Pulse
o.bind("SUPER + ALT + P", "Spotify Pulse card", "omarchy-shell spotify-pulse toggle")
o.bind("SUPER + ALT + H", "Like song", "omarchy-shell spotify-pulse like")
o.bind("SUPER + ALT + O", "Open Spotify", "omarchy-shell spotify-pulse open")
o.bind("SUPER + ALT + Z", "Sleep in 30 minutes", "omarchy-shell spotify-pulse sleep 30")
```

- These keys are free on a default Omarchy setup. Check yours with `omarchy menu keybindings --print`.
- Play/pause, next, previous and volume already work with your keyboard's media keys; no binding needed.
- The name in quotes is what Omarchy's keybindings menu (`SUPER + K`) shows.

## Visualizer

With `cava` installed (`omarchy pkg add cava`), the waves in the bar and card follow the real audio levels and the cover's glow breathes with the bass. cava only runs while music plays and stops the moment you pause. Without it (or with `visualizer false`), the waves use a gentle built-in animation.

cava listens to your system's audio output, so it reacts to whatever is playing, not only Spotify. Nothing is recorded or leaves your machine.

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing changed after installing or updating | Run `omarchy restart shell`. |
| Nothing in the bar | Spotify Pulse follows the **Spotify desktop app** only (not the web player). Start it, or set `showWhenClosed true`. |
| Card colors are gray | That cover has little color, so your Omarchy accent is used. Check `albumColors` is on. |
| "No lyrics for this song" | lrclib.net doesn't have it yet. Anyone can add lyrics there. |
| "Couldn't reach lrclib.net" | You're offline or lrclib is down. Turn Lyrics off and on to retry. |
| Lyrics run early or late | Press `[` or `]` with the card open. |
| Waves don't follow the music | Install cava (`omarchy pkg add cava`). `omarchy-shell spotify-pulse status` shows `"visualizer": "no-cava"` without it. |
| The heart shakes / Open does nothing | Spotify's window wasn't found. Make sure the Spotify app is open (not only its tray icon). |
| Like removed a song | Like toggles: on an already-liked song it unlikes. Press it again. |
| Share says "couldn't copy" | The image is still saved in `~/Pictures/Spotify Pulse/`. Check `wl-copy` is installed. |
| Bar text too wide | Lower `maxWidth`, or set `showArtist false`. |

For anything else, `omarchy-shell spotify-pulse status` shows what the plugin sees, which is useful in a bug report.

## Privacy

- **Album colors:** each cover is downloaded once from Spotify's image CDN into `~/.cache/spotify-pulse/` (pruned after 7 days) so its colors can be sampled locally.
- **Lyrics:** only while Lyrics is on, or with `barLyrics` enabled, the song's title, artist, album and length are sent to [lrclib.net](https://lrclib.net).
- **Recently played and stats:** the last 24 tracks (title, artist, album, cover link and Spotify link) and today's listening time and song count are kept in `~/.local/state/spotify-pulse/`, on your machine only. Turn off with `history false`, wipe with `clearHistory`.
- **Share:** the image is saved in `~/Pictures/Spotify Pulse/` and copied to your clipboard. Nothing is uploaded.
- **Like and Open in Spotify:** send a keyboard shortcut or focus request to the Spotify window through Hyprland. Nothing goes over the network.
- **Visualizer:** cava reads audio levels locally; nothing is recorded or sent anywhere.

## Limitations

Spotify Pulse talks to Spotify through MPRIS, the standard Linux media-control interface, which can't browse playlists, add to them or show the queue. Those need Spotify's Web API, which since February 2026 requires Spotify Premium and your own developer app, so this plugin doesn't use it. Instead:
- **Like** works through Spotify's own shortcut (it toggles, and can't show the liked state).
- **Add to playlist** is one click away with **Open in Spotify**.
- **Recently played** stands in for the queue.

## Uninstall

```bash
omarchy plugin remove io.github.iammhador.spotify-pulse
rm -rf ~/.cache/spotify-pulse ~/.local/state/spotify-pulse   # optional: cached covers, history, stats
```

Shared images in `~/Pictures/Spotify Pulse/` are yours to keep or delete. If you disabled another Spotify widget for this one, turn it back on with `omarchy plugin enable <its id>`.

## Credits

Spotify player detection is adapted from [Spotify Mini](https://github.com/LainsMain/omarchy-spotify-mini) by LainsMain (MIT). The demo uses made-up tracks and generated covers, and shows the 1.0 design.

## License

[MIT](LICENSE)
