import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Uri youtubeSearchUri(String query) =>
    Uri.https('www.youtube.com', '/results', {'search_query': query.trim()});

class DiscoveryOfflineException extends StateError {
  DiscoveryOfflineException()
    : super('No connection. Showing your local library instead.');
}

class DiscoveryResult {
  const DiscoveryResult(
    this.id,
    this.title,
    this.channel,
    this.thumbnail, {
    this.duration,
  });
  final String id, title, channel;
  final String? thumbnail;
  final Duration? duration;
}

class DiscoveryClient {
  DiscoveryClient(this.dio);
  final Dio dio;
  static const endpoint = String.fromEnvironment('YOUTUBE_DISCOVERY_ENDPOINT');
  bool get configured => Uri.tryParse(endpoint)?.scheme == 'https';
  Future<DiscoveryResult> details(String id) async {
    final client = YoutubeExplode();
    try {
      final video = await client.videos
          .get(id)
          .timeout(const Duration(seconds: 30));
      return DiscoveryResult(
        video.id.value,
        video.title,
        video.author,
        video.thumbnails.mediumResUrl,
        duration: video.duration,
      );
    } finally {
      client.close();
    }
  }

  Future<List<DiscoveryResult>> search(String query) async {
    if (!configured) {
      final client = YoutubeExplode();
      try {
        final videos = await client.search
            .searchContent(query.trim(), filter: TypeFilters.video)
            .timeout(const Duration(seconds: 30));
        return videos
            .whereType<SearchVideo>()
            .where((v) => !v.isLive)
            .take(20)
            .map(
              (v) => DiscoveryResult(
                v.id.value,
                v.title,
                v.author,
                ThumbnailSet(v.id.value).mediumResUrl,
                duration: parseYoutubeDuration(v.duration),
              ),
            )
            .toList();
      } catch (_) {
        throw StateError(
          'YouTube search is unavailable. Check your connection and try again.',
        );
      } finally {
        client.close();
      }
    }
    try {
      final response = await dio.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: {'q': query, 'maxResults': 20},
      );
      final items = response.data?['items'] as List? ?? [];
      return items.map((value) {
        final item = value as Map<String, dynamic>;
        final snippet = item['snippet'] as Map<String, dynamic>;
        return DiscoveryResult(
          (item['id'] as Map)['videoId'] as String,
          snippet['title'] as String,
          snippet['channelTitle'] as String,
          ((snippet['thumbnails'] as Map?)?['medium'] as Map?)?['url']
              as String?,
        );
      }).toList();
    } on DioException catch (e) {
      if ([
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
      ].contains(e.type)) {
        throw DiscoveryOfflineException();
      }
      if (e.response?.statusCode == 403 || e.response?.statusCode == 429) {
        throw StateError(
          'Discovery quota reached. Try again later; local music still works.',
        );
      }
      throw StateError(
        'Discovery is unavailable. Check your connection or search your local library.',
      );
    }
  }
}

Duration? parseYoutubeDuration(String value) {
  final parts = value.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  var seconds = 0;
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0) return null;
    seconds = seconds * 60 + number;
  }
  return Duration(seconds: seconds);
}
