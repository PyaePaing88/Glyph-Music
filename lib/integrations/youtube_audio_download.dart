import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/storage/music_importer.dart';
import '../features/library/domain/song.dart';
import 'discovery_client.dart';
import 'ranged_audio_download.dart';
import 'youtube_stream_client.dart';

/// Saves the offered audio bytes in their original container; no MP3 transcode.
class YoutubeAudioDownload {
  void _checkCanceled(CancelToken token) {
    if (token.isCancelled) throw token.cancelError!;
  }

  Future<Song?> save(
    DiscoveryResult result,
    MusicImporter importer, {
    required CancelToken token,
    required void Function(double) onProgress,
    required void Function() onValidating,
    int targetBitrate = 192,
  }) async {
    final client = YoutubeExplode();
    File? temp;
    unawaited(token.whenCancel.then((_) => client.close()));
    try {
      if (await importer.repository.hasSource('youtube', result.id)) {
        return null;
      }
      final manifest = await client.videos.streams
          .getManifest(result.id, ytClients: [glyphYoutubeClient])
          .timeout(const Duration(seconds: 45));
      _checkCanceled(token);
      final offered = manifest.audioOnly
          .where((s) => ['mp4', 'webm'].contains(s.container.name))
          .toList();
      if (offered.isEmpty) {
        throw StateError('No downloadable audio is available for this video.');
      }
      final preferred = offered.any((s) => s.container.name == 'mp4')
          ? 'mp4'
          : 'webm';
      final compatible = offered
          .where((s) => s.container.name == preferred)
          .toList();
      final underLimit = compatible
          .where((s) => s.bitrate.kiloBitsPerSecond <= targetBitrate)
          .toList();
      final choices = underLimit.isEmpty ? compatible : underLimit;
      choices.sort(
        (a, b) => underLimit.isEmpty
            ? a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond)
            : b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
      );
      final stream = choices.first;
      final total = stream.size.totalBytes;
      await importer.checkSpace(total, copies: 2);
      final extension = stream.container.name == 'mp4' ? 'm4a' : 'webm';
      temp = File(
        p.join(
          (await getTemporaryDirectory()).path,
          '${const Uuid().v4()}.$extension',
        ),
      );
      await RangedAudioDownload().save(
        stream.url,
        temp,
        totalBytes: total,
        maxBytes: MusicImporter.maxBytes,
        token: token,
        headers: YoutubeHttpClient.defaultHeaders,
        onProgress: onProgress,
      );
      _checkCanceled(token);
      onValidating();
      final cover = await _cover(result.thumbnail);
      _checkCanceled(token);
      return await importer.importDownloadedAudio(
        temp,
        videoId: result.id,
        title: result.title,
        artist: result.channel,
        extension: extension,
        bitrate: stream.bitrate.kiloBitsPerSecond.round(),
        cover: cover,
        isCanceled: () => token.isCancelled,
      );
    } on DioException catch (error) {
      if (!token.isCancelled &&
          [403, 410].contains(error.response?.statusCode)) {
        throw StateError(
          'YouTube declined this audio download. Try another result or retry later.',
        );
      }
      rethrow;
    } on FormatException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } catch (_) {
      _checkCanceled(token);
      throw StateError(
        'YouTube could not provide this audio. It may be restricted or temporarily unavailable. Try another result.',
      );
    } finally {
      if (temp != null && await temp.exists()) await temp.delete();
      client.close();
    }
  }

  Future<Uint8List?> _cover(String? url) async {
    if (url == null || Uri.tryParse(url)?.scheme != 'https') return null;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    try {
      final response = await dio.get<ResponseBody>(
        url,
        options: Options(responseType: ResponseType.stream),
      );
      final bytes = BytesBuilder();
      await for (final chunk in response.data!.stream) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) return null;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      return null;
    } finally {
      dio.close(force: true);
    }
  }
}
