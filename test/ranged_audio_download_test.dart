import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/integrations/ranged_audio_download.dart';

class RangeAdapter implements HttpClientAdapter {
  RangeAdapter(this.respond);
  final ResponseBody Function(RequestOptions, int) respond;
  int requests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options, requests++);
  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late File target;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('glyph-range-test-');
    target = File('${directory.path}/audio.m4a');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('joins exact byte ranges without duplicating audio', () async {
    final bytes = List<int>.generate(600000, (i) => i % 251);
    final adapter = RangeAdapter((request, _) {
      final range = RegExp(r'bytes=(\d+)-(\d+)')
          .firstMatch(request.headers['range'] as String)!;
      final start = int.parse(range[1]!), end = int.parse(range[2]!);
      expect(
        end - start + 1,
        lessThanOrEqualTo(RangedAudioDownload.chunkBytes),
      );
      return ResponseBody.fromBytes(
        bytes.sublist(start, end + 1),
        206,
        headers: {
          'content-range': ['bytes $start-$end/${bytes.length}'],
        },
      );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    var progress = 0.0;
    await RangedAudioDownload(client: dio).save(
      Uri.parse('https://audio.example/test'),
      target,
      totalBytes: bytes.length,
      maxBytes: 1000000,
      token: CancelToken(),
      onProgress: (value) => progress = value,
    );
    expect(await target.readAsBytes(), bytes);
    expect(adapter.requests, 3);
    expect(progress, 1);
    dio.close();
  });

  test(
    'rejects repeated or incorrect ranges and removes the partial file',
    () async {
      final adapter = RangeAdapter(
        (request, index) => ResponseBody.fromBytes(
          List.filled(RangedAudioDownload.chunkBytes, 1),
          206,
          headers: {
            'content-range': [
              'bytes 0-${RangedAudioDownload.chunkBytes - 1}/600000',
            ],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      await expectLater(
        RangedAudioDownload(client: dio).save(
          Uri.parse('https://audio.example/test'),
          target,
          totalBytes: 600000,
          maxBytes: 1000000,
          token: CancelToken(),
          onProgress: (_) {},
        ),
        throwsFormatException,
      );
      expect(adapter.requests, 2);
      expect(await target.exists(), false);
      dio.close();
    },
  );

  test('rejects redirects to insecure audio sources', () async {
    final adapter = RangeAdapter(
      (request, index) => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['http://audio.example/unsafe'],
        },
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    await expectLater(
      RangedAudioDownload(client: dio).save(
        Uri.parse('https://audio.example/test'),
        target,
        totalBytes: 100,
        maxBytes: 1000000,
        token: CancelToken(),
        onProgress: (_) {},
      ),
      throwsFormatException,
    );
    expect(adapter.requests, 1);
    expect(await target.exists(), false);
    dio.close();
  });

  test('cancel does not leave a partial audio file', () async {
    final token = CancelToken();
    final adapter = RangeAdapter((request, index) {
      token.cancel();
      return ResponseBody.fromBytes(
        List.filled(100, 1),
        206,
        headers: {
          'content-range': ['bytes 0-99/100'],
        },
      );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    await expectLater(
      RangedAudioDownload(client: dio).save(
        Uri.parse('https://audio.example/test'),
        target,
        totalBytes: 100,
        maxBytes: 1000000,
        token: token,
        onProgress: (_) {},
      ),
      throwsA(isA<DioException>()),
    );
    expect(await target.exists(), false);
    dio.close();
  });
}
