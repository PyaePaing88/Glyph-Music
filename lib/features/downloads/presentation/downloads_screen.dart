import 'package:flutter/material.dart';

import '../../../app/app.dart';
import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../integrations/authorized_catalog.dart';
import 'catalog_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => LivePage(
    c: c,
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (AuthorizedCatalog.configured)
            IconButton(
              tooltip: 'Browse authorized catalog',
              onPressed: () => openPage(context, CatalogScreen(c: c)),
              icon: const Icon(Icons.travel_explore),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Theme.of(context).colorScheme.onSurface,
        foregroundColor: Theme.of(context).colorScheme.surface,
        onPressed: () => newDownload(context, c),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
        children: [
          const DotTitle('KEEP THE MUSIC', height: 27),
          const SizedBox(height: 16),
          Text(
            'Save audio from a source that permits downloads. Files stay on your device, ready for offline listening.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (c.downloads.isEmpty)
            const EmptyCollection(
              title: 'Good things, kept close.',
              message: 'Add an authorized direct MP3 link, or import music you already own from your library.',
              icon: Icons.downloading_outlined,
            ),
          ...c.downloads.map(
            (j) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        j.status == 'completed'
                            ? Icons.offline_pin_outlined
                            : Icons.downloading_outlined,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          j.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (j.status == 'downloading')
                        IconButton(
                          tooltip: 'Cancel download',
                          onPressed: () => j.token?.cancel(),
                          icon: const Icon(Icons.close),
                        ),
                      if ([
                        'failed',
                        'canceled',
                        'interrupted',
                      ].contains(j.status))
                        IconButton(
                          tooltip: 'Retry download',
                          onPressed: () =>
                              c.run(() => c.retryDownload(j)),
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (['downloading', 'validating'].contains(j.status)) ...[
                    LinearProgressIndicator(
                      value: j.progress == 0 || j.status == 'validating'
                          ? null
                          : j.progress,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    j.status == 'downloading'
                        ? (j.progress == 0
                              ? 'Downloading…'
                              : '${(j.progress * 100).toStringAsFixed(0)}% downloaded')
                        : j.status == 'duplicate'
                        ? 'Already in your library'
                        : j.status == 'completed'
                        ? 'Saved · Ready offline'
                        : j.status == 'validating'
                        ? 'Checking audio and saving…'
                        : j.status,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (j.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        j.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> newDownload(BuildContext context, AppController c) async {
  final url = TextEditingController(), name = TextEditingController();
  var authorized = false;
  String? error;
  final ok = await showGlyphDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Add an authorized source'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Track name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Direct HTTPS MP3 link',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'The original MP3 is preserved. Quality depends on the source; this app does not upscale or convert audio.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: authorized,
                onChanged: (v) => set(() => authorized = v!),
                title: const Text(
                  'I own this audio or the source explicitly permits downloading it.',
                ),
                subtitle: const Text('For YouTube audio, use Search → YouTube.'),
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
            onPressed: !authorized
                ? null
                : () {
                    final uri = Uri.tryParse(url.text.trim());
                    if (uri == null ||
                        uri.scheme != 'https' ||
                        uri.host.isEmpty) {
                      set(() => error = 'Enter a valid HTTPS link');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
            child: const Text('Download'),
          ),
        ],
      ),
    ),
  );
  final source = url.text.trim(), title = name.text.trim();
  // Route transitions may still paint fields; Flutter owns their final frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    url.dispose();
    name.dispose();
  });
  if (ok == true) c.run(() => c.download(source, title));
}
