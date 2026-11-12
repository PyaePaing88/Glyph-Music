import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/music_database.dart';
import '../domain/song.dart';
import '../domain/phone_audio_track.dart';

class LibraryRepository {
  LibraryRepository(this.db);
  final MusicDatabase db;
  static const uuid = Uuid();
  Future<List<Song>> songs() async =>
      (await db.rows('SELECT * FROM songs ORDER BY title COLLATE NOCASE'))
          .map(Song.fromJson)
          .toList();
  Future<void> addSong(
    Song song, {
    String source = 'import',
    String? sourceId,
    String mimeType = 'audio/mpeg',
  }) async {
    final values = {
      ...song.toJson(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'source_type': source,
      'source_id': sourceId,
      'mime_type': mimeType,
    };
    await db.customStatement(
      'INSERT INTO songs (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
      values.values.toList(),
    );
  }

  /// A complete, permission-granted MediaStore snapshot. Failed/denied scans
  /// never call this method, so they cannot erase the device library.
  Future<int> syncPhoneAudio(List<PhoneAudioTrack> tracks) async {
    var added = 0;
    await db.transaction(() async {
      final namespace =
          await setting('phone_audio_namespace') as String? ?? uuid.v4();
      await setSetting('phone_audio_namespace', namespace);
      final existing = {
        for (final row in await db.rows(
          "SELECT id,source_id FROM songs WHERE source_type='device'",
        ))
          row['source_id'] as String: row['id'] as String,
      };
      final seen = <String>{};
      for (final track in tracks) {
        if (!track.uri.startsWith('content://media/') || !seen.add(track.uri)) {
          continue;
        }
        final id = existing[track.uri];
        // MediaStore identity is namespaced to this installation. It isn't a
        // byte hash: scanning does not reread/copy the user's entire storage.
        final hash =
            'device:$namespace:${track.uri}:${track.bytes}:${track.modified}';
        if (id == null) {
          await addSong(
            Song(
              id: uuid.v4(),
              title: track.title,
              artist: track.artist,
              album: track.album,
              path: track.uri,
              hash: hash,
              bytes: track.bytes,
              durationMs: track.durationMs,
              createdAt: track.added > 0
                  ? DateTime.fromMillisecondsSinceEpoch(track.added * 1000)
                  : DateTime.now(),
              artwork: track.artwork,
            ),
            source: 'device',
            sourceId: track.uri,
            mimeType: track.mimeType,
          );
          added++;
        } else {
          // Preserve edited tags, favorites, listening history and playlist IDs.
          await db.customStatement(
            'UPDATE songs SET local_path=?,file_size_bytes=?,duration_ms=?,content_hash=?,mime_type=?,artwork_path=COALESCE(artwork_path,?),updated_at=? WHERE id=?',
            [
              track.uri,
              track.bytes,
              track.durationMs,
              hash,
              track.mimeType,
              track.artwork,
              DateTime.now().millisecondsSinceEpoch,
              id,
            ],
          );
        }
      }
      for (final entry in existing.entries) {
        if (!seen.contains(entry.key)) await delete(entry.value);
      }
    });
    return added;
  }

  Future<bool> hasSource(String source, String id) async => (await db.rows(
    'SELECT id FROM songs WHERE source_type = ? AND source_id = ? LIMIT 1',
    [Variable(source), Variable(id)],
  )).isNotEmpty;

  Future<Set<String>> youtubeSourceIds() async => (await db.rows(
    "SELECT source_id FROM songs WHERE source_type = 'youtube' AND source_id IS NOT NULL",
  )).map((row) => row['source_id'] as String).toSet();

  Future<bool> containsHash(String hash) async => (await db.rows(
    'SELECT id FROM songs WHERE content_hash = ?',
    [Variable(hash)],
  )).isNotEmpty;
  Future<void> favorite(Song song) => db.customStatement(
    'UPDATE songs SET is_favorite = ?, updated_at = ? WHERE id = ?',
    [song.favorite ? 0 : 1, DateTime.now().millisecondsSinceEpoch, song.id],
  );
  Future<void> edit(
    Song song,
    String title,
    String artist,
    String album,
    String genre,
    String? artwork,
  ) => db.customStatement(
    'UPDATE songs SET title=?, artist=?, album=?, genre=?, artwork_path=?, updated_at=? WHERE id=?',
    [
      title,
      artist,
      album,
      genre,
      artwork,
      DateTime.now().millisecondsSinceEpoch,
      song.id,
    ],
  );
  Future<void> duration(String id, int ms) =>
      db.customStatement('UPDATE songs SET duration_ms=? WHERE id=?', [ms, id]);
  Future<void> delete(String id) =>
      db.customStatement('DELETE FROM songs WHERE id=?', [id]);
  Future<void> recordPlay(String id, int listenedMs) => db.transaction(
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.customStatement('INSERT INTO play_history VALUES (?, ?, ?, ?)', [
        uuid.v4(),
        id,
        now,
        listenedMs,
      ]);
      await db.customStatement(
        'UPDATE songs SET play_count=play_count+1, last_played_at=? WHERE id=?',
        [now, id],
      );
    },
  );
  Future<List<MusicPlaylist>> playlists() async {
    final records = await db.rows(
      'SELECT * FROM playlists ORDER BY sort_order, created_at',
    );
    final members = await db.rows(
      'SELECT * FROM playlist_songs ORDER BY sort_order',
    );
    return records
        .map(
          (r) => MusicPlaylist(
            id: r['id'] as String,
            name: r['name'] as String,
            description: r['description'] as String,
            artwork: r['artwork_path'] as String?,
            songIds: members
                .where((m) => m['playlist_id'] == r['id'])
                .map((m) => m['song_id'] as String)
                .toList(),
          ),
        )
        .toList();
  }

  Future<void> savePlaylist(
    String id,
    String name,
    String description,
    List<String> ids, {
    String? artwork,
  }) => db.transaction(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.customStatement(
      'INSERT INTO playlists(id,name,description,artwork_path,created_at,updated_at) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, description=excluded.description, artwork_path=excluded.artwork_path, updated_at=excluded.updated_at',
      [id, name, description, artwork, now, now],
    );
    await db.customStatement('DELETE FROM playlist_songs WHERE playlist_id=?', [
      id,
    ]);
    for (final (i, songId) in ids.toSet().indexed) {
      await db.customStatement('INSERT INTO playlist_songs VALUES(?,?,?,?,?)', [
        uuid.v4(),
        id,
        songId,
        i,
        now,
      ]);
    }
  });
  Future<void> deletePlaylist(String id) =>
      db.customStatement('DELETE FROM playlists WHERE id=?', [id]);
  Future<void> reorderPlaylists(List<String> ids) => db.transaction(() async {
    for (final (i, id) in ids.indexed) {
      await db.customStatement('UPDATE playlists SET sort_order=? WHERE id=?', [
        i,
        id,
      ]);
    }
  });
  Future<void> setSetting(String key, dynamic value) => db.customStatement(
    'INSERT INTO app_settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, jsonEncode(value)],
  );
  Future<dynamic> setting(String key) async {
    final r = await db.rows('SELECT value FROM app_settings WHERE key=?', [
      Variable(key),
    ]);
    return r.isEmpty ? null : jsonDecode(r.first['value'] as String);
  }

  Future<List<String>> searches(String scope) async => (await db.rows(
    'SELECT query FROM search_history WHERE scope=? ORDER BY searched_at DESC LIMIT 12',
    [Variable(scope)],
  )).map((r) => r['query'] as String).toList();
  Future<void> rememberSearch(String query, String scope) async {
    if (query.trim().isEmpty) return;
    await db.customStatement(
      'INSERT INTO search_history VALUES(?,?,?,?) ON CONFLICT(query,scope) DO UPDATE SET searched_at=excluded.searched_at',
      [uuid.v4(), query.trim(), scope, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> clearSearches() =>
      db.customStatement('DELETE FROM search_history');
  Future<void> clearHistory() => db.transaction(() async {
    await db.customStatement('DELETE FROM play_history');
    await db.customStatement(
      'UPDATE songs SET play_count=0,last_played_at=NULL',
    );
  });
  Future<Map<String, dynamic>> backup() async {
    final hashesById = {for (final song in await songs()) song.id: song.hash};
    final collections = await playlists();
    return {
      'format': 'glyph-metadata',
      'version': 1,
      'songs': await db.rows(
        'SELECT content_hash,title,artist,album,genre,is_favorite FROM songs',
      ),
      'playlists': [
        for (final pl in collections)
          {
            'name': pl.name,
            'description': pl.description,
            'hashes': [
              for (final id in pl.songIds)
                if (hashesById.containsKey(id)) hashesById[id],
            ],
          },
      ],
      'settings': await db.rows(
        "SELECT * FROM app_settings WHERE key IN ('theme','quality','accent','accentColour','sleepMinutes')",
      ),
    };
  }

  Future<int> restore(Map<String, dynamic> data) async {
    if (data['format'] != 'glyph-metadata' || data['version'] != 1) {
      throw const FormatException('Unsupported Glyph backup');
    }
    final local = await songs();
    final byHash = {for (final s in local) s.hash: s};
    var matched = 0;
    await db.transaction(() async {
      for (final value in data['songs'] as List) {
        final m = value as Map<String, dynamic>;
        final s = byHash[m['content_hash']];
        if (s == null) continue;
        await db.customStatement(
          'UPDATE songs SET title=?,artist=?,album=?,genre=?,is_favorite=? WHERE id=?',
          [
            m['title'],
            m['artist'],
            m['album'],
            m['genre'],
            m['is_favorite'],
            s.id,
          ],
        );
        matched++;
      }
      for (final value in data['playlists'] as List) {
        final pl = value as Map<String, dynamic>;
        await savePlaylist(
          uuid.v4(),
          pl['name'] as String,
          pl['description'] as String? ?? '',
          (pl['hashes'] as List)
              .where(byHash.containsKey)
              .map((h) => byHash[h]!.id)
              .toList(),
        );
      }
      for (final value in data['settings'] as List) {
        final s = value as Map<String, dynamic>;
        if ([
          'theme',
          'quality',
          'accent',
          'accentColour',
          'sleepMinutes',
        ].contains(s['key'])) {
          await setSetting(
            s['key'] as String,
            jsonDecode(s['value'] as String),
          );
        }
      }
    });
    return matched;
  }
}
