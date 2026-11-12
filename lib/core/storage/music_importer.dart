import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/library/data/library_repository.dart';
import '../../features/library/domain/song.dart';

class MusicImporter {
  MusicImporter(this.repository);
  final LibraryRepository repository;
  static const maxBytes = 500 * 1024 * 1024;
  static const platform = MethodChannel('glyph/storage');
  Future<Directory> get directory async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'music'))..createSync(recursive: true);
  }

  Future<void> checkSpace(int bytes, {int copies = 1}) async {
    if (bytes <= 0 || bytes > maxBytes) {
      throw const FormatException('Choose an MP3 smaller than 500 MB.');
    }
    if (Platform.isAndroid) {
      final free = await platform.invokeMethod<int>('availableBytes');
      if (free != null && free < bytes * copies + 10 * 1024 * 1024) {
        throw const FileSystemException('Not enough free device storage.');
      }
    }
  }

  Future<Song?> importFile(
    File source, {
    String? name,
    String sourceType = 'import',
  }) async {
    await checkSpace(await source.length());
    final hash = (await sha256.bind(source.openRead()).first).toString();
    if (await repository.containsHash(hash)) return null;
    final dir = await directory;
    final id = const Uuid().v4();
    final temp = File(p.join(dir.path, '$id.part'));
    final target = File(p.join(dir.path, '$id.mp3'));
    File? artwork;
    final probe = AudioPlayer();
    try {
      final tags = await readMp3Tags(source);
      await source.copy(temp.path);
      await temp.rename(target.path);
      final duration = await probe
          .setFilePath(target.path)
          .timeout(const Duration(seconds: 15));
      if (duration == null || duration.inMilliseconds <= 0) {
        throw const FormatException('This file has no playable MP3 audio.');
      }
      if (tags.picture != null) {
        artwork = File(p.join(dir.path, '$id.jpg'));
        await artwork.writeAsBytes(tags.picture!, flush: true);
      }
      final song = Song(
        id: id,
        title: tags.title ?? p.basenameWithoutExtension(name ?? source.path),
        artist: tags.artist ?? 'Unknown artist',
        album: tags.album ?? '',
        genre: tags.genre ?? '',
        path: target.path,
        hash: hash,
        bytes: await target.length(),
        durationMs: duration.inMilliseconds,
        createdAt: DateTime.now(),
        artwork: artwork?.path,
        bitrate: tags.bitrate,
      );
      await repository.addSong(song, source: sourceType);
      return song;
    } catch (_) {
      if (await target.exists()) await target.delete();
      if (artwork != null && await artwork.exists()) await artwork.delete();
      rethrow;
    } finally {
      await probe.dispose();
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<bool> isManaged(String path) async =>
      !path.startsWith('content://') &&
      p.isWithin((await directory).path, p.normalize(p.absolute(path)));

  Future<Song?> importDownloadedAudio(
    File source, {
    required String videoId,
    required String title,
    required String artist,
    required String extension,
    required int bitrate,
    Uint8List? cover,
    bool Function()? isCanceled,
  }) async {
    if (!['m4a', 'webm'].contains(extension)) {
      throw const FormatException('Unsupported audio format.');
    }
    await checkSpace(await source.length());
    final hash = (await sha256.bind(source.openRead()).first).toString();
    if (await repository.containsHash(hash) ||
        await repository.hasSource('youtube', videoId)) {
      return null;
    }
    final dir = await directory;
    final id = const Uuid().v4();
    final target = File(p.join(dir.path, '$id.$extension'));
    File? artwork;
    final probe = AudioPlayer();
    try {
      await source.copy(target.path);
      final duration = await probe
          .setFilePath(target.path)
          .timeout(const Duration(seconds: 20));
      if (duration == null || duration.inMilliseconds <= 0) {
        throw const FormatException(
          'The downloaded audio is incomplete or cannot be played.',
        );
      }
      if (isCanceled?.call() == true) throw StateError('Download canceled.');
      if (cover != null &&
          cover.isNotEmpty &&
          cover.length <= 2 * 1024 * 1024) {
        artwork = File(p.join(dir.path, '$id.jpg'));
        await artwork.writeAsBytes(cover, flush: true);
      }
      final song = Song(
        id: id,
        title: title,
        artist: artist,
        path: target.path,
        hash: hash,
        bytes: await target.length(),
        durationMs: duration.inMilliseconds,
        createdAt: DateTime.now(),
        artwork: artwork?.path,
        bitrate: bitrate,
      );
      if (isCanceled?.call() == true) throw StateError('Download canceled.');
      await repository.addSong(
        song,
        source: 'youtube',
        sourceId: videoId,
        mimeType: extension == 'm4a' ? 'audio/mp4' : 'audio/webm',
      );
      return song;
    } catch (_) {
      if (await target.exists()) await target.delete();
      if (artwork != null && await artwork.exists()) await artwork.delete();
      rethrow;
    } finally {
      await probe.dispose();
    }
  }
}

class Mp3Tags {
  String? title, artist, album, genre;
  Uint8List? picture;
  int? bitrate;
}

int _syncSafe(List<int> b, int at) =>
    ((b[at] & 127) << 21) |
    ((b[at + 1] & 127) << 14) |
    ((b[at + 2] & 127) << 7) |
    (b[at + 3] & 127);
String _tagText(List<int> b) {
  if (b.isEmpty) return '';
  final encoding = b.first;
  final bytes = b.sublist(1);
  String text;
  if (encoding == 1 || encoding == 2) {
    var start = 0;
    var little = false;
    if (bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 254) {
      little = true;
      start = 2;
    } else if (bytes.length >= 2 && bytes[0] == 254 && bytes[1] == 255) {
      start = 2;
    }
    text = String.fromCharCodes([
      for (var i = start; i + 1 < bytes.length; i += 2)
        little
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
    ]);
  } else {
    text = encoding == 3
        ? utf8.decode(bytes, allowMalformed: true)
        : latin1.decode(bytes);
  }
  return text.replaceAll('\u0000', '').trim();
}

/// Reads a bounded ID3v2.3/v2.4 tag and confirms an MPEG Layer III frame.
Future<Mp3Tags> readMp3Tags(File file) async {
  final tags = Mp3Tags();
  final handle = await file.open();
  try {
    final head = await handle.read(10);
    var offset = 0;
    if (head.length < 10) {
      throw const FormatException('The audio file is empty or incomplete.');
    }
    if (ascii.decode(head.take(3).toList(), allowInvalid: true) == 'ID3') {
      final size = _syncSafe(head, 6);
      final version = head[3];
      offset = 10 + size;
      if (size > 8 * 1024 * 1024) {
        throw const FormatException('The MP3 metadata is too large.');
      }
      final data = await handle.read(size);
      if (data.length != size) {
        throw const FormatException('Incomplete MP3 metadata.');
      }
      if ((version == 3 || version == 4) && head[5] & 0xc0 == 0) {
        var at = 0;
        while (at + 10 <= data.length) {
          final key = ascii.decode(
            data.sublist(at, at + 4),
            allowInvalid: true,
          );
          final length = version == 4
              ? _syncSafe(data, at + 4)
              : ByteData.sublistView(data).getUint32(at + 4);
          if (length <= 0 || at + 10 + length > data.length) break;
          final flags = data[at + 9];
          final body = data.sublist(at + 10, at + 10 + length);
          if (flags == 0) {
            final text = key.startsWith('T') ? _tagText(body) : '';
            if (text.isNotEmpty) {
              switch (key) {
                case 'TIT2':
                  tags.title = text;
                case 'TPE1':
                  tags.artist = text;
                case 'TALB':
                  tags.album = text;
                case 'TCON':
                  tags.genre = text;
              }
            }
            if (key == 'APIC' && body.length > 5 && body[0] == 0) {
              final mimeEnd = body.indexOf(0, 1);
              final descEnd = mimeEnd < 0 ? -1 : body.indexOf(0, mimeEnd + 2);
              if (descEnd >= 0 && descEnd + 1 < body.length) {
                tags.picture = Uint8List.fromList(body.sublist(descEnd + 1));
              }
            }
          }
          at += 10 + length;
        }
      }
    }
    await handle.setPosition(offset);
    final audio = await handle.read(65536);
    var valid = false;
    for (var i = 0; i + 4 < audio.length; i++) {
      final b = audio[i + 1], c = audio[i + 2];
      if (audio[i] == 255 &&
          b & 0xe0 == 0xe0 &&
          b & 6 == 2 &&
          b & 0x18 != 8 &&
          c >> 4 > 0 &&
          c >> 4 < 15 &&
          c & 12 != 12) {
        const v1 = [
          0,
          32,
          40,
          48,
          56,
          64,
          80,
          96,
          112,
          128,
          160,
          192,
          224,
          256,
          320,
        ];
        const v2 = [
          0,
          8,
          16,
          24,
          32,
          40,
          48,
          56,
          64,
          80,
          96,
          112,
          128,
          144,
          160,
        ];
        tags.bitrate = (b & 0x18 == 0x18 ? v1 : v2)[c >> 4];
        valid = true;
        break;
      }
    }
    if (!valid) {
      throw const FormatException('This is not a supported MP3 file.');
    }
    if (await file.length() >= 128) {
      await handle.setPosition(await file.length() - 128);
      final tail = await handle.read(128);
      if (ascii.decode(tail.take(3).toList(), allowInvalid: true) == 'TAG') {
        String value(int a, int b) =>
            latin1.decode(tail.sublist(a, b)).replaceAll('\u0000', '').trim();
        tags.title ??= value(3, 33).isEmpty ? null : value(3, 33);
        tags.artist ??= value(33, 63).isEmpty ? null : value(33, 63);
        tags.album ??= value(63, 93).isEmpty ? null : value(63, 93);
      }
    }
    return tags;
  } finally {
    await handle.close();
  }
}
