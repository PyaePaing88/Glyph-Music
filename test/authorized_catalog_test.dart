import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/integrations/authorized_catalog.dart';

void main() {
  test('catalog exposes only permitted, HTTPS, original MP3 variants', () {
    Map<String, dynamic> variant(
      int kbps, {
      String scheme = 'https',
      String mime = 'audio/mpeg',
    }) => {
      'url': '$scheme://audio.example.test/track-$kbps.mp3',
      'bitrateKbps': kbps,
      'mimeType': mime,
    };
    final result = AuthorizedCatalog.parse({
      'tracks': [
        {
          'id': 'ok',
          'title': 'Original',
          'downloadAllowed': true,
          'licenseUrl': 'https://example.test/license',
          'originalBitrateKbps': 192,
          'variants': [
            variant(320),
            variant(192),
            variant(128, scheme: 'http'),
            variant(128, mime: 'text/html'),
            variant(128),
          ],
        },
        {
          'id': 'no',
          'title': 'No permission',
          'downloadAllowed': false,
          'variants': [variant(192)],
        },
        {
          'id': 'missing-license',
          'title': 'No license',
          'downloadAllowed': true,
          'variants': [variant(192)],
        },
      ],
    });
    expect(result.single.id, 'ok');
    expect(result.single.variants.map((v) => v.bitrate), [128, 192]);
  });
}
