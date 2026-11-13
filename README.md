# Glyph Music

An Android-first Flutter music player built from `FLUTTER_MUSIC_PLAYER_REQUIREMENTS.md`. The app starts with an empty library and works without an account or network connection.

## Run

Development baseline: Flutter **3.47.9**, Dart **3.13.7**, Java **17**, Android SDK **36**, minimum Android **24**. Dependency versions are locked in `pubspec.lock`.

On this Windows workspace, use the wrapper to avoid native-tool failures caused by the space in `Music player`:

```powershell
.\scripts\flutter.ps1 pub get
.\scripts\flutter.ps1 run
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
.\scripts\flutter.ps1 build apk --debug
```

The wrapper uses the local SDKs in `.tools` when present, otherwise your installed Flutter/Android SDK. It supplies a reversible drive mapping to this project. `subst` lists mappings; remove an unused mapping with `subst G: /D` after stopping Flutter/Gradle. The mapping does not move the project. Tools and caches are ignored by Git.

With Flutter already installed in a path without spaces, the ordinary `flutter pub get`, `flutter run`, and `flutter test` commands work. Connect an Android phone with USB debugging enabled or start an emulator. This repository currently supplies an Android target; iOS is not scaffolded.

Debug APK output: `build/app/outputs/flutter-apk/app-debug.apk`. Development builds use the Android debug key. Configure a private signing key before release distribution; do not commit signing keys or API secrets.

### Background playback

Playback uses an Android media playback foreground service, independent of the
visible activity. After playback starts, temporary pauses retain foreground
protection so notification/headset controls can resume music in the background.
Removing Glyph from Recents does not request playback to stop. The notification's
Stop action and an enabled sleep timer still stop playback.

If the phone restricts background activity, open **Settings > Background playback**
in Glyph, then allow background usage or unrestricted battery use in the phone's
app settings. Android Force stop, the system's active-app Stop action, and device
manufacturer process restrictions can still terminate playback.

Device regression check: with the sleep timer off, play a multi-track queue,
lock the screen, and verify playback continues through a track change. Remove
Glyph from Recents while playing; verify music and notification controls still
work, including pause/resume while locked. Reopen Glyph and verify the same queue
and position remain. Verify notification Stop and an enabled sleep timer stop
music. Repeat with the phone's background battery restriction disabled if needed.

## Implemented

- Original monochrome Nothing-inspired light, dark, and system themes, dot-matrix headings, procedural record artwork, and a rotating Now Playing record.
- Swipe navigation between Home, YouTube Search, Library, and Playlists with preserved screen state; local search in Library, songs/artists/albums/genres, favorites, recently played, playlists, Now Playing, queue, downloads, and settings screens.
- MP3 file import through the system picker, optional selected-folder scanning, bounded ID3v2.3/v2.4 and ID3v1 tag reading, embedded artwork where supported, real decoder validation, content-hash duplicate detection, app-managed copies, and storage checks.
- Automatic Android phone audio discovery on opening/resuming Glyph, plus manual rescan in Library/Settings. Uses MediaStore across shared internal/removable storage, includes recordings and short clips, reads available metadata/artwork, and plays original content URIs without copying audio. Audio permission is requested once; denial never clears the existing library. Rescans preserve user edits, favorites, history and playlist membership, deduplicate media identities and remove entries for deleted shared files.
- Local `just_audio` playback and an `audio_service` media session: play/pause, previous/next, seek, shuffle, repeat one/all, notification/headset interfaces, audio focus, and unplug handling through `audio_session`/`just_audio`.
- Ordered queues, play next/add/reorder/remove, paused queue restoration and saved position. Positions are checkpointed every five seconds and on pause/media-item changes. History counts a track after 30 seconds or half its duration for short tracks.
- Drift-managed asynchronous SQLite with foreign keys, indexes, transactions, deliberate cascading, and schema version 1. Playlist deletion preserves audio; song deletion cleans dependent playlist/history records.
- Playlist create/edit dialogs contain name, description, and artwork only. Creation opens the empty playlist. Its Add tracks action opens a full Tracks page with search and checkboxes; Done saves selection. Metadata edits preserve membership. Manual playlist/track reordering and favorite/history collections remain available.
- Library metadata/artwork editing, confirmed record-only or managed-file deletion, storage summary, temporary picker-cache clearing, local privacy controls, and metadata JSON backup/restore matched by audio content hash.
- Authorized direct HTTPS MP3 downloads with bounded streaming, progress/cancel/retry, HTTPS-only redirects, completion/format/size validation, temporary-file cleanup, and deduplication. Downloads preserve the source bytes; they do not transcode or claim to improve source quality.
- Optional authorized catalog adapter with source-license attribution and selection among actual offered original 128/192/256/320 kbps MP3 variants. The quality preference selects among those variants, never an invented transcode.
- YouTube search shows results inside Glyph Music, with title, channel, artwork, duration where available, and Download. Successful audio downloads appear in the local track list after size and decoder validation. Source audio stays in its offered M4A/WebM container; no MP3 conversion or quality upscaling is claimed. Progress, cancellation, retry, source/hash deduplication, and partial-file cleanup are included.
- Native translucent Android widgets: wide **4×2**, square **2×2**, and tall **2×4** (columns × rows), with artwork, title, artist, and previous/play-pause/next controls. The white outline and tall-layout brand label are removed. Widget playback actions open the activity when needed and wait for queue restoration before acting. Android 15+ generated previews, populated XML previews, and legacy PNG previews are included.
- Glyph Music launcher name and an original dotted play/record icon, including adaptive and Android monochrome themed variants.

## Optional online services

Everything local works with neither endpoint configured. No private server credential is embedded in the app.

### YouTube

Open Search and type a query. YouTube search starts automatically after a brief pause in typing; the keyboard Search action runs it immediately. Local collection search remains in Library. Results stay inside Glyph Music. Tap Download to save available audio into the local track list. No proxy/API key is required for the default `youtube_explode_dart` adapter. The external-video action remains optional. YouTube can reject restricted or unavailable streams; failures never become playable library entries. The adapter may need updates when YouTube changes its service. See the [integration's documentation](https://github.com/Hexer10/youtube_explode_dart).

To use an optional official-API search proxy instead of the default search adapter:

`server/youtube_proxy.mjs` is a dependency-free Node 22+ example that calls the official YouTube Data API `search.list`. Run it separately with a server-side `YOUTUBE_API_KEY`, put it behind HTTPS, apply production rate limiting, and restrict the key to the appropriate API and server. The example binds to localhost and includes a small bounded cache and per-address limit; it is not deployed automatically.

```powershell
$env:YOUTUBE_API_KEY = 'server-side-key'
node server/youtube_proxy.mjs
```

Build the mobile app with your deployed endpoint:

```powershell
.\scripts\flutter.ps1 run --dart-define=YOUTUBE_DISCOVERY_ENDPOINT=https://your-server.example/youtube/search
```

The endpoint receives `q` and returns the official search response shape (`items[].id.videoId`, `items[].snippet`). API quota and connectivity failures show an error with a retry action on the YouTube Search screen. A disconnected search attempt is handled without affecting the local player.

References: [YouTube search API](https://developers.google.com/youtube/v3/docs/search/list), [YouTube API policies](https://developers.google.com/youtube/terms/developer-policies).

### Authorized catalog

Optionally build with `--dart-define=AUTHORIZED_CATALOG_ENDPOINT=https://your-server.example/audio`. This enables the catalog action in Downloads. The endpoint receives `q` and returns:

```json
{
  "tracks": [{
    "id": "owned-recording-1",
    "title": "First Light",
    "artist": "Your artist",
    "downloadAllowed": true,
    "licenseUrl": "https://your-server.example/licenses/recording-1",
    "originalBitrateKbps": 320,
    "variants": [
      {"url": "https://your-server.example/audio/recording-192.mp3", "mimeType": "audio/mpeg", "bitrateKbps": 192},
      {"url": "https://your-server.example/audio/recording-320.mp3", "mimeType": "audio/mpeg", "bitrateKbps": 320}
    ]
  }]
}
```

Only connect providers whose licenses actually permit downloading. The adapter requires explicit per-item permission, an HTTPS license URL, and HTTPS MP3 variants. It omits variants above a declared original bitrate. Direct links require confirmation that the user owns the audio or the source permits downloading.

## Storage and limitations

Widgets use a translucent surface; wallpaper shows through the borderless background. Widgets follow the app theme: System adapts to the phone light/dark setting, while Light and Dark stay fixed. Text, transport controls, and shortcuts use matching readable colors. This does not request system wallpaper access or apply launcher-level background blur. Grid sizes and corner treatment depend on the launcher. After updating the APK, remove and re-add old widgets if the launcher retains old previews. Native widget/icon changes require an APK rebuild and full app restart; Flutter hot reload cannot apply them.

Widget playback opens Glyph Music as needed, restores its queue, and then handles the button action. It supports a closed app or ordinary process death. Android 15+ system **Force stop** explicitly disables widgets until the app is reopened; see [Android stopped-state behavior](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state).

Live validation: the former default source client returned HTTP 403 during longer audio downloads. Version 1.3 uses the compatibility client proposed in [upstream PR #389](https://github.com/Hexer10/youtube_explode_dart/pull/389). A complete 10,271,496-byte public Blender sample audio transfer now passes with the same validated range transport used by the app. Availability still depends on the source; failures remove partial data. See [build validation](docs/BUILD_VALIDATION.md).

Imported/downloaded audio and artwork are copied into private application-support storage; SQLite stores metadata, not audio bytes. Scanned phone audio stays in its original location and needs READ_MEDIA_AUDIO (Android 13+) or READ_EXTERNAL_STORAGE (Android 12 and earlier). No all-files-management permission is requested. Android's shared media index cannot expose other apps' private audio, DRM-protected offline caches or files hidden from its index. Metadata quality and playable formats depend on the file and device decoder. Uninstalling Glyph removes managed copies but leaves scanned originals untouched. Folder import depends on the Android document provider exposing a readable directory.

The MP3 limit is 500 MB per file. Unknown-length downloads reserve conservative space for a maximum-size file and the validated managed copy. Rich/unsupported ID3 encodings may fall back to filenames and unknown artist; artwork can be corrected locally. Metadata edits affect the Glyph database, not the MP3's embedded tags.

Metadata backups contain edited text, favorites, ordered playlists, and theme/quality preferences. They do not contain audio, artwork, play history, download history, or an active queue. Managed imports/downloads match by SHA-256 after reimporting original audio. Scanned phone tracks use a media identity scoped to this installation, so their metadata can be restored in the same installation; cross-device matching of scanned tracks is not supported. Restore adds playlists rather than replacing the entire library.

Crossfade, MP3 conversion, lyrics, M3U exchange, arbitrary storage relocation, and download pause/resume are not implemented. Device media behavior, launcher cold starts, startup targets, battery use, and large-library rendering need the real-device checks below. No release-signing credentials, online catalog, or API endpoint are supplied by default.

## Structure and verification

`lib/app` owns bootstrap/navigation/application state; `lib/features` contains domain/library persistence and feature screens; `lib/core` contains SQLite, audio, storage, and shared UI; `lib/integrations` contains official discovery and authorized-catalog adapters. Riverpod injects the application controller and the controller notifies presentation listeners. SQLite is accessed through Drift's background executor and explicit, reviewable SQL; no code generation is needed.

Automated coverage includes foreign keys and deletion, transaction rollback, ordered playlists, duplicate hashes, file-backed restart persistence, metadata backup/restore, local search including 10,000 records, MP3 tag/file validation, catalog permission/quality filtering, light/dark navigation, playlist creation, and scalable display components.

Use `flutter test --dart-define=GLYPH_CAPTURE=true` to regenerate the real-widget previews under `docs/screenshots`. The capture test loads the SDK's Roboto and Material icon fonts. These previews are Flutter widget renders. The Now Playing preview uses a test-only metadata fixture and does not demonstrate device audio playback.

[Device acceptance checklist](docs/DEVICE_TESTS.md) covers airplane mode, background playback, Bluetooth, notification controls, launcher widgets, storage failures, and performance measurement.

Primary integration references: [just_audio](https://pub.dev/packages/just_audio), [audio_service](https://pub.dev/packages/audio_service), [Drift](https://pub.dev/packages/drift), [home_widget](https://pub.dev/packages/home_widget). These packages provide their own open-source licenses. Flutter includes dependency notices in its license registry.

