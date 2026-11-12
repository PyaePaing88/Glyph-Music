import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../integrations/discovery_client.dart';
import '../../library/domain/song.dart';
import '../../library/presentation/library_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.c});
  final AppController c;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  int _searchRevision = 0;
  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchRevision != widget.c.searchRevision) {
      _searchRevision = widget.c.searchRevision;
      _history();
    }
  }

  final input = TextEditingController();
  bool online = false, loading = false;
  bool searched = false;
  String? error;
  List<DiscoveryResult> results = [];
  List<String> history = [];
  int request = 0;
  @override
  void initState() {
    super.initState();
    _history();
  }

  Future<void> _history() async {
    final scope = online;
    final list = await widget.c.repository.searches(
      online ? 'youtube' : 'local',
    );
    if (mounted && scope == online) setState(() => history = list);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> search(String value) async {
    final q = value.trim();
    if (q.isEmpty) return;
    final token = ++request;
    final scope = online;
    await widget.c.repository.rememberSearch(q, scope ? 'youtube' : 'local');
    await _history();
    if (!mounted || token != request || !scope) return;
    setState(() {
      loading = true;
      error = null;
      results = [];
      searched = true;
    });
    try {
      final list = await widget.c.discovery.search(q);
      if (mounted && token == request) setState(() => results = list);
    } catch (e) {
      if (mounted && token == request) {
        if (e is DiscoveryOfflineException) {
          setState(() {
            online = false;
            error = null;
          });
          widget.c.message(e.message);
          await _history();
        } else {
          setState(() => error = widget.c.errorText(e));
        }
      }
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final local = searchSongs(c.songs, input.text);
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DotTitle('FIND YOUR SOUND', height: 28),
                const SizedBox(height: 12),
                Text(
                  'Somewhere between a memory and a new favorite.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: input,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) {
                    if (online) {
                      request++;
                      loading = false;
                      results = [];
                      error = null;
                      searched = false;
                    }
                    setState(() {});
                  },
                  onSubmitted: search,
                  decoration: InputDecoration(
                    hintText: online
                        ? 'Search YouTube'
                        : 'Songs, artists, albums…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: input.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              request++;
                              input.clear();
                              setState(() {
                                results = [];
                                searched = false;
                                error = null;
                                loading = false;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in [false, true])
                      ChoiceChip(
                        showCheckmark: false,
                        avatar: Icon(
                          source
                              ? Icons.play_circle_outline
                              : Icons.offline_pin_outlined,
                          size: 18,
                          color: online == source
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontFamily: 'sans-serif',
                          color: online == source
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        label: Text(source ? 'YouTube' : 'Local library'),
                        selected: online == source,
                        onSelected: (_) {
                          request++;
                          setState(() {
                            online = source;
                            searched = false;
                            error = null;
                            results = [];
                            loading = false;
                          });
                          _history();
                        },
                      ),
                  ],
                ),
                if (online) ...[
                  const SizedBox(height: 16),
                  Text(
                    'YouTube results stay here. Download music to your Tracks.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: loading || input.text.trim().isEmpty
                        ? null
                        : () => search(input.text),
                    icon: const Icon(Icons.search, size: 18),
                    label: Text('Search YouTube'),
                  ),
                ],
                if (input.text.isEmpty) ...[
                  SectionHeading(
                    'Recent searches',
                    trailing: TextButton(
                      onPressed: () => c.run(() async {
                        await c.clearSearches();
                        await _history();
                      }),
                      child: const Text('Clear'),
                    ),
                  ),
                  if (history.isEmpty)
                    Text(
                      'A clean slate. Search your local collection anytime.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ...history.map(
                    (q) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, size: 20),
                      title: Text(q),
                      trailing: const Icon(Icons.north_west, size: 18),
                      onTap: () {
                        input.text = q;
                        setState(() {});
                        search(q);
                      },
                    ),
                  ),
                ],
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (error != null)
                  EmptyCollection(
                    title: 'Discovery is taking a break',
                    message: error!,
                    icon: Icons.cloud_off_outlined,
                    action: () {
                      request++;
                      setState(() {
                        online = false;
                        error = null;
                        loading = false;
                      });
                      _history();
                    },
                    actionLabel: 'Search local music',
                  ),
                if (!online && input.text.isNotEmpty && local.isEmpty)
                  const EmptyCollection(
                    title: 'No tracks found',
                    message: 'Try a different title, artist, album, or genre.',
                  ),
                if (!online && input.text.isNotEmpty && local.isNotEmpty)
                  SectionHeading('${local.length} local results'),
                if (online &&
                    !loading &&
                    error == null &&
                    results.isEmpty &&
                    input.text.isNotEmpty)
                  EmptyCollection(
                    title: searched ? 'No videos found' : 'Ready to explore',
                    message: searched
                        ? 'Try another song title or artist.'
                        : 'Tap Search YouTube to find music.',
                    icon: Icons.explore_outlined,
                  ),
              ],
            ),
          ),
        ),
        if (!online && input.text.isNotEmpty)
          SliverList.builder(
            itemCount: local.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SongTile(c: c, song: local[i], tracks: local),
            ),
          )
        else if (online)
          SliverList.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              final r = results[i];
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            r.thumbnail == null
                                ? const Icon(Icons.play_circle_outline)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      r.thumbnail!,
                                      width: 56,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const SizedBox(
                                        width: 56,
                                        child: Icon(Icons.play_circle_outline),
                                      ),
                                    ),
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${r.channel} · YouTube',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if (r.duration != null)
                                    Text(
                                      clockTime(r.duration!),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ListenableBuilder(
                          listenable: c,
                          builder: (context, _) {
                            final job = c.downloads
                                .where(
                                  (j) =>
                                      j.sourceType == 'youtube' &&
                                      j.url == r.id,
                                )
                                .firstOrNull;
                            final saved = c.youtubeTrackIds.contains(r.id);
                            final active =
                                job != null &&
                                [
                                  'downloading',
                                  'validating',
                                ].contains(job.status);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      key: ValueKey('youtube-download-${r.id}'),
                                      onPressed: saved || active
                                          ? null
                                          : () => c.run(
                                              () => c.downloadYoutube(r),
                                            ),
                                      icon: Icon(
                                        saved
                                            ? Icons.download_done
                                            : Icons.download,
                                      ),
                                      label: Text(
                                        saved
                                            ? 'Saved to Tracks'
                                            : active
                                            ? (job.status == 'validating'
                                                  ? 'Saving…'
                                                  : 'Downloading…')
                                            : 'Download',
                                      ),
                                    ),
                                    if (active)
                                      TextButton(
                                        onPressed: () => job.token?.cancel(),
                                        child: const Text('Cancel'),
                                      ),
                                    IconButton(
                                      tooltip: 'Open video in YouTube',
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 20,
                                      ),
                                      onPressed: () => c.run(() async {
                                        final ok = await launchUrl(
                                          Uri.https(
                                            'www.youtube.com',
                                            '/watch',
                                            {'v': r.id},
                                          ),
                                          mode: LaunchMode.externalApplication,
                                        );
                                        if (!ok) {
                                          throw StateError(
                                            'No app is available to open YouTube.',
                                          );
                                        }
                                      }),
                                    ),
                                  ],
                                ),
                                if (active)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: LinearProgressIndicator(
                                      value: job.progress == 0
                                          ? null
                                          : job.progress.clamp(0, 1),
                                    ),
                                  ),
                                if (job?.status == 'failed')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      job!.error ??
                                          'Download failed. Try again.',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
