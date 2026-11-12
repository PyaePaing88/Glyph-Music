import 'package:flutter/material.dart';

import '../../../app/app.dart';
import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../core/widgets/alphabet_track_browser.dart';
import '../domain/song.dart';
import '../../playlists/presentation/playlists_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.c});
  final AppController c;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String category = 'Songs', sort = 'Title', query = '';
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tracks = searchSongs(c.songs, query)
      ..sort(
        (a, b) => switch (sort) {
          'Artist' => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
          'Album' => a.album.toLowerCase().compareTo(b.album.toLowerCase()),
          'Date added' => b.createdAt.compareTo(a.createdAt),
          'Duration' => b.durationMs.compareTo(a.durationMs),
          'Most played' => b.playCount.compareTo(a.playCount),
          _ => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        },
      );
    final groups = <String, List<Song>>{};
    if (category != 'Songs') {
      for (final s in tracks) {
        final value = switch (category) {
          'Artists' => s.artist,
          'Albums' => s.album,
          _ => s.genre,
        };
        (groups[value.isEmpty
                    ? 'Unknown ${category.toLowerCase().substring(0, category.length - 1)}'
                    : value] ??=
                [])
            .add(s);
      }
    }
    return AlphabetTrackBrowser(
      labels: category == 'Songs'
          ? tracks
                .map(
                  (s) => switch (sort) {
                    'Artist' => s.artist,
                    'Album' => s.album,
                    _ => s.title,
                  },
                )
                .toList()
          : const [],
      builder: (controller, headerKey, itemExtent) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              key: headerKey,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: DotTitle('LIBRARY', height: 31)),
                      if (c.phoneAudioAccess != 'unsupported')
                        IconButton(
                          tooltip: 'Scan phone audio',
                          onPressed: c.scanningPhone
                              ? null
                              : () => c.scanPhoneAudio(requestPermission: true),
                          icon: const Icon(Icons.refresh),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Import music',
                        icon: const Icon(Icons.add_circle_outline),
                        onSelected: (v) => c.importMusic(folder: v == 'folder'),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'files',
                            child: Text('Import MP3 files'),
                          ),
                          PopupMenuItem(
                            value: 'folder',
                            child: Text('Import a folder'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${c.songs.length} tracks · ${fileSize(c.totalBytes)} · Stored locally',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Find something you love',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ['Songs', 'Artists', 'Albums', 'Genres']
                          .map(
                            (v) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  v,
                                  style: TextStyle(
                                    color: category == v
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                  ),
                                ),
                                selected: category == v,
                                onSelected: (_) => setState(() => category = v),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Row(
                    children: [
                      const Eyebrow('Your collection'),
                      const Spacer(),
                      PopupMenuButton<String>(
                        initialValue: sort,
                        onSelected: (v) => setState(() => sort = v),
                        itemBuilder: (_) =>
                            [
                                  'Title',
                                  'Artist',
                                  'Album',
                                  'Date added',
                                  'Duration',
                                  'Most played',
                                ]
                                .map(
                                  (v) =>
                                      PopupMenuItem(value: v, child: Text(v)),
                                )
                                .toList(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              Text(
                                sort,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.sort, size: 18),
                            ],
                          ),
                        ),
                      ),
                      if (tracks.isNotEmpty)
                        IconButton(
                          tooltip: 'Play all',
                          onPressed: () => c.playSongs(tracks),
                          icon: const Icon(Icons.play_circle_outline),
                        ),
                    ],
                  ),
                  if (c.busy || c.scanningPhone)
                    const LinearProgressIndicator(minHeight: 2),
                  if (c.scanningPhone)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Finding audio on your phone…'),
                    ),
                  if (['denied', 'blocked'].contains(c.phoneAudioAccess))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.audio_file_outlined),
                      title: const Text('Find audio on your phone'),
                      subtitle: const Text(
                        'Allow audio access to show music and recordings in Library.',
                      ),
                      trailing: TextButton(
                        onPressed: c.allowPhoneAudio,
                        child: Text(
                          c.phoneAudioAccess == 'blocked'
                              ? 'Settings'
                              : 'Allow',
                        ),
                      ),
                    ),
                  if (c.phoneScanError != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Phone scan could not finish'),
                      subtitle: Text(c.phoneScanError!),
                      trailing: TextButton(
                        onPressed: () =>
                            c.scanPhoneAudio(requestPermission: true),
                        child: const Text('Retry'),
                      ),
                    ),
                  if (tracks.isEmpty)
                    EmptyCollection(
                      title: c.songs.isEmpty
                          ? 'A fresh start.'
                          : 'Nothing found',
                      message: c.songs.isEmpty
                          ? 'Audio found on your phone appears here. You can also import your own MP3s.'
                          : 'Try another title, artist, album, or genre.',
                      action: c.songs.isEmpty && !c.busy
                          ? () => c.importMusic()
                          : null,
                    ),
                ],
              ),
            ),
          ),
          if (category == 'Songs')
            SliverFixedExtentList.builder(
              itemExtent: itemExtent,
              itemCount: tracks.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SongTile(c: c, song: tracks[i], tracks: tracks),
              ),
            )
          else
            SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final name = groups.keys.elementAt(i), songs = groups[name]!;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 6,
                  ),
                  leading: RecordArt(
                    path: songs.first.artwork,
                    size: 52,
                    seed: i,
                  ),
                  title: Text(name),
                  subtitle: Text('${songs.length} tracks'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openPage(
                    context,
                    CollectionScreen(
                      c: c,
                      title: name,
                      kind: 'group',
                      ids: songs.map((s) => s.id).toList(),
                    ),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({
    super.key,
    required this.c,
    required this.title,
    required this.kind,
    this.ids = const [],
  });
  final AppController c;
  final String title, kind;
  final List<String> ids;
  @override
  Widget build(BuildContext context) => LivePage(
    c: c,
    builder: (context) {
      final songs = switch (kind) {
        'favorites' => c.favorites,
        'recent' => c.recent,
        _ => c.songs.where((s) => ids.contains(s.id)).toList(),
      };
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: AlphabetTrackBrowser(
          labels: songs.map((s) => s.title).toList(),
          builder: (controller, headerKey, itemExtent) => CustomScrollView(
            controller: controller,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  key: headerKey,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          RecordArt(
                            size: 100,
                            path: songs.firstOrNull?.artwork,
                            seed: kind == 'favorites' ? 0 : 2,
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Eyebrow('$kind collection'),
                                const SizedBox(height: 8),
                                Text(
                                  '${songs.length} tracks',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: songs.isEmpty
                                      ? null
                                      : () => c.playSongs(songs),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Play all'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (songs.isEmpty)
                      const EmptyCollection(
                        title: 'Room for good music',
                        message: 'Your tracks will appear here as you listen and add favorites.',
                      ),
                  ],
                ),
              ),
              SliverFixedExtentList.builder(
                itemExtent: itemExtent,
                itemCount: songs.length,
                itemBuilder: (context, i) =>
                    SongTile(c: c, song: songs[i], tracks: songs),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.c,
    required this.song,
    required this.tracks,
  });
  final AppController c;
  final Song song;
  final List<Song> tracks;
  @override
  Widget build(BuildContext context) {
    final active = c.current?.id == song.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      leading: Stack(
        alignment: Alignment.center,
        children: [
          RecordArt(path: song.artwork, size: 50, seed: song.title.length),
          if (active)
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.graphic_eq,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
        ],
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: active ? Theme.of(context).colorScheme.secondary : null,
        ),
      ),
      subtitle: Text(
        '${song.artist}  ·  ${clockTime(Duration(milliseconds: song.durationMs))}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () => c.playSongs(
        tracks,
        index: tracks
            .indexWhere((s) => s.id == song.id)
            .clamp(0, tracks.length - 1),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Track options for ${song.title}',
        icon: const Icon(Icons.more_horiz),
        position: PopupMenuPosition.under,
        onSelected: (value) => c.run(() async {
          switch (value) {
            case 'next':
              await c.enqueue(song, next: true);
            case 'queue':
              await c.enqueue(song);
            case 'favorite':
              await c.favorite(song);
            case 'playlist':
              if (context.mounted) await addToPlaylist(context, c, song);
            case 'edit':
              if (context.mounted) await editSong(context, c, song);
            case 'delete':
              if (context.mounted) await deleteSongDialog(context, c, song);
          }
        }),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'next',
            child: _TrackMenuLabel(Icons.skip_next_outlined, 'Play next'),
          ),
          const PopupMenuItem(
            value: 'queue',
            child: _TrackMenuLabel(Icons.queue_music, 'Add to queue'),
          ),
          PopupMenuItem(
            value: 'favorite',
            child: _TrackMenuLabel(
              song.favorite ? Icons.favorite : Icons.favorite_border,
              song.favorite ? 'Remove favorite' : 'Add to favorites',
            ),
          ),
          const PopupMenuItem(
            value: 'playlist',
            child: _TrackMenuLabel(Icons.playlist_add, 'Add to playlist'),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: _TrackMenuLabel(Icons.edit_outlined, 'Edit metadata'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: _TrackMenuLabel(
              Icons.delete_outline,
              'Delete…',
              destructive: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackMenuLabel extends StatelessWidget {
  const _TrackMenuLabel(this.icon, this.label, {this.destructive = false});
  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.secondary : colors.onSurface;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

Future<void> editSong(BuildContext context, AppController c, Song song) async {
  final title = TextEditingController(text: song.title),
      artist = TextEditingController(text: song.artist),
      album = TextEditingController(text: song.album),
      genre = TextEditingController(text: song.genre);
  var art = song.artwork;
  final saved = await showGlyphDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Make it yours'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: artist,
                decoration: const InputDecoration(labelText: 'Artist'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: album,
                decoration: const InputDecoration(labelText: 'Album'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: genre,
                decoration: const InputDecoration(labelText: 'Genre'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  RecordArt(size: 52, path: art),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => c.run(() async {
                      final path = await c.pickArtwork();
                      if (path != null && context.mounted) {
                        set(() => art = path);
                      }
                    }),
                    child: const Text('Change artwork'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Edits are saved in your Glyph library. The MP3 tags remain as imported.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (title.text.trim().isNotEmpty) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved == true) {
    await c.repository.edit(
      song,
      title.text.trim(),
      artist.text.trim().isEmpty ? 'Unknown artist' : artist.text.trim(),
      album.text.trim(),
      genre.text.trim(),
      art,
    );
    await c.refresh();
  }
  title.dispose();
  artist.dispose();
  album.dispose();
  genre.dispose();
}

Future<void> deleteSongDialog(
  BuildContext context,
  AppController c,
  Song song,
) async {
  var file = false;
  final ok = await showGlyphDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Remove track?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '“${song.title}” will be removed from the library, playlists, and queue.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: file,
              onChanged: (v) => set(() => file = v!),
              title: const Text('Also delete the app-managed audio file'),
              subtitle: const Text(
                'Your original imported file is unaffected.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep track'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ),
  );
  if (ok == true) await c.deleteSong(song, file);
}

Future<void> addToPlaylist(
  BuildContext context,
  AppController c,
  Song song,
) async {
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Add to playlist')),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Create a playlist'),
            onTap: () => Navigator.pop(context, 'new'),
          ),
          ...c.playlists.map(
            (pl) => ListTile(
              title: Text(pl.name),
              subtitle: Text('${pl.songIds.length} tracks'),
              onTap: () => Navigator.pop(context, pl.id),
            ),
          ),
        ],
      ),
    ),
  );
  if (id == 'new' && context.mounted) {
    await editPlaylist(context, c);
  } else if (id != null) {
    final pl = c.playlists.firstWhere((p) => p.id == id);
    await c.repository.savePlaylist(pl.id, pl.name, pl.description, [
      ...pl.songIds,
      song.id,
    ], artwork: pl.artwork);
    await c.refresh();
    c.message('Added to ${pl.name}');
  }
}
