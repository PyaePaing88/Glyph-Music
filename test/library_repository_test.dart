import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/library/domain/song.dart';

Song track(
  String id, {
  String title = 'Track',
  String artist = 'Artist',
  String album = 'Album',
  String genre = 'Ambient',
}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: album,
  genre: genre,
  path: '/music/$id.mp3',
  hash: 'hash-$id',
  bytes: 100,
  durationMs: 60000,
  createdAt: DateTime(2026),
);

void main() {
  // Independent executors are intentional in these persistence tests.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MusicDatabase db;
  late LibraryRepository repo;
  setUp(() {
    db = MusicDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });
  tearDown(() async => db.close());

  test('playlist order persists, duplicate membership is removed, deletion cascades', () async {
    await repo.addSong(track('a'));
    await repo.addSong(track('b'));
    await repo.savePlaylist('p', 'Morning', 'Slow start', ['b', 'a', 'b']);
    expect((await repo.playlists()).single.songIds, ['b', 'a']);
    await repo.savePlaylist('p', 'Evening', 'Quiet', ['a', 'b']);
    expect((await repo.playlists()).single.songIds, ['a', 'b']);
    await repo.delete('a');
    expect((await repo.playlists()).single.songIds, ['b']);
    await repo.deletePlaylist('p');
    expect((await repo.songs()).single.id, 'b');
  });

  test(
    'invalid playlist transaction rolls back without destroying old order',
    () async {
      await repo.addSong(track('a'));
      await repo.savePlaylist('p', 'Keep me', '', ['a']);
      await expectLater(
        repo.savePlaylist('p', 'Broken', '', ['missing']),
        throwsA(anything),
      );
      final pl = (await repo.playlists()).single;
      expect(pl.name, 'Keep me');
      expect(pl.songIds, ['a']);
    },
  );

  test('stable content hash prevents duplicate audio records', () async {
    await repo.addSong(track('a'));
    expect(await repo.containsHash('hash-a'), isTrue);
    await expectLater(repo.addSong(track('a')), throwsA(anything));
    expect(await repo.songs(), hasLength(1));
  });

  test(
    'metadata backup restores ordered playlists and flags by content hash',
    () async {
      await repo.addSong(track('a'));
      await repo.addSong(track('b'));
      await repo.favorite((await repo.songs()).firstWhere((s) => s.id == 'a'));
      await repo.savePlaylist('p', 'Rotation', 'A description', ['b', 'a']);
      await repo.setSetting('theme', 'dark');
      await repo.setSetting('accentColour', 0xff2784c5);
      final backup = await repo.backup();
      await repo.setSetting('accentColour', 0xff000000);
      await repo.deletePlaylist('p');
      await repo.favorite((await repo.songs()).firstWhere((s) => s.id == 'a'));
      expect(await repo.restore(backup), 2);
      expect((await repo.playlists()).single.songIds, ['b', 'a']);
      expect(
        (await repo.songs()).firstWhere((s) => s.id == 'a').favorite,
        isTrue,
      );
      expect(await repo.setting('theme'), 'dark');
      expect(await repo.setting('accentColour'), 0xff2784c5);
    },
  );

  test(
    'favorites, queue settings, and history survive a database reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'glyph-persistence-',
      );
      final file = File('${directory.path}/test.sqlite');
      var persistent = MusicDatabase(NativeDatabase(file));
      var repository = LibraryRepository(persistent);
      await repository.addSong(track('a'));
      await repository.favorite((await repository.songs()).single);
      await repository.recordPlay('a', 30000);
      await repository.setSetting('playback', {
        'ids': ['a'],
        'position': 1234,
      });
      await persistent.close();
      persistent = MusicDatabase(NativeDatabase(file));
      repository = LibraryRepository(persistent);
      expect((await repository.songs()).single.favorite, isTrue);
      expect((await repository.songs()).single.playCount, 1);
      expect((await repository.setting('playback'))['position'], 1234);
      await repository.clearHistory();
      expect((await repository.songs()).single.lastPlayed, isNull);
      await persistent.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'local search matches multiple words across title, artist, album and genre',
    () {
      final songs = [
        track('a', title: 'First Light', artist: 'Nora', album: 'Open Sky'),
        track('b', title: 'Night Drive', artist: 'Nora'),
      ];
      expect(searchSongs(songs, '  NORA light ').map((s) => s.id), ['a']);
      expect(searchSongs(songs, 'sky ambient').map((s) => s.id), ['a']);
      expect(searchSongs(songs, 'missing'), isEmpty);
      expect(searchSongs(songs, ''), hasLength(2));
    },
  );

  test('10,000 track collection returns the correct offline result', () {
    final songs = List.generate(
      10000,
      (i) => track('$i', title: 'Song $i', artist: 'Artist ${i % 100}'),
    );
    expect(searchSongs(songs, 'Song 9999 Artist 99').single.id, '9999');
  });
}
