import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/core/storage/music_importer.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('glyph-tags-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('reads UTF-8 ID3 title and MPEG Layer III bitrate', () async {
    final text = [3, ...utf8.encode('First Light')];
    final frame = [
      ...ascii.encode('TIT2'),
      0,
      0,
      0,
      text.length,
      0,
      0,
      ...text,
    ];
    final bytes = [
      ...ascii.encode('ID3'),
      3,
      0,
      0,
      0,
      0,
      0,
      frame.length,
      ...frame,
      255,
      251,
      144,
      0,
      ...List.filled(500, 0),
    ];
    final file = await File('${dir.path}/track.mp3').writeAsBytes(bytes);
    final tags = await readMp3Tags(file);
    expect(tags.title, 'First Light');
    expect(tags.bitrate, 128);
  });
  test('rejects a renamed non-MP3 and a truncated ID3 tag', () async {
    final html = await File('${dir.path}/fake.mp3')
        .writeAsString('<html>Not audio</html>');
    await expectLater(readMp3Tags(html), throwsFormatException);
    final broken = await File('${dir.path}/broken.mp3')
        .writeAsBytes([...ascii.encode('ID3'), 3, 0, 0, 0, 0, 1, 0]);
    await expectLater(readMp3Tags(broken), throwsFormatException);
  });
}
