# Nothing Glyph music visualizer

Settings > Music > Music visualizer enables or disables music-reactive Glyph lights. The preference defaults to off and is saved locally and in metadata backups. Playback pause, buffering, completion, stop, and the sleep timer release the capture and turn off the lights. The native plugin belongs to the playback engine, including widget cold starts.

The Android Visualizer reads waveform samples from just_audio's nonzero audio session, never the global output mix. It does not open the microphone. Android nevertheless requires RECORD_AUDIO permission for this API; permission is requested only when the user enables the feature. Denied permission and unsupported hardware leave music playback available. Waveform RMS controls the number of illuminated segments, with a noise floor and a short decay at 25 frames per second.

Supported Glyph Interface devices: Phone (1), (2), (2a), (2a) Plus, (3a)/(3a) Pro, (4a), and (4b), on Android 14 or later, according to the bundled SDK's device detection. Glyph Matrix devices are not supported by this implementation. Device settings, firmware and SDK authorization may restrict access, particularly background access; confirm behavior on physical hardware.

## SDK and authorization

The bundled android/app/libs/glyph-matrix-sdk-2.0.aar is Nothing's official SDK (also contains the Glyph Interface API):
https://github.com/Nothing-Developer-Programme/Glyph-Developer-Kit

Downloaded from sdk/glyph-matrix-sdk-2.0.aar on 2026-11-13.
SHA-256: 329393019db5f0f987c6245855d13fa273d06756c68829ca0f6ae686ba336da1
Git blob: 7fdd2e8ec41e6fef2aaa3f31963d06807421dfaf

Nothing documents that Android 14/15 needs a Nothing-issued API key for production. Pass -PnothingGlyphApiKey=YOUR_KEY to Gradle, or set nothingGlyphApiKey in your local Gradle properties. The default test key requires Glyph developer mode on those OS versions:

    adb shell settings put global nt_glyph_interface_debug_enable 1

Developer mode expires after 48 hours. Nothing documents removal of the API-key restriction starting with Android 16 for apps targeting that version or later. The NothingKey manifest entry is retained for compatibility. Do not treat a successful APK build as evidence of hardware authorization.

The SDK manifest requires API 33; the application overrides that library minimum because all Glyph SDK access is gated to API 34+ and the SDK manifest contains no automatic components. The player retains its API 24 minimum.

## Physical-device verification

- Enable while paused: permission prompt appears once and the preference persists.
- Play quiet and loud passages: lights follow actual audio, including through track changes and seeks.
- Pause, buffer, stop, finish a queue and expire a sleep timer: lights turn off.
- Disable during playback: lights turn off immediately; audio continues.
- Restart and start playback from a widget: the saved setting is applied.
- Deny/revoke audio permission and disable phone Glyph access: the app remains usable and displays a status.
- Check unsupported phones and Glyph Matrix phones: enable is rejected without affecting playback.
- Check physical-device background and screen-off behavior under the installed Nothing OS SDK policy.
