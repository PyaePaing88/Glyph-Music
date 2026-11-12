import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../app/app.dart';
import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../core/widgets/alphabet_track_browser.dart';
import '../../library/domain/song.dart';
import '../../library/presentation/library_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
        child: Row(
          children: [
            const Expanded(child: DotTitle('PLAYLISTS', height: 30)),
            IconButton(
              tooltip: 'Create playlist',
              onPressed: () => editPlaylist(context, c),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          header: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Eyebrow('Soundtracks for the everyday.'),
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: Icon(
                    Icons.favorite,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                title: const Text('Favorites'),
                subtitle: Text(
                  '${c.favorites.length} tracks · Always up to date',
                ),
                onTap: () => openPage(
                  context,
                  CollectionScreen(c: c, title: 'Favorites', kind: 'favorites'),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: const Icon(Icons.history),
                ),
                title: const Text('Recently played'),
                subtitle: const Text('Your listening timeline'),
                onTap: () => openPage(
                  context,
                  CollectionScreen(
                    c: c,
                    title: 'Recently played',
                    kind: 'recent',
                  ),
                ),
              ),
              const Divider(height: 40),
              if (c.playlists.isEmpty)
                EmptyCollection(
                  title: 'Set the mood.',
                  message: 'Morning commutes. Late-night thoughts. Give every moment its own soundtrack.',
                  action: () => editPlaylist(context, c),
                  actionLabel: 'Create playlist',
                  icon: Icons.queue_music,
                ),
            ],
          ),
          itemCount: c.playlists.length,
          onReorderItem: (oldIndex, newIndex) => c.run(() async {
            final ids = c.playlists.map((p) => p.id).toList();
            final id = ids.removeAt(oldIndex);
            ids.insert(newIndex, id);
            await c.repository.reorderPlaylists(ids);
            await c.refresh();
          }),
          itemBuilder: (context, i) {
            final pl = c.playlists[i];
            return ListTile(
              key: ValueKey(pl.id),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              leading: RecordArt(path: pl.artwork, size: 60, seed: i),
              title: Text(pl.name),
              subtitle: Text(
                '${pl.songIds.length} tracks${pl.description.isEmpty ? '' : ' · ${pl.description}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
              onTap: () => openPage(context, PlaylistDetail(c: c, id: pl.id)),
            );
          },
        ),
      ),
    ],
  );
}

class PlaylistDetail extends StatelessWidget {
  const PlaylistDetail({super.key, required this.c, required this.id});
  final AppController c;
  final String id;
  @override
  Widget build(BuildContext context) => LivePage(
    c: c,
    builder: (context) {
      final pl = c.playlists.where((p) => p.id == id).firstOrNull;
      if (pl == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('This playlist has been removed.')),
        );
      }
      final tracks = pl.songIds
          .map((id) => c.songs.where((s) => s.id == id).firstOrNull)
          .whereType<Song>()
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Your playlist'),
          actions: [
            IconButton(
              tooltip: 'Edit playlist',
              onPressed: () => editPlaylist(context, c, playlist: pl),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete playlist',
              onPressed: () => c.run(() async {
                final ok = await showGlyphDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Delete ${pl.name}?'),
                    content: const Text(
                      'Your songs will stay in your library.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await c.repository.deletePlaylist(id);
                  await c.refresh();
                  if (context.mounted) Navigator.pop(context);
                }
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: AlphabetTrackBrowser(
          labels: tracks.map((s) => s.title).toList(),
          leadingPadding: 24,
          builder: (controller, headerKey, itemExtent) =>
              ReorderableListView.builder(
                scrollController: controller,
                itemExtent: itemExtent,
                padding: const EdgeInsets.all(24),
                header: Column(
                  key: headerKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: RecordArt(
                        path: pl.artwork,
                        size: 200,
                        seed: pl.name.length,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Eyebrow('A personal rotation'),
                    const SizedBox(height: 8),
                    Text(
                      pl.name,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    if (pl.description.isNotEmpty)
                      Text(
                        pl.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${tracks.length} tracks · ${clockTime(Duration(milliseconds: tracks.fold(0, (n, s) => n + s.durationMs)))} total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: tracks.isEmpty
                              ? null
                              : () => c.playSongs(tracks, shuffle: false),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play playlist'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: 'Shuffle play',
                                child: OutlinedButton.icon(
                                  onPressed: tracks.isEmpty
                                      ? null
                                      : () =>
                                            c.playSongs(tracks, shuffle: true),
                                  icon: const Icon(Icons.shuffle),
                                  label: const Text('Shuffle play'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              tooltip: 'Add or remove tracks',
                              onPressed: () => openPage(
                                context,
                                PlaylistTracksPage(c: c, id: pl.id),
                              ),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (tracks.isEmpty)
                      const EmptyCollection(
                        title: 'Room for a few favorites',
                        message: 'Add music from your local library to start this playlist.',
                      ),
                  ],
                ),
                buildDefaultDragHandles: false,
                itemCount: tracks.length,
                onReorderItem: (a, b) => c.run(() async {
                  final ids = List<String>.of(pl.songIds);
                  final item = ids.removeAt(a);
                  ids.insert(b, item);
                  await c.repository.savePlaylist(
                    id,
                    pl.name,
                    pl.description,
                    ids,
                    artwork: pl.artwork,
                  );
                  await c.refresh();
                }),
                itemBuilder: (context, i) => Row(
                  key: ValueKey(tracks[i].id),
                  children: [
                    Expanded(
                      child: SongTile(c: c, song: tracks[i], tracks: tracks),
                    ),
                    IconButton(
                      tooltip: 'Remove from playlist',
                      onPressed: () => c.run(() async {
                        await c.repository.savePlaylist(
                          id,
                          pl.name,
                          pl.description,
                          pl.songIds.where((s) => s != tracks[i].id).toList(),
                          artwork: pl.artwork,
                        );
                        await c.refresh();
                      }),
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
        ),
      );
    },
  );
}

Future<String?> editPlaylist(
  BuildContext context,
  AppController c, {
  MusicPlaylist? playlist,
}) async {
  final name = TextEditingController(text: playlist?.name ?? '');
  final description = TextEditingController(text: playlist?.description ?? '');
  var art = playlist?.artwork;
  var validation = false;
  final ok = await showGlyphDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        scrollable: true,
        title: Text(playlist == null ? 'Create playlist' : 'Edit playlist'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: 'Playlist name',
                  errorText: validation && name.text.trim().isEmpty
                      ? 'Enter a name'
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: description,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              TextButton.icon(
                onPressed: () => c.run(() async {
                  final path = await c.pickArtwork();
                  if (path != null && ctx.mounted) set(() => art = path);
                }),
                icon: const Icon(Icons.image_outlined),
                label: Text(art == null ? 'Add artwork' : 'Change artwork'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                set(() => validation = true);
              } else {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  String? savedId;
  if (ok == true) {
    await c.run(() async {
      final id = playlist?.id ?? const Uuid().v4();
      final latest = c.playlists.where((p) => p.id == id).firstOrNull;
      if (playlist != null && latest == null) {
        throw StateError('This playlist has been removed.');
      }
      await c.repository.savePlaylist(
        id,
        name.text.trim(),
        description.text.trim(),
        latest?.songIds ?? const [],
        artwork: art,
      );
      await c.refresh();
      savedId = id;
    });
  }
  name.dispose();
  description.dispose();
  if (savedId != null && playlist == null && context.mounted) {
    openPage(context, PlaylistDetail(c: c, id: savedId!));
  }
  return savedId;
}

class PlaylistTracksPage extends StatefulWidget {
  const PlaylistTracksPage({super.key, required this.c, required this.id});
  final AppController c;
  final String id;
  @override
  State<PlaylistTracksPage> createState() => _PlaylistTracksPageState();
}

class _PlaylistTracksPageState extends State<PlaylistTracksPage> {
  late final List<String> selected;
  String query = '';
  bool saving = false;
  @override
  void initState() {
    super.initState();
    selected = List.of(
      widget.c.playlists.where((p) => p.id == widget.id).firstOrNull?.songIds ??
          <String>[],
    );
  }

  Future<void> save() async {
    setState(() => saving = true);
    var saved = false;
    await widget.c.run(() async {
      final pl = widget.c.playlists.where((p) => p.id == widget.id).firstOrNull;
      if (pl == null) throw StateError('This playlist has been removed.');
      final available = widget.c.songs.map((s) => s.id).toSet();
      await widget.c.repository.savePlaylist(
        pl.id,
        pl.name,
        pl.description,
        selected.where(available.contains).toList(),
        artwork: pl.artwork,
      );
      await widget.c.refresh();
      saved = true;
    });
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final tracks = searchSongs(widget.c.songs, query);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Tracks'),
          actions: [
            TextButton(
              onPressed: saving ? null : save,
              child: const Text('Done'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  hintText: 'Search tracks',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${selected.length} selected'),
              ),
            ),
            Expanded(
              child: tracks.isEmpty
                  ? const SingleChildScrollView(
                      child: EmptyCollection(
                        title: 'No tracks to select',
                        message: 'Import or download music, or try a different search.',
                      ),
                    )
                  : AlphabetTrackBrowser(
                      labels: tracks.map((s) => s.title).toList(),
                      builder: (controller, headerKey, itemExtent) =>
                          ListView.builder(
                            controller: controller,
                            itemExtent: itemExtent,
                            itemCount: tracks.length,
                            itemBuilder: (context, index) {
                              final song = tracks[index];
                              return CheckboxListTile(
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  song.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                secondary: RecordArt(
                                  path: song.artwork,
                                  size: 40,
                                ),
                                value: selected.contains(song.id),
                                onChanged: saving
                                    ? null
                                    : (value) => setState(() {
                                        if (value == true) {
                                          selected.add(song.id);
                                        } else {
                                          selected.remove(song.id);
                                        }
                                      }),
                              );
                            },
                          ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(
                      saving ? 'Saving…' : 'Save ${selected.length} tracks',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
