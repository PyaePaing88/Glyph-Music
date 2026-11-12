import 'dart:async';

import 'package:flutter/foundation.dart';

String sleepDurationLabel(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest ${rest == 1 ? 'minute' : 'minutes'}';
  final label = '$hours ${hours == 1 ? 'hour' : 'hours'}';
  return rest == 0 ? label : '$label $rest ${rest == 1 ? 'minute' : 'minutes'}';
}

String sleepCountdown(Duration remaining) {
  final seconds = (remaining.inMilliseconds / 1000).ceil().clamp(0, 86400);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$tail'
      : '$minutes:$tail';
}

/// Lives with playback, independently of the visible screen or navigation.
class SleepTimer extends ChangeNotifier {
  SleepTimer({required this.onExpired, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Future<void> Function() onExpired;
  final DateTime Function() _now;
  DateTime? _deadline;
  Timer? _alarm;
  Timer? _updates;
  int _generation = 0;

  DateTime? get deadline => _deadline;
  bool get active => _deadline != null;
  Duration get remaining {
    final difference = _deadline?.difference(_now()) ?? Duration.zero;
    return difference.isNegative ? Duration.zero : difference;
  }

  void start(Duration duration) {
    if (duration <= Duration.zero) throw ArgumentError.value(duration);
    _schedule(_now().add(duration));
  }

  Future<void> restore(DateTime? deadline) async {
    cancel();
    if (deadline == null) return;
    if (!deadline.isAfter(_now())) {
      await onExpired();
    } else {
      _schedule(deadline);
    }
  }

  void _schedule(DateTime deadline) {
    cancel();
    _deadline = deadline;
    final generation = _generation;
    _alarm = Timer(remaining, () => unawaited(_expire(generation)));
    _updates = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remaining == Duration.zero) {
        unawaited(_expire(generation));
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> expireIfDue() async {
    if (active && remaining == Duration.zero) await _expire(_generation);
  }

  Future<void> _expire(int generation) async {
    if (generation != _generation || !active) return;
    cancel();
    await onExpired();
  }

  void cancel() {
    _generation++;
    _alarm?.cancel();
    _updates?.cancel();
    _alarm = null;
    _updates = null;
    final changed = active;
    _deadline = null;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _alarm?.cancel();
    _updates?.cancel();
    _generation++;
    super.dispose();
  }
}
