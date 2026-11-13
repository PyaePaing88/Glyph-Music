import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../integrations/discovery_client.dart';

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
  Timer? _debounce;
  String _lastText = '';
  TextRange _lastComposing = TextRange.empty;
  String? _activeQuery;
  bool waiting = false;
  bool loading = false;
  bool searched = false;
  String? error;
  List<DiscoveryResult> results = [];
  List<String> history = [];
  int request = 0;
  @override
  void initState() {
    super.initState();
    input.addListener(_queryChanged);
    _history();
  }

  void _queryChanged() {
    final value = input.value;
    if (value.text == _lastText && value.composing == _lastComposing) return;
    _lastText = value.text;
    _lastComposing = value.composing;
    _debounce?.cancel();
    request++;
    final query = value.text.trim();
    final composing = value.composing.isValid && !value.composing.isCollapsed;
    setState(() {
      loading = false;
      waiting = query.isNotEmpty;
      results = [];
      error = null;
      searched = false;
    });
    if (query.isNotEmpty && !composing) {
      _debounce = Timer(const Duration(milliseconds: 500), () {
        unawaited(search(query));
      });
    }
  }

  Future<void> _history() async {
    final list = await widget.c.repository.searches('youtube');
    if (mounted) setState(() => history = list);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    input.removeListener(_queryChanged);
    input.dispose();
    super.dispose();
  }

  Future<void> search(String value) async {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) return;
    if (loading && _activeQuery == q) return;
    _activeQuery = q;
    final token = ++request;
    setState(() {
      waiting = false;
      loading = true;
      error = null;
      results = [];
      searched = true;
    });
    try {
      await widget.c.repository.rememberSearch(q, 'youtube');
      await _history();
      if (!mounted || token != request) return;
      final list = await widget.c.discovery.search(q);
      if (mounted && token == request) setState(() => results = list);
    } catch (e) {
      if (mounted && token == request) {
        setState(() => error = widget.c.errorText(e));
      }
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: DotTitle('FIND YOUR SOUND', height: 28)),
                const SizedBox(height: 12),
                Text(
                  'Somewhere between a memory and a new favorite.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: input,
                  textAlign: TextAlign.left,
                  textInputAction: TextInputAction.search,
                  onSubmitted: search,
                  decoration: InputDecoration(
                    hintText: 'Search YouTube',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: input.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: input.clear,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Search YouTube as you type. Download music to your Tracks.',
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                      'Search YouTube to discover music and videos.',
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ...history.map(
                    (q) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, size: 20),
                      title: Text(q, textAlign: TextAlign.start),
                      trailing: const Icon(Icons.north_west, size: 18),
                      onTap: () {
                        input.text = q;
                        setState(() {});
                        search(q);
                      },
                    ),
                  ),
                ],
                if (loading || waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (error != null)
                  EmptyCollection(
                    title: 'Discovery is taking a break',
                    message: error!,
                    icon: Icons.cloud_off_outlined,
                    action: () => search(input.text),
                    actionLabel: 'Try again',
                  ),
                if (!loading &&
                    !waiting &&
                    error == null &&
                    results.isEmpty &&
                    input.text.isNotEmpty)
                  EmptyCollection(
                    title: searched ? 'No videos found' : 'Ready to explore',
                    message: searched
                        ? 'Try another song title or artist.'
                        : 'Type a song title or artist to find music.',
                    icon: Icons.explore_outlined,
                  ),
              ],
            ),
          ),
        ),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  r.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${r.channel} · YouTube',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (r.duration != null)
                                  Text(
                                    clockTime(r.duration!),
                                    textAlign: TextAlign.center,
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
                                    j.sourceType == 'youtube' && j.url == r.id,
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    key: ValueKey('youtube-download-${r.id}'),
                                    onPressed: saved || active
                                        ? null
                                        : () =>
                                              c.run(() => c.downloadYoutube(r)),
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
                                        Uri.https('www.youtube.com', '/watch', {
                                          'v': r.id,
                                        }),
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
                                    job!.error ?? 'Download failed. Try again.',
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
