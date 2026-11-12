import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/integrations/discovery_client.dart';

void main() {
  test('YouTube durations tolerate live and archived-live labels', () {
    expect(
      parseYoutubeDuration('3:42'),
      const Duration(minutes: 3, seconds: 42),
    );
    expect(
      parseYoutubeDuration('1:02:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(parseYoutubeDuration('Streamed'), isNull);
    expect(parseYoutubeDuration('LIVE'), isNull);
    expect(parseYoutubeDuration(''), isNull);
  });
}
