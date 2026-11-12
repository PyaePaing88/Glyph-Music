import 'dart:io';

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    required this.hash,
    required this.bytes,
    this.album = '',
    this.genre = '',
    this.durationMs = 0,
    this.favorite = false,
    this.playCount = 0,
    this.lastPlayed,
    required this.createdAt,
    this.artwork,
    this.bitrate,
  });
  final String id, title, artist, album, genre, path, hash;
  final String? artwork;
  final int bytes, durationMs, playCount;
  final int? bitrate;
  final bool favorite;
  final DateTime createdAt;
  final DateTime? lastPlayed;
  bool get isOnPhone => path.startsWith('content://media/');
  Uri get audioUri => isOnPhone ? Uri.parse(path) : Uri.file(path);
  bool get isAvailable => isOnPhone || File(path).existsSync();
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'genre': genre,
    'local_path': path,
    'content_hash': hash,
    'file_size_bytes': bytes,
    'duration_ms': durationMs,
    'is_favorite': favorite ? 1 : 0,
    'play_count': playCount,
    'created_at': createdAt.millisecondsSinceEpoch,
    'last_played_at': lastPlayed?.millisecondsSinceEpoch,
    'artwork_path': artwork,
    'bitrate_kbps': bitrate,
  };
  factory Song.fromJson(Map<String, dynamic> j) => Song(
    id: j['id'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String,
    album: j['album'] as String? ?? '',
    genre: j['genre'] as String? ?? '',
    path: j['local_path'] as String,
    hash: j['content_hash'] as String,
    bytes: j['file_size_bytes'] as int,
    durationMs: j['duration_ms'] as int? ?? 0,
    favorite: j['is_favorite'] == 1,
    playCount: j['play_count'] as int? ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['created_at'] as int),
    lastPlayed: j['last_played_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(j['last_played_at'] as int),
    artwork: j['artwork_path'] as String?,
    bitrate: j['bitrate_kbps'] as int?,
  );
}

class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    this.artwork,
    this.songIds = const [],
  });
  final String id, name, description;
  final String? artwork;
  final List<String> songIds;
}

List<Song> searchSongs(List<Song> songs, String query) {
  final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
  return songs.where((s) {
    final text = '${s.title} ${s.artist} ${s.album} ${s.genre}'.toLowerCase();
    return words.every(text.contains);
  }).toList();
}
