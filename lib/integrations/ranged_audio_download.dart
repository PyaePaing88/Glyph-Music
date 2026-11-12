import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';

/// Copies an exact-sized audio resource with bounded, validated HTTP ranges.
class RangedAudioDownload {
  RangedAudioDownload({Dio? client}) : _provided = client;
  final Dio? _provided;
  static const chunkBytes = 256 * 1024;

  Future<void> save(
    Uri uri,
    File target, {
    required int totalBytes,
    required int maxBytes,
    required CancelToken token,
    required void Function(double) onProgress,
    Map<String, String> headers = const {},
  }) async {
    if (totalBytes <= 0 || totalBytes > maxBytes) {
      throw const FormatException('The audio file exceeds the download limit.');
    }
    final client =
        _provided ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
    IOSink? sink;
    var complete = false;
    try {
      if (token.isCancelled) throw token.cancelError!;
      sink = target.openWrite();
      var received = 0;
      var location = uri;
      var lastUpdate = DateTime.now();
      while (received < totalBytes) {
        if (token.isCancelled) throw token.cancelError!;
        final start = received;
        final end = math.min(start + chunkBytes, totalBytes) - 1;
        Response<ResponseBody>? response;
        for (var redirects = 0; redirects < 6; redirects++) {
          if (location.scheme != 'https' ||
              location.host.isEmpty ||
              location.userInfo.isNotEmpty) {
            throw const FormatException(
              'The audio source is not a secure download.',
            );
          }
          response = await client.getUri<ResponseBody>(
            location,
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: false,
              headers: {...headers, 'range': 'bytes=$start-$end'},
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ),
            cancelToken: token,
          );
          if (response.statusCode! < 300) break;
          final next = response.headers.value('location');
          await response.data!.stream.drain<void>();
          if (next == null) {
            throw const FormatException('Invalid audio source redirect.');
          }
          location = location.resolve(next);
        }
        if (response == null || response.statusCode! >= 300) {
          throw const FormatException(
            'Too many audio source redirects. Please retry.',
          );
        }
        var responseEnd = totalBytes - 1;
        if (response.statusCode == 206) {
          final range = RegExp(
            r'^bytes (\d+)-(\d+)/(\d+)$',
            caseSensitive: false,
          ).firstMatch(response.headers.value('content-range') ?? '');
          if (range == null ||
              int.parse(range[1]!) != start ||
              int.parse(range[3]!) != totalBytes ||
              int.parse(range[2]!) > end ||
              int.parse(range[2]!) < start) {
            throw const FormatException(
              'The audio source returned an invalid byte range.',
            );
          }
          responseEnd = int.parse(range[2]!);
        } else if (response.statusCode != 200 || start != 0) {
          throw const FormatException(
            'The audio source does not support a complete download.',
          );
        }
        await for (final chunk in response.data!.stream) {
          if (token.isCancelled) throw token.cancelError!;
          received += chunk.length;
          if (received > responseEnd + 1 || received > maxBytes) {
            throw const FormatException(
              'The audio download exceeds its expected size.',
            );
          }
          sink.add(chunk);
          if (DateTime.now().difference(lastUpdate).inMilliseconds >= 250) {
            onProgress(received / totalBytes);
            lastUpdate = DateTime.now();
          }
        }
        if (received != responseEnd + 1) {
          throw const FormatException(
            'The download was incomplete. Please retry.',
          );
        }
        await sink.flush();
      }
      if (token.isCancelled) throw token.cancelError!;
      await sink.close();
      sink = null;
      complete = true;
      onProgress(1);
    } finally {
      try {
        await sink?.close();
      } finally {
        if (!complete && await target.exists()) await target.delete();
        if (_provided == null) client.close(force: true);
      }
    }
  }
}
