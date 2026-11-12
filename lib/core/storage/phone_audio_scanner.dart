import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/library/domain/phone_audio_track.dart';

class PhoneAudioScan {
  const PhoneAudioScan(this.access, [this.tracks = const []]);
  final String access;
  final List<PhoneAudioTrack> tracks;
}

class PhoneAudioScanner {
  static const channel = MethodChannel('glyph/phone_audio');

  Future<PhoneAudioScan> scan({bool requestPermission = false}) async {
    if (!Platform.isAndroid) return const PhoneAudioScan('unsupported');
    var access = await channel.invokeMethod<String>('access') ?? 'denied';
    if (access == 'denied' && requestPermission) {
      access = await channel.invokeMethod<String>('requestAccess') ?? 'denied';
    }
    if (access != 'granted') return PhoneAudioScan(access);
    final rows = await channel.invokeListMethod<Object?>('scan');
    if (rows == null) throw StateError('Phone audio index was unavailable.');
    return PhoneAudioScan('granted', [
      for (final row in rows)
        PhoneAudioTrack.fromMap(row! as Map<Object?, Object?>),
    ]);
  }

  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');
}
