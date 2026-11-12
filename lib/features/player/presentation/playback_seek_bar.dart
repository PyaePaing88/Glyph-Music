import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/design.dart';

/// Keeps scrubbing local to the UI and commits one seek when the finger lifts.
class PlaybackSeekBar extends StatefulWidget {
  const PlaybackSeekBar({
    super.key,
    required this.positions,
    required this.readPosition,
    required this.duration,
    required this.onSeek,
    this.compact = false,
  });

  final Stream<Duration> positions;
  final Duration Function() readPosition;
  final Duration duration;
  final Future<void> Function(Duration) onSeek;
  final bool compact;

  @override
  State<PlaybackSeekBar> createState() => _PlaybackSeekBarState();
}

class _PlaybackSeekBarState extends State<PlaybackSeekBar> {
  StreamSubscription<Duration>? _subscription;
  late Duration _position;
  double? _preview;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _position = widget.readPosition();
    _subscription = widget.positions.listen((value) {
      // Late playback ticks must not move the thumb out from under the finger,
      // or replace the preview while the audio engine completes a seek.
      if (!mounted || _preview != null) return;
      setState(() => _position = value);
    });
  }

  @override
  void didUpdateWidget(PlaybackSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positions != widget.positions) {
      unawaited(_subscription?.cancel());
      _revision++;
      _preview = null;
      _listen();
    }
    if (widget.duration <= Duration.zero) {
      _revision++;
      _preview = null;
    }
  }

  Future<void> _commit(double value) async {
    final revision = ++_revision;
    final target = Duration(milliseconds: value.round());
    setState(() => _preview = value);
    try {
      await widget.onSeek(target);
    } catch (_) {
      // Restore the engine's position if seeking fails. The caller reports errors.
    } finally {
      if (mounted && revision == _revision) {
        setState(() {
          _position = widget.readPosition();
          _preview = null;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds.clamp(0, 1 << 53).toDouble();
    final value = (_preview ?? _position.inMilliseconds.toDouble()).clamp(
      0.0,
      total,
    );
    final position = Duration(milliseconds: value.round());
    final textStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace', fontSize: widget.compact ? 10 : 12);
    final slider = Semantics(
      label: 'Playback position',
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: widget.compact ? 2 : 3,
          thumbShape: RoundSliderThumbShape(
            enabledThumbRadius: widget.compact ? 6 : 10,
          ),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: SizedBox(
          height: 44,
          child: Slider(
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 12 : 16),
            value: value,
            max: total > 0 ? total : 1,
            onChangeStart: total <= 0
                ? null
                : (value) {
                    _revision++;
                    setState(() => _preview = value);
                  },
            onChanged: total <= 0
                ? null
                : (value) => setState(() => _preview = value),
            onChangeEnd: total <= 0
                ? null
                : (value) => unawaited(_commit(value)),
            semanticFormatterCallback: (value) =>
                '${clockTime(Duration(milliseconds: value.round()))} of ${clockTime(widget.duration)}',
          ),
        ),
      ),
    );
    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
        child: Row(
          children: [
            Text(clockTime(position), style: textStyle),
            Expanded(child: slider),
            Text(clockTime(widget.duration), style: textStyle),
          ],
        ),
      );
    }
    return Column(
      children: [
        slider,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(clockTime(position), style: textStyle),
            Text(clockTime(widget.duration), style: textStyle),
          ],
        ),
      ],
    );
  }
}
