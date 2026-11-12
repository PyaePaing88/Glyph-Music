import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_music/core/widgets/accent_colour.dart';
import 'package:glyph_music/core/widgets/design.dart';

void main() {
  test('saved custom colour is used in both themes with readable controls', () {
    for (final argb in [0xff2784c5, 0xff000000, 0xffffffff]) {
      final accent = AccentColour.fromSetting(argb);
      expect(accent.colour.toARGB32(), argb);
      for (final brightness in Brightness.values) {
        final theme = glyphTheme(brightness, accentColour: accent);
        expect(theme.colorScheme.secondary.toARGB32(), argb);
        expect(theme.colorScheme.onSecondary, accent.foreground);
        expect(theme.sliderTheme.thumbColor, accent.colour);
      }
    }
    expect(AccentColour.fromSetting(0xffffffff).foreground, Colors.black);
    expect(AccentColour.fromSetting(0xff000000).foreground, Colors.white);
  });

  test(
    'legacy orange settings and invalid saved colours have safe defaults',
    () {
      expect(
        AccentColour.fromSetting(null, legacyOrange: true),
        AccentColour.orange,
      );
      expect(AccentColour.fromSetting(null), AccentColour.red);
      expect(AccentColour.fromSetting('invalid'), AccentColour.red);
      expect(AccentColour.fromSetting(-1), AccentColour.red);
      expect(AccentColour.fromSetting(0x1ffffffff), AccentColour.red);
    },
  );
}
