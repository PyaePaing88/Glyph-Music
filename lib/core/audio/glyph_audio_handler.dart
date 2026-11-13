import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:home_widget/home_widget.dart';

import '../../features/library/domain/song.dart';
import '../widgets/accent_colour.dart';
import 'glyph_visualizer.dart';

class GlyphAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final player = AudioPlayer();
  final visualizer = GlyphVisualizer();
  late final Stream<Duration> smoothPositionStream = player
      .createPositionStream(
        steps: 10000,
        minPeriod: const Duration(milliseconds: 16),
        maxPeriod: const Duration(milliseconds: 33),
      );
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final errors = StreamController<String>.broadcast();
  Future<void> Function(String action)? mediaButtonAction;

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    final callback = mediaButtonAction;
    if (callback == null) return super.click(button);
    await callback(switch (button) {
      MediaButton.previous => 'previous',
      MediaButton.next => 'next',
      MediaButton.media => 'play_pause',
    });
  }

  Future<void> initialize() async {
    visualizer.initialize();
    _subscriptions.add(
      player.androidAudioSessionIdStream.listen((_) => _syncVisualizer()),
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.add(mediaItem.listen((_) => unawaited(_updateWidgets())));
    _subscriptions.add(player.playbackEventStream.listen((_) => _broadcast()));
    _subscriptions.add(player.playerStateStream.listen((_) => _broadcast()));
    _subscriptions.add(player.loopModeStream.listen((_) => _broadcast()));
    _subscriptions.add(
      player.shuffleModeEnabledStream.listen((_) => _broadcast()),
    );
    _subscriptions.add(
      player.currentIndexStream.listen((index) {
        if (index != null && index < queue.value.length) {
          mediaItem.add(queue.value[index]);
          _broadcast();
        }
      }),
    );
    _subscriptions.add(
      player.durationStream.listen((duration) {
        if (duration != null && mediaItem.value != null) {
          mediaItem.add(mediaItem.value!.copyWith(duration: duration));
        }
      }),
    );
    _subscriptions.add(
      player.errorStream.listen(
        (error) => errors.add(
          'Unable to play this file. It may be missing or damaged.',
        ),
      ),
    );
  }

  void _broadcast() {
    _syncVisualizer();
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: [0, 1, 2],
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
        repeatMode: switch (player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
    unawaited(_updateWidgets());
  }

  Future<void> setWidgetAccent(AccentColour accent) async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.saveWidgetData('accentColour', accent.colour.toARGB32());
      await HomeWidget.saveWidgetData(
        'accentForeground',
        accent.foreground.toARGB32(),
      );
      await _updateWidgets();
    } catch (_) {
      /* Launcher support never prevents changing the app theme. */
    }
  }

  void _syncVisualizer() {
    unawaited(
      visualizer.updatePlayback(
        player.androidAudioSessionId,
        player.playing && player.processingState == ProcessingState.ready,
      ),
    );
  }

  Future<void> setWidgetTheme(String mode) async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.saveWidgetData('themeMode', mode);
      await _updateWidgets();
    } catch (_) {
      /* Launcher support never prevents changing the app theme. */
    }
  }

  Future<void> _updateWidgets() async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.saveWidgetData(
        'title',
        mediaItem.value?.title ?? 'Your music. Your space.',
      );
      await HomeWidget.saveWidgetData(
        'artist',
        mediaItem.value?.artist ?? 'Open Glyph to import music',
      );
      await HomeWidget.saveWidgetData('playing', player.playing);
      await HomeWidget.saveWidgetData(
        'artwork',
        mediaItem.value?.artUri?.toFilePath() ?? '',
      );
      for (final name in [
        'GlyphCompactWidget',
        'GlyphMediumWidget',
        'GlyphLargeWidget',
      ]) {
        await HomeWidget.updateWidget(androidName: name);
      }
    } catch (_) {
      /* Launcher support never prevents playback. */
    }
  }

  Future<void> load(
    List<Song> songs, {
    int index = 0,
    Duration position = Duration.zero,
    bool autoplay = true,
  }) async {
    if (songs.isEmpty) {
      await stop();
      await player.clearAudioSources();
      queue.add([]);
      mediaItem.add(null);
      return;
    }
    final items = songs
        .map(
          (s) => MediaItem(
            id: s.id,
            title: s.title,
            artist: s.artist,
            album: s.album,
            artUri: s.artwork == null ? null : Uri.file(s.artwork!),
            duration: Duration(milliseconds: s.durationMs),
            extras: {'path': s.path},
          ),
        )
        .toList();
    queue.add(items);
    try {
      if (!songs[index].isAvailable) {
        throw const FileSystemException('Missing audio file');
      }
      await player.setAudioSources(
        songs.indexed
            .map(
              (entry) =>
                  AudioSource.uri(entry.$2.audioUri, tag: items[entry.$1]),
            )
            .toList(),
        initialIndex: index,
        initialPosition: position,
      );
      if (autoplay) unawaited(play());
    } catch (_) {
      await player.stop();
      await player.clearAudioSources();
      queue.add([]);
      mediaItem.add(null);
      errors.add(
        'This track cannot be opened. Check audio access or scan phone audio again; the original file may have moved.',
      );
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    try {
      await player.play();
    } catch (_) {
      errors.add('Playback failed. Try another track.');
    }
  }

  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> skipToNext() => player.seekToNext();
  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) =>
      player.seek(Duration.zero, index: index);
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      player.setLoopMode(switch (repeatMode) {
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group => LoopMode.all,
        _ => LoopMode.off,
      });
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode != AudioServiceShuffleMode.none) await player.shuffle();
    await player.setShuffleModeEnabled(
      shuffleMode != AudioServiceShuffleMode.none,
    );
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await player.dispose();
    await visualizer.dispose();
    await errors.close();
  }
}
