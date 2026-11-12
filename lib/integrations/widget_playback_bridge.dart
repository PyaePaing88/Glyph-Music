import 'dart:io';

import 'package:flutter/services.dart';

import '../app/app_controller.dart';

class WidgetPlaybackBridge {
  static const channel = MethodChannel('glyph/widget_playback');
  static const backgroundChannel = MethodChannel('glyph/widget_background');

  static Future<void> bind(AppController controller) async {
    if (!Platform.isAndroid) return;
    // The service channel also exists when no activity has ever been opened.
    await bindChannel(controller, backgroundChannel, acknowledge: true);
    await bindChannel(controller, channel);
  }

  static Future<void> bindChannel(
    AppController controller,
    MethodChannel source, {
    bool acknowledge = false,
  }) async {
    var pending = Future<void>.value();
    Future<void> drain() {
      pending = pending.then((_) async {
        try {
          final actions =
              await source.invokeListMethod<String>('takeActions') ?? [];
          for (final action in actions) {
            await controller.widgetPlayback(action);
          }
          if (acknowledge) await source.invokeMethod<void>('actionsComplete');
        } on MissingPluginException {
          // A channel's native owner can be absent until its service or activity
          // is created. It will signal again when ready; commands stay queued.
        }
      });
      return pending;
    }

    source.setMethodCallHandler((call) async {
      if (call.method == 'available') await drain();
    });
    await drain();
  }
}
