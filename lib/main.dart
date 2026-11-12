import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'core/audio/glyph_audio_handler.dart';
import 'core/database/music_database.dart';
import 'features/library/data/library_repository.dart';
import 'integrations/widget_playback_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final database = await MusicDatabase.open();
    final playbackReady = Completer<AppController>();
    final handler = await AudioService.init<GlyphAudioHandler>(
      builder: () => GlyphAudioHandler()
        ..mediaButtonAction = (action) async {
          final controller = await playbackReady.future;
          await controller.widgetPlayback(action);
        },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.glyph.music.playback',
        androidNotificationChannelName: 'Glyph playback',
        androidNotificationIcon: 'drawable/ic_notification',
        // Keep the service (and its Flutter engine) alive across temporary
        // pauses and removal of the activity from Recents. Explicit Stop and
        // the sleep timer still release it by publishing the idle state.
        androidStopForegroundOnPause: false,
      ),
    );
    await handler.initialize();
    final controller = AppController(LibraryRepository(database), handler);
    await controller.initialize();
    playbackReady.complete(controller);
    await WidgetPlaybackBridge.bind(controller);
    runApp(
      ProviderScope(
        overrides: [controllerProvider.overrideWithValue(controller)],
        child: const GlyphApp(),
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 24),
                  const Text(
                    'Glyph could not start',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Close and reopen the app. Your music remains in local storage.',
                  ),
                  const SizedBox(height: 24),
                  SelectableText('$error'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
