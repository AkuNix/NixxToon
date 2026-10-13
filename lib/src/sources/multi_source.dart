import '../models/comic_models.dart';
import '../store/library_store.dart';
import 'komik_source.dart';
import 'komiku_source.dart';
import 'komikpedia_source.dart';

// Gabungan N sumber di balik 1 kontrak. Tiap sumber degradasi mandiri:
// satu gagal -> lainnya tetap jalan. Urutan prioritas: kp, ks, km.
class MultiSource implements KomikSource {
  final Map<String, KomikSource> sources;
  final LibraryStore store;

  MultiSource(this.sources, this.store);

  @override
  String get id => 'mix';
  @override
  String get name => 'Semua';

  KomikSource _of(String src) => sources[src] ?? sources['kp']!;

  /// Dorong setting kualitas gambar ke adapter yg mendukung (KP).
  void syncSettings() {
    final kp = sources['kp'];
    if (kp is KomikpediaSource) kp.imgSize = store.imgQuality;
  }

  List<String> get order => [
        for (final k in const ['kp', 'ks', 'km'])
          if (sources.containsKey(k)) k,
        for (final k in sources.keys)
          if (k != 'kp' && k != 'ks' && k != 'km') k,
      ];

  @override
  Future<List<ChapterRef>> recentChapters({int limit = 25}) async {
    final lists = await Future.wait([
      for (final id in order)
        sources[id]!
            .recentChapters(limit: limit)
            .catchError((_) => <ChapterRef>[]),
    ]);
    final all = [for (final l in lists) ...l];
    all.sort((a, b) => (b.published ?? DateTime(2000))
        .compareTo(a.published ?? DateTime(2000)));
    return all.take(limit * 2).toList();
  }

  @override
  Future<List<SeriesInfo>> searchSeries(String query) async {
    // Lokal di atas indeks cache (lengkap, offline-capable).
    if (!store.hasSeriesIndex) await refreshIndex();
    final q = query.trim();
    if (q.isEmpty) return const [];
    final starts = <SeriesInfo>[];
    final contains = <SeriesInfo>[];
    for (final s in store.cachedSeries()) {
      switch (matchTitleOf(s, q)) {
        case 2:
          starts.add(s);
        case 1:
          contains.add(s);
      }
    }
    return [...starts, ...contains].take(30).toList();
  }

  static int matchTitleOf(SeriesInfo s, String q) {
    String norm(String x) =>
        x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final t = norm(s.title);
    final l = norm(s.label);
    final qq = norm(q);
    if (qq.isEmpty) return 0;
    if (t.startsWith(qq) || l.startsWith(qq)) return 2;
    if (t.contains(qq) || l.contains(qq)) return 1;
    return 0;
  }

  @override
  Future<SeriesInfo> seriesDetail(String label, {String src = 'kp'}) =>
      _of(src).seriesDetail(label, src: src);

  @override
  Future<List<ChapterRef>> chapterList(String label, {String src = 'kp'}) =>
      _of(src).chapterList(label, src: src);

  @override
  Future<ChapterPages> chapterPages(ChapterRef chapter) =>
      _of(chapter.src).chapterPages(chapter);

  @override
  Future<List<SeriesInfo>> allSeries() async {
    if (!store.hasSeriesIndex) await refreshIndex();
    return store.cachedSeries();
  }

  bool _refreshing = false;

  /// Refresh indeks semua sumber -> cache. KP+KS selalu (murah);
  /// KM (158 hlm) hanya bila full atau cache belum ada KM.
  /// Dijaga anti-ganda: tak pernah 2 crawl bersamaan.
  Future<void> refreshIndex({bool full = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      for (final id in ['kp', 'ks']) {
        if (!sources.containsKey(id)) continue;
        try {
          await store.saveSeriesIndex(await sources[id]!.allSeries());
        } catch (_) {}
      }
      final km = sources['km'];
      final hasKm = store.cachedSeriesOf('km').isNotEmpty;
      if (km == null || (!full && hasKm)) return;
      await store.setIndexStatus('km:0');
      try {
        final all = km is KomikuSource
            ? await km.allSeries(
                onProgress: (p) => store.setIndexStatus('km:$p'))
            : await km.allSeries();
        await store.saveSeriesIndex(all);
      } catch (_) {}
      await store.setIndexStatus('');
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<List<SeriesInfo>> popular() async {
    final cached = store.cachedPopular();
    if (cached.isNotEmpty) return cached;
    return refreshPopular();
  }

  Future<List<SeriesInfo>> refreshPopular() async {
    final lists = await Future.wait([
      for (final id in order)
        sources[id]!.popular().catchError((_) => <SeriesInfo>[]),
    ]);
    final seen = <String>{};
    final out = <SeriesInfo>[];
    for (final l in lists) {
      for (final s in l) {
        final key = s.title
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(s);
        if (out.length >= 30) break;
      }
      if (out.length >= 30) break;
    }
    await store.savePopular(out);
    return out;
  }
}
