import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/network/resumable_file_downloader.dart';

/// آدرس پایه‌ی انتشار نقشه‌های ABTINMAP (ریپوی abtin-maps).
const String kAbmReleaseBase = String.fromEnvironment(
  'ABTIN_MAP_BASE',
  defaultValue:
      'https://github.com/abtin123/abtin-maps/releases/download/maps-v4',
);

const String kAbmManifestUrl = '$kAbmReleaseBase/manifest.json';

class AbmFormatException implements Exception {
  const AbmFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// یک فایل قابل دانلود از ریلیز گیت‌هاب: یا کل نقشهٔ یک کشور (تک‌فایلی)
/// یا یکی از پارت‌های یک نقشهٔ چندپارتی (`XX.abm.part0`, `XX.abm.part1`, ...).
///
/// از آنجا که هر آبجکت ریلیزِ گیت‌هاب حداکثر ۲ گیگابایت است، مانیفست برای
/// کشورهای بزرگ‌تر (مثل کانادا، آلمان، فرانسه، روسیه) به‌جای یک فایل، چند
/// پارت منتشر می‌کند که باید به ترتیب دانلود و به هم چسبانده شوند.
class AbmFilePart {
  const AbmFilePart({required this.name, this.size = 0, this.sha256 = ''});

  final String name;
  final int size;

  /// هش SHA-256 این پارت (برای اعتبارسنجی پس از دانلود). ممکن است خالی باشد.
  final String sha256;

  factory AbmFilePart.fromJson(Map<String, dynamic> json) => AbmFilePart(
        name: json['name'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        sha256: (json['sha256'] as String?) ?? '',
      );
}

/// ارجاع مانیفست به patch باینریِ افزایشی میان یک نسخهٔ مشخص و نسخهٔ جدید.
/// patch تنها زمانی معتبر است که هش ABM نصب‌شده با [baseSha256] برابر باشد.
class AbmMapPatch {
  const AbmMapPatch({
    required this.baseSha256,
    required this.manifestFile,
    required this.binFile,
    required this.size,
    required this.sha256,
  });

  final String baseSha256;
  final String manifestFile;
  final String binFile;
  final int size;
  final String sha256;

  factory AbmMapPatch.fromJson(Map<String, dynamic> json) => AbmMapPatch(
        baseSha256: (json['base_sha256'] as String?) ?? '',
        manifestFile: (json['manifest_file'] as String?) ?? '',
        binFile: (json['bin_file'] as String?) ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        sha256: (json['sha256'] as String?) ?? '',
      );

  bool get isUsable =>
      baseSha256.isNotEmpty && manifestFile.isNotEmpty && binFile.isNotEmpty;
}

class AbmDownloadCancelled implements Exception {
  const AbmDownloadCancelled();
  @override
  String toString() => 'دانلود توسط کاربر متوقف شد.';
}

class AbmDownloadProgress {
  const AbmDownloadProgress(this.received, this.total);
  final int received;
  final int? total;
  double? get fraction =>
      (total == null || total == 0) ? null : received / total!;
}

/// دانلود، کش و باز کردن فایل‌های .abm به‌صورت کاملاً آفلاین‌محور:
/// یک‌بار دانلود، سپس همه‌ی مسیریابی/رندر از فایل لوکال خوانده می‌شود.
class AbmMapService {
  AbmMapService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Directory? _dir;

  Future<Directory> _mapsDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'abtinmap'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<File> localFile(String name) async =>
      File(p.join((await _mapsDir()).path, name));

  Future<File> _versionFile(String name) async =>
      File(p.join((await _mapsDir()).path, '$name.version'));

  Future<bool> isInstalled(String name) async =>
      (await localFile(name)).exists();

  Future<String?> installedVersion(String name) async {
    final f = await _versionFile(name);
    if (!await f.exists()) return null;
    return (await f.readAsString()).trim();
  }

  /// دانلود (یا به‌روزرسانی) نقشه. اگر فایل موجود و هم‌نسخه باشد کاری نمی‌کند.
  Future<File> download(
    String name, {
    String? url,
    String? version,
    bool force = false,
    void Function(AbmDownloadProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final target = await localFile(name);
    
    if (!force && await target.exists()) {
      if (version == null || (await installedVersion(name)) == version) {
        
        return target;
      }
    }

    final uri = Uri.parse(url ?? '$kAbmReleaseBase/$name');
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'AbtinMaps/1.0 (ir.abtin.abtin_maps)';
    final response = await _client.send(request);
    
    if (response.statusCode != 200) {
      throw AbmFormatException(
          'دانلود نقشه ناموفق بود (HTTP ${response.statusCode})');
    }

    final tmp = File('${target.path}.part');
    final sink = tmp.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) {
          throw const AbmDownloadCancelled();
        }
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(AbmDownloadProgress(received, response.contentLength));
      }
    } catch (error) {
      await sink.close();
      
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    await sink.close();
    

    // فایل باز فعلی باید قبل از جای‌گزینی بسته شود.
    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
    await (await _versionFile(name)).writeAsString(version ?? 'unknown');
    return target;
  }

  /// نصب یک ABM کوچکِ همراه APK برای آزمون end-to-end. مسیر همان نصب شبکه‌ای
  /// است: ابتدا فایل موقت نوشته، checksum بررسی و سپس اتمیک جایگزین می‌شود.
  /// بنابراین بستهٔ آزمایشی renderer یا راه میان‌برِ جدا نمی‌سازد.
  Future<File> installBundledAsset({
    required String name,
    required String assetPath,
    required String version,
    void Function(AbmDownloadProgress)? onProgress,
  }) async {
    final target = await localFile(name);
    if (await target.exists() &&
        (version.isEmpty || (await installedVersion(name)) == version)) {
      return target;
    }
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final pending = File('${target.path}.part');
    await _deleteIfExists(pending);
    try {
      await pending.writeAsBytes(bytes, flush: true);
      onProgress?.call(AbmDownloadProgress(bytes.length, bytes.length));
      if (version.isNotEmpty && !await _matchesSha256(pending, version)) {
        throw const AbmFormatException('هش بستهٔ نقشهٔ آزمایشی معتبر نیست.');
      }
      if (await target.exists()) await target.delete();
      await pending.rename(target.path);
      await (await _versionFile(name)).writeAsString(version, flush: true);
      return target;
    } catch (_) {
      await _deleteIfExists(pending);
      rethrow;
    }
  }

  /// دانلود (یا به‌روزرسانی) یک بستهٔ نقشه که ممکن است از چند پارت تشکیل
  /// شده باشد (کشورهای بزرگ که به‌خاطر سقف ۲ گیگابایتیِ آبجکت‌های ریلیز
  /// گیت‌هاب به چند فایل `part0`, `part1`, ... تقسیم شده‌اند).
  ///
  /// هر پارت جداگانه و با قابلیت ادامه‌ی دانلود (Range/Resume) دریافت
  /// می‌شود، در صورت وجود `sha256` اعتبارسنجی می‌شود، و در پایان همهٔ پارت‌ها
  /// به ترتیب به فایل نهاییِ `<id>.abm` چسبانده می‌شوند. اگر پارتی از قبل
  /// روی دیسک باشد و اندازه/هشش درست باشد، دوباره دانلود نمی‌شود — بنابراین
  /// قطع‌شدن اینترنت وسط دانلود یک نقشهٔ چندگیگابایتی، کل کار را از صفر
  /// شروع نمی‌کند.
  Future<File> downloadRegion({
    required String id,
    List<AbmFilePart> files = const [],
    AbmMapPatch? patch,
    String downloadBase = '',
    int totalSizeBytes = 0,
    String expectedSha256 = '',
    bool force = false,
    void Function(AbmDownloadProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final name = '$id.abm';
    final target = await localFile(name);
    
    if (!force && await target.exists()) {
      // The ABM file is the source of truth. The sidecar version is only an
      // optimization and may be missing after an older install/restore.
      final sidecarVersion = await installedVersion(name);
      String? localSha;
      if (expectedSha256.isNotEmpty) {
        localSha = await _matchesSha256(target, expectedSha256)
            ? expectedSha256
            : await _sha256(target);
      } else if (patch?.isUsable == true) {
        // A patch can still be selected when the online manifest omitted the
        // target SHA. In that case we need the actual installed ABM SHA to
        // validate patch.base_sha256.
        localSha = await _sha256(target);
      }
      if (expectedSha256.isEmpty || localSha == expectedSha256) {
        if (expectedSha256.isNotEmpty && sidecarVersion != expectedSha256) {
          await (await _versionFile(name)).writeAsString(expectedSha256);
        }
        
        return target;
      }
      if (patch != null &&
          patch.isUsable &&
          localSha == patch.baseSha256) {
        try {
          return await _downloadAndApplyPatch(
            id: id,
            target: target,
            downloadBase: downloadBase,
            patch: patch,
            expectedSha256: expectedSha256,
            onProgress: onProgress,
            isCancelled: isCancelled,
          );
        } on AbmDownloadCancelled {
          rethrow;
        } catch (error) {
          // patch یک بهینه‌سازی است: خطای آن نباید نسخهٔ فعلی را خراب کند و
          // در صورت نیاز دانلود کاملِ معتبر را جایگزین می‌کنیم.
          
        }
      }
    }

    final parts = files.isNotEmpty
        ? files
        : [
            AbmFilePart(
                name: name, size: totalSizeBytes, sha256: expectedSha256)
          ];
    final base = downloadBase.isNotEmpty ? downloadBase : '$kAbmReleaseBase/';
    final total = totalSizeBytes > 0
        ? totalSizeBytes
        : parts.fold<int>(0, (sum, part) => sum + part.size);

    final dir = await _mapsDir();
    final downloader = ResumableFileDownloader(
      userAgent: 'AbtinMaps/1.0 (ir.abtin.abtin_maps)',
    );
    var bytesBeforePart = 0;
    final partFiles = <File>[];

    for (final part in parts) {
      if (isCancelled?.call() ?? false) throw const AbmDownloadCancelled();
      final partFile = File(p.join(dir.path, part.name));
      if (!await _partIsValid(partFile, part)) {
        final baseForPart = bytesBeforePart;
        try {
          await downloader.download(
            sources: [Uri.parse('$base${part.name}')],
            destination: partFile,
            minimumBytes: part.size > 0 ? part.size : null,
            onProgress: (progress) {
              // چک کردن لغو در هر chunk (نه فقط بین پارت‌ها)؛ وگرنه دکمه‌ی
              // «توقف» تا پایان کامل دانلودِ همان پارت اثری ندارد.
              if (isCancelled?.call() ?? false) {
                downloader.cancel();
                return;
              }
              onProgress?.call(AbmDownloadProgress(
                baseForPart + progress.receivedBytes,
                total > 0 ? total : null,
              ));
            },
          );
        } on FileDownloadCancelled {
          throw const AbmDownloadCancelled();
        } on FileDownloadException catch (error) {
          throw AbmFormatException(error.message);
        }
        if (isCancelled?.call() ?? false) throw const AbmDownloadCancelled();
        if (part.sha256.isNotEmpty &&
            !await _matchesSha256(partFile, part.sha256)) {
          await _deleteIfExists(partFile);
          throw AbmFormatException(
              'پارت «${part.name}» ناقص یا خراب دانلود شد؛ دوباره تلاش کنید.');
        }
      }
      bytesBeforePart += part.size;
      partFiles.add(partFile);
    }

    // برای نقشهٔ تک‌فایلی، خودِ partFile همان فایل نهایی است. قبلاً اینجا
    // فایل چندگیگابایتی یک بار دیگر copy و سپس دوباره SHA-256 می‌شد؛ به همین
    // دلیل UI تا حدود ۸۰٪ می‌رسید و مرحلهٔ «نصب» طولانی به نظر می‌رسید.
    // وقتی پارت SHA-256 معتبر شده است، همان فایل را اتمیکاً نهایی می‌کنیم.
    final File finalFile;
    if (partFiles.length == 1 && partFiles.first.path == target.path) {
      finalFile = target;
      // اگر checksum پارت و checksum نسخه هر دو حاضرند، _partIsValid همین
      // فایل را قبلاً تأیید کرده است و دیگر نباید فایل بزرگ دوباره hash شود.
      if (expectedSha256.isNotEmpty && parts.first.sha256.isEmpty) {
        if (!await _matchesSha256(finalFile, expectedSha256)) {
          await _deleteIfExists(finalFile);
          throw const AbmFormatException(
              'فایل نهایی نقشه نامعتبر است؛ دوباره تلاش کنید.');
        }
      }
    } else {
      final tmp = File('${target.path}.part');
      await _deleteIfExists(tmp);
      if (partFiles.length == 1) {
        await partFiles.first.rename(tmp.path);
      } else {
        final sink = tmp.openWrite();
        try {
          for (final partFile in partFiles) {
            await sink.addStream(partFile.openRead());
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      

      if (expectedSha256.isNotEmpty &&
          !await _matchesSha256(tmp, expectedSha256)) {
        await _deleteIfExists(tmp);
        throw const AbmFormatException(
            'فایل نهایی نقشه پس از ترکیب پارت‌ها نامعتبر بود؛ دوباره تلاش کنید.');
      }
      await _deleteIfExists(target);
      await tmp.rename(target.path);
      finalFile = target;
    }

    
    await (await _versionFile(name))
        .writeAsString(expectedSha256.isNotEmpty ? expectedSha256 : 'unknown');

    // پارت‌های موقت را فقط پس از موفقیتِ کامل پاک می‌کنیم.
    //
    // نکته‌ی مهم: وقتی نقشه فقط یک پارت دارد (یعنی اکثر کشورها — همه‌ی
    // آن‌هایی که به‌خاطر سقف ۲گیگابایتیِ ریلیز گیت‌هاب نیازی به تقسیم ندارند)،
    // نامِ آن پارت دقیقاً همان `<id>.abm` است؛ یعنی `partFile.path` با
    // `target.path` یکی است. پیش از این، این حلقه بدون بررسی، همان فایلِ
    // نهاییِ تازه‌نصب‌شده را هم پاک می‌کرد — نتیجه‌اش این بود که دانلود ظاهراً
    // با موفقیت تمام می‌شد اما بلافاصله فایل نصب‌شده حذف می‌شد، و کاربر با
    // برگشتن به صفحه‌ی دانلود دوباره «نصب‌نشده» می‌دید و مجبور بود از صفر
    // دانلود کند. اینجا صراحتاً از حذفِ فایلی که همان فایل نهایی است
    // جلوگیری می‌شود.
    for (final partFile in partFiles) {
      if (partFile.path == target.path) continue;
      await _deleteIfExists(partFile);
    }
    onProgress?.call(AbmDownloadProgress(total, total > 0 ? total : null));
    return target;
  }

  Future<File> _downloadAndApplyPatch({
    required String id,
    required File target,
    required String downloadBase,
    required AbmMapPatch patch,
    required String expectedSha256,
    required void Function(AbmDownloadProgress)? onProgress,
    required bool Function()? isCancelled,
  }) async {
    final base = downloadBase.isNotEmpty ? downloadBase : '$kAbmReleaseBase/';
    final manifestResponse = await _client
        .get(Uri.parse('$base${patch.manifestFile}'))
        .timeout(const Duration(seconds: 20));
    if (manifestResponse.statusCode != HttpStatus.ok) {
      throw const AbmFormatException(
          'دریافت مشخصات به‌روزرسانی نقشه ناموفق بود.');
    }
    final decoded = jsonDecode(utf8.decode(manifestResponse.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const AbmFormatException('مشخصات به‌روزرسانی نقشه نامعتبر است.');
    }
    final manifest = _AbmChunkPatchManifest.fromJson(decoded);
    if (manifest.code != id ||
        manifest.baseSha256 != patch.baseSha256 ||
        (expectedSha256.isNotEmpty &&
            manifest.targetSha256 != expectedSha256) ||
        manifest.targetSize <= 0 ||
        manifest.chunkSize <= 0 ||
        !await _matchesSha256(target, patch.baseSha256)) {
      throw const AbmFormatException(
          'نسخهٔ نصب‌شده با به‌روزرسانی نقشه سازگار نیست.');
    }

    final dir = await _mapsDir();
    final patchFile = File(p.join(dir.path, '$id.update.abmpatch'));
    final downloader = ResumableFileDownloader(
      userAgent: 'AbtinMaps/1.0 (ir.abtin.abtin_maps)',
    );
    try {
      await downloader.download(
        sources: [Uri.parse('$base${patch.binFile}')],
        destination: patchFile,
        minimumBytes: patch.size > 0 ? patch.size : null,
        onProgress: (progress) {
          if (isCancelled?.call() ?? false) {
            downloader.cancel();
            return;
          }
          onProgress?.call(
            AbmDownloadProgress(progress.receivedBytes, progress.totalBytes),
          );
        },
      );
    } on FileDownloadCancelled {
      throw const AbmDownloadCancelled();
    } on FileDownloadException catch (error) {
      throw AbmFormatException(error.message);
    }

    if (isCancelled?.call() ?? false) throw const AbmDownloadCancelled();
    if ((patch.sha256.isNotEmpty &&
            !await _matchesSha256(patchFile, patch.sha256)) ||
        (manifest.patchSha256.isNotEmpty &&
            !await _matchesSha256(patchFile, manifest.patchSha256))) {
      await _deleteIfExists(patchFile);
      throw const AbmFormatException('هش فایل به‌روزرسانی نقشه نادرست است.');
    }

    final pending = await _applyChunkPatch(
      source: target,
      patchFile: patchFile,
      manifest: manifest,
      isCancelled: isCancelled,
    );
    if (expectedSha256.isNotEmpty &&
        !await _matchesSha256(pending, expectedSha256)) {
      await _deleteIfExists(pending);
      throw const AbmFormatException(
          'نسخهٔ ساخته‌شده از به‌روزرسانی نقشه معتبر نیست.');
    }
    if (await target.exists()) await target.delete();
    await pending.rename(target.path);
    await (await _versionFile('$id.abm')).writeAsString(
      expectedSha256.isNotEmpty ? expectedSha256 : manifest.targetSha256,
    );
    await _deleteIfExists(patchFile);
    
    return target;
  }

  Future<File> _applyChunkPatch({
    required File source,
    required File patchFile,
    required _AbmChunkPatchManifest manifest,
    required bool Function()? isCancelled,
  }) async {
    final pending = File('${source.path}.update');
    await _deleteIfExists(pending);
    final sourceReader = await source.open();
    final patchReader = await patchFile.open();
    final output = pending.openWrite();
    try {
      final changedBlocks = {
        for (final block in manifest.blocks) block.index: block
      };
      final blockCount =
          (manifest.targetSize + manifest.chunkSize - 1) ~/ manifest.chunkSize;
      for (var index = 0; index < blockCount; index++) {
        if (isCancelled?.call() ?? false) throw const AbmDownloadCancelled();
        final expectedLength = index == blockCount - 1
            ? manifest.targetSize - index * manifest.chunkSize
            : manifest.chunkSize;
        final changed = changedBlocks[index];
        if (changed != null) {
          if (changed.size != expectedLength || changed.offset < 0) {
            throw const AbmFormatException(
                'بلوک به‌روزرسانی نقشه نامعتبر است.');
          }
          await patchReader.setPosition(changed.offset);
          final bytes = await patchReader.read(expectedLength);
          if (bytes.length != expectedLength) {
            throw const AbmFormatException('فایل به‌روزرسانی نقشه ناقص است.');
          }
          output.add(bytes);
        } else {
          await sourceReader.setPosition(index * manifest.chunkSize);
          final bytes = await sourceReader.read(expectedLength);
          if (bytes.length != expectedLength) {
            throw const AbmFormatException(
                'نسخهٔ قبلی نقشه برای به‌روزرسانی معتبر نیست.');
          }
          output.add(bytes);
        }
      }
      await output.flush();
    } catch (_) {
      await _deleteIfExists(pending);
      rethrow;
    } finally {
      await output.close();
      await patchReader.close();
      await sourceReader.close();
    }
    return pending;
  }

  Future<bool> _partIsValid(File file, AbmFilePart part) async {
    if (!await file.exists()) return false;
    if (part.size > 0 && await file.length() != part.size) return false;
    if (part.sha256.isEmpty) return true;
    return _matchesSha256(file, part.sha256);
  }

  Future<bool> _matchesSha256(File file, String expected) async {
    if (expected.isEmpty) return true;
    return (await _sha256(file)).toLowerCase() == expected.toLowerCase();
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteMap(String name) async {
    final f = await localFile(name);
    if (await f.exists()) await f.delete();
    final v = await _versionFile(name);
    if (await v.exists()) await v.delete();
  }

  /// بستن کلاینت شبکه هنگام dispose شدن provider؛ فایل‌های ABM فقط در زمان خواندن باز می‌مانند.
  void closeMap() {
    _client.close();
  }

  Future<List<String>> installedMaps() async {
    final dir = await _mapsDir();
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((n) => n.toLowerCase().endsWith('.abm'))
        .toList();
  }
}

class _AbmChunkPatchManifest {
  const _AbmChunkPatchManifest({
    required this.code,
    required this.baseSha256,
    required this.targetSha256,
    required this.targetSize,
    required this.chunkSize,
    required this.patchSha256,
    required this.blocks,
  });

  final String code;
  final String baseSha256;
  final String targetSha256;
  final int targetSize;
  final int chunkSize;
  final String patchSha256;
  final List<_AbmChunkPatchBlock> blocks;

  factory _AbmChunkPatchManifest.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 'ABTINMAP-CHUNK-PATCH/1') {
      throw const AbmFormatException('نسخهٔ patch نقشه پشتیبانی نمی‌شود.');
    }
    final blocks = (json['blocks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_AbmChunkPatchBlock.fromJson)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (blocks.map((block) => block.index).toSet().length != blocks.length ||
        blocks.any((block) => block.index < 0 || block.size <= 0)) {
      throw const AbmFormatException('بلوک‌های patch نقشه نامعتبر هستند.');
    }
    return _AbmChunkPatchManifest(
      code: (json['code'] as String?) ?? '',
      baseSha256: (json['base_sha256'] as String?) ?? '',
      targetSha256: (json['target_sha256'] as String?) ?? '',
      targetSize: (json['target_size'] as num?)?.toInt() ?? 0,
      chunkSize: (json['chunk_size'] as num?)?.toInt() ?? 0,
      patchSha256: (json['patch_sha256'] as String?) ?? '',
      blocks: blocks,
    );
  }
}

class _AbmChunkPatchBlock {
  const _AbmChunkPatchBlock({
    required this.index,
    required this.offset,
    required this.size,
  });

  final int index;
  final int offset;
  final int size;

  factory _AbmChunkPatchBlock.fromJson(Map<String, dynamic> json) =>
      _AbmChunkPatchBlock(
        index: (json['index'] as num?)?.toInt() ?? -1,
        offset: (json['offset'] as num?)?.toInt() ?? -1,
        size: (json['size'] as num?)?.toInt() ?? -1,
      );
}
