import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// SQL is explicit here so schema and foreign-key behavior remain reviewable.
// Drift still supplies asynchronous SQLite execution and transactions.
class MusicDatabase extends GeneratedDatabase {
  MusicDatabase(super.executor);
  static Future<MusicDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    return MusicDatabase(
      NativeDatabase.createInBackground(File(p.join(dir.path, 'glyph.sqlite'))),
    );
  }

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final sql in schema) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
  static const schema = [
    '''CREATE TABLE songs (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT NOT NULL,
      album TEXT NOT NULL DEFAULT '', genre TEXT NOT NULL DEFAULT '',
      duration_ms INTEGER NOT NULL DEFAULT 0, local_path TEXT NOT NULL,
      artwork_path TEXT, content_hash TEXT NOT NULL UNIQUE,
      mime_type TEXT NOT NULL DEFAULT 'audio/mpeg', bitrate_kbps INTEGER,
      file_size_bytes INTEGER NOT NULL, source_type TEXT NOT NULL DEFAULT 'import',
      source_id TEXT, is_favorite INTEGER NOT NULL DEFAULT 0,
      play_count INTEGER NOT NULL DEFAULT 0, last_played_at INTEGER,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    'CREATE INDEX songs_title ON songs(title COLLATE NOCASE)',
    'CREATE INDEX songs_artist ON songs(artist COLLATE NOCASE)',
    'CREATE INDEX songs_album ON songs(album COLLATE NOCASE)',
    'CREATE INDEX songs_recent ON songs(last_played_at)',
    '''CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '', artwork_path TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    '''CREATE TABLE playlist_songs (id TEXT PRIMARY KEY,
      playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
      song_id TEXT NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
      sort_order INTEGER NOT NULL, added_at INTEGER NOT NULL,
      UNIQUE(playlist_id, song_id))''',
    'CREATE INDEX playlist_order ON playlist_songs(playlist_id, sort_order)',
    '''CREATE TABLE play_history (id TEXT PRIMARY KEY,
      song_id TEXT NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
      played_at INTEGER NOT NULL, listened_ms INTEGER NOT NULL)''',
    '''CREATE TABLE downloads (id TEXT PRIMARY KEY, source_type TEXT NOT NULL,
      source_id TEXT, display_name TEXT NOT NULL, destination_path TEXT NOT NULL,
      status TEXT NOT NULL, progress REAL NOT NULL DEFAULT 0, total_bytes INTEGER,
      error_message TEXT, created_at INTEGER NOT NULL, completed_at INTEGER)''',
    '''CREATE TABLE search_history (id TEXT PRIMARY KEY, query TEXT NOT NULL,
      scope TEXT NOT NULL, searched_at INTEGER NOT NULL, UNIQUE(query, scope))''',
    'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ];
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Variable> args = const [],
  ]) async => (await customSelect(
    sql,
    variables: args,
  ).get()).map((r) => r.data).toList();
}
