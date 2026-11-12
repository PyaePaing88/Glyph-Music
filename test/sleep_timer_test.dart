import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/audio/sleep_timer.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/core/widgets/design.dart';
import 'package:glyph_music/features/home/presentation/home_screen.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/settings/presentation/settings_screen.dart';

class SleepAudio extends GlyphAudioHandler {
  int stops = 0;
  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  test('sleep duration labels', () {
    expect(sleepDurationLabel(60), '1 hour');
    expect(sleepDurationLabel(1), '1 minute');
    expect(sleepDurationLabel(90), '1 hour 30 minutes');
    expect(sleepCountdown(const Duration(hours: 1)), '1:00:00');
  });

  testWidgets('deadline stops once, independently of visible widgets', (
    tester,
  ) async {
    var now = DateTime(2026);
    var stops = 0;
    final timer = SleepTimer(
      now: () => now,
      onExpired: () async {
        stops++;
      },
    );
    addTearDown(timer.dispose);
    timer.start(const Duration(minutes: 1));
    now = now.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 59));
    expect(stops, 0);
    expect(timer.remaining, const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(stops, 1);
    expect(timer.active, isFalse);
    await tester.pump(const Duration(minutes: 1));
    expect(stops, 1);
  });

  testWidgets('cancel and restart cannot fire an old timer', (tester) async {
    var now = DateTime(2026);
    var stops = 0;
    final timer = SleepTimer(
      now: () => now,
      onExpired: () async {
        stops++;
      },
    );
    addTearDown(timer.dispose);
    timer.start(const Duration(seconds: 10));
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    timer.start(const Duration(seconds: 20));
    now = now.add(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 7));
    expect(stops, 0);
    expect(timer.active, isTrue);
    timer.cancel();
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(stops, 0);
  });

  testWidgets(
    'restores the original deadline and handles expired saved timers',
    (tester) async {
      var now = DateTime(2026);
      var stops = 0;
      final timer = SleepTimer(
        now: () => now,
        onExpired: () async {
          stops++;
        },
      );
      addTearDown(timer.dispose);
      final deadline = now.add(const Duration(seconds: 40));
      await timer.restore(deadline);
      expect(timer.deadline, deadline);
      now = now.add(const Duration(seconds: 40));
      await tester.pump(const Duration(seconds: 40));
      expect(stops, 1);
      await timer.restore(now.subtract(const Duration(seconds: 1)));
      expect(timer.active, isFalse);
      expect(stops, 2);
    },
  );

  testWidgets('checks overdue deadlines when the clock advances', (
    tester,
  ) async {
    var now = DateTime(2026);
    var stops = 0;
    final timer = SleepTimer(
      now: () => now,
      onExpired: () async {
        stops++;
      },
    );
    addTearDown(timer.dispose);
    timer.start(const Duration(hours: 1));
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(stops, 1);
  });

  testWidgets(
    'one hour default is persisted, expiry stops playback and clears mode',
    (tester) async {
      final db = MusicDatabase(NativeDatabase.memory());
      final audio = (await tester.runAsync(() async => SleepAudio()))!;
      final c = AppController(LibraryRepository(db), audio);
      addTearDown(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
      expect(c.sleepMinutes, 60);
      final beforeStart = DateTime.now();
      await tester.runAsync(() => c.setSleepMode(true));
      final afterStart = DateTime.now();
      expect(
        c.sleepTimer.deadline!.isBefore(
          beforeStart.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
      expect(
        c.sleepTimer.deadline!.isAfter(
          afterStart.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
      expect(
        await tester.runAsync(() => c.repository.setting('sleepDeadline')),
        c.sleepTimer.deadline!.millisecondsSinceEpoch,
      );
      final savedDeadline = c.sleepTimer.deadline;
      c.sleepTimer.cancel();
      await tester.runAsync(c.initialize);
      expect(c.sleepTimer.active, isTrue);
      expect(
        c.sleepTimer.deadline!.millisecondsSinceEpoch,
        savedDeadline!.millisecondsSinceEpoch,
      );
      final oldDeadline = c.sleepTimer.deadline!;
      await tester.runAsync(() => c.setSleepMinutes(90));
      expect(c.sleepTimer.deadline!.isAfter(oldDeadline), isTrue);
      c.sleepTimer.start(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(audio.stops, 1);
      expect(c.sleepTimer.active, isFalse);
      expect(
        await tester.runAsync(() => c.repository.setting('sleepDeadline')),
        isNull,
      );
      final backup = await tester.runAsync(c.repository.backup);
      final settings = backup!['settings'] as List;
      expect(settings.any((dynamic s) => s['key'] == 'sleepMinutes'), isTrue);
      expect(settings.any((dynamic s) => s['key'] == 'sleepDeadline'), isFalse);
    },
  );

  testWidgets('Home switches Sleep mode on and off with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => SleepAudio()))!;
    final c = AppController(LibraryRepository(db), audio);
    addTearDown(() async {
      c.dispose();
      await audio.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: glyphTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: HomeScreen(c: c, onLibrary: () {}, onSearch: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep mode'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(c.sleepTimer.active, isTrue);
    expect(find.textContaining('Stops in'), findsOneWidget);
    await tester.tap(find.text('Sleep mode'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(c.sleepTimer.active, isFalse);
    expect(audio.stops, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Settings saves preset and custom sleep durations', (
    tester,
  ) async {
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => SleepAudio()))!;
    final c = AppController(LibraryRepository(db), audio);
    addTearDown(() async {
      c.dispose();
      await audio.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: glyphTheme(Brightness.dark),
        home: SettingsScreen(c: c),
      ),
    );
    await tester.tap(find.text('Sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 minutes'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(c.sleepMinutes, 15);
    await tester.tap(find.text('Sleep timer'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom duration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 720 minutes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '75');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(c.sleepMinutes, 75);
    expect(
      await tester.runAsync(() => c.repository.setting('sleepMinutes')),
      75,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
