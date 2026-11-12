import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/core/widgets/alphabet_track_browser.dart';
import 'package:glyph_music/core/widgets/design.dart';

void main() {
  test('index includes numbers and non-Latin titles under #', () {
    expect(trackInitial('  blue hour'), 'B');
    expect(trackInitial('123'), '#');
    expect(trackInitial('မြန်မာ'), '#');
    expect(trackInitial(''), '#');
  });

  for (final size in [const Size(390, 844), const Size(640, 360)]) {
    testWidgets('jumps through a long custom order at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final labels = List.generate(200, (i) => 'A track $i');
      labels[75] = 'Blue hour';
      labels[40] = 'Zebra';
      labels[160] = '123';
      late ScrollController scroll;
      await tester.pumpWidget(
        MaterialApp(
          theme: glyphTheme(Brightness.dark),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: AlphabetTrackBrowser(
                labels: labels,
                builder: (controller, headerKey, extent) {
                  scroll = controller;
                  return CustomScrollView(
                    controller: controller,
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(key: headerKey, height: 240),
                      ),
                      SliverFixedExtentList.builder(
                        itemExtent: extent,
                        itemCount: labels.length,
                        itemBuilder: (_, i) => Text(labels[i]),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 240 + 75 * 160);
      expect(find.text('Blue hour'), findsOneWidget);
      await tester.tap(find.text('Z'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 240 + 40 * 160);
      expect(find.text('Zebra'), findsOneWidget);
      final before = scroll.offset;
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      expect(scroll.offset, before);
      await tester.tap(find.text('#'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 240 + 160 * 160);
      expect(find.text('123'), findsOneWidget);
      await tester.dragFrom(
        tester.getCenter(find.text('B')),
        tester.getCenter(find.text('Z')) - tester.getCenter(find.text('B')),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, 240 + 40 * 160);
      expect(tester.takeException(), isNull);
    });
  }
}
