import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/core/widgets/design.dart';
import 'package:glyph_music/features/player/presentation/playback_seek_bar.dart';

void main() {
  for (final compact in [false, true]) {
    testWidgets(
      'scrubbing previews smoothly and seeks once (compact=$compact)',
      (tester) async {
        final positions = StreamController<Duration>.broadcast(sync: true);
        var actual = const Duration(seconds: 30);
        final seeks = <Duration>[];
        final completeSeek = Completer<void>();
        var openedPlayer = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: glyphTheme(Brightness.dark),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: InkWell(
                    onTap: () => openedPlayer++,
                    child: PlaybackSeekBar(
                      compact: compact,
                      positions: positions.stream,
                      readPosition: () => actual,
                      duration: const Duration(minutes: 2),
                      onSeek: (target) async {
                        seeks.add(target);
                        await completeSeek.future;
                        actual = target;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(Slider));
        final gesture = await tester.startGesture(
          Offset(rect.center.dx, rect.center.dy),
        );
        await gesture.moveBy(const Offset(35, 0));
        await tester.pump();
        final preview = tester.widget<Slider>(find.byType(Slider)).value;
        expect(preview, greaterThan(30000));
        expect(seeks, isEmpty);
        positions.add(const Duration(seconds: 31));
        await tester.pump();
        expect(tester.widget<Slider>(find.byType(Slider)).value, preview);
        await gesture.up();
        await tester.pump();
        expect(seeks, hasLength(1));
        positions.add(const Duration(seconds: 32));
        await tester.pump();
        expect(tester.widget<Slider>(find.byType(Slider)).value, preview);
        expect(openedPlayer, 0);
        completeSeek.complete();
        await tester.pumpAndSettle();
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          closeTo(seeks.single.inMilliseconds.toDouble(), 1),
        );
        positions.add(actual + const Duration(seconds: 1));
        await tester.pump();
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          seeks.single.inMilliseconds + 1000,
        );
        // Tapping the seek track also must not open the surrounding mini-player.
        await tester.tapAt(Offset(rect.left + rect.width * .3, rect.center.dy));
        await tester.pumpAndSettle();
        expect(seeks, hasLength(2));
        expect(openedPlayer, 0);
        await tester.pumpWidget(const SizedBox());
        await positions.close();
      },
    );
  }

  testWidgets('disabled duration and overrun positions stay in range', (
    tester,
  ) async {
    final positions = StreamController<Duration>.broadcast(sync: true);
    Widget view(Duration duration) => MaterialApp(
      home: Scaffold(
        body: PlaybackSeekBar(
          positions: positions.stream,
          readPosition: () => const Duration(minutes: 3),
          duration: duration,
          onSeek: (_) async {},
        ),
      ),
    );
    await tester.pumpWidget(view(Duration.zero));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    await tester.pumpWidget(view(const Duration(minutes: 2)));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 120000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await positions.close();
  });

  testWidgets('changing tracks discards an unfinished drag and pending seek', (
    tester,
  ) async {
    final positions = StreamController<Duration>.broadcast(sync: true);
    final seekFinished = Completer<void>();
    Widget view(String id, Duration position) => MaterialApp(
      home: Scaffold(
        body: PlaybackSeekBar(
          key: ValueKey(id),
          positions: positions.stream,
          readPosition: () => position,
          duration: const Duration(minutes: 2),
          onSeek: (_) => seekFinished.future,
        ),
      ),
    );
    await tester.pumpWidget(view('first', const Duration(seconds: 30)));
    await tester.tap(find.byType(Slider));
    await tester.pump();
    await tester.pumpWidget(view('second', const Duration(seconds: 5)));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 5000);
    seekFinished.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 5000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await positions.close();
  });
}
