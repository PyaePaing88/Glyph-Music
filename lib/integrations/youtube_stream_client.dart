import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Compatibility client proposed upstream in youtube_explode_dart PR #389.
// Keep this local until the library publishes the client in a stable release.
const glyphYoutubeClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'osName': 'visionOS',
      'osVersion': '26.5.23O471',
      'userAgent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
    },
  },
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');
