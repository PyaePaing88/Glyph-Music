import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Only passes the player's session ID; native code never captures global audio.
class GlyphVisualizer {
  static const channel = MethodChannel('glyph/visualizer');
  final status = ValueNotifier<String>('off');
  (int?, bool)? _lastPlayback;

  void initialize() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'status' && call.arguments is String) {
        status.value = call.arguments as String;
      }
    });
  }

  Future<bool> setEnabled(
    bool enabled, {
    bool requestPermission = false,
  }) async {
    try {
      return await channel.invokeMethod<bool>('setEnabled', {
            'enabled': enabled,
            'requestPermission': requestPermission,
          }) ??
          false;
    } on MissingPluginException {
      status.value = enabled ? 'unsupported' : 'off';
      return !enabled;
    } on PlatformException {
      status.value = 'unavailable';
      return !enabled;
    }
  }

  Future<void> updatePlayback(int? sessionId, bool playing) async {
    final state = (sessionId, playing);
    if (_lastPlayback == state) return;
    _lastPlayback = state;
    try {
      await channel.invokeMethod<void>('updatePlayback', {
        'sessionId': sessionId,
        'playing': playing,
      });
    } on MissingPluginException {
      // Other platforms continue to play normally.
    } on PlatformException {
      status.value = 'unavailable';
    }
  }

  Future<void> dispose() async {
    await setEnabled(false);
    channel.setMethodCallHandler(null);
    status.dispose();
  }
}
