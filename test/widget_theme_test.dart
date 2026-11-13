import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';

class ThemeAudio extends GlyphAudioHandler {
  final widgetThemes = <String>[];

  @override
  Future<void> setWidgetTheme(String mode) async => widgetThemes.add(mode);
}

void main() {
  testWidgets('widgets receive restored theme and subsequent theme choices', (
    tester,
  ) async {
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => ThemeAudio()))!;
    final repository = LibraryRepository(db);
    final c = AppController(repository, audio);
    addTearDown(() async {
      await tester.runAsync(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
    });
    await tester.runAsync(() async {
      await repository.setSetting('theme', 'light');
      await c.initialize();
    });
    expect(c.theme, ThemeMode.light);
    expect(audio.widgetThemes, ['light']);
    for (final mode in [ThemeMode.dark, ThemeMode.system, ThemeMode.light]) {
      await tester.runAsync(() => c.setTheme(mode));
      expect(audio.widgetThemes.last, mode.name);
      expect(
        await tester.runAsync(() => repository.setting('theme')),
        mode.name,
      );
    }
    expect(audio.widgetThemes, ['light', 'dark', 'system', 'light']);
  });
}
