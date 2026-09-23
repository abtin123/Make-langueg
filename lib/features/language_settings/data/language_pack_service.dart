import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_flags.dart';
import 'language_pack_catalog.dart';

class LanguagePackException implements Exception {
  const LanguagePackException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LanguageDownloadProgress {
  const LanguageDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.resuming,
  });

  final int receivedBytes;
  final int totalBytes;
  final bool resuming;

  double get fraction => totalBytes <= 0
      ? 0
      : (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
}

/// Downloads language packs from the GitHub release published by
/// Make-langueg. No language-pack JSON/manifest is bundled in the APK.
class LanguagePackService {
  LanguagePackService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  List<LanguagePack>? _memory;

  static const Duration _manifestCacheMaxAge = Duration(hours: 12);

  Future<Directory> _packsDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/language_packs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifestCacheFile() async =>
      File('${(await _packsDir()).path}/.manifest.json');

  Future<File> _fileFor(LanguagePack pack) async =>
      File('${(await _packsDir()).path}/${pack.localFileName}');

  Map<String, String> _validateCompleteValues(
    Object? decoded, {
    required String languageCode,
  }) {
    if (decoded is! Map<String, dynamic>) {
      throw LanguagePackException(
          'بستهٔ زبان «$languageCode» ساختار JSON معتبر ندارد.');
    }
    // بسته می‌تواند ناقص باشد؛ کلیدهای موجود روی override ذخیره می‌شوند و
    // کلیدهای غایب/خالی از ترجمهٔ پیش‌فرض خود اپ استفاده می‌کنند.
    return decoded
        .map((key, value) => MapEntry(key, value.toString()))
        .map((key, value) => MapEntry(key, value.trim()))
      ..removeWhere((key, value) => value.isEmpty);
  }

  Future<bool> isDownloaded(LanguagePack pack) async =>
      (await _fileFor(pack)).exists();

  Future<LanguageDownloadProgress> pendingProgress(LanguagePack pack) async {
    final file = await _fileFor(pack);
    final received = await file.exists() ? await file.length() : 0;
    return LanguageDownloadProgress(
      receivedBytes: received,
      totalBytes: pack.sizeBytes,
      resuming: received > 0 && received < pack.sizeBytes,
    );
  }

  Future<void> download(
    LanguagePack pack, {
    void Function(LanguageDownloadProgress progress)? onProgress,
  }) async {
    if (pack.downloadUrl.isEmpty) {
      throw LanguagePackException(
          'برای زبان «${pack.name}» لینک دانلود وجود ندارد.');
    }

    final request = http.Request('GET', Uri.parse(pack.downloadUrl));
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw LanguagePackException(
        'دانلود زبان «${pack.name}» ناموفق بود (HTTP ${response.statusCode}).',
      );
    }

    final advertisedLength = response.contentLength;
    final total = advertisedLength != null && advertisedLength > 0
        ? advertisedLength
        : pack.sizeBytes;
    final bytes = BytesBuilder(copy: false);
    var received = 0;
    onProgress?.call(LanguageDownloadProgress(
      receivedBytes: 0,
      totalBytes: total,
      resuming: false,
    ));

    await for (final chunk in response.stream) {
      bytes.add(chunk);
      received += chunk.length;
      onProgress?.call(LanguageDownloadProgress(
        receivedBytes: received,
        totalBytes: total,
        resuming: false,
      ));
    }

    final packed = bytes.takeBytes();
    Uint8List raw;
    try {
      raw = Uint8List.fromList(gzip.decode(packed));
    } catch (_) {
      throw LanguagePackException(
          'فایل زبان «${pack.name}» بستهٔ ABL معتبر نیست.');
    }

    final values = _validateCompleteValues(
      jsonDecode(utf8.decode(raw)),
      languageCode: pack.code,
    );

    final file = await _fileFor(pack);
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(packed, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);

    // Parse the persisted bytes again before exposing the language to the UI.
    final persisted = await file.readAsBytes();
    final persistedRaw = gzip.decode(persisted);
    final persistedValues = _validateCompleteValues(
      jsonDecode(utf8.decode(persistedRaw)),
      languageCode: pack.code,
    );
    AppStrings.registerDownloadedLanguage(pack.code, persistedValues);

    onProgress?.call(LanguageDownloadProgress(
      receivedBytes: packed.length,
      totalBytes: packed.length,
      resuming: false,
    ));
  }

  Future<List<LanguagePack>> fetchManifest({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null) return _memory!;

    final cache = await _manifestCacheFile();
    if (!forceRefresh && await cache.exists()) {
      try {
        final age = DateTime.now().difference(await cache.lastModified());
        if (age < _manifestCacheMaxAge) {
          return _memory = _parseManifest(
              jsonDecode(await cache.readAsString(encoding: utf8)));
        }
      } catch (_) {}
    }

    try {
      final response = await _client.get(Uri.parse(kLangPacksManifestUrl));
      if (response.statusCode != HttpStatus.ok) {
        throw LanguagePackException(
          'دریافت فهرست زبان‌ها ناموفق بود (HTTP ${response.statusCode}).',
        );
      }
      final body = utf8.decode(response.bodyBytes);
      final parsed = _parseManifest(jsonDecode(body));
      await cache.writeAsString(body, flush: true, encoding: utf8);
      return _memory = parsed;
    } catch (error) {
      try {
        if (await cache.exists()) {
          return _memory = _parseManifest(
              jsonDecode(await cache.readAsString(encoding: utf8)));
        }
      } catch (_) {}
      if (error is LanguagePackException) rethrow;
      throw const LanguagePackException(
          'فهرست زبان‌ها از GitHub در دسترس نیست.');
    }
  }

  List<LanguagePack> _parseManifest(Object? decoded) {
    Object? languagesRaw;
    if (decoded is Map<String, dynamic>) {
      languagesRaw =
          decoded['languages'] ?? decoded['language_packs'] ?? decoded['packs'];
    } else if (decoded is List) {
      languagesRaw = decoded;
    }
    if (languagesRaw is Map) {
      languagesRaw = [
        for (final entry in languagesRaw.entries)
          if (entry.value is Map)
            <String, dynamic>{
              ...Map<String, dynamic>.from(entry.value as Map),
              'language_code': entry.key.toString(),
            },
      ];
    }
    if (languagesRaw is! List) {
      throw const LanguagePackException(
          'manifest زبان ساختار languages معتبری ندارد.');
    }
    final result = <LanguagePack>[];
    for (final item in languagesRaw) {
      if (item is! Map) continue;
      try {
        result.add(
            LanguagePack.fromManifestJson(Map<String, dynamic>.from(item)));
      } on FormatException {
        // Ignore malformed entries, not the complete catalog.
      }
    }
    if (result.isEmpty) {
      throw const LanguagePackException(
          'هیچ بستهٔ زبان قابل دانلودی در manifest پیدا نشد.');
    }
    return result;
  }

  Future<void> delete(LanguagePack pack) async {
    final file = await _fileFor(pack);
    if (await file.exists()) await file.delete();
    AppStrings.unregisterDownloadedLanguage(pack.code);
  }

  Future<Set<String>> loadAllDownloaded() async {
    final loaded = <String>{};
    final dir = await _packsDir();
    if (!await dir.exists()) return loaded;

    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^lang_([a-zA-Z-]+)\.abl$').firstMatch(name);
      if (match == null) continue;
      final code = match.group(1)!.toLowerCase();
      try {
        final packed = await entity.readAsBytes();
        final raw = gzip.decode(packed);
        final values = _validateCompleteValues(
          jsonDecode(utf8.decode(raw)),
          languageCode: code,
        );
        AppStrings.registerDownloadedLanguage(code, values);
        loaded.add(code);
      } catch (_) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    return loaded;
  }

  @override
  void dispose() => _client.close();
}
