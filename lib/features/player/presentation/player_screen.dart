import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../app/app.dart';
import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import 'playback_seek_bar.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) {
    final song = c.current;
    if (song == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPage(context, PlayerScreen(c: c)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 4, 6),
                child: Row(
                  children: [
                    RecordArt(
                      path: song.artwork,
                      size: 44,
                      seed: song.title.length,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontSize: 13),
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous track',
                      onPressed: () => c.run(c.audio.skipToPrevious),
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      tooltip: c.audio.player.playing ? 'Pause' : 'Play',
                      onPressed: c.toggle,
                      icon: Icon(
                        c.audio.player.playing ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next track',
                      onPressed: () => c.run(c.audio.skipToNext),
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ),
              StreamBuilder<Duration?>(
                stream: c.audio.player.durationStream,
                initialData: c.audio.player.duration,
                builder: (context, snapshot) => PlaybackSeekBar(
                  key: ValueKey('mini-seek-${song.id}'),
                  positions: c.audio.smoothPositionStream,
                  readPosition: () => c.audio.player.position,
                  duration:
                      snapshot.data ?? Duration(milliseconds: song.durationMs),
                  compact: true,
                  onSeek: (position) => c.run(() async {
                    await c.audio.seek(position);
                    await c.persistQueue();
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => LivePage(
    c: c,
    builder: (context) {
      final song = c.current;
      final colors = Theme.of(context).colorScheme;
      if (song == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyCollection(
            title: 'A little quiet.',
            message: 'Choose a track from your library to start listening.',
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close player',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          title: const Center(child: Eyebrow('Now playing · local audio')),
          actions: [
            IconButton(
              tooltip: 'Open queue',
              onPressed: () => openPage(context, QueueScreen(c: c)),
              icon: const Icon(Icons.queue_music),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        RecordArt(
                          path: song.artwork,
                          size: math.min(constraints.maxWidth - 72, 340),
                          playing: c.audio.player.playing,
                          seed: song.title.length,
                        ),
                        const SizedBox(height: 36),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    song.artist,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: song.favorite
                                  ? 'Remove favorite'
                                  : 'Favorite track',
                              onPressed: () => c.run(() => c.favorite(song)),
                              icon: Icon(
                                song.favorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: song.favorite ? colors.secondary : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        StreamBuilder<Duration?>(
                          stream: c.audio.player.durationStream,
                          initialData: c.audio.player.duration,
                          builder: (context, snapshot) => PlaybackSeekBar(
                            key: ValueKey('player-seek-${song.id}'),
                            positions: c.audio.smoothPositionStream,
                            readPosition: () => c.audio.player.position,
                            duration:
                                snapshot.data ??
                                Duration(milliseconds: song.durationMs),
                            onSeek: (position) => c.run(() async {
                              await c.audio.seek(position);
                              await c.persistQueue();
                            }),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip:
                                  'Shuffle ${c.audio.player.shuffleModeEnabled ? 'on' : 'off'}',
                              color: c.audio.player.shuffleModeEnabled
                                  ? colors.secondary
                                  : colors.onSurfaceVariant,
                              onPressed: () => c.run(
                                () => c.audio.setShuffleMode(
                                  c.audio.player.shuffleModeEnabled
                                      ? AudioServiceShuffleMode.none
                                      : AudioServiceShuffleMode.all,
                                ),
                              ),
                              icon: const Icon(Icons.shuffle, size: 23),
                            ),
                            IconButton(
                              tooltip: 'Previous track',
                              onPressed: () => c.run(c.audio.skipToPrevious),
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                size: 38,
                              ),
                            ),
                            SizedBox.square(
                              dimension: 72,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: EdgeInsets.zero,
                                  backgroundColor: colors.secondary,
                                  foregroundColor: colors.onSecondary,
                                ),
                                onPressed: c.toggle,
                                child: Icon(
                                  c.audio.player.playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 38,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next track',
                              onPressed: () => c.run(c.audio.skipToNext),
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                size: 38,
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  'Repeat: ${c.audio.playbackState.value.repeatMode.name}',
                              color:
                                  c.audio.playbackState.value.repeatMode ==
                                      AudioServiceRepeatMode.none
                                  ? colors.onSurfaceVariant
                                  : colors.secondary,
                              onPressed: () => c.run(() {
                                final mode =
                                    c.audio.playbackState.value.repeatMode;
                                return c.audio.setRepeatMode(
                                  mode == AudioServiceRepeatMode.none
                                      ? AudioServiceRepeatMode.all
                                      : mode == AudioServiceRepeatMode.all
                                      ? AudioServiceRepeatMode.one
                                      : AudioServiceRepeatMode.none,
                                );
                              }),
                              icon: Icon(
                                c.audio.playbackState.value.repeatMode ==
                                        AudioServiceRepeatMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                size: 23,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.speaker_outlined,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            const Eyebrow('System audio output'),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.offline_pin_outlined, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'MP3${song.bitrate == null ? '' : ' · ${song.bitrate} kbps'} · ${fileSize(song.bytes)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const Eyebrow('ON DEVICE'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => LivePage(
    c: c,
    builder: (context) {
      final tracks = c.queueSongs;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Your queue'),
          actions: [
            TextButton(
              onPressed: tracks.isEmpty ? null : () => c.run(c.clearQueue),
              child: const Text('Clear'),
            ),
          ],
        ),
        body: ReorderableListView.builder(
          padding: const EdgeInsets.all(20),
          buildDefaultDragHandles: false,
          header: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DotTitle('UP NEXT', height: 30),
                const SizedBox(height: 12),
                Text(
                  '${tracks.length} tracks · Drag to change the mood',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (tracks.isEmpty)
                  const EmptyCollection(
                    title: 'Nothing in the queue',
                    message: 'Play a song or add tracks from your library.',
                  ),
              ],
            ),
          ),
          itemCount: tracks.length,
          onReorderItem: (a, b) => c.run(() => c.reorderQueue(a, b)),
          itemBuilder: (context, i) {
            final s = tracks[i];
            final active = c.audio.player.currentIndex == i;
            return ListTile(
              key: ValueKey('$i-${s.id}'),
              contentPadding: EdgeInsets.zero,
              leading: RecordArt(
                path: s.artwork,
                size: 48,
                seed: s.title.length,
              ),
              title: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? Theme.of(context).colorScheme.secondary
                      : null,
                ),
              ),
              subtitle: Text(s.artist, maxLines: 1),
              onTap: () => c.run(() async {
                await c.audio.skipToQueueItem(i);
                c.audio.play();
              }),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Remove from queue',
                    onPressed: () => c.run(() => c.removeQueue(i)),
                    icon: const Icon(Icons.close, size: 19),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
