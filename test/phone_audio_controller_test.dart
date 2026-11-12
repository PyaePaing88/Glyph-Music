import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/core/audio/glyph_audio_handler.dart';
import 'package:glyph_music/core/database/music_database.dart';
import 'package:glyph_music/core/storage/phone_audio_scanner.dart';
import 'package:glyph_music/features/library/data/library_repository.dart';

import 'phone_audio_test.dart' show phoneTrack;

class TestPhoneScanner extends PhoneAudioScanner {
  PhoneAudioScan response = const PhoneAudioScan('denied');
  bool fail = false;
  final permissionRequests = <bool>[];
  @override
  Future<PhoneAudioScan> scan({bool requestPermission = false}) async {
    permissionRequests.add(requestPermission);
    if (fail) throw StateError('Audio index temporarily unavailable');
    return response;
  }
}

void main() {
  testWidgets(
    'startup asks once; denied or failed scans preserve the existing phone library',
    (tester) async {
      final database = MusicDatabase(NativeDatabase.memory());
      final audio = (await tester.runAsync(() async => GlyphAudioHandler()))!;
      final scanner = TestPhoneScanner();
      final controller = AppController(
        LibraryRepository(database),
        audio,
        phoneScanner: scanner,
      );
      await tester.runAsync(() async {
        await controller.scanPhoneAudio(
          requestPermission: true,
          automatic: true,
        );
        await controller.scanPhoneAudio(
          requestPermission: true,
          automatic: true,
        );
        expect(scanner.permissionRequests, [true, false]);
        expect(controller.phoneAudioAccess, 'denied');
        scanner.response = PhoneAudioScan('granted', [phoneTrack(1)]);
        await controller.scanPhoneAudio(requestPermission: true);
        expect(controller.songs, hasLength(1));
        expect(controller.songs.single.audioUri.scheme, 'content');
        expect(controller.scanningPhone, isFalse);
        scanner.response = const PhoneAudioScan('denied');
        await controller.scanPhoneAudio(automatic: true);
        expect(controller.songs, hasLength(1));
        scanner.fail = true;
        await controller.scanPhoneAudio(automatic: true);
        expect(controller.phoneScanError, contains('temporarily unavailable'));
        expect(controller.songs, hasLength(1));
        expect(await controller.repository.songs(), hasLength(1));
        expect(controller.scanningPhone, isFalse);
        controller.dispose();
        await audio.dispose();
        await database.close();
      });
    },
  );
}
