import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/localization/locale_flags.dart';

class VoicePackRemote {
  const VoicePackRemote({
    required this.name,
    required this.language,
    required this.languageCode,
    required this.genderLabel,
    required this.voiceName,
    required this.displayName,
    required this.sizeBytes,
    required this.downloadUrl,
  });

  final String name;
  final String language;
  final String languageCode;
  final String genderLabel;
  final String voiceName;
  final String displayName;
  final int sizeBytes;
  final String downloadUrl;

  /// پرچمِ نمایشیِ این بستهٔ صوتی، بر پایهٔ کدِ زبان (نه کدِ کشور، چون مانیفست
  /// صوتی کدِ کشور ندارد).
  String get flag => flagAssetForLanguageCode(languageCode);

  bool get isFemale {
    final g = genderLabel.trim().toLowerCase();
    return g.contains('زن') || g.contains('female') || g == 'f';
  }

  bool get isMale {
    final g = genderLabel.trim().toLowerCase();
    return g.contains('مرد') || g.contains('male') || g == 'm';
  }

  String get _cleanLanguage => cleanLocalizedLabel(language);
  String get _cleanVoiceName => cleanLocalizedLabel(_bareVoiceName(voiceName));
  String get _cleanDisplayName => cleanLocalizedLabel(displayName.replaceAll(
      RegExp(r'\s*[\(\[]?(زن|مرد|female|male)[\)\]]?', caseSensitive: false),
      ''));

  /// نامِ خالصِ گوینده از رشته‌های خامِ موتورهای TTS مثل «ar-SA-ZariyahNeural»
  /// یا «en-GB-AndrewMultilingualNeural» → فقط «Zariyah» / «Andrew». پیشوندِ
  /// کدِ زبان-کشور و پسوندهای فنی (Neural، Neural2، Multilingual و…) حذف
  /// می‌شوند چون پرچمِ کنارِ اسم، خودش زبان را نشان می‌دهد.
  static String _bareVoiceName(String raw) {
    var out = raw.trim();
    if (out.isEmpty) return out;
    // پیشوندِ locale مثل «ar-SA-» یا «en-GB-».
    out = out.replaceFirst(RegExp(r'^[a-zA-Z]{2,3}-[a-zA-Z]{2,4}-'), '');
    // پسوندهای فنیِ متداول موتورهای TTS.
    out = out.replaceAll(
      RegExp(r'(Multilingual)?(Neural)(2|HD)?$', caseSensitive: false),
      '',
    );
    return out.trim();
  }

  /// نام نمایشی، بدون اضافاتی مثل کدِ زبان («fa»، «(en)») که در مانیفست
  /// همراهِ نام آمده — چون خودِ برچسب یا پرچمِ کنارش همان اطلاعات را می‌دهد.
  String get title => _cleanVoiceName.isNotEmpty
      ? '$_cleanLanguage — $_cleanVoiceName'
      : _cleanDisplayName;

  /// فقط نامِ کوتاهِ صدا (مثل «Zariyah»)، بدون نام زبان — برای فهرست دانلودِ\
  /// بسته‌های صوتی که پرچم خودش نشان‌دهندهٔ زبان است.
  String get shortName =>
      _cleanVoiceName.isNotEmpty ? _cleanVoiceName : _cleanDisplayName;

  factory VoicePackRemote.fromJson(Map<String, dynamic> json) =>
      VoicePackRemote(
        name: json['name'] as String,
        language: json['language'] as String,
        languageCode: (json['language_code'] as String?) ?? '',
        genderLabel: (json['gender_label'] as String?) ?? '',
        voiceName: (json['voice_name'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        sizeBytes: (json['size'] as num).toInt(),
        downloadUrl: json['download_url'] as String,
      );
}

class VoicePackException implements Exception {
  const VoicePackException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// بازهٔ یک فرمان داخل فایل MP3 واحد. زمان‌ها بر حسب ثانیه هستند.
class VoiceCue {
  const VoiceCue({required this.start, required this.end, required this.text});
  final Duration start;
  final Duration end;
  final String text;
}

/// فایل قابل پخش استخراج‌شده همراه نقشهٔ فرمان‌ها. در فایل MP3 عادی cue وجود
/// ندارد؛ فایل‌های ABV نسخهٔ ۱ یک فایل MP3 و همهٔ cueها را با هم دارند.
class VoicePlaybackBundle {
  const VoicePlaybackBundle({required this.file, this.cues = const {}});
  final File file;
  final Map<String, VoiceCue> cues;
}

class VoicePackService {
  static const String manifestUrl =
      'https://github.com/abtin123/Make-voice/releases/download/voicepacks-latest/manifest.json';

  final http.Client _client = http.Client();
  List<VoicePackRemote>? _memory;

  /// حداکثر «تازگیِ» کشِ محلیِ مانیفست صوتی — دقیقاً مثل [MapCatalogService]:
  /// تا وقتی کش از این مدت قدیمی‌تر نشده، به شبکه سر زده نمی‌شود. مانیفستِ
  /// بسته‌های صوتی کم تغییر می‌کند و چک‌کردنش با هر بار خروج و ورود به صفحهٔ
  /// صدا (یا رفتن اپ به پس‌زمینه و برگشتن) هم غیرضروری است و هم روی اتصال‌های
  /// کند کاربر را معطل می‌کند؛ فقط دکمهٔ «تازه‌سازی» دستی این کش را دور می‌زند.
  static const Duration _maxCacheAge = Duration(days: 1);

  Future<File> _manifestCacheFile() async {
    final dir = await _packsDir();
    return File(p.join(dir.path, '.manifest_cache.json'));
  }

  Future<Directory> _packsDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/voice_packs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeName(String name) => p.basename(name);

  Future<File> _fileForName(String name) async {
    final dir = await _packsDir();
    return File(p.join(dir.path, _safeName(name)));
  }

  Future<File?> downloadedFile(String name) async {
    final file = await _fileForName(name);
    return await file.exists() ? file : null;
  }

  List<VoicePackRemote> _parseManifest(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['voices'] is! List) {
      throw const VoicePackException('ساختار مانیفست صوتی نامعتبر است.');
    }
    return (decoded['voices'] as List)
        .whereType<Map<String, dynamic>>()
        .map(VoicePackRemote.fromJson)
        .toList();
  }

  /// فهرست بسته‌های صوتی. اول کشِ حافظه/دیسکِ تازه (اگر [forceRefresh] نباشد
  /// و قدیمی‌تر از [_maxCacheAge] نشده باشد)، وگرنه مانیفست آنلاین؛ اگر شبکه
  /// شکست بخورد، به کشِ قدیمی (حتی منقضی‌شده) برمی‌گردد تا صفحه خالی نماند.
  Future<List<VoicePackRemote>> fetchManifest(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null) return _memory!;

    final cache = await _manifestCacheFile();
    if (!forceRefresh) {
      try {
        if (await cache.exists()) {
          final age = DateTime.now().difference(await cache.lastModified());
          if (age < _maxCacheAge) {
            return _memory =
                _parseManifest(await cache.readAsString(encoding: utf8));
          }
        }
      } catch (_) {
        // کش خراب است؛ به مسیر شبکه ادامه می‌دهیم.
      }
    }

    try {
      final res = await _client.get(Uri.parse(manifestUrl));
      if (res.statusCode != 200) {
        throw VoicePackException(
            'دریافت فهرست بسته‌های صوتی ناموفق بود (کد ${res.statusCode}).');
      }
      final bodyUtf8 = utf8.decode(res.bodyBytes);
      final parsed = _parseManifest(bodyUtf8);
      await cache.writeAsString(bodyUtf8, flush: true, encoding: utf8);
      return _memory = parsed;
    } catch (error) {
      try {
        if (await cache.exists()) {
          return _memory =
              _parseManifest(await cache.readAsString(encoding: utf8));
        }
      } catch (_) {
        // کشِ قدیمی هم خراب است.
      }
      if (error is VoicePackException) rethrow;
      throw const VoicePackException('فهرست بسته‌های صوتی در دسترس نیست.');
    }
  }

  Future<Set<String>> installedFiles() async {
    final dir = await _packsDir();
    if (!await dir.exists()) return {};
    return dir
        .listSync()
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .where((name) => !name.startsWith('.'))
        .toSet();
  }

  Future<void> download(VoicePackRemote pack,
      {void Function(double progress)? onProgress}) async {
    final request = http.Request('GET', Uri.parse(pack.downloadUrl));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw VoicePackException(
          'دانلود بستهٔ صوتیِ «${pack.title}» ناموفق بود (کد ${response.statusCode}).');
    }
    final total = response.contentLength ?? pack.sizeBytes;
    var received = 0;
    final target = await _fileForName(pack.name);
    final sink = target.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<VoicePlaybackBundle?> playableVoiceBundle(
      String downloadedName) async {
    final source = await downloadedFile(downloadedName);
    if (source == null) return null;
    if (p.extension(source.path).toLowerCase() == '.mp3')
      return VoicePlaybackBundle(file: source);
    if (p.extension(source.path).toLowerCase() != '.abv') return null;

    final bytes = await source.readAsBytes();
    if (bytes.length < 12 || utf8.decode(bytes.sublist(0, 4)) != 'ABV1') {
      throw const VoicePackException('فایل صوتی دانلودشده معتبر نیست.');
    }
    final header = ByteData.sublistView(bytes);
    final jsonLength = header.getUint32(4, Endian.little);
    final audioLength = header.getUint32(8, Endian.little);
    final jsonStart = 12;
    final audioStart = jsonStart + jsonLength;
    final audioEnd = audioStart + audioLength;
    if (jsonLength == 0 || audioEnd > bytes.length) {
      throw const VoicePackException('ساختار فایل صوتی دانلودشده ناقص است.');
    }
    final metaRaw =
        GZipDecoder().decodeBytes(bytes.sublist(jsonStart, audioStart));
    final decoded = jsonDecode(utf8.decode(metaRaw));
    final meta =
        decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    final dir = await _packsDir();
    final preview = File(p.join(
        dir.path, '.preview_${p.basenameWithoutExtension(source.path)}.mp3'));
    if (!await preview.exists() ||
        await preview.length() == 0 ||
        (await preview.lastModified()).isBefore(await source.lastModified())) {
      final mp3 =
          GZipDecoder().decodeBytes(bytes.sublist(audioStart, audioEnd));
      await preview.writeAsBytes(Uint8List.fromList(mp3), flush: true);
    }
    return VoicePlaybackBundle(file: preview, cues: _readCues(meta['cues']));
  }

  Map<String, VoiceCue> _readCues(Object? value) {
    if (value is! Map) return const {};
    final cues = <String, VoiceCue>{};
    for (final entry in value.entries) {
      final data = entry.value;
      if (entry.key is! String || data is! Map) continue;
      final start = data['start'];
      final end = data['end'];
      if (start is! num || end is! num || end <= start || start < 0) continue;
      cues[entry.key as String] = VoiceCue(
        start: Duration(milliseconds: (start * 1000).round()),
        end: Duration(milliseconds: (end * 1000).round()),
        text: data['text'] is String ? data['text'] as String : '',
      );
    }
    return cues;
  }

  /// برای سازگاری با دکمهٔ پخش نمونه؛ همهٔ فایل یک‌تکه پخش می‌شود.
  Future<File?> playablePreviewFile(String downloadedName) async =>
      (await playableVoiceBundle(downloadedName))?.file;

  Future<void> delete(VoicePackRemote pack) async {
    final file = await _fileForName(pack.name);
    if (await file.exists()) await file.delete();
    final preview = File(p.join((await _packsDir()).path,
        '.preview_${p.basenameWithoutExtension(file.path)}.mp3'));
    if (await preview.exists()) await preview.delete();
  }
}
