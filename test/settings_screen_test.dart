import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/core/widgets/design.dart';

import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/settings/presentation/settings_screen.dart';

class SettingsController extends AppController {
  SettingsController(super.repository, super.audio);
  int resets = 0;
  @override
  Future<void> deleteLocalData() async {
    resets++;
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'settings choices persist and details remain accessible in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = MusicDatabase(NativeDatabase.memory());
        final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
        final c = SettingsController(LibraryRepository(db), audio);
        addTearDown(() async {
          c.dispose();
          await audio.dispose();
          await db.close();
        });
        c.phoneAudioAccess = 'granted';
        await tester.pumpWidget(
          MaterialApp(
            theme: glyphTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: SettingsScreen(c: c),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Delete all app data'), findsNothing);
        expect(find.text('Export backup'), findsNothing);
        await tester.tap(find.text('Theme'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Dark'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(c.theme, ThemeMode.dark);
        expect(
          await tester.runAsync(() => c.repository.setting('theme')),
          'dark',
        );

        await tester.ensureVisible(find.text('Accent colour'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accent colour'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(TextField, 'Hex colour'),
        );
        await tester.enterText(find.byType(TextField), 'XYZ');
        await tester.pumpAndSettle();
        expect(find.text('Enter 6 hex digits'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Apply'))
              .onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextField), '2784C5');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Apply'));
        await tester.tap(find.text('Apply'));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(c.accentColour.colour.toARGB32(), 0xff2784c5);
        expect(
          await tester.runAsync(() => c.repository.setting('accentColour')),
          0xff2784c5,
        );
        await tester.ensureVisible(find.text('Download quality'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Download quality'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('320 kbps'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('320 kbps'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(c.quality, 320);
        expect(
          await tester.runAsync(() => c.repository.setting('quality')),
          320,
        );

        await tester.ensureVisible(find.text('Storage'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Storage'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Clear temporary files'),
          200,
        );
        await tester.pumpAndSettle();
        expect(find.text('Clear temporary files'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Backup & restore'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Backup & restore'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Music and artwork are not included'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(find.text('Export backup'), 200);
        await tester.pumpAndSettle();
        expect(find.text('Export backup'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Restore backup'), 200);
        await tester.pumpAndSettle();
        expect(find.text('Restore backup'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Privacy & data'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Privacy & data'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Clear recent searches'),
          200,
        );
        await tester.pumpAndSettle();
        expect(find.text('Clear recent searches'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Clear listening history'),
          200,
        );
        await tester.pumpAndSettle();
        expect(find.text('Clear listening history'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Delete all app data'), 200);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete all app data'));
        await tester.pumpAndSettle();
        expect(find.text('Delete all Glyph data?'), findsOneWidget);
        expect(c.resets, 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(c.resets, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
