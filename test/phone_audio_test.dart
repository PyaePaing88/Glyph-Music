import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';
import 'package:glyph_music/features/library/domain/phone_audio_track.dart';
import 'package:glyph_music/features/library/domain/song.dart';

PhoneAudioTrack phoneTrack(
  int id, {
  String title = 'Recording',
  int bytes = 100,
}) => PhoneAudioTrack(
  uri: 'content://media/external/audio/media/$id',
  title: title,
  artist: 'Artist',
  album: 'Album',
  bytes: bytes,
  durationMs: 1200,
  modified: 1234,
  added: 1200,
  mimeType: 'audio/mp4',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MusicDatabase db;
  late LibraryRepository repository;
  setUp(() {
    db = MusicDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });
  tearDown(() => db.close());

  test('repeated snapshots deduplicate and preserve user metadata and playlist membership', () async {
    expect(
      await repository.syncPhoneAudio([
        phoneTrack(1),
        phoneTrack(2),
        phoneTrack(1),
      ]),
      2,
    );
    final original = (await repository.songs()).first;
    await repository.edit(
      original,
      'My title',
      'My artist',
      'My album',
      'Voice',
      null,
    );
    await repository.favorite(original);
    await repository.savePlaylist('p', 'Recordings', '', [original.id]);
    expect(
      await repository.syncPhoneAudio([
        phoneTrack(1, title: 'Source changed', bytes: 110),
        phoneTrack(2),
      ]),
      0,
    );
    final updated = (await repository.songs()).singleWhere(
      (s) => s.id == original.id,
    );
    expect(updated.title, 'My title');
    expect(updated.artist, 'My artist');
    expect(updated.favorite, isTrue);
    expect((await repository.playlists()).single.songIds, [original.id]);
    expect(updated.bytes, 110);
    expect(updated.audioUri.scheme, 'content');
    expect(updated.isAvailable, isTrue);
  });

  test('removed phone files are pruned without touching imported or downloaded tracks', () async {
    await repository.syncPhoneAudio([phoneTrack(1), phoneTrack(2)]);
    await repository.addSong(
      Song(
        id: 'private',
        title: 'Managed',
        artist: 'Artist',
        path: '/app/music/file.mp3',
        hash: 'private-hash',
        bytes: 50,
        createdAt: DateTime(2026),
      ),
    );
    await repository.syncPhoneAudio([phoneTrack(2)]);
    expect(
      (await repository.songs()).map((s) => s.path),
      unorderedEquals([phoneTrack(2).uri, '/app/music/file.mp3']),
    );
    await repository.syncPhoneAudio([]);
    expect((await repository.songs()).single.id, 'private');
  });

  test(
    'new installation uses a separate device identity for metadata backups',
    () async {
      await repository.syncPhoneAudio([phoneTrack(1)]);
      final oldHash = (await repository.songs()).single.hash;
      await repository.syncPhoneAudio([]);
      await repository.setSetting('phone_audio_namespace', 'other-install');
      await repository.syncPhoneAudio([phoneTrack(1)]);
      expect((await repository.songs()).single.hash, isNot(oldHash));
    },
  );
}
