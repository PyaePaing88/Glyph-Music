import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/audio/glyph_visualizer.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/settings/presentation/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var accepted = true;
  setUp(() {
    calls.clear();
    accepted = true;
    messenger.setMockMethodCallHandler(GlyphVisualizer.channel, (call) async {
      calls.add(call);
      return call.method == 'setEnabled' ? accepted : null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(GlyphVisualizer.channel, null),
  );

  test(
    'forwards playback session changes and pause without global capture',
    () async {
      final visualizer = GlyphVisualizer()..initialize();
      await visualizer.updatePlayback(null, false);
      await visualizer.updatePlayback(42, true);
      await visualizer.updatePlayback(42, true);
      await visualizer.updatePlayback(43, true);
      await visualizer.updatePlayback(43, false);
      expect(calls.map((call) => call.arguments), [
        {'sessionId': null, 'playing': false},
        {'sessionId': 42, 'playing': true},
        {'sessionId': 43, 'playing': true},
        {'sessionId': 43, 'playing': false},
      ]);
      await visualizer.dispose();
      expect(calls.last.arguments['enabled'], false);
    },
  );

  test('unsupported native implementation fails gracefully', () async {
    messenger.setMockMethodCallHandler(GlyphVisualizer.channel, null);
    final visualizer = GlyphVisualizer();
    expect(await visualizer.setEnabled(true), false);
    expect(visualizer.status.value, 'unsupported');
    await visualizer.dispose();
  });

  test('visualizer preference survives a metadata backup round trip', () async {
    final db = MusicDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LibraryRepository(db);
    await repository.setSetting('musicVisualizer', true);
    final backup = await repository.backup();
    await repository.setSetting('musicVisualizer', false);
    await repository.restore(backup);
    expect(await repository.setting('musicVisualizer'), true);
  });

  testWidgets(
    'settings toggle saves enable and disable, rejects denied access',
    (tester) async {
      final db = MusicDatabase(NativeDatabase.memory());
      final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
      final c = AppController(LibraryRepository(db), audio);
      addTearDown(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(c: c)));
      final toggle = find.widgetWithText(SwitchListTile, 'Music visualizer');
      await tester.ensureVisible(toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      await tester.runAsync(() async {
        await c.setMusicVisualizer(true);
        expect(await c.repository.setting('musicVisualizer'), true);
      });
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, true);
      expect(calls.last.arguments, {
        'enabled': true,
        'requestPermission': true,
      });
      await tester.runAsync(() async {
        await c.setMusicVisualizer(false);
        expect(await c.repository.setting('musicVisualizer'), false);
        accepted = false;
        await c.setMusicVisualizer(true);
        expect(await c.repository.setting('musicVisualizer'), false);
      });
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, false);
    },
  );
}
