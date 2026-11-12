import 'package:dio/dio.dart';

class AudioVariant {
  const AudioVariant(this.url, this.bitrate);
  final Uri url;
  final int bitrate;
}

class CatalogTrack {
  const CatalogTrack(
    this.id,
    this.title,
    this.artist,
    this.license,
    this.variants,
  );
  final String id, title, artist;
  final Uri license;
  final List<AudioVariant> variants;
}

/// A configured provider must explicitly authorize downloads for every item.
/// Only original MP3 variants actually offered by that provider are selectable.
class AuthorizedCatalog {
  static const endpoint = String.fromEnvironment('AUTHORIZED_CATALOG_ENDPOINT');
  static bool get configured => Uri.tryParse(endpoint)?.scheme == 'https';
  static List<CatalogTrack> parse(Map<String, dynamic> data) {
    final tracks = <CatalogTrack>[];
    for (final value in data['tracks'] as List? ?? []) {
      final item = value as Map<String, dynamic>;
      if (item['downloadAllowed'] != true) continue;
      final license = Uri.tryParse(item['licenseUrl'] as String? ?? '');
      if (license == null ||
          license.scheme != 'https' ||
          license.host.isEmpty) {
        continue;
      }
      final original = item['originalBitrateKbps'] as int?;
      final variants = <AudioVariant>[];
      for (final value in item['variants'] as List? ?? []) {
        final v = value as Map<String, dynamic>;
        final url = Uri.tryParse(v['url'] as String? ?? '');
        final rate = v['bitrateKbps'] as int?;
        if (url == null ||
            url.scheme != 'https' ||
            url.host.isEmpty ||
            v['mimeType'] != 'audio/mpeg' ||
            ![128, 192, 256, 320].contains(rate)) {
          continue;
        }
        if (original != null && rate! > original) continue;
        variants.add(AudioVariant(url, rate!));
      }
      variants.sort((a, b) => a.bitrate.compareTo(b.bitrate));
      if (variants.isNotEmpty) {
        tracks.add(
          CatalogTrack(
            item['id'] as String,
            item['title'] as String,
            item['artist'] as String? ?? 'Unknown artist',
            license,
            variants,
          ),
        );
      }
    }
    return tracks;
  }

  Future<List<CatalogTrack>> search(String query) async {
    if (!configured) {
      throw StateError(
        'No authorized catalog is configured. You can still add a permitted direct MP3 link.',
      );
    }
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    try {
      final response = await client.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: {'q': query},
      );
      return parse(response.data ?? {});
    } finally {
      client.close();
    }
  }
}
