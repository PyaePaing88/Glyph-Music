import 'package:flutter/material.dart';

class AccentColour {
  const AccentColour(this.colour);

  static const red = AccentColour(Color(0xffd71920));
  static const orange = AccentColour(Color(0xffff5722));
  final Color colour;

  String get label =>
      '#${(colour.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Color get foreground =>
      colour.computeLuminance() > 0.179 ? Colors.black : Colors.white;

  static AccentColour fromSetting(Object? value, {bool legacyOrange = false}) {
    if (value is int && value >= 0 && value <= 0xffffffff) {
      return AccentColour(Color(value | 0xff000000));
    }
    return legacyOrange ? orange : red;
  }
}
