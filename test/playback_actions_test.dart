import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/core/widgets/design.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/library/domain/song.dart';
import 'package:glyph_music/features/playlists/presentation/playlists_screen.dart';

class RecordingAudio extends GlyphAudioHandler {
  final events = <String>[];
  int? loadedIndex;

  @override
  Future<void> load(
    List<Song> songs, {
    int index = 0,
    Duration position = Duration.zero,
    bool autoplay = true,
  }) async {
    events.add('load:$autoplay');
    loadedIndex = index;
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    events.add('shuffle:${mode.name}');
  }

  @override
  Future<void> play() async {
    events.add('play');
  }
}

class PlaylistActionController extends AppController {
  PlaylistActionController(super.repository, super.audio);
  bool? requestedShuffle;
  List<Song>? requestedTracks;
  @override
  Future<void> playSongs(
    List<Song> tracks, {
    int index = 0,
    bool? shuffle,
  }) async {
    requestedShuffle = shuffle;
    requestedTracks = tracks;
  }
}

List<Song> sampleSongs() => List.generate(
  5,
  (i) => Song(
    id: '$i',
    title: 'Track $i',
    artist: 'Artist',
    path: '/test/$i.mp3',
    hash: '$i',
    bytes: 100,
    createdAt: DateTime(2026),
  ),
);

void main() {
  testWidgets(
    'shuffle starts after enabling shuffle and preserves queue order',
    (tester) async {
      final db = MusicDatabase(NativeDatabase.memory());
      final audio = (await tester.runAsync(() async => RecordingAudio()))!;
      final c = AppController(LibraryRepository(db), audio);
      final songs = sampleSongs();
      c.songs = songs;
      await tester.runAsync(() => c.playSongs(songs, shuffle: true));
      expect(audio.events, ['load:false', 'shuffle:all', 'play']);
      expect(audio.loadedIndex, inInclusiveRange(0, songs.length - 1));
      expect(c.queueIds, songs.map((s) => s.id));
      audio.events.clear();
      await tester.runAsync(() => c.playSongs(songs, shuffle: false));
      expect(audio.events, ['load:false', 'shuffle:none', 'play']);
      expect(audio.loadedIndex, 0);
      await tester.runAsync(() async {
        c.dispose();
        await audio.dispose();
        await db.close();
      });
    },
  );

  testWidgets('media buttons wait for readiness and dispatch each action', (
    tester,
  ) async {
    final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
    final ready = Completer<void>();
    final actions = <String>[];
    audio.mediaButtonAction = (action) async {
      await ready.future;
      actions.add(action);
    };
    final pending = audio.click();
    await tester.pump();
    expect(actions, isEmpty);
    ready.complete();
    await pending;
    await audio.click(MediaButton.previous);
    await audio.click(MediaButton.next);
    expect(actions, ['play_pause', 'previous', 'next']);
    await tester.runAsync(audio.dispose);
  });

  testWidgets('playlist exposes shuffle and ordered play with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = MusicDatabase(NativeDatabase.memory());
    final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
    final c = PlaylistActionController(LibraryRepository(db), audio);
    c.songs = sampleSongs();
    final ids = c.songs.map((s) => s.id).toList();
    c.playlists = [MusicPlaylist(id: 'test', name: 'A playlist', songIds: ids)];
    await tester.pumpWidget(
      MaterialApp(
        theme: glyphTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: PlaylistDetail(c: c, id: 'test'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Shuffle play'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Shuffle play'));
    expect(c.requestedShuffle, isTrue);
    expect(c.requestedTracks, c.songs);
    await tester.ensureVisible(find.text('Play playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play playlist'));
    expect(c.requestedShuffle, isFalse);
    expect(c.playlists.single.songIds, ids);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await audio.dispose();
      await db.close();
    });
  });
}
