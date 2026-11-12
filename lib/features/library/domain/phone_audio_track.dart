class PhoneAudioTrack {
  const PhoneAudioTrack({
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    required this.bytes,
    required this.durationMs,
    required this.modified,
    required this.added,
    required this.mimeType,
    this.artwork,
  });

  final String uri, title, artist, album, mimeType;
  final int bytes, durationMs, modified, added;
  final String? artwork;

  factory PhoneAudioTrack.fromMap(Map<Object?, Object?> row) => PhoneAudioTrack(
    uri: row['uri'] as String,
    title: row['title'] as String,
    artist: row['artist'] as String,
    album: row['album'] as String,
    bytes: (row['bytes'] as num).toInt(),
    durationMs: (row['durationMs'] as num).toInt(),
    modified: (row['modified'] as num).toInt(),
    added: (row['added'] as num).toInt(),
    mimeType: row['mimeType'] as String,
    artwork: row['artwork'] as String?,
  );
}
