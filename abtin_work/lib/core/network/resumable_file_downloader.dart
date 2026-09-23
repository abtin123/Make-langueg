import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// وضعیت پیشرفت یک فایل در حال دریافت.
class FileDownloadProgress {
  const FileDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}

/// لغو کنترل‌شدهٔ دانلود؛ این خطا نباید در رابط کاربری به‌عنوان خرابی شبکه
/// نمایش داده شود.
class FileDownloadCancelled implements Exception {
  const FileDownloadCancelled([this.message = 'دانلود توسط کاربر متوقف شد.']);

  final String message;

  @override
  String toString() => message;
}

/// خطایی با متن قابل نمایش برای خطاهای شبکه، پاسخ نامعتبر و فایل ناقص.
class FileDownloadException implements Exception {
  const FileDownloadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// دانلودر فایل HTTP که روی فایل `.part` کار می‌کند.
///
/// فایل نهایی فقط پس از دریافت کامل و انتقال اتمیک جایگزین می‌شود؛ بنابراین
/// قطع اینترنت یا بسته‌شدن برنامه نمی‌تواند فایل نصب‌شدهٔ قبلی را خراب کند.
class ResumableFileDownloader {
  ResumableFileDownloader({
    this.connectTimeout = const Duration(seconds: 30),
    this.stallTimeout = const Duration(seconds: 45),
    this.userAgent = 'AbtinMaps/1.0',
  });

  final Duration connectTimeout;
  final Duration stallTimeout;
  final String userAgent;

  http.Client? _activeClient;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  Future<File> download({
    required List<Uri> sources,
    required File destination,
    void Function(FileDownloadProgress progress)? onProgress,
    int maxAttemptsPerSource = 2,
    int? minimumBytes,
  }) async {
    if (sources.isEmpty) {
      throw const FileDownloadException(
          'هیچ آدرس دانلودی برای فایل تعریف نشده است.');
    }
    if (maxAttemptsPerSource < 1) {
      throw ArgumentError.value(maxAttemptsPerSource, 'maxAttemptsPerSource');
    }

    _cancelled = false;
    final part = File('${destination.path}.part');
    await destination.parent.create(recursive: true);

    final failures = <String>[];
    for (final source in sources) {
      for (var attempt = 1; attempt <= maxAttemptsPerSource; attempt++) {
        _throwIfCancelled();
        try {
          final result = await _downloadFromSource(
            source: source,
            part: part,
            destination: destination,
            onProgress: onProgress,
            minimumBytes: minimumBytes,
          );
          return result;
        } on FileDownloadCancelled {
          rethrow;
        } on FileDownloadException catch (error) {
          failures.add('${source.host} (تلاش $attempt): ${error.message}');
          if (attempt < maxAttemptsPerSource) {
            await Future<void>.delayed(Duration(seconds: attempt * 2));
          }
        } catch (error) {
          if (_cancelled) throw const FileDownloadCancelled();
          failures.add('${source.host} (تلاش $attempt): $error');
          if (attempt < maxAttemptsPerSource) {
            await Future<void>.delayed(Duration(seconds: attempt * 2));
          }
        }
      }
    }

    throw FileDownloadException(
      'دانلود از سرورهای موجود ناموفق بود. ${failures.join(' | ')}',
    );
  }

  Future<File> _downloadFromSource({
    required Uri source,
    required File part,
    required File destination,
    required void Function(FileDownloadProgress progress)? onProgress,
    required int? minimumBytes,
  }) async {
    var existingBytes = await _fileLength(part);
    var allowResume = existingBytes > 0;

    for (var resetAttempt = 0; resetAttempt < 2; resetAttempt++) {
      _throwIfCancelled();
      final client = http.Client();
      _activeClient = client;
      IOSink? sink;
      try {
        final request = http.Request('GET', source)
          ..followRedirects = true
          ..maxRedirects = 8
          ..headers.addAll(<String, String>{
            'User-Agent': userAgent,
            'Accept':
                'application/octet-stream,application/zip,application/x-bzip2,*/*',
            // دانلود قابل ادامه با پاسخ فشرده‌شدهٔ HTTP سازگار نیست.
            'Accept-Encoding': 'identity',
          });
        if (allowResume) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }

        final response = await client.send(request).timeout(connectTimeout);
        _throwIfCancelled();

        // برخی سرورها Range را نادیده می‌گیرند و پاسخ 200 می‌دهند. در این
        // حالت فایل بخش‌بندی‌شده را پاک کرده و دریافت را از ابتدا آغاز می‌کنیم.
        if (allowResume && response.statusCode == HttpStatus.ok) {
          await response.stream.drain<void>();
          await _deleteIfExists(part);
          existingBytes = 0;
          allowResume = false;
          continue;
        }
        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          await response.stream.drain<void>();
          await _deleteIfExists(part);
          existingBytes = 0;
          allowResume = false;
          continue;
        }
        final expectedStatus =
            allowResume ? HttpStatus.partialContent : HttpStatus.ok;
        if (response.statusCode != expectedStatus) {
          await response.stream.drain<void>();
          throw FileDownloadException(
            'سرور ${source.host} پاسخ HTTP ${response.statusCode} برگرداند.',
          );
        }

        final totalBytes = response.contentLength == null
            ? null
            : existingBytes + response.contentLength!;
        sink = part.openWrite(
            mode: allowResume ? FileMode.append : FileMode.write);
        var receivedBytes = existingBytes;
        onProgress?.call(FileDownloadProgress(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
        ));

        await for (final chunk in response.stream.timeout(stallTimeout)) {
          _throwIfCancelled();
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(FileDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ));
        }
        await sink.flush();
        await sink.close();
        sink = null;
        _throwIfCancelled();

        final finalLength = await _fileLength(part);
        if (totalBytes != null && finalLength != totalBytes) {
          throw const FileDownloadException(
              'فایل دانلودشده ناقص است؛ اندازهٔ دریافت‌شده با پاسخ سرور یکی نیست.');
        }
        if (minimumBytes != null && finalLength < minimumBytes) {
          throw FileDownloadException(
            'فایل دانلودشده کوچک‌تر از حد معتبر است (${finalLength} بایت).',
          );
        }

        await _deleteIfExists(destination);
        await part.rename(destination.path);
        onProgress?.call(FileDownloadProgress(
          receivedBytes: finalLength,
          totalBytes: finalLength,
        ));
        return destination;
      } on TimeoutException {
        if (_cancelled) throw const FileDownloadCancelled();
        throw FileDownloadException(
            'دریافت داده از ${source.host} بیش از حد مجاز طول کشید.');
      } on http.ClientException catch (error) {
        if (_cancelled) throw const FileDownloadCancelled();
        throw FileDownloadException(
            'اتصال به ${source.host} برقرار نشد: ${error.message}',
            cause: error);
      } finally {
        if (sink != null) {
          await sink.close();
        }
        if (identical(_activeClient, client)) {
          _activeClient = null;
        }
        client.close();
      }
    }

    throw const FileDownloadException('سرور از ادامهٔ دانلود پشتیبانی نکرد.');
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const FileDownloadCancelled();
  }

  Future<int> _fileLength(File file) async {
    if (!await file.exists()) return 0;
    return file.length();
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
