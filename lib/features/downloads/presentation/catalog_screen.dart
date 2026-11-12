import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../integrations/authorized_catalog.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.c});
  final AppController c;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<CatalogTrack> tracks = [];
  bool loading = false;
  String? error;
  Future<void> search(String q) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await AuthorizedCatalog().search(q);
      if (mounted) setState(() => tracks = result);
    } catch (e) {
      if (mounted) setState(() => error = widget.c.errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Authorized catalog')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const DotTitle('MORE TO KEEP', height: 28),
        const SizedBox(height: 20),
        TextField(
          textInputAction: TextInputAction.search,
          onSubmitted: search,
          decoration: const InputDecoration(
            hintText: 'Search your connected catalog',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 20),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null)
          EmptyCollection(
            title: 'Catalog unavailable',
            message: error!,
            icon: Icons.cloud_off_outlined,
          ),
        if (!loading && error == null && tracks.isEmpty)
          const EmptyCollection(
            title: 'Find a new rotation',
            message: 'Search music from your connected provider. Only tracks with explicit download permission appear.',
            icon: Icons.travel_explore,
          ),
        ...tracks.map(
          (track) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.audio_file_outlined),
            title: Text(track.title),
            subtitle: Text('${track.artist} · Downloads permitted'),
            trailing: const Icon(Icons.download_outlined),
            onTap: () => chooseVariant(context, widget.c, track),
          ),
        ),
      ],
    ),
  );
}

Future<void> chooseVariant(
  BuildContext context,
  AppController c,
  CatalogTrack track,
) async {
  var selected = track.variants.lastWhere(
    (v) => v.bitrate <= c.quality,
    orElse: () => track.variants.first,
  );
  final chosen = await showGlyphDialog<AudioVariant>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(track.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose an original MP3 offered by this source.'),
            const SizedBox(height: 12),
            ...track.variants.map(
              (v) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  identical(selected, v)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text('${v.bitrate} kbps MP3'),
                onTap: () => set(() => selected = v),
              ),
            ),
            TextButton.icon(
              onPressed: () => c.run(() async {
                if (!await launchUrl(
                  track.license,
                  mode: LaunchMode.externalApplication,
                )) {
                  throw StateError('The license link could not be opened.');
                }
              }),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Source license & permission'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, selected),
            child: const Text('Save offline'),
          ),
        ],
      ),
    ),
  );
  if (chosen != null) {
    await c.run(() => c.download(chosen.url.toString(), track.title));
  }
}
