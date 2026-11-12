import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/app/app_controller.dart';
import 'package:glyph_music/integrations/widget_playback_bridge.dart';

class _PlaybackController implements AppController {
  final actions = <String>[];
  Completer<void>? firstAction;

  @override
  Future<void> widgetPlayback(String action) async {
    actions.add(action);
    if (actions.length == 1) await firstAction?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('glyph/test_widget_background');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(source, null);
    source.setMethodCallHandler(null);
  });

  Future<void> signal() async {
    final complete = Completer<void>();
    await messenger.handlePlatformMessage(
      source.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('available'),
      ),
      (_) => complete.complete(),
    );
    await complete.future;
  }

  test(
    'cold service commands run in order before startup is acknowledged',
    () async {
      final controller = _PlaybackController();
      final events = <String>[];
      messenger.setMockMethodCallHandler(source, (call) async {
        events.add(call.method);
        if (call.method == 'takeActions') return ['play_pause', 'next'];
        if (call.method == 'actionsComplete') {
          expect(controller.actions, ['play_pause', 'next']);
        }
        return null;
      });
      await WidgetPlaybackBridge.bindChannel(
        controller,
        source,
        acknowledge: true,
      );
      expect(events, ['takeActions', 'actionsComplete']);
    },
  );

  test(
    'service created after app startup can deliver queued commands',
    () async {
      final controller = _PlaybackController();
      await WidgetPlaybackBridge.bindChannel(
        controller,
        source,
        acknowledge: true,
      );
      var acknowledged = false;
      messenger.setMockMethodCallHandler(source, (call) async {
        if (call.method == 'takeActions') return ['play_pause'];
        if (call.method == 'actionsComplete') acknowledged = true;
        return null;
      });
      await signal();
      expect(controller.actions, ['play_pause']);
      expect(acknowledged, isTrue);
    },
  );

  test('a second widget tap waits for the first command to finish', () async {
    final controller = _PlaybackController()..firstAction = Completer<void>();
    var reads = 0;
    messenger.setMockMethodCallHandler(source, (call) async {
      if (call.method == 'takeActions') {
        reads++;
        return [reads == 1 ? 'play_pause' : 'next'];
      }
      return null;
    });
    final binding = WidgetPlaybackBridge.bindChannel(
      controller,
      source,
      acknowledge: true,
    );
    await Future<void>.delayed(Duration.zero);
    final second = signal();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    controller.firstAction!.complete();
    await binding;
    await second;
    expect(controller.actions, ['play_pause', 'next']);
  });
}
