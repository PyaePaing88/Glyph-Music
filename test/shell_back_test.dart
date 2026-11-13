import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';

void main() {
  late MusicDatabase db;
  late GlyphAudioHandler audio;
  late AppController c;
  late List<String> platformCalls;

  Future<void> mount(WidgetTester tester, {double keyboardHeight = 0}) async {
    db = MusicDatabase(NativeDatabase.memory());
    audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
    c = AppController(LibraryRepository(db), audio);
    platformCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await tester.runAsync(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: EdgeInsets.only(bottom: keyboardHeight)),
          child: child!,
        ),
        home: GlyphShell(c: c),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('exit requires two Back presses within two seconds', (
    tester,
  ) async {
    await mount(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Press Back again to exit'), findsOneWidget);
    expect(
      platformCalls.where((call) => call == 'SystemNavigator.pop'),
      isEmpty,
    );

    await tester.pump(const Duration(milliseconds: 2100));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      platformCalls.where((call) => call == 'SystemNavigator.pop'),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      platformCalls.where((call) => call == 'SystemNavigator.pop'),
      hasLength(1),
    );
  });

  testWidgets(
    'changing tabs resets the exit prompt and detail routes pop normally',
    (tester) async {
      await mount(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.text('Library').hitTestable());
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        platformCalls.where((call) => call == 'SystemNavigator.pop'),
        isEmpty,
      );
      expect(find.text('Press Back again to exit'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      final shellContext = tester.element(find.byType(GlyphShell));
      Navigator.of(shellContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Detail screen')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Detail screen'), findsNothing);
      expect(
        platformCalls.where((call) => call == 'SystemNavigator.pop'),
        isEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press Back again to exit'), findsOneWidget);
      expect(
        platformCalls.where((call) => call == 'SystemNavigator.pop'),
        isEmpty,
      );
    },
  );

  testWidgets('Back with the keyboard visible does not arm app exit', (
    tester,
  ) async {
    await mount(tester, keyboardHeight: 240);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Press Back again to exit'), findsNothing);
    expect(
      platformCalls.where((call) => call == 'SystemNavigator.pop'),
      isEmpty,
    );
  });
}
