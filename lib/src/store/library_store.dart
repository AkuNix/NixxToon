import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/comic_models.dart';

// Penyimpanan lokal NixxToon: 1 file JSON. Cukup buat bookmark +
// riwayat + posisi baca skala solo. Tanpa adapter/codegen.
class LibraryStore extends ChangeNotifier {
  Map<String, dynamic> _data = {
    'bookmarks': <String, dynamic>{},
    'history': <dynamic>[],
    'progress': <String, dynamic>{},
    'latestSeen': <String, dynamic>{},
    'downloaded': <String, dynamic>{},
    'series': <String, dynamic>{},
    'settings': <String, dynamic>{
      'readerBg': 'black', // black | gray | white
      'showPageNum': true,
      'keepScreenOn': false,
      'fullscreen': true,
      'wifiOnly': false,
      'autoDownload': false,
      'autoCheckUpdate': true,
      'imgQuality': 's1080', // s720 | s1080 | s1600 | asli
    },
  };

  bool _loaded = false;

  /// Progres halaman: murni memori + file kecil terpisah.
  /// File indeks besar tak pernah tersentuh saat scroll (P1 anti-lag).
  Map<String, dynamic> _progress = {};
  Timer? _saveTimer;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        _data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _migrate();
      }
      final pf = await _progressFile();
      if (await pf.exists()) {
        final m = jsonDecode(await pf.readAsString());
        if (m is Map) _progress.addAll(m.cast<String, dynamic>());
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Kunci lama polos ("Lookism") -> "kp:Lookism". Sekali jalan.
  /// + pindahkan progress lama ke file kecilnya.
  void _migrate() {
    final old = (_data['progress'] as Map?)?.cast<String, dynamic>();
    if (old != null) {
      _progress.addAll(old);
      _data.remove('progress');
    }    for (final k in ['bookmarks', 'latestSeen', 'series']) {
      final m = (_data[k] as Map?)?.cast<String, dynamic>();
      if (m == null) continue;
      for (final key in m.keys.toList()) {
        if (!key.contains(':')) {
          m['kp:$key'] = m.remove(key);
        }
      }
    }
    for (final h in (_data['history'] as List? ?? [])) {
      final e = (h as Map).cast<String, dynamic>();
      final s = e['series'] as String? ?? '';
      if (s.isNotEmpty && !s.contains(':')) {
        e['series'] = 'kp:$s';
      }
      e['src'] ??= 'kp';
    }
    for (final e in ((_data['downloaded'] as Map?)?.values ?? [])) {
      final m = (e as Map).cast<String, dynamic>();
      m['src'] ??= 'kp';
      m['at'] ??= '';
    }
  }

  static String _key(String src, String label) => '$src:$label';

  static (String, String) _split(String key) {
    final i = key.indexOf(':');
    if (i < 0) return ('kp', key);
    return (key.substring(0, i), key.substring(i + 1));
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nixxtoon_library.json');
  }

  Future<File> _progressFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nixxtoon_progress.json');
  }

  /// Tulis tunda 1.5 dtk (debounce): scroll cepat tak menulis berkali-kali.
  Future<void> _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), () => _persist());
    return Future.value();
  }

  Future<void> _persist() async {
    try {
      final main = Map<String, dynamic>.from(_data)..remove('progress');
      await (await _file()).writeAsString(jsonEncode(main));
      await (await _progressFile()).writeAsString(jsonEncode(_progress));
    } catch (_) {}
  }

  Map<String, dynamic> get _marks =>
      (_data['bookmarks'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get history =>
      [for (final h in (_data['history'] as List)) (h as Map).cast<String, dynamic>()];

  bool isBookmarked(String src, String label) =>
      _marks.containsKey(_key(src, label));

  List<SeriesInfo> get bookmarks => [
        for (final e in _marks.entries)
          () {
            final (src, label) = _split(e.key);
            final v = (e.value as Map).cast<String, dynamic>();
            return SeriesInfo(
              src: src,
              label: label,
              title: v['title'] as String? ?? label,
              cover: v['cover'] as String? ?? '',
              status: v['status'] as String? ?? '',
              type: '',
              genres: const [],
              synopsis: '',
              projectUrl: '',
              updated: null,
            );
          }(),
      ];

  Future<void> toggleBookmark(SeriesInfo s) async {
    final k = _key(s.src, s.label);
    if (_marks.containsKey(k)) {
      _marks.remove(k);
    } else {
      _marks[k] = {
        'title': s.title,
        'cover': s.cover,
        'status': s.status,
      };
    }
    notifyListeners();
    await _save();
  }

  /// Riwayat: 1 entri per series (yg terbaru menimpa), max 50.
  Future<void> recordHistory({
    required String src,
    required String series,
    required String seriesTitle,
    required String cover,
    required ChapterRef chapter,
  }) async {
    final k = _key(src, series);
    final h =
        history.where((e) => e['series'] != k).take(49).toList();
    h.insert(0, {
      'src': src,
      'series': k,
      'seriesTitle': seriesTitle,
      'cover': cover,
      'chapter': chapter.title,
      'url': chapter.url,
      'at': DateTime.now().toIso8601String(),
    });
    _data['history'] = h;
    notifyListeners();
    await _save();
  }

  int progressOf(String chapterUrl) =>
      (_progress[chapterUrl] as num?)?.toInt() ?? 0;

  Future<void> setProgress(String chapterUrl, int page) async {
    _progress[chapterUrl] = page;
    await _save();
  }

  double latestSeen(String src, String label) =>
      ((_data['latestSeen'] as Map)[_key(src, label)] as num?)?.toDouble() ??
      -1;

  Future<void> setLatestSeen(
      String src, String label, double number) async {
    ((_data['latestSeen'] as Map))[_key(src, label)] = number;
    await _save();
  }

  // ---------- indeks series (cover/search/baru) ----------

  Map<String, dynamic> get _series =>
      ((_data['series'] ??= <String, dynamic>{}) as Map)
          .cast<String, dynamic>();

  Future<void> saveSeriesIndex(List<SeriesInfo> all) async {
    for (final s in all) {
      if (s.label.isEmpty) continue;
      _series[_key(s.src, s.label)] = s.toCache();
    }
    notifyListeners();
    await _save();
  }

  List<SeriesInfo> cachedSeries() {
    final out = <SeriesInfo>[];
    for (final e in _series.entries) {
      final (src, label) = _split(e.key);
      final m = (e.value as Map).cast<String, dynamic>();
      // src tersimpan menang atas prefix (migrasi aman).
      out.add(SeriesInfo.fromCache(label, {...m, 'src': m['src'] ?? src}));
    }
    return out;
  }

  List<SeriesInfo> cachedSeriesOf(String src) =>
      cachedSeries().where((s) => s.src == src).toList();

  String coverOf(String src, String label) =>
      _series[_key(src, label)]?['cover'] as String? ?? '';

  String titleOf(String src, String label) =>
      _series[_key(src, label)]?['title'] as String? ?? label;

  bool get hasSeriesIndex => _series.isNotEmpty;

  List<String> sourcesInIndex() => {
        for (final e in _series.entries) _split(e.key).$1,
      }.toList();

  // ---------- progres crawl indeks (khusus Komiku, background) ----------

  String get indexStatus =>
      _data['indexStatus'] as String? ?? '';

  Future<void> setIndexStatus(String v) async {
    _data['indexStatus'] = v;
    notifyListeners();
    await _save();
  }

  // ---------- cache populer (TTL 12 jam) ----------

  List<SeriesInfo> cachedPopular() {
    final m = (_data['popular'] as Map?)?.cast<String, dynamic>();
    if (m == null) return const [];
    final at = DateTime.tryParse(m['at'] as String? ?? '');
    if (at == null ||
        DateTime.now().difference(at).inHours >= 12) {
      return const [];
    }
    return [
      for (final e in (m['items'] as List? ?? []))
        () {
          final mm = (e as Map).cast<String, dynamic>();
          final (src, label) = _split(mm['key'] as String? ?? '');
          return SeriesInfo.fromCache(
              label, {...mm['info'] as Map, 'src': src});
        }(),
    ];
  }

  Future<void> savePopular(List<SeriesInfo> items) async {
    _data['popular'] = {
      'at': DateTime.now().toIso8601String(),
      'items': [
        for (final s in items)
          {'key': _key(s.src, s.label), 'info': s.toCache()},
      ],
    };
    notifyListeners();
    await _save();
  }

  // ---------- settings ----------

  Map<String, dynamic> get _settings =>
      ((_data['settings'] ??= <String, dynamic>{}) as Map)
          .cast<String, dynamic>();

  T setting<T>(String key, T fallback) {
    final v = _settings[key];
    return v is T ? v : fallback;
  }

  String get readerBg => setting('readerBg', 'black');
  bool get showPageNum => setting('showPageNum', true);
  bool get keepScreenOn => setting('keepScreenOn', false);
  bool get fullscreen => setting('fullscreen', true);
  bool get wifiOnly => setting('wifiOnly', false);
  bool get autoDownload => setting('autoDownload', false);
  bool get autoCheckUpdate => setting('autoCheckUpdate', true);
  String get imgQuality => setting('imgQuality', 's1080');

  Future<void> setSetting(String key, Object value) async {
    _settings[key] = value;
    notifyListeners();
    await _save();
  }

  // ---------- data ----------

  Future<void> clearHistory() async {
    _data['history'] = <dynamic>[];
    notifyListeners();
    await _save();
  }

  Future<int> downloadBytes() async {
    var total = 0;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dl = Directory('${dir.path}/nixxtoon_dl');
      if (!await dl.exists()) return 0;
      await for (final e in dl.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  Future<void> clearDownloads() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dl = Directory('${dir.path}/nixxtoon_dl');
      if (await dl.exists()) await dl.delete(recursive: true);
    } catch (_) {}
    _data['downloaded'] = <String, dynamic>{};
    notifyListeners();
    await _save();
  }

  Future<void> resetAll() async {
    await clearDownloads();
    _data['bookmarks'] = <String, dynamic>{};
    _data['history'] = <dynamic>[];
    _data['progress'] = <String, dynamic>{};
    _data['latestSeen'] = <String, dynamic>{};
    _data['series'] = <String, dynamic>{};
    _data['popular'] = <String, dynamic>{};
    notifyListeners();
    await _save();
  }

  // ---------- download offline ----------

  Map<String, dynamic> get _dl =>
      ((_data['downloaded'] ??= <String, dynamic>{}) as Map)
          .cast<String, dynamic>();

  bool isDownloaded(String chapterUrl) => _dl.containsKey(chapterUrl);

  String? downloadDir(String chapterUrl) =>
      _dl[chapterUrl]?['dir'] as String?;

  Future<void> markDownloaded(String chapterUrl, String src, String series,
      String title, String dir, int count,
      [List<PageImage> pages = const []]) async {
    _dl[chapterUrl] = {
      'src': src,
      'series': series,
      'title': title,
      'dir': dir,
      'count': count,
      'aspects': [for (final p in pages) p.aspect],
      'at': DateTime.now().toIso8601String(),
    };
    notifyListeners();
    await _save();
  }

  Future<void> removeDownload(String chapterUrl) async {
    final dir = downloadDir(chapterUrl);
    if (dir != null) {
      try {
        await Directory(dir).delete(recursive: true);
      } catch (_) {}
    }
    _dl.remove(chapterUrl);
    notifyListeners();
    await _save();
  }
  /// Halaman offline urut file + rasio tersimpan. null kalau belum lengkap.
  /// File 0 byte (gagal/corrupt) dibuang: dianggap belum lengkap,
  /// bukan ditampilkan rusak.
  Future<List<PageImage>?> localPages(String chapterUrl) async {
    final rec = _dl[chapterUrl];
    if (rec == null) return null;
    final d = Directory(rec['dir'] as String? ?? '');
    if (!await d.exists()) {
      _dl.remove(chapterUrl);
      notifyListeners();
      await _save();
      return null;
    }
    final all = <String>[];
    final files = <String>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      all.add(e.path);
      try {
        if (await e.length() > 0) files.add(e.path);
      } catch (_) {}
    }
    // Ada yg corrupt/hilang -> belum lengkap (bisa unduh ulang).
    if (files.length != all.length) return null;
    files.sort();
    final want = (rec['count'] as num?)?.toInt() ?? 0;
    if (files.isEmpty || (want > 0 && files.length < want)) return null;
    final aspects = rec['aspects'] as List? ?? [];
    return [
      for (var i = 0; i < files.length; i++)
        PageImage(
          url: files[i],
          aspect: (i < aspects.length
                  ? (aspects[i] as num?)?.toDouble()
                  : null) ??
              0.75,
        ),
    ];
  }

  /// Daftar unduhan untuk tab Offline. Terbaru dulu.
  List<Map<String, dynamic>> get downloads {
    final out = <Map<String, dynamic>>[];
    for (final e in _dl.entries) {
      final m = (e.value as Map).cast<String, dynamic>();
      out.add({'url': e.key, ...m});
    }
    out.sort((a, b) => (b['at'] as String? ?? '')
        .compareTo(a['at'] as String? ?? ''));
    return out;
  }
}
