import 'package:flutter/material.dart';

String trackInitial(String title) {
  final value = title.trimLeft().toUpperCase();
  if (value.isEmpty) return '#';
  final first = value.substring(0, 1);
  return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
}

/// A jump index that preserves the list's current sorting and playlist order.
class AlphabetTrackBrowser extends StatefulWidget {
  const AlphabetTrackBrowser({
    super.key,
    required this.labels,
    required this.builder,
    this.leadingPadding = 0,
  });

  final List<String> labels;
  final double leadingPadding;
  final Widget Function(
    ScrollController controller,
    GlobalKey headerKey,
    double itemExtent,
  )
  builder;

  @override
  State<AlphabetTrackBrowser> createState() => _AlphabetTrackBrowserState();
}

class _AlphabetTrackBrowserState extends State<AlphabetTrackBrowser> {
  final _controller = ScrollController();
  final _headerKey = GlobalKey();
  String? _selected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = 80.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
    final initials = widget.labels.map(trackInitial).toList();
    final colors = Theme.of(context).colorScheme;
    final letters = [
      '#',
      ...List.generate(26, (i) => String.fromCharCode(65 + i)),
    ];

    void jump(String letter) {
      final index = initials.indexOf(letter);
      if (index < 0 || !_controller.hasClients) return;
      final headerHeight = _headerKey.currentContext?.size?.height ?? 0;
      setState(() => _selected = letter);
      _controller.jumpTo(
        (widget.leadingPadding + headerHeight + index * extent).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: widget.builder(_controller, _headerKey, extent)),
        if (initials.isNotEmpty)
          SizedBox(
            width: 32,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = (constraints.maxHeight / letters.length).clamp(
                  1.0,
                  22.0,
                );
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (details) => jump(
                      letters[(details.localPosition.dy / height).floor().clamp(
                        0,
                        26,
                      )],
                    ),
                    onVerticalDragUpdate: (details) => jump(
                      letters[(details.localPosition.dy / height).floor().clamp(
                        0,
                        26,
                      )],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: letters.map((letter) {
                        final enabled = initials.contains(letter);
                        final selected = enabled && _selected == letter;
                        return Semantics(
                          button: true,
                          enabled: enabled,
                          label: 'Jump to $letter',
                          child: InkWell(
                            onTap: enabled ? () => jump(letter) : null,
                            child: Container(
                              width: 32,
                              height: height,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected ? colors.secondary : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                letter,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontSize: (height - 2).clamp(6.0, 11.0),
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? colors.onSecondary
                                      : enabled
                                      ? colors.onSurface
                                      : colors.onSurface.withValues(alpha: .25),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
