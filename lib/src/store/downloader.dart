import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/comic_models.dart';
import '../sources/komik_source.dart';
import 'library_store.dart';

// Download chapter ke folder app-private (tanpa izin storage).
// 1 chapter = 1 grup task (group = chapter.url).
class DownloadCenter extends ChangeNotifier {
  final KomikSource _source;
  final LibraryStore _store;

  /// url -> 0..1 (got/want) saat berjalan.
  final Map<String, double> running = {};
  final Map<String, String> failed = {};

  String titleOf(String url) => _title[url] ?? url;

  final Map<String, int> _want = {};
  final Map<String, int> _got = {};
  final Map<String, int> _failedN = {};
  final Map<String, String> _src = {};
  final Map<String, String> _series = {};
  final Map<String, String> _title = {};
  final Map<String, String> _dir = {};
  final Map<String, String> _rel = {};
  final Map<String, List<double?>> _aspects = {};
  final Map<String, List<String>> _urls = {};
  final _retried = <String>{};

  DownloadCenter(this._source, this._store) {
    FileDownloader().updates.listen(_onUpdate);
  }

  static String safe(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  Future<void> downloadChapter(ChapterRef chapter) async {
    final url = chapter.url;
    if (running.containsKey(url) || _store.isDownloaded(url)) return;
    running[url] = 0;
    failed.remove(url);
    _retried.remove(url); // coba manual = kesempatan retry otomatis baru
    notifyListeners();
    try {
      final pages = await _source.chapterPages(chapter);
      if (pages.images.isEmpty) throw StateError('0 gambar');
      final docs = await getApplicationDocumentsDirectory();
      // ponytail: folder privat app, tanpa permission_handler
      final rel =
          'nixxtoon_dl/${safe(chapter.src)}/${safe(chapter.series)}/${safe(chapter.number.toString())}';
      _want[url] = pages.images.length;
      _got[url] = 0;
      _failedN[url] = 0;
      _src[url] = chapter.src;
      _series[url] = chapter.series;
      _title[url] = chapter.title;
      _dir[url] = '${docs.path}/$rel';
      _rel[url] = rel;
      _aspects[url] = [for (final p in pages.images) p.aspect];
      _urls[url] = [for (final p in pages.images) p.url];
      await _enqueueAll(url, rel);
    } catch (e) {
      _clear(url);
      failed[url] = e.toString();
      notifyListeners();
    }
  }

  Future<void> _enqueueAll(String url, String rel) async {
    final urls = _urls[url] ?? const [];
    var i = 0;
    for (final img in urls) {
      i++;
      final ok = await FileDownloader().enqueue(
        DownloadTask(
          url: img,
          directory: rel,
          baseDirectory: BaseDirectory.applicationDocuments,
          filename: '${i.toString().padLeft(3, '0')}.jpg',
          group: url,
          updates: Updates.status,
          retries: 2,
          requiresWiFi: _store.wifiOnly,
        ),
      );
      if (!ok) throw StateError('enqueue gagal');
    }
  }

  void _onUpdate(TaskUpdate e) {
    if (e is! TaskStatusUpdate) return;
    final url = e.task.group;
    if (!running.containsKey(url)) return;
    switch (e.status) {
      case TaskStatus.complete:
        _got[url] = (_got[url] ?? 0) + 1;
        _settle(url);
      case TaskStatus.failed:
      case TaskStatus.notFound:
      case TaskStatus.canceled:
        _failedN[url] = (_failedN[url] ?? 0) + 1;
        _settle(url);
      default:
        break;
    }
  }

  /// Selesai saat semua tugas berhenti (sukses+gagal == target).
  /// Gagal -> coba ulang otomatis 1x, lalu tandai gagal + tombol ulangi.
  void _settle(String url) {
    final want = _want[url] ?? 1;
    final got = _got[url] ?? 0;
    final bad = _failedN[url] ?? 0;
    if (got + bad < want) {
      running[url] = got / want;
      notifyListeners();
      return;
    }
    if (bad == 0) {
      final dir = _dir[url] ?? '';
      final src = _src[url] ?? 'kp';
      final series = _series[url] ?? '';
      final title = _title[url] ?? '';
      final aspects = _aspects[url] ?? const <double?>[];
      _clear(url);
      _store.markDownloaded(url, src, series, title, dir, want,
          [for (final a in aspects) PageImage(url: '', aspect: a)]);
      notifyListeners();
      return;
    }
    if (!_retried.contains(url)) {
      // Coba ulang 1x: file gagal ditimpa ulang.
      _retried.add(url);
      _got[url] = 0;
      _failedN[url] = 0;
      running[url] = 0;
      notifyListeners();
      final rel = _rel[url] ?? '';
      _enqueueAll(url, rel).catchError((Object err) {
        _clear(url);
        failed[url] = err.toString();
        notifyListeners();
        return <void>[];
      });
      return;
    }
    _clear(url);
    failed[url] = '$bad gambar gagal. Ketuk untuk coba lagi.';
    notifyListeners();
  }

  void _clear(String url) {
    running.remove(url);
    _want.remove(url);
    _got.remove(url);
    _failedN.remove(url);
    _src.remove(url);
    _series.remove(url);
    _title.remove(url);
    _dir.remove(url);
    _rel.remove(url);
    _aspects.remove(url);
    _urls.remove(url);
  }
}
