import 'package:flutter/material.dart';

import '../../../app/app.dart';
import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../core/audio/sleep_timer.dart';
import '../../downloads/presentation/downloads_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../library/presentation/library_screen.dart';
import '../../playlists/presentation/playlists_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.c,
    required this.onLibrary,
    required this.onSearch,
  });
  final AppController c;
  final VoidCallback onLibrary, onSearch;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Row(
          children: [
            const Expanded(child: DotTitle('GLYPH', height: 33)),
            IconButton(
              tooltip: 'Downloads',
              onPressed: () => openPage(context, DownloadsScreen(c: c)),
              icon: const Icon(Icons.downloading_outlined),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => openPage(context, SettingsScreen(c: c)),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.secondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Eyebrow('All yours. Always offline.')),
            const Eyebrow('VOL. 01'),
          ],
        ),
        const SizedBox(height: 22),
        ListenableBuilder(
          listenable: c.sleepTimer,
          builder: (context, _) => Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: c.sleepTimer.active ? colors.secondary : colors.outline,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(
                c.sleepTimer.active ? Icons.bedtime : Icons.bedtime_outlined,
                color: c.sleepTimer.active
                    ? colors.secondary
                    : colors.onSurfaceVariant,
              ),
              title: const Text('Sleep mode'),
              subtitle: Text(
                c.sleepTimer.active
                    ? 'Stops in ${sleepCountdown(c.sleepTimer.remaining)}'
                    : 'Auto-stop after ${sleepDurationLabel(c.sleepMinutes)}',
              ),
              activeTrackColor: colors.secondary,
              value: c.sleepTimer.active,
              onChanged: (value) => c.run(() => c.setSleepMode(value)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xff171717),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Stack(
            children: [
              const Positioned(right: -54, top: 48, child: TransformArt()),
              Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow(
                      'A little less noise.',
                      color: Color(0xffb4b4b4),
                    ),
                    const SizedBox(height: 30),
                    const DotTitle(
                      'YOUR MUSIC.',
                      height: 30,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    const DotTitle(
                      'YOUR SPACE.',
                      height: 30,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 20),
                    const SizedBox(
                      width: 175,
                      child: Text(
                        'Keep the songs.\nLose the distractions.',
                        style: TextStyle(
                          color: Color(0xffaaaaaa),
                          height: 1.7,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Eyebrow(
                      'NO ACCOUNT. NO ALGORITHM.',
                      color: Color(0xff8c8c8c),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionHeading(
          'Made for your mood',
          trailing: IconButton(
            tooltip: 'Search music',
            onPressed: onSearch,
            icon: const Icon(Icons.arrow_outward, size: 21),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _CollectionCard(
                title: 'Favorites',
                caption: '${c.favorites.length} tracks',
                icon: Icons.favorite_border,
                onTap: () => openPage(
                  context,
                  CollectionScreen(c: c, title: 'Favorites', kind: 'favorites'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CollectionCard(
                title: 'On repeat',
                caption: 'Your listening history',
                icon: Icons.history,
                onTap: () => openPage(
                  context,
                  CollectionScreen(
                    c: c,
                    title: 'Recently played',
                    kind: 'recent',
                  ),
                ),
              ),
            ),
          ],
        ),
        if (c.playlists.isNotEmpty) ...[
          const SectionHeading('Your rotations'),
          SizedBox(
            height: 155,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: c.playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final pl = c.playlists[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () =>
                      openPage(context, PlaylistDetail(c: c, id: pl.id)),
                  child: SizedBox(
                    width: 125,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RecordArt(path: pl.artwork, size: 100, seed: i),
                        const SizedBox(height: 8),
                        Text(
                          pl.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${pl.songIds.length} tracks',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        SectionHeading(
          'Recently played',
          trailing: TextButton(
            onPressed: onLibrary,
            child: const Text('View library'),
          ),
        ),
        if (c.recent.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.graphic_eq, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your next favorite starts here'),
                      Text(
                        'Import a track and make yourself at home.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ...c.recent
              .take(4)
              .map((s) => SongTile(c: c, song: s, tracks: c.recent)),
        const SizedBox(height: 32),
        const Center(child: Eyebrow('Less, but better.  /  GLYPH')),
      ],
    );
  }
}

class TransformArt extends StatelessWidget {
  const TransformArt({super.key});
  @override
  Widget build(BuildContext context) =>
      Transform.rotate(angle: -.3, child: const RecordArt(size: 245, seed: 1));
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.title,
    required this.caption,
    required this.icon,
    required this.onTap,
  });
  final String title, caption;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.secondary),
              const Spacer(),
              const Icon(Icons.arrow_outward, size: 16),
            ],
          ),
          const SizedBox(height: 28),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
