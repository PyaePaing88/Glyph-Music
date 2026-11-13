import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/core/widgets/design.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/library/domain/song.dart';
import 'package:glyph_music/features/search/presentation/search_screen.dart';
import 'package:glyph_music/features/library/presentation/library_screen.dart';
import 'package:glyph_music/features/playlists/presentation/playlists_screen.dart';
import 'package:glyph_music/integrations/discovery_client.dart';

void main() {
  for (final size in [const Size(320, 740), const Size(640, 360)]) {
    testWidgets(
      'YouTube results and download stay in app at $size with large text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        final launches = <Map<Object?, Object?>>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'launch') {
              launches.add(call.arguments as Map<Object?, Object?>);
            }
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final db = MusicDatabase(NativeDatabase.memory());
        final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
        final discovery = TestDiscovery();
        final c = DownloadTestController(
          LibraryRepository(db),
          audio,
          discovery,
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: glyphTheme(Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: key,
                  child: SearchScreen(c: c),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Local library'), findsNothing);
        const query = 'Björk & music #1 မြန်မာ';
        await tester.enterText(find.byType(TextField), query);
        expect(
          find.widgetWithText(FilledButton, 'Search YouTube'),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(launches, isEmpty);
        expect(discovery.queries, [query]);
        expect(await tester.runAsync(() => c.repository.searches('youtube')), [
          query,
        ]);
        expect(find.text('Discovery is taking a break'), findsNothing);
        final download = find.byKey(
          const ValueKey('youtube-download-test-video'),
        );
        await tester.scrollUntilVisible(
          download,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('First Light'), findsOneWidget);
        await tester.tap(download);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(c.requestedDownloads, ['test-video']);
        expect(c.songs.single.title, 'First Light');
        expect(find.text('Saved to Tracks'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(tester, key, 'search-${size.width.toInt()}');
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          c.dispose();
          await audio.dispose();
          await db.close();
        });
      },
    );
  }
  setUpAll(() async {
    if (!const bool.fromEnvironment('GLYPH_CAPTURE')) return;
    final sdk = Platform.environment['FLUTTER_ROOT'] ?? '.tools/flutter';
    final fonts = '$sdk/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'sans-serif': 'roboto-regular.ttf',
      'Roboto': 'roboto-regular.ttf',
      'monospace': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File('$fonts/${entry.value}')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await loader.load();
    }
  });
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'empty library navigation and playlist creation in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = MusicDatabase(NativeDatabase.memory());
        final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
        final c = AppController(
          LibraryRepository(db),
          audio,
          discovery: TestDiscovery(),
        )..theme = mode;
        final previewKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: previewKey,
            child: ProviderScope(
              overrides: [controllerProvider.overrideWithValue(c)],
              child: const GlyphApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Import music'), findsNothing);
        expect(find.text('TRACKS'), findsNothing);
        expect(find.text('ON YOUR DEVICE'), findsNothing);
        expect(find.byTooltip('Settings'), findsOneWidget);
        await capturePreview(tester, previewKey, 'home-${mode.name}');
        await tester.tap(find.text('Library'));
        await tester.pumpAndSettle();
        expect(find.text('A fresh start.'), findsOneWidget);
        await capturePreview(tester, previewKey, 'library-${mode.name}');
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'unknown');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        expect(find.text('First Light'), findsOneWidget);
        await tester.tap(find.text('Playlists'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Create playlist'));
        await tester.pumpAndSettle();
        final dialogContext = tester.element(find.byType(AlertDialog));
        final dialogTheme = Theme.of(dialogContext).dialogTheme;
        expect(
          dialogTheme.backgroundColor,
          Theme.of(dialogContext).colorScheme.surface,
        );
        expect(dialogTheme.surfaceTintColor, Colors.transparent);
        await tester.enterText(
          find.widgetWithText(TextField, 'Playlist name'),
          'Late nights',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        // SQLite runs outside the fake frame clock.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(c.playlists.single.name, 'Late nights');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          c.dispose();
          await audio.dispose();
          await db.close();
        });
      },
    );
  }
  testWidgets('widget play preserves an explicitly empty queue', (
    tester,
  ) async {
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
    final c = AppController(LibraryRepository(db), audio);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('glyph-empty-queue-'),
    ))!;
    final file = File('${directory.path}/track.mp3');
    await tester.runAsync(() => file.writeAsBytes([1, 2, 3]));
    c.songs = [
      Song(
        id: 'track',
        title: 'Track',
        artist: 'Artist',
        path: file.path,
        hash: 'hash',
        bytes: 3,
        createdAt: DateTime(2026),
      ),
    ];
    await tester.runAsync(() => c.widgetPlayback('play_pause'));
    expect(c.queueIds, isEmpty);
    expect(audio.mediaItem.value, isNull);
    expect(c.notice, contains('Choose a song'));
    await tester.runAsync(() async {
      c.dispose();
      await audio.dispose();
      await db.close();
      await directory.delete(recursive: true);
    });
  });
  testWidgets('dot headings and empty states support large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: glyphTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    DotTitle('YOUR MUSIC'),
                    EmptyCollection(
                      title: 'A fresh start.',
                      message: 'Import local music to begin listening.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'playlist metadata dialog and full-page track selection are separate',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = MusicDatabase(NativeDatabase.memory());
      final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
      final c = AppController(LibraryRepository(db), audio);
      await tester.runAsync(() async {
        for (final title in ['Blue hour', 'Morning song']) {
          await c.repository.addSong(
            Song(
              id: title,
              title: title,
              artist: 'Test artist',
              path: '/test/$title.mp3',
              hash: title,
              bytes: 100,
              createdAt: DateTime(2026),
            ),
          );
        }
        await c.refresh();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: glyphTheme(Brightness.light),
          home: Scaffold(
            body: LivePage(
              c: c,
              builder: (_) => PlaylistsScreen(c: c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Create playlist'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Find tracks to add'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Playlist name'),
        'My playlist',
      );
      await tester.tap(find.text('Save'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(c.playlists.single.songIds, isEmpty);
      await tester.ensureVisible(find.byTooltip('Add or remove tracks'));
      await tester.tap(find.byTooltip('Add or remove tracks'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PlaylistTracksPage), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.text('Blue hour'));
      await tester.tap(find.text('Morning song'));
      await tester.tap(find.text('Done'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(c.playlists.single.songIds, ['Blue hour', 'Morning song']);
      await tester.tap(find.byTooltip('Edit playlist'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Playlist name'),
        'Renamed playlist',
      );
      await tester.tap(find.text('Save'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(c.playlists.single.name, 'Renamed playlist');
      expect(c.playlists.single.songIds, ['Blue hour', 'Morning song']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
    },
  );
  for (final playlist in [false, true]) {
    testWidgets(
      'alphabet jumps in ${playlist ? 'playlist' : 'library'} track list',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = MusicDatabase(NativeDatabase.memory());
        final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
        final c = AppController(LibraryRepository(db), audio);
        c.songs = List.generate(
          80,
          (i) => Song(
            id: '$i',
            title: i == 40
                ? 'Blue hour'
                : i == 10
                ? 'Zebra'
                : 'A track $i',
            artist: 'Test artist',
            path: '/test/$i.mp3',
            hash: '$i',
            bytes: 100,
            createdAt: DateTime(2026),
          ),
        );
        final ids = c.songs.map((s) => s.id).toList();
        c.playlists = [
          MusicPlaylist(id: 'test', name: 'Custom order', songIds: ids),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: glyphTheme(Brightness.dark),
            home: playlist
                ? PlaylistDetail(c: c, id: 'test')
                : Scaffold(body: LibraryScreen(c: c)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('B'));
        await tester.pumpAndSettle();
        expect(find.text('Blue hour').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Track options for Blue hour'));
        await tester.pumpAndSettle();
        expect(find.text('Play next'), findsOneWidget);
        expect(find.byIcon(Icons.playlist_add), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Z'));
        await tester.pumpAndSettle();
        expect(find.text('Zebra').hitTestable(), findsOneWidget);
        expect(c.playlists.single.songIds, ids);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          c.dispose();
          await audio.dispose();
          await db.close();
        });
      },
    );
  }
  testWidgets('mini player opens now playing and favorite persists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
    final c = AppController(LibraryRepository(db), audio)
      ..theme = ThemeMode.dark;
    const id = 'preview-track';
    final song = Song(
      id: id,
      title: 'First Light',
      artist: 'The quiet hours',
      album: 'A personal rotation',
      path: '/preview/track.mp3',
      hash: 'preview-only',
      bytes: 4320000,
      durationMs: 180000,
      createdAt: DateTime(2026),
    );
    await tester.runAsync(() async {
      await c.repository.addSong(song);
      await c.refresh();
    });
    c.queueIds = [id];
    audio.mediaItem.add(
      const MediaItem(
        id: id,
        title: 'First Light',
        artist: 'The quiet hours',
        duration: Duration(minutes: 3),
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [controllerProvider.overrideWithValue(c)],
          child: const GlyphApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Previous track'), findsOneWidget);
    expect(
      tester.getCenter(find.byTooltip('Previous track')).dx,
      lessThan(tester.getCenter(find.byTooltip('Play')).dx),
    );
    await tester.tap(find.text('First Light'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open queue'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byTooltip('Favorite track'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(c.current!.favorite, isTrue);
    await capturePreview(tester, key, 'player-dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await audio.dispose();
      await db.close();
    });
  });
}

Future<void> capturePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (!const bool.fromEnvironment('GLYPH_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  boundary.markNeedsPaint();
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await Directory('docs/screenshots').create(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

class TestDiscovery extends DiscoveryClient {
  TestDiscovery() : super(Dio());
  final queries = <String>[];
  @override
  Future<List<DiscoveryResult>> search(String query) async {
    queries.add(query);
    return const [
      DiscoveryResult('test-video', 'First Light', 'The quiet hours', null),
    ];
  }
}

class DownloadTestController extends AppController {
  DownloadTestController(super.repository, super.audio, DiscoveryClient client)
    : super(discovery: client);
  final requestedDownloads = <String>[];
  @override
  Future<void> downloadYoutube(
    DiscoveryResult result, {
    DownloadJob? retry,
  }) async {
    requestedDownloads.add(result.id);
    await repository.addSong(
      Song(
        id: result.id,
        title: result.title,
        artist: result.channel,
        path: '/test/downloaded.m4a',
        hash: result.id,
        bytes: 1200,
        createdAt: DateTime(2026),
      ),
      source: 'youtube',
      sourceId: result.id,
      mimeType: 'audio/mp4',
    );
    await refresh();
  }
}
