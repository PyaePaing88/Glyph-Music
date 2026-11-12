# Build validation

Validated on 6 November 2026 with Flutter 3.47.9, Dart 3.13.7, Java 17, Android SDK 36.

- Automated tests: **23 passed**. Includes responsive in-app YouTube results/download dispatch, persisted search history, playlist metadata-only dialogs, full-page checkbox membership selection, metadata edits preserving tracks, empty-queue widget protection, exact HTTP range assembly, invalid ranges, cancellation cleanup, insecure redirects, and existing library/audio metadata tests.
- Static analysis: `analyze --no-pub lib test` clean.
- Android debug APK build succeeded from final source.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`, 203298226 bytes.
- Package: `app.glyph.glyph_music`, version **1.2.0 (3)**, launcher label **Glyph Music**.
- Minimum SDK 24, target SDK 36; ARM64, ARMv7 and x86_64.
- Development signature: APK Signature Scheme v2 verified. An earlier 1.2 build was installed on the A069 with `adb install -r`, preserving its library. The final APK update is pending because the USB device disconnected before installation.
- SHA-256: `8FF76900AE2B02E6567CCFCD661D6E3EA12DECFBB76C300C633338FBBC0C0B62`.

## Device widget checks

On A069 / Android 17 (API 37):

- Native `RemoteViews` rendered at 140x140, 120x140, 270x140 and 140x300 dp with nonempty artwork/title/artist and visible previous/play-pause/next controls within bounds.
- Native fixture renders under `docs/screenshots/widget-*-native.png` reviewed: no white outline, no tall-layout brand label. The test gradient makes translucency visible; these are actual native layout renders, not launcher screenshots.
- **Cold-start playback passed** with the phone unlocked: the real widget PendingIntent launched a fresh Glyph Music process and a playing system media session was observed. The check sent pause afterward. The earlier locked-phone attempts could not start the activity until the phone was unlocked.
- Device checks ran on the 1.2 build before the final empty-queue safeguard; the safeguard has its own automated regression test.
- Widget playback waits for controller/queue initialization. It restores the saved queue; an explicitly cleared queue remains empty.
- Launcher-specific picker caching, all resize gestures and all skip/shortcut interactions still require manual checks. Grid sizes depend on the launcher.
- Android 15+ system Force stop disables widgets until the app is reopened. This differs from closing the app or ordinary process death. See [Android stopped-state behavior](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state).

Debug-only device checks (excluded from release builds):

```powershell
.\.tools\android-sdk\platform-tools\adb.exe shell am instrument -w app.glyph.glyph_music/.WidgetLayoutCheck
.\.tools\android-sdk\platform-tools\adb.exe shell am instrument -w app.glyph.glyph_music/.WidgetPlaybackCheck
```

The playback check needs an unlocked phone and a valid saved local queue.

## YouTube verification and remaining limitation

- Live default search returned 20 in-app results without a proxy/API key.
- Duration parsing tolerates archived-live labels such as `Streamed` rather than failing the entire result list.
- A complete short public M4A audio transfer succeeded: **117,526 bytes**, using the same range transport as the app. The test file is in ignored local tools storage and was not added as a sample song to the user's library.
- A longer Blender test audio stream offered 10,271,496 bytes. Initial validated ranges downloaded, but YouTube rejected a later range at offset 1,048,576 with HTTP 403. Alternative supported source clients did not resolve the rejection on this connection.
- **Full-length YouTube downloads remain unverified and blocked in that live test.** The app shows the source rejection, removes incomplete audio, and does not add an invalid track. Do not represent this case as verified working.
- Available completed downloads keep their native M4A/WebM container. Files undergo size/hash/source deduplication and decoder validation before adding database records; no MP3 conversion or invented bitrate upgrade is performed.
- Automated search/download UI tests use a fake network/download controller to verify result presentation, button dispatch and saved-track state. They are not proof of live YouTube download completion or native decoder playback.
- The optional official-API search proxy remains available; it is not deployed and no server credentials were configured.

See [device acceptance checks](DEVICE_TESTS.md) for remaining background/Bluetooth/storage/performance checks. This APK is signed for development testing.
