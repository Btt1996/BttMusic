# Btt Music (BTmu)

A complete native iOS rebuild of Btt Music — offline-first music player, Telegram
audio sync, X1 metadata identification, X2 freely-licensed audio acquisition,
on-device Smart Remix analysis, remote theming, JSON backup/restore, and a
YouTube import bridge to a self-hosted yt-dlp server.

- Developer: Ahmed Taboubi
- Bundle identifier: `com.ahmed.btmu` (preserved from the original app)
- Platform: SwiftUI + SwiftData + AVFoundation, iOS 18+
- No WebView, no Capacitor, no JavaScript bridge — fully native.

## Project layout

```
ios-btt-music/BttMusic/
  BttMusicApp.swift        App entry, SwiftData container, splash
  AudioEngine.swift        AVAudioEngine graph, crossfade, EQ, limiter, Remote Command Center
  LibraryStore.swift       Import, metadata, duplicates, storage stats, playlists, export
  Models.swift             SwiftData models (Track, Playlist)
  TelegramService.swift    Telegram Bot API client (token in Keychain)
  X1SpotifyService.swift   Keyless Spotify metadata import (embed pages)
  X2AcquisitionService.swift  Authorized free-source audio (Internet Archive, Jamendo)
  RemixAnalyzer.swift      BPM/energy/brightness analysis + sequence generation
  UpdateService.swift      GitHub release checking
  DesignSystem.swift       BT brand colors, gradients, cards
  Views/…                  Library, Playlists, Get Music (Telegram/X1/X2), Remix, Settings, Player
```

## Build

1. Open `ios-btt-music/BttMusic.xcodeproj` in Xcode 16+.
2. Select the **BttMusic** target and your development team (Signing & Capabilities).
3. Run on an iOS 18+ simulator or device. Background audio (`UIBackgroundModes: audio`)
   is already configured in build settings.

### GitHub Actions: unsigned device IPA (no Apple account needed)

Run **Actions → Build Unsigned IPA → Run workflow** on `main`. The workflow
(`.github/workflows/build-unsigned-ipa.yml`) on a GitHub-hosted macOS runner:

1. decodes the base64 binary assets (PNGs are stored as `.png.b64` because the
   repo was pushed through an API that only writes text files);
2. archives the app for `generic/platform=iOS` (arm64 devices) with
   `CODE_SIGNING_ALLOWED=NO`;
3. verifies the binary is a real **iOS-device** build (`lipo` arm64 + `vtool`
   `platform iOS`, explicitly rejecting `iossimulator`), the bundle id is
   `com.ahmed.btmu`, and `ShareExtension.appex` is embedded;
4. uploads **`BttMusic-Unsigned.ipa`** as a run artifact — download it from the
   run page on your iPhone and sign/install with Sideloadly, AltStore or
   TrollStore.

On a Mac you can do the same locally: `./scripts/make-unsigned-ipa.sh`.

## Features

### Music engine
AVAudioEngine graph: dual `AVAudioPlayerNode` crossfade pair → 2-band EQ
(bass shelf 120 Hz / treble shelf 8 kHz) → Apple PeakLimiter. Volume boost up to
300% is implemented as limiter PreGain (+9.54 dB), so the limiter is forced
engaged while boosting to prevent clipping. Lock-screen controls, AirPods/Bluetooth,
interruption and headphone-disconnect handling, queue persistence.

### Telegram import
Native Telegram Bot API client: create a bot with @BotFather, paste the token
(stored in the iOS Keychain only), scan `getUpdates` for audio, download with
progress into the library with duplicate detection by `file_unique_id`.

**Important limitation (investigated):** the Bot API can only see audio that is
*sent to your bot*. It cannot read arbitrary public channels (e.g. the old app's
curated list like @ElectronicMusicHub) unless the bot is an admin there — and the
old Capacitor app had exactly the same constraint behind its web view. Proper
alternatives:
1. Forward channel audio to your bot in Telegram, then Refresh (works today);
2. Add your bot as an admin to a channel you own, then bulk-import;
3. A self-hosted MTProto user-session service would read arbitrary channels but
   is against Telegram's ToS for unofficial automation — not implemented.

### X1 — metadata only
Parses public `open.spotify.com` playlist/album/track links keylessly via the
official embed pages (`__NEXT_DATA__` → `trackList`). Verified against a real
public playlist (2026-11): titles, artists and track URIs extract correctly.
Native URLSession has no CORS restriction, so the old app's CORS-relay proxy is
only a fallback. X1 never downloads audio. Saved playlists match tracks already
in your library.

### X2 — audio acquisition (authorized sources only)
Internet Archive (verified live: search → item metadata → real MP3 URLs) and
Jamendo (add your own client ID in Settings; Jamendo requires one). No DRM
circumvention, no Spotify/YouTube audio extraction — that is not technically or
legally possible on-device (yt-dlp cannot run on iOS; documented decision).

### Smart Remix
On-device analysis: BPM via onset-envelope autocorrelation (60–180), energy via
mean RMS, brightness via zero-crossing rate (mood heuristic). True musical-key
detection is not practical with light DSP and is approximated by brightness
clustering — labeled as heuristic in the UI. Sequences follow an energy arc
(warm-up → build → peak → cooldown) and save as playlists.

### Storage
Usage dashboard per source, duplicate detection (title+artist+duration),
confirmed-only cleanup, full JSON backup export, format/container explanation
in-app. No automatic transcoding — quality is never degraded without consent.

### Backup & restore
`BackupService` exports the whole library (track metadata + playlist structure,
playlists referencing tracks by title+artist keys) as one JSON file. Restore
uses a Files picker with a preview of counts and playlist names before anything
is touched; restoring never overwrites — existing tracks are matched by
title+artist and left untouched, and entries whose audio file is missing on the
target device are restored as metadata-only and flagged in the report.

### Remote theming
All colors, corner radii, typography character (display/body font design) and
the visibility of acquisition cards are data-driven (`ThemeEngine.swift`). The
bundled "BT Signature" theme matches the BT gradient brand. Point Settings at
a theme JSON (GitHub raw or any CDN), tap Apply — the whole app restyles live,
no reinstall. Reset returns to the bundled theme.

**Theme JSON structure** (full example: `docs/theme-example.json`):

| Field | Type | Meaning |
|---|---|---|
| `name` | String | Shown in Settings after applying |
| `palette` | Object | 9 hex colors: `canvas`, `surface`, `surfaceRaised`, `accentA/B/C` (the BT gradient), `textPrimary`, `textSecondary`, `textTertiary`. Hex may be `#RRGGBB` or `#RRGGBBAA`. |
| `displayFontDesign` | String | `serif`, `rounded` or `default` — face of headlines |
| `bodyFontDesign` | String | Same choices for body text |
| `cardCornerRadius` | Number | Card corner radius (pt) |
| `artworkCornerRadius` | Number | Artwork corner radius (pt) |
| `featureFlags` | Object | `{"youtube": bool, "remix": bool, "x2": bool}` — hides/shows acquisition cards |

A malformed JSON is rejected without touching the current theme. A valid
remote theme is cached (`cached-theme.json`) and survives relaunch.

### YouTube import (honest scope)
iOS cannot run yt-dlp (a Python pipeline) and apps must not extract YouTube
streams themselves. The app registers the `bttmu://` scheme and ships a Share
Extension: share a YouTube URL from Safari → the extension forwards it to the
app (`bttmu://youtube-import?url=…`, pasteboard fallback). The app submits the
link to a yt-dlp-compatible server YOU host and imports the returned audio
file. Without your own server configured, the screen says so and does nothing
— no on-device extraction, no DRM circumvention.

**Server architecture** (implemented in the app; the server itself is what you
host — a working reference is `tools/ytdlp_server.py`):

```
iPhone (Btt Music)                your server (any host with Python)
────────────────────              ──────────────────────────────────
Share Extension ──bttmu://──▶  app shows YouTube Import
app  POST /extract {"url": …} ──▶ yt-dlp downloads bestaudio (m4a)
app  ◀── 200 {"title", "download_url"}
app  GET download_url ──────────▶  static file / signed URL
app  imports into library (duplicate check by source URL)
```

Implemented in the app: URL-scheme entry (`onOpenURL`), Share Extension
forwarding, server base-URL configuration, `POST /extract` submission,
audio download with the parsed `download_url`, library import with duplicate
detection. Requiring external hosting: the machine running yt-dlp
(home server / VPS), its public reachability (HTTPS recommended), and any
authentication you want on it. Link sharing works without the server; audio
downloading does not — it is never claimed to work otherwise.

### Volume booster switch
The booster is now DISABLED by default; an explicit toggle enables it (in the
player's Sound sheet). While off, playback is bit-identical to the
unprocessed graph. The 300% digital gain still routes through the PeakLimiter
so peaks are caught whenever boosting is engaged. Gain mapping: 100% → 0 dB,
200% → +6.02 dB, 300% → +9.54 dB (verified by unit tests); the limiter is
forced engaged while boosting even if the user's limiter preference is off.

### Triple-press (investigated)
iOS does not expose AirPods stem-press events to apps — a triple-press cannot
be a custom app action. What iOS does natively: on AirPods, double-press =
skip forward, triple-press = previous track, routed to the app through
`MPRemoteCommandCenter`. The app registers `nextTrackCommand` and
`previousTrackCommand` (plus play/pause and scrub positions), so the hardware
double/triple-press controls work through Apple's supported path with no
further implementation possible or needed.

### Splash
Animated splash: ambient gradient glow, spring-in BT logo, serif wordmark,
drawing gradient rule line, "BY TABOUBI AHMED" credit.

### Updates
GitHub release check (configurable `owner/repo` in Settings) with release notes.
An iOS app cannot silently replace its own executable: installation happens via
TestFlight / App Store / your sideloading workflow.

## Tested / untested

Tested (iOS simulator, 2026-11-09):
- Launch, splash, Library empty state, tab navigation (Library / Playlists /
  Get Music / Remix / Settings)
- X1 screen with Spotify link input, X2/Telegram screens render
- X1 embed parsing (live HTTP verification of `__NEXT_DATA__`/`trackList`)
- X2 archive.org search + metadata + MP3 resolution (live HTTP verification)
- Full compile of the app target (simulator build succeeded)

Not tested yet (requires a device / credentials / media):
- Actual audio playback sound output, background/lock-screen playback, AirPods controls
- EQ/boost audible effect (graph compiles and is wired; audio path unverified in simulator)
- Telegram bot connect/scan/download with a real bot token
- X2 downloads of a full audio file into the library
- Smart Remix on real audio files (analysis code is pure Foundation/AVFoundation, unit-testable)
- Duplicate cleanup and library import via the Files picker

## Signing an IPA

To produce an installable, signed IPA you need:
1. An Apple Developer Program membership ($99/yr) → a Team ID.
2. Set the team in Xcode (Signing & Capabilities) or `DEVELOPMENT_TEAM` in the
   project, then **Product → Archive → Distribute App**, or use
   `xcodebuild archive` + `xcodebuild -exportArchive` with an App Store Connect
   profile.
3. For sideloading without the App Store: a development/ad-hoc profile listing
   your device UDIDs, or tools like AltStore/Sideloadly with your Apple ID.

The Rork build service can produce unsigned/CI artifacts; App Store and
TestFlight delivery goes through its publish flow with your account connected.

## Repository history

The original repositories (spotify_to_mp3 and the previous btmu sources) are
preserved untouched. This repo is the clean native rebuild.
