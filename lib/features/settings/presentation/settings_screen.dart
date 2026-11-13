import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app.dart';
import '../../../app/app_controller.dart';
import '../../../core/widgets/design.dart';
import '../../../core/widgets/accent_colour.dart';
import '../../../core/audio/sleep_timer.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) => LivePage(
    c: c,
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          const SectionHeading('Appearance'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.contrast,
                title: 'Theme',
                subtitle: switch (c.theme) {
                  ThemeMode.system => 'Follow phone settings',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                },
                onTap: () => _chooseTheme(context, c),
              ),
              _SettingsRow(
                icon: Icons.palette_outlined,
                title: 'Accent colour',
                subtitle: c.accentColour.label,
                onTap: () => _chooseAccentColour(context, c),
              ),
            ],
          ),
          const SectionHeading('Music'),
          _SettingsGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.graphic_eq),
                title: const Text('Music visualizer'),
                subtitle: Text(c.musicVisualizerStatus),
                value: c.musicVisualizerEnabled,
                onChanged: c.changingMusicVisualizer
                    ? null
                    : (value) => c.run(() => c.setMusicVisualizer(value)),
              ),
              _SettingsRow(
                icon: Icons.bedtime_outlined,
                title: 'Sleep timer',
                subtitle: sleepDurationLabel(c.sleepMinutes),
                onTap: () => _chooseSleepDuration(context, c),
              ),
              if (Platform.isAndroid)
                _SettingsRow(
                  icon: Icons.battery_full,
                  title: 'Background playback',
                  subtitle: 'If music stops, allow background usage or unrestricted battery use in app settings.',
                  onTap: () async {
                    try {
                      await const MethodChannel('glyph/background_playback')
                          .invokeMethod<void>('openAppSettings');
                    } on PlatformException {
                      c.message(
                        'Open phone Settings > Apps > Glyph Music > Battery to allow background usage.',
                      );
                    } on MissingPluginException {
                      c.message(
                        'Open phone Settings > Apps > Glyph Music > Battery to allow background usage.',
                      );
                    }
                  },
                ),
              if (c.phoneAudioAccess != 'unsupported')
                _SettingsRow(
                  icon: Icons.library_music_outlined,
                  title: c.scanningPhone
                      ? 'Finding music…'
                      : 'Scan phone audio',
                  subtitle: 'Find music stored on your phone',
                  onTap: c.scanningPhone ? null : c.allowPhoneAudio,
                ),
              _SettingsRow(
                icon: Icons.high_quality_outlined,
                title: 'Download quality',
                subtitle: '${c.quality} kbps',
                onTap: () => _chooseQuality(context, c),
              ),
            ],
          ),
          const SectionHeading('Library'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.storage_outlined,
                title: 'Storage',
                subtitle:
                    '${c.songs.length} tracks · ${fileSize(c.totalBytes)}',
                onTap: () => openPage(context, _StorageSettings(c: c)),
              ),
              _SettingsRow(
                icon: Icons.backup_outlined,
                title: 'Backup & restore',
                subtitle: 'Playlists, favorites and settings',
                onTap: () => openPage(context, _BackupSettings(c: c)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy & data',
                subtitle: 'Searches, listening history and app data',
                onTap: () => openPage(context, _PrivacySettings(c: c)),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Glyph Music · 1.3',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).dividerColor),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 56, endIndent: 16),
          child,
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    leading: Icon(
      icon,
      size: 22,
      color: destructive ? Theme.of(context).colorScheme.error : null,
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 15,
        color: destructive ? Theme.of(context).colorScheme.error : null,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

Future<void> _chooseAccentColour(BuildContext context, AppController c) async {
  var hsv = HSVColor.fromColor(c.accentColour.colour);
  final hex = TextEditingController(text: c.accentColour.label.substring(1));
  String? error;
  final choice = await showGlyphDialog<AccentColour>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final accent = AccentColour(hsv.toColor());
        void update(HSVColor value) => set(() {
          hsv = value;
          hex.text = AccentColour(value.toColor()).label.substring(1);
          error = null;
        });
        return AlertDialog(
          title: const Text('Accent colour'),
          scrollable: true,
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: accent.colour,
                    child: Icon(
                      Icons.play_arrow,
                      color: accent.foreground,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Hue'),
                Slider(
                  semanticFormatterCallback: (v) => '${v.round()} degrees',
                  value: hsv.hue,
                  max: 360,
                  onChanged: (v) => update(hsv.withHue(v)),
                ),
                const Text('Saturation'),
                Slider(
                  semanticFormatterCallback: (v) =>
                      '${(v * 100).round()} percent',
                  value: hsv.saturation,
                  onChanged: (v) => update(hsv.withSaturation(v)),
                ),
                const Text('Brightness'),
                Slider(
                  semanticFormatterCallback: (v) =>
                      '${(v * 100).round()} percent',
                  value: hsv.value,
                  onChanged: (v) => update(hsv.withValue(v)),
                ),
                TextField(
                  controller: hex,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Hex colour',
                    prefixText: '#',
                    errorText: error,
                  ),
                  onChanged: (value) => set(() {
                    final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value);
                    error = valid ? null : 'Enter 6 hex digits';
                    if (valid) {
                      hsv = HSVColor.fromColor(
                        Color(0xff000000 | int.parse(value, radix: 16)),
                      );
                    }
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: error == null
                  ? () => Navigator.pop(ctx, accent)
                  : null,
              child: const Text('Apply'),
            ),
          ],
        );
      },
    ),
  );
  hex.dispose();
  if (choice != null) await c.run(() => c.setAccentColour(choice));
}

Future<void> _chooseSleepDuration(BuildContext context, AppController c) async {
  const presets = [15, 30, 45, 60, 90, 120];
  var choice = await showGlyphDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sleep timer'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.sleepTimer.active
                  ? 'Changing the duration restarts the current timer.'
                  : 'Switch Sleep mode on from Home to start the timer.',
            ),
            const SizedBox(height: 12),
            RadioGroup<int>(
              groupValue: c.sleepMinutes,
              onChanged: (value) => Navigator.pop(ctx, value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final minutes in [
                    ...presets,
                    if (!presets.contains(c.sleepMinutes)) c.sleepMinutes,
                  ])
                    RadioListTile(
                      value: minutes,
                      title: Text(sleepDurationLabel(minutes)),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, -1),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Custom duration'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (choice == -1 && context.mounted) {
    final input = TextEditingController(text: '${c.sleepMinutes}');
    var invalid = false;
    choice = await showGlyphDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          void save() {
            final value = int.tryParse(input.text);
            if (value == null || value < 1 || value > 720) {
              set(() => invalid = true);
            } else {
              Navigator.pop(ctx, value);
            }
          }

          return AlertDialog(
            title: const Text('Custom duration'),
            scrollable: true,
            content: TextField(
              controller: input,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 3,
              onSubmitted: (_) => save(),
              decoration: InputDecoration(
                labelText: 'Minutes',
                helperText: '1 to 720 minutes',
                errorText: invalid ? 'Enter 1 to 720 minutes' : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(onPressed: save, child: const Text('Save')),
            ],
          );
        },
      ),
    );
    input.dispose();
  }
  if (choice != null && choice > 0) {
    final minutes = choice;
    await c.run(() => c.setSleepMinutes(minutes));
  }
}

Future<void> _chooseTheme(BuildContext context, AppController c) async {
  final choice = await showGlyphDialog<ThemeMode>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Theme'),
      content: SizedBox(
        width: 360,
        child: RadioGroup<ThemeMode>(
          groupValue: c.theme,
          onChanged: (value) => Navigator.pop(ctx, value),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile(
                value: ThemeMode.system,
                title: Text('System'),
                subtitle: Text('Follow phone settings'),
              ),
              RadioListTile(value: ThemeMode.light, title: Text('Light')),
              RadioListTile(value: ThemeMode.dark, title: Text('Dark')),
            ],
          ),
        ),
      ),
      scrollable: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (choice != null) await c.run(() => c.setTheme(choice));
}

Future<void> _chooseQuality(BuildContext context, AppController c) async {
  final choice = await showGlyphDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Download quality'),
      content: SizedBox(
        width: 360,
        child: RadioGroup<int>(
          groupValue: c.quality,
          onChanged: (value) => Navigator.pop(ctx, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Used when a download offers more than one MP3 quality.',
              ),
              const SizedBox(height: 12),
              for (final quality in [128, 192, 256, 320])
                RadioListTile(value: quality, title: Text('$quality kbps')),
            ],
          ),
        ),
      ),
      scrollable: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (choice != null) await c.run(() => c.setQuality(choice));
}

class _StorageSettings extends StatelessWidget {
  const _StorageSettings({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) => LivePage(
    c: c,
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.library_music_outlined,
                title: '${c.songs.length} tracks',
                subtitle: '${fileSize(c.totalBytes)} of library audio',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Music on your phone stays in its original location. Imported files are copied into Glyph.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Uninstalling Glyph removes its imported copies. Keep a separate backup of your music.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.cleaning_services_outlined,
                title: 'Clear temporary files',
                subtitle: 'Your library and playlists are kept',
                onTap: () => c.run(() async {
                  if (c.busy ||
                      c.downloads.any(
                        (d) =>
                            d.status == 'downloading' ||
                            d.status == 'validating',
                      )) {
                    throw StateError(
                      'Wait for current imports or downloads to finish.',
                    );
                  }
                  await FilePicker.platform.clearTemporaryFiles();
                  c.message('Temporary files cleared.');
                }),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _BackupSettings extends StatelessWidget {
  const _BackupSettings({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & restore')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Save your playlists, favorites, track details and settings.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Music and artwork are not included. Back up those files separately.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.ios_share,
              title: 'Export backup',
              subtitle: 'Save a backup file',
              onTap: () => c.run(c.exportBackup),
            ),
            _SettingsRow(
              icon: Icons.file_download_outlined,
              title: 'Restore backup',
              subtitle: 'Choose a saved backup file',
              onTap: () => c.run(c.importBackup),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Before restoring, import the same MP3s into your library. Restore adds playlists and updates matching tracks.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _PrivacySettings extends StatelessWidget {
  const _PrivacySettings({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & data')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Your library stays on this device.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'No account, analytics or cloud sync. Online searches and downloads connect to YouTube or your configured search server and follow those services’ privacy policies.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.search_off,
              title: 'Clear recent searches',
              onTap: () => c.run(() async {
                await c.clearSearches();
                c.message('Recent searches cleared.');
              }),
            ),
            _SettingsRow(
              icon: Icons.history,
              title: 'Clear listening history',
              subtitle: 'Reset play counts and recently played',
              onTap: () => c.run(() async {
                if (await confirm(
                  context,
                  'Clear listening history?',
                  'Play counts and recently played activity will be reset.',
                )) {
                  await c.repository.clearHistory();
                  await c.refresh();
                }
              }),
            ),
          ],
        ),
        const SectionHeading('Reset'),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.delete_outline,
              title: 'Delete all app data',
              subtitle: 'Remove imported music, playlists and settings',
              destructive: true,
              onTap: () => c.run(() async {
                if (await confirm(
                  context,
                  'Delete all Glyph data?',
                  'This permanently deletes audio copied into Glyph and all local app records. Back up your audio first. Your original source files remain untouched.',
                )) {
                  await c.deleteLocalData();
                }
              }),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showGlyphDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        scrollable: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;
