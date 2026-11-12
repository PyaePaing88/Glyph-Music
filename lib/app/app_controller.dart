import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show PositionDiscontinuityReason;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/audio/glyph_audio_handler.dart';
import '../core/audio/sleep_timer.dart';
import '../core/widgets/accent_colour.dart';
import '../core/storage/music_importer.dart';
import '../core/storage/phone_audio_scanner.dart';
import '../features/library/data/library_repository.dart';
import '../features/library/domain/song.dart';
import '../integrations/discovery_client.dart';
import '../integrations/youtube_audio_download.dart';

final controllerProvider = Provider<AppController>(
  (ref) => throw UnimplementedError('Override at bootstrap'),
);

class DownloadJob {
  DownloadJob({
    required this.id,
    required this.url,
    required this.name,
    this.status = 'queued',
    this.progress = 0,
    this.error,
    this.sourceType = 'authorized_download',
  });
  final String id, url, name;
  final String sourceType;
  String status;
  double progress;
  String? error;
  CancelToken? token;
}

class AppController extends ChangeNotifier {
  AppController(
    this.repository,
    this.audio, {
    DiscoveryClient? discovery,
    PhoneAudioScanner? phoneScanner,
  }) : importer = MusicImporter(repository),
       phoneScanner = phoneScanner ?? PhoneAudioScanner(),
       discovery =
           discovery ??
           DiscoveryClient(
             Dio(
               BaseOptions(
                 connectTimeout: const Duration(seconds: 15),
                 receiveTimeout: const Duration(seconds: 25),
               ),
             ),
           );
  final LibraryRepository repository;
  final GlyphAudioHandler audio;
  final MusicImporter importer;
  final PhoneAudioScanner phoneScanner;
  bool scanningPhone = false;
  String phoneAudioAccess = Platform.isAndroid ? 'unknown' : 'unsupported';
  String? phoneScanError;
  final DiscoveryClient discovery;
  List<Song> _songs = [];
  Map<String, Song> _songsById = {};
  List<Song> get songs => _songs;
  set songs(List<Song> value) {
    _songs = value;
    _songsById = {for (final song in value) song.id: song};
  }

  List<MusicPlaylist> playlists = [];
  List<String> queueIds = [];
  List<DownloadJob> downloads = [];
  Set<String> youtubeTrackIds = {};
  ThemeMode theme = ThemeMode.system;
  int quality = 192;
  int sleepMinutes = 60;
  late final SleepTimer sleepTimer = SleepTimer(
    onExpired: () => run(() async {
      // Clear the saved deadline before stopping so a later timer cannot be
      // overwritten by an expired timer's asynchronous cleanup.
      await Future.wait<void>([
        repository.setSetting('sleepDeadline', null),
        audio.stop(),
      ]);
      await persistQueue();
      message('Sleep timer finished. Music stopped.');
    }),
  );
  AccentColour accentColour = AccentColour.red;
  bool busy = false;
  String? notice;
  int searchRevision = 0;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _timer;
  String? _historyId;
  int _listenedMs = 0;
  bool _counted = false;
  DateTime? _lastTick;
  int _ticks = 0;
  Song? get current => _songsById[audio.mediaItem.value?.id];

  List<Song> get queueSongs =>
      queueIds.map((id) => _songsById[id]).whereType<Song>().toList();
  List<Song> get favorites => songs.where((s) => s.favorite).toList();
  List<Song> get recent =>
      songs.where((s) => s.lastPlayed != null).toList()
        ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
  int get totalBytes => songs.fold(0, (n, s) => n + s.bytes);
  Future<void> initialize() async {
    await refresh();
    await _readSettings();
    final saved = await repository.setting('playback') as Map<String, dynamic>?;
    if (saved != null) {
      final ids = (saved['ids'] as List).cast<String>();
      queueIds = ids
          .where((id) => songs.any((s) => s.id == id && s.isAvailable))
          .toList();
      if (queueIds.isNotEmpty) {
        final index =
            (saved['index'] as int? ??
                    queueIds.indexOf(saved['current'] as String? ?? ''))
                .clamp(0, queueIds.length - 1);
        try {
          await audio.load(
            queueSongs,
            index: index < 0 ? 0 : index,
            position: Duration(milliseconds: saved['position'] as int? ?? 0),
            autoplay: false,
          );
          await audio.setRepeatMode(
            AudioServiceRepeatMode.values[saved['repeat'] as int? ?? 0],
          );
          await audio.setShuffleMode(
            saved['shuffle'] == true
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
          );
        } catch (_) {
          notice = 'The previous queue could not be restored. Import or select a track to continue.';
        }
      }
    }
    final sleepDeadline = await repository.setting('sleepDeadline');
    await sleepTimer.restore(
      sleepDeadline is int
          ? DateTime.fromMillisecondsSinceEpoch(sleepDeadline)
          : null,
    );
    await repository.db.customStatement(
      "UPDATE downloads SET status='interrupted',error_message='Interrupted. Tap retry to start again.' WHERE status IN ('queued','downloading','validating')",
    );
    downloads =
        (await repository.db.rows(
              'SELECT * FROM downloads ORDER BY created_at DESC',
            ))
            .map(
              (r) => DownloadJob(
                id: r['id'] as String,
                url: r['source_id'] as String? ?? '',
                name: r['display_name'] as String,
                status: r['status'] as String,
                progress: (r['progress'] as num).toDouble(),
                error: r['error_message'] as String?,
                sourceType: r['source_type'] as String,
              ),
            )
            .toList();
    _subscriptions.add(
      audio.mediaItem.listen((_) {
        notifyListeners();
        unawaited(persistQueue());
      }),
    );
    _subscriptions.add(
      audio.playbackState.listen((state) {
        notifyListeners();
        if (!state.playing) unawaited(persistQueue());
      }),
    );
    _subscriptions.add(audio.errors.stream.listen(message));
    _subscriptions.add(
      audio.player.positionDiscontinuityStream.listen((event) {
        if (event.reason == PositionDiscontinuityReason.autoAdvance) {
          _historyId = null;
        }
      }),
    );
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_tick()),
    );
    notifyListeners();
  }

  Future<void> _readSettings() async {
    final mode = await repository.setting('theme');
    theme = ThemeMode.values.firstWhere(
      (v) => v.name == mode,
      orElse: () => ThemeMode.system,
    );
    quality = await repository.setting('quality') as int? ?? 192;
    if (![128, 192, 256, 320].contains(quality)) quality = 192;
    accentColour = AccentColour.fromSetting(
      await repository.setting('accentColour'),
      legacyOrange: await repository.setting('accent') == true,
    );
    await audio.setWidgetAccent(accentColour);
    final savedSleep = await repository.setting('sleepMinutes');
    sleepMinutes = savedSleep is int && savedSleep >= 1 && savedSleep <= 720
        ? savedSleep
        : 60;
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    final id = current?.id;
    final historyKey = '$id:${audio.player.currentIndex}';
    if (historyKey != _historyId) {
      _historyId = historyKey;
      _listenedMs = 0;
      _counted = false;
    }
    final delta = _lastTick == null
        ? 0
        : now.difference(_lastTick!).inMilliseconds.clamp(0, 1500);
    _lastTick = now;
    if (audio.player.playing &&
        audio.playbackState.value.processingState ==
            AudioProcessingState.ready &&
        id != null) {
      _listenedMs += delta;
      // Count only after 30 seconds (or half of a short track), never on a tap.
      final threshold = (current!.durationMs ~/ 2).clamp(1000, 30000);
      if (!_counted && _listenedMs >= threshold) {
        _counted = true;
        await repository.recordPlay(id, _listenedMs);
        await refresh();
      }
    }
    if (++_ticks % 5 == 0) await persistQueue();
  }

  Future<void> persistQueue() async {
    await repository.setSetting('playback', {
      'ids': queueIds,
      'current': current?.id,
      'index': audio.player.currentIndex,
      'position': audio.player.position.inMilliseconds,
      'repeat': audio.playbackState.value.repeatMode.index,
      'shuffle': audio.player.shuffleModeEnabled,
    });
  }

  Future<void> refresh() async {
    songs = await repository.songs();
    playlists = await repository.playlists();
    youtubeTrackIds = await repository.youtubeSourceIds();
    notifyListeners();
  }

  Future<void> scanPhoneAudio({
    bool requestPermission = false,
    bool automatic = false,
  }) async {
    if (scanningPhone || busy) return;
    scanningPhone = true;
    phoneScanError = null;
    notifyListeners();
    try {
      var ask = requestPermission;
      if (automatic && ask) {
        ask = await repository.setting('phone_audio_access_requested') != true;
      }
      if (ask) {
        await repository.setSetting('phone_audio_access_requested', true);
      }
      final result = await phoneScanner.scan(requestPermission: ask);
      phoneAudioAccess = result.access;
      if (result.access != 'granted') return;
      final added = await repository.syncPhoneAudio(result.tracks);
      await refresh();
      final remaining = queueSongs;
      if (remaining.length != queueIds.length) {
        final index = (audio.player.currentIndex ?? 0).clamp(
          0,
          remaining.isEmpty ? 0 : remaining.length - 1,
        );
        final position = audio.player.position;
        final playing = audio.player.playing;
        queueIds = remaining.map((s) => s.id).toList();
        await audio.load(
          remaining,
          index: index,
          position: position,
          autoplay: playing,
        );
        await persistQueue();
      }
      if (!automatic) {
        message(
          '$added new tracks found. ${result.tracks.length} audio files on your phone.',
        );
      }
    } catch (error) {
      phoneScanError = errorText(error);
      if (!automatic) message(phoneScanError!);
    } finally {
      scanningPhone = false;
      notifyListeners();
    }
  }

  Future<void> allowPhoneAudio() async {
    if (phoneAudioAccess == 'blocked') {
      await run(phoneScanner.openSettings);
    } else {
      await scanPhoneAudio(requestPermission: true);
    }
  }

  void message(String value) {
    notice = value;
    notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      message(errorText(e));
    }
  }

  String errorText(Object e) {
    if (e is FormatException) return e.message;
    if (e is FileSystemException) {
      return 'Storage could not be accessed. Check free space and choose the file again.';
    }
    if (e is StateError) return e.message;
    if (e is DioException) {
      return CancelToken.isCancel(e)
          ? 'Download canceled.'
          : 'Download failed. Check your connection and the source link.';
    }
    return 'This action could not be completed. Please try again.';
  }

  Future<void> importMusic({bool folder = false}) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    var added = 0, duplicates = 0, failed = 0;
    try {
      List<(File, String)> files = [];
      if (folder) {
        final dir = await FilePicker.platform.getDirectoryPath();
        if (dir == null) return;
        await for (final file in Directory(
          dir,
        ).list(recursive: true, followLinks: false)) {
          if (file is File && p.extension(file.path).toLowerCase() == '.mp3') {
            files.add((file, p.basename(file.path)));
          }
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp3'],
          allowMultiple: true,
        );
        if (result == null) return;
        files = result.files
            .where((f) => f.path != null)
            .map((f) => (File(f.path!), f.name))
            .toList();
      }
      for (final (file, name) in files) {
        try {
          final song = await importer.importFile(file, name: name);
          song == null ? duplicates++ : added++;
        } catch (_) {
          failed++;
        }
      }
      await refresh();
      message(
        '$added imported · $duplicates duplicates skipped${failed > 0 ? ' · $failed unreadable or unsupported files' : ''}',
      );
    } catch (e) {
      message(errorText(e));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> playSongs(
    List<Song> tracks, {
    int index = 0,
    bool? shuffle,
  }) async => run(() async {
    if (tracks.isEmpty) return;
    _historyId = null;
    queueIds = tracks.map((s) => s.id).toList();
    try {
      await audio.load(
        tracks,
        index: shuffle == true ? math.Random().nextInt(tracks.length) : index,
        autoplay: shuffle == null,
      );
      if (shuffle != null) {
        await audio.setShuffleMode(
          shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
        );
        unawaited(audio.play());
      }
    } catch (_) {
      queueIds = [];
      await persistQueue();
      rethrow;
    }
    await persistQueue();
    notifyListeners();
  });
  Future<void> toggle() => run(() async {
    if (current == null) return;
    if (audio.player.playing) {
      await audio.pause();
      await persistQueue();
    } else {
      if (audio.player.processingState.name == 'completed') {
        await audio.seek(Duration.zero);
      }
      unawaited(audio.play());
    }
  });
  Future<void> favorite(Song s) async {
    await repository.favorite(s);
    await refresh();
  }

  Future<void> clearSearches() async {
    await repository.clearSearches();
    searchRevision++;
    notifyListeners();
  }

  Future<void> enqueue(Song s, {bool next = false}) async {
    final list = queueSongs;
    final playing = audio.player.playing;
    final position = audio.player.position;
    final index = audio.player.currentIndex ?? 0;
    list.insert(next ? (index + 1).clamp(0, list.length) : list.length, s);
    queueIds = list.map((s) => s.id).toList();
    await audio.load(list, index: index, position: position, autoplay: playing);
    await persistQueue();
    message(next ? 'Playing next' : 'Added to queue');
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final oldCurrent = audio.player.currentIndex ?? 0;
    final ids = List<int>.generate(queueIds.length, (i) => i);
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    final list = queueSongs;
    final reordered = ids.map((i) => list[i]).toList();
    final position = audio.player.position, playing = audio.player.playing;
    queueIds = reordered.map((s) => s.id).toList();
    await audio.load(
      reordered,
      index: ids.indexOf(oldCurrent),
      position: position,
      autoplay: playing,
    );
    await persistQueue();
    notifyListeners();
  }

  Future<void> removeQueue(int index) async {
    final list = queueSongs;
    final old = audio.player.currentIndex ?? 0;
    final position = audio.player.position, playing = audio.player.playing;
    list.removeAt(index);
    queueIds = list.map((s) => s.id).toList();
    final newIndex = (index < old ? old - 1 : old).clamp(
      0,
      list.isEmpty ? 0 : list.length - 1,
    );
    await audio.load(
      list,
      index: newIndex,
      position: index == old ? Duration.zero : position,
      autoplay: playing,
    );
    await persistQueue();
    notifyListeners();
  }

  Future<void> clearQueue() async {
    await audio.load([]);
    queueIds = [];
    await persistQueue();
    notifyListeners();
  }

  Future<void> deleteSong(Song s, bool deleteFile) async {
    for (var i = queueIds.length - 1; i >= 0; i--) {
      if (queueIds[i] == s.id) await removeQueue(i);
    }
    if (deleteFile && await importer.isManaged(s.path)) {
      final file = File(s.path);
      if (await file.exists()) await file.delete();
      if (s.artwork != null && await importer.isManaged(s.artwork!)) {
        final art = File(s.artwork!);
        if (await art.exists()) await art.delete();
      }
    }
    await repository.delete(s.id);
    await refresh();
  }

  Future<String?> pickArtwork() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final file = result?.files.first;
    if (file?.path == null) return null;
    if (file!.size > 10 * 1024 * 1024) {
      throw const FormatException('Choose artwork smaller than 10 MB.');
    }
    final target = p.join(
      (await importer.directory).path,
      '${const Uuid().v4()}${p.extension(file.path!)}',
    );
    await File(file.path!).copy(target);
    return target;
  }

  Future<void> setTheme(ThemeMode value) async {
    theme = value;
    await repository.setSetting('theme', value.name);
    notifyListeners();
  }

  Future<void> setQuality(int value) async {
    quality = value;
    await repository.setSetting('quality', value);
    notifyListeners();
  }

  Future<void> setAccentColour(AccentColour value) async {
    await repository.setSetting('accentColour', value.colour.toARGB32());
    accentColour = value;
    notifyListeners();
    await audio.setWidgetAccent(value);
  }

  Future<void> setSleepMode(bool enabled) async {
    if (enabled) {
      sleepTimer.start(Duration(minutes: sleepMinutes));
    } else {
      sleepTimer.cancel();
    }
    await repository.setSetting(
      'sleepDeadline',
      sleepTimer.deadline?.millisecondsSinceEpoch,
    );
  }

  Future<void> setSleepMinutes(int minutes) async {
    if (minutes < 1 || minutes > 720) throw ArgumentError.value(minutes);
    sleepMinutes = minutes;
    await repository.setSetting('sleepMinutes', minutes);
    if (sleepTimer.active) await setSleepMode(true);
    notifyListeners();
  }

  Future<void> exportBackup() async {
    final bytes = Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(await repository.backup()),
      ),
    );
    await FilePicker.platform.saveFile(
      dialogTitle: 'Export Glyph metadata',
      fileName: 'glyph-backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
  }

  Future<void> importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.first.path;
    if (path == null) return;
    if (await File(path).length() > 20 * 1024 * 1024) {
      throw const FormatException('Backup is too large.');
    }
    final count = await repository.restore(
      jsonDecode(await File(path).readAsString()) as Map<String, dynamic>,
    );
    await _readSettings();
    await refresh();
    message(
      'Restored metadata for $count matching tracks. Import original audio separately.',
    );
  }

  Future<void> deleteLocalData() async {
    if (busy || scanningPhone) {
      throw StateError(
        'Wait for the current import to finish before deleting local data.',
      );
    }
    if (downloads.any(
      (j) => ['downloading', 'validating'].contains(j.status),
    )) {
      throw StateError('Cancel active downloads before deleting local data.');
    }
    sleepTimer.cancel();
    await clearQueue();
    final dir = await importer.directory;
    if (await dir.exists()) await dir.delete(recursive: true);
    await repository.db.transaction(() async {
      for (final table in [
        'songs',
        'playlists',
        'downloads',
        'search_history',
        'app_settings',
      ]) {
        await repository.db.customStatement('DELETE FROM $table');
      }
    });
    downloads = [];
    theme = ThemeMode.system;
    quality = 192;
    sleepMinutes = 60;
    accentColour = AccentColour.red;
    await audio.setWidgetAccent(accentColour);
    await refresh();
  }

  Future<void> download(String url, String name, {DownloadJob? retry}) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Use a direct HTTPS MP3 download link.');
    }
    if (_youtubeHost(uri.host)) {
      throw const FormatException(
        'Use Search → YouTube to download this track into your library.',
      );
    }
    if (downloads.any(
      (j) => j.status == 'downloading' || j.status == 'validating',
    )) {
      throw StateError('Wait for the current download or cancel it first.');
    }
    final job =
        retry ??
        DownloadJob(
          id: const Uuid().v4(),
          url: url,
          name: name.trim().isEmpty ? 'Downloaded track' : name.trim(),
        );
    if (retry == null) downloads.insert(0, job);
    job.status = 'downloading';
    job.error = null;
    job.progress = 0;
    job.token = CancelToken();
    notifyListeners();
    await repository.db.customStatement(
      'INSERT INTO downloads(id,source_type,source_id,display_name,destination_path,status,created_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,error_message=NULL,progress=0',
      [
        job.id,
        'authorized_download',
        url,
        job.name,
        '',
        'downloading',
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final temp = File(
      p.join((await getTemporaryDirectory()).path, '${job.id}.part'),
    );
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: false,
      ),
    );
    IOSink? sink;
    try {
      var location = uri;
      Response<ResponseBody>? response;
      for (var n = 0; n < 6; n++) {
        response = await client.get<ResponseBody>(
          location.toString(),
          options: Options(
            responseType: ResponseType.stream,
            validateStatus: (s) => s != null && s >= 200 && s < 400,
          ),
          cancelToken: job.token,
        );
        if (response.statusCode! >= 300) {
          await response.data!.stream.drain<void>();
          location = location.resolve(response.headers.value('location') ?? '');
          if (location.scheme != 'https' || _youtubeHost(location.host)) {
            throw const FormatException(
              'The source redirected to an unsupported location.',
            );
          }
        } else {
          break;
        }
      }
      if (response == null || response.statusCode! >= 300) {
        throw const FormatException('Too many redirects from the source.');
      }
      final total = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      await importer.checkSpace(total ?? MusicImporter.maxBytes, copies: 2);
      sink = temp.openWrite();
      var received = 0, lastUpdate = DateTime.now();
      await for (final chunk in response.data!.stream) {
        if (job.token!.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.cancel,
          );
        }
        received += chunk.length;
        if (received > MusicImporter.maxBytes) {
          throw const FormatException('Download exceeds the 500 MB limit.');
        }
        sink.add(chunk);
        if (DateTime.now().difference(lastUpdate).inMilliseconds > 250) {
          job.progress = total == null ? 0 : received / total;
          notifyListeners();
          lastUpdate = DateTime.now();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (job.token!.isCancelled) {
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        );
      }
      if (total != null && received != total) {
        throw const FormatException('Download was incomplete. Please retry.');
      }
      job.status = 'validating';
      notifyListeners();
      final song = await importer.importFile(
        temp,
        name: '${job.name}.mp3',
        sourceType: 'authorized_download',
      );
      job.status = song == null ? 'duplicate' : 'completed';
      job.progress = 1;
      await refresh();
    } catch (e) {
      job.status = job.token!.isCancelled ? 'canceled' : 'failed';
      job.error = errorText(e);
    } finally {
      await sink?.close();
      if (await temp.exists()) await temp.delete();
      client.close(force: true);
      await repository.db.customStatement(
        'UPDATE downloads SET status=?,progress=?,error_message=?,completed_at=? WHERE id=?',
        [
          job.status,
          job.progress,
          job.error,
          DateTime.now().millisecondsSinceEpoch,
          job.id,
        ],
      );
      notifyListeners();
    }
  }

  Future<void> retryDownload(DownloadJob job) async {
    if (job.sourceType == 'youtube') {
      final result = await discovery.details(job.url);
      await downloadYoutube(result, retry: job);
    } else {
      await download(job.url, job.name, retry: job);
    }
  }

  Future<void> downloadYoutube(
    DiscoveryResult result, {
    DownloadJob? retry,
  }) async {
    if (downloads.any(
      (j) => ['downloading', 'validating'].contains(j.status),
    )) {
      throw StateError('Wait for the current download or cancel it first.');
    }
    if (youtubeTrackIds.contains(result.id)) {
      message('Already saved in Tracks.');
      return;
    }
    final job =
        retry ??
        DownloadJob(
          id: const Uuid().v4(),
          url: result.id,
          name: result.title,
          sourceType: 'youtube',
        );
    if (retry == null) downloads.insert(0, job);
    job.status = 'downloading';
    job.error = null;
    job.progress = 0;
    job.token = CancelToken();
    notifyListeners();
    try {
      await repository.db.customStatement(
        'INSERT INTO downloads(id,source_type,source_id,display_name,destination_path,status,created_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,error_message=NULL,progress=0',
        [
          job.id,
          'youtube',
          result.id,
          result.title,
          '',
          'downloading',
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      final song = await YoutubeAudioDownload().save(
        result,
        importer,
        token: job.token!,
        onProgress: (progress) {
          job.progress = progress;
          notifyListeners();
        },
        onValidating: () {
          job.status = 'validating';
          notifyListeners();
        },
        targetBitrate: quality,
      );
      job.status = song == null ? 'duplicate' : 'completed';
      job.progress = 1;
      await refresh();
      message(
        song == null
            ? 'Already saved in Tracks.'
            : 'Saved to Tracks. Ready offline.',
      );
    } catch (e) {
      job.status = job.token!.isCancelled ? 'canceled' : 'failed';
      job.error = job.token!.isCancelled ? null : errorText(e);
    } finally {
      await repository.db.customStatement(
        'UPDATE downloads SET status=?,progress=?,error_message=?,completed_at=? WHERE id=?',
        [
          job.status,
          job.progress,
          job.error,
          DateTime.now().millisecondsSinceEpoch,
          job.id,
        ],
      );
      notifyListeners();
    }
  }

  Future<void> widgetPlayback(String action) => run(() async {
    await sleepTimer.expireIfDue();
    if (!['play_pause', 'previous', 'next'].contains(action)) return;
    if (current == null || audio.queue.value.isEmpty) {
      final available = queueSongs.where((s) => s.isAvailable).toList();
      if (available.isEmpty) {
        message('Choose a song from Tracks before using playback controls.');
        return;
      }
      queueIds = available.map((s) => s.id).toList();
      await audio.load(available, autoplay: false);
    }
    if (action == 'play_pause') {
      await toggle();
    } else {
      if (action == 'previous') await audio.skipToPrevious();
      if (action == 'next') await audio.skipToNext();
      unawaited(audio.play());
    }
    await persistQueue();
  });

  bool _youtubeHost(String host) => [
    'youtube.com',
    'youtu.be',
    'googlevideo.com',
    'youtube-nocookie.com',
  ].any((h) => host == h || host.endsWith('.$h'));
  @override
  void dispose() {
    sleepTimer.dispose();
    _timer?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
