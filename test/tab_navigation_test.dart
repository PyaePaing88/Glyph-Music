import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/search/presentation/search_screen.dart';
import 'package:glyph_music/integrations/discovery_client.dart';

class RetryDiscovery extends DiscoveryClient {
  RetryDiscovery() : super(Dio());
  final queries = <String>[];

  @override
  Future<List<DiscoveryResult>> search(String query) async {
    queries.add(query);
    if (queries.length == 1) throw DiscoveryOfflineException();
    return const [DiscoveryResult('video', 'Online result', 'Artist', null)];
  }
}

class PendingDiscovery extends DiscoveryClient {
  PendingDiscovery() : super(Dio());
  final queries = <String>[];
  final responses = <Completer<List<DiscoveryResult>>>[];

  @override
  Future<List<DiscoveryResult>> search(String query) {
    queries.add(query);
    final response = Completer<List<DiscoveryResult>>();
    responses.add(response);
    return response.future;
  }
}

Future<void> finishSearch(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('swipes and tab taps stay in sync and preserve screen state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
    final c = AppController(
      LibraryRepository(db),
      audio,
      discovery: RetryDiscovery(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
    });
    await tester.pumpWidget(MaterialApp(home: GlyphShell(c: c)));
    await tester.pumpAndSettle();

    int selectedTab() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
    Future<void> swipe(double offset) async {
      await tester.drag(find.byType(PageView), Offset(offset, 0));
      await tester.pumpAndSettle();
    }

    expect(selectedTab(), 0);
    await swipe(-320);
    expect(selectedTab(), 1);
    expect(find.text('Local library'), findsNothing);
    await tester.enterText(
      find.byType(TextField).hitTestable(),
      'keep this query',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await finishSearch(tester);
    await swipe(-320);
    expect(selectedTab(), 2);
    await tester.tap(find.text('Artists').hitTestable());
    await tester.pumpAndSettle();
    await swipe(-320);
    expect(selectedTab(), 3);
    await swipe(-320);
    expect(selectedTab(), 3);
    await swipe(320);
    expect(selectedTab(), 2);
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'Artists').hitTestable(),
          )
          .selected,
      isTrue,
    );
    await swipe(320);
    expect(selectedTab(), 1);
    expect(
      tester
          .widget<TextField>(find.byType(TextField).hitTestable())
          .controller!
          .text,
      'keep this query',
    );
    await tester.tap(find.text('Home').hitTestable());
    await tester.pumpAndSettle();
    expect(selectedTab(), 0);
    await swipe(320);
    expect(selectedTab(), 0);
    await tester.tap(find.text('Playlists').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      allOf(greaterThan(0), lessThan(3)),
    );
    await tester.pumpAndSettle();
    expect(selectedTab(), 3);
    expect(find.byTooltip('Create playlist').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline search stays on YouTube and retries the same query', (
    tester,
  ) async {
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
    final discovery = RetryDiscovery();
    final c = AppController(LibraryRepository(db), audio, discovery: discovery);
    await tester.runAsync(() async {
      await c.repository.rememberSearch('local history', 'local');
      await c.repository.rememberSearch('youtube history', 'youtube');
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchScreen(c: c)),
      ),
    );
    await finishSearch(tester);
    expect(find.text('youtube history'), findsOneWidget);
    expect(find.text('local history'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).textAlign,
      TextAlign.left,
    );
    await tester.enterText(find.byType(TextField), 'a song');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await finishSearch(tester);
    expect(find.text('Discovery is taking a break'), findsOneWidget);
    expect(find.text('Search local music'), findsNothing);
    expect(find.textContaining('Showing your local library'), findsNothing);
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await finishSearch(tester);
    expect(discovery.queries, ['a song', 'a song']);
    expect(find.text('Online result'), findsOneWidget);
    expect(find.text('Discovery is taking a break'), findsNothing);
    expect(await tester.runAsync(() => c.repository.searches('local')), [
      'local history',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typing debounces searches, ignores old results, and clear cancels work',
    (tester) async {
      final db = MusicDatabase(NativeDatabase.memory());
      final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
      final discovery = PendingDiscovery();
      final c = AppController(
        LibraryRepository(db),
        audio,
        discovery: discovery,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          c.dispose();
          await audio.dispose();
          await db.close();
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SearchScreen(c: c)),
        ),
      );
      await finishSearch(tester);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'artist');
      await tester.pump(const Duration(milliseconds: 499));
      expect(discovery.queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(discovery.queries, ['artist']);

      await tester.enterText(find.byType(TextField), 'new song');
      discovery.responses[0].complete(const [
        DiscoveryResult('old', 'Old result', 'Artist', null),
      ]);
      await tester.pump();
      expect(find.text('Old result'), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(discovery.queries, ['artist', 'new song']);
      await tester.tap(find.byTooltip('Clear search'));
      discovery.responses[1].complete(const [
        DiscoveryResult('new', 'Late result', 'Artist', null),
      ]);
      await finishSearch(tester);
      expect(find.text('Late result'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.enterText(find.byType(TextField), 'cancel this');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump(const Duration(seconds: 1));
      expect(discovery.queries, ['artist', 'new song']);

      await tester.enterText(find.byType(TextField), 'centered');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      discovery.responses[2].complete([]);
      await tester.pumpAndSettle();
      final status = tester.getCenter(find.text('No videos found'));
      final screen = tester.getCenter(find.byType(SearchScreen));
      expect(status.dx, closeTo(screen.dx, 1));
      expect(find.widgetWithText(FilledButton, 'Search YouTube'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
