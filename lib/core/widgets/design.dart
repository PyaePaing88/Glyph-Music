import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accent_colour.dart';

const glyphRed = Color(0xffd71920);

/// Wait for the dialog's exit animation before its field controllers are freed.
Future<T?> showGlyphDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context).push<T>(route);
  await route.completed;
  return result;
}

ThemeData glyphTheme(
  Brightness brightness, {
  AccentColour accentColour = AccentColour.red,
}) {
  final dark = brightness == Brightness.dark;
  final bg = Color(dark ? 0xff101010 : 0xfff5f5f3);
  final fg = Color(dark ? 0xfff5f5f5 : 0xff111111);
  final secondary = Color(dark ? 0xffaaaaaa : 0xff666666);
  final border = Color(dark ? 0xff333333 : 0xffd8d8d8);
  final red = accentColour.colour;
  final scheme = ColorScheme.fromSeed(seedColor: red, brightness: brightness)
      .copyWith(
        primary: fg,
        primaryContainer: fg,
        onPrimaryContainer: bg,
        secondaryContainer: Color(dark ? 0xff1c1c1c : 0xffffffff),
        onSecondaryContainer: fg,
        onPrimary: bg,
        secondary: red,
        onSecondary: accentColour.foreground,
        surface: Color(dark ? 0xff1c1c1c : 0xffffffff),
        onSurface: fg,
        onSurfaceVariant: secondary,
        outline: border,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      textStyle: TextStyle(color: fg, fontSize: 14),
    ),
    dividerColor: border,
    fontFamily: 'sans-serif',
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w500,
        letterSpacing: -1.5,
        color: fg,
      ),
      headlineSmall: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.8,
        color: fg,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w500,
        color: fg,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: fg,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: fg),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: secondary),
      labelSmall: TextStyle(
        fontSize: 10,
        letterSpacing: 1.5,
        color: secondary,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: fg),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: fg,
        foregroundColor: bg,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: border),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
      selectedColor: fg,
      labelStyle: TextStyle(fontSize: 12, color: fg, fontFamily: 'sans-serif'),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: fg,
      inactiveTrackColor: border,
      thumbColor: red,
      trackHeight: 2,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: fg,
      contentTextStyle: TextStyle(color: bg),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      indicatorColor: scheme.surface,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, color: fg),
      ),
    ),
  );
}

String clockTime(Duration duration) {
  final total = duration.inSeconds.clamp(0, 359999);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

String fileSize(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
  );
}

class DotTitle extends StatelessWidget {
  const DotTitle(this.text, {super.key, this.height = 30, this.color});
  final String text;
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    return Semantics(
      label: text,
      header: true,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CustomPaint(
            size: Size(text.length * height * 6 / 7, height * scale),
            painter: _DotPainter(
              text,
              color ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.text, this.color);
  final String text;
  final Color color;
  static const glyphs = {
    'A': ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
    'B': ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
    'C': ['01111', '10000', '10000', '10000', '10000', '10000', '01111'],
    'D': ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
    'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    'F': ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
    'G': ['01111', '10000', '10000', '10111', '10001', '10001', '01111'],
    'H': ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
    'I': ['11111', '00100', '00100', '00100', '00100', '00100', '11111'],
    'J': ['00111', '00010', '00010', '00010', '10010', '10010', '01100'],
    'K': ['10001', '10010', '10100', '11000', '10100', '10010', '10001'],
    'L': ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
    'M': ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
    'N': ['10001', '11001', '10101', '10011', '10001', '10001', '10001'],
    'O': ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
    'P': ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
    'Q': ['01110', '10001', '10001', '10001', '10101', '10010', '01101'],
    'R': ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
    'S': ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
    'T': ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
    'U': ['10001', '10001', '10001', '10001', '10001', '10001', '01110'],
    'V': ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
    'W': ['10001', '10001', '10001', '10101', '10101', '11011', '10001'],
    'X': ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
    'Y': ['10001', '10001', '01010', '00100', '00100', '00100', '00100'],
    'Z': ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
    '.': ['00000', '00000', '00000', '00000', '00000', '00100', '00100'],
    ' ': ['00000', '00000', '00000', '00000', '00000', '00000', '00000'],
  };
  @override
  void paint(Canvas canvas, Size size) {
    final step = math.min(size.height / 7, size.width / (text.length * 6));
    final paint = Paint()..color = color;
    for (final (i, c) in text.toUpperCase().split('').indexed) {
      final pattern = glyphs[c] ?? glyphs['.']!;
      for (var y = 0; y < 7; y++) {
        for (var x = 0; x < 5; x++) {
          if (pattern[y][x] == '1') {
            canvas.drawCircle(
              Offset((i * 6 + x + .5) * step, (y + .5) * step),
              step * .31,
              paint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.text != text || old.color != color;
}

class RecordArt extends StatefulWidget {
  const RecordArt({
    super.key,
    this.path,
    this.size = 100,
    this.playing = false,
    this.seed = 0,
  });
  final String? path;
  final double size;
  final bool playing;
  final int seed;
  @override
  State<RecordArt> createState() => _RecordArtState();
}

class _RecordArtState extends State<RecordArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  @override
  void initState() {
    super.initState();
    if (widget.playing) rotation.repeat();
  }

  @override
  void didUpdateWidget(RecordArt old) {
    super.didUpdateWidget(old);
    widget.playing ? rotation.repeat() : rotation.stop();
  }

  @override
  void dispose() {
    rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final art = ClipRRect(
      borderRadius: BorderRadius.circular(widget.size > 150 ? 28 : 12),
      child: SizedBox.square(
        dimension: widget.size,
        child: widget.path != null
            ? Image.file(
                File(widget.path!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    CustomPaint(painter: _RecordPainter(widget.seed)),
              )
            : CustomPaint(painter: _RecordPainter(widget.seed)),
      ),
    );
    return RepaintBoundary(
      child: widget.playing && !reduce
          ? AnimatedBuilder(
              animation: rotation,
              builder: (_, child) => Transform.rotate(
                angle: rotation.value * math.pi * 2,
                child: ClipOval(child: child),
              ),
              child: art,
            )
          : art,
    );
  }
}

class _RecordPainter extends CustomPainter {
  _RecordPainter(this.seed);
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    canvas.drawRect(
      rect,
      Paint()..color = Color(seed.isEven ? 0xff252525 : 0xff353331),
    );
    for (var x = 8.0; x < size.width; x += 12) {
      for (var y = 8.0; y < size.height; y += 12) {
        canvas.drawCircle(
          Offset(x, y),
          .65,
          Paint()..color = Colors.white.withValues(alpha: .1),
        );
      }
    }
    canvas.drawCircle(
      center,
      size.width * .43,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff101010), Color(0xff4a4a4a), Color(0xff111111)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    final groove = Paint()
      ..color = Colors.white.withValues(alpha: .13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6;
    for (
      var radius = size.width * .17;
      radius < size.width * .41;
      radius += size.width * .017
    ) {
      canvas.drawCircle(center, radius, groove);
    }
    canvas.drawCircle(
      center,
      size.width * .15,
      Paint()..color = seed % 3 == 0 ? glyphRed : const Color(0xffd7d5cf),
    );
    canvas.drawCircle(
      center,
      size.width * .025,
      Paint()..color = const Color(0xff161616),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * .34),
      -1.1,
      .65,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .1,
    );
  }

  @override
  bool shouldRepaint(_RecordPainter old) => old.seed != seed;
}

class EmptyCollection extends StatelessWidget {
  const EmptyCollection({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel = 'Import music',
    this.icon = Icons.library_music_outlined,
  });
  final String title, message, actionLabel;
  final VoidCallback? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Icon(icon, size: 28),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: action,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel),
          ),
        ],
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
}
