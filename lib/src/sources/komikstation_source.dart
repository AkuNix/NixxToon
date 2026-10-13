import 'package:dio/dio.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/comic_models.dart';
import 'komik_source.dart';
import 'series_index.dart';

// KomikStation = WordPress MangaStream. Semua static HTML (tanpa JS):
// katalog + populer + terbaru di /manga/, chapter di #readerarea,
// chapter-list server-rendered di #chapterlist, sitemap untuk recent.
// Risiko jujur: Cloudflare kadang challenge IP tertentu (dio tak bisa JS).
class KomikStationSource implements KomikSource {
  @override
  String get id => 'ks';
  @override
  String get name => 'KomikStation';

  static const baseUrl = 'https://komikstation.org';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': _ua, 'Referer': '$baseUrl/'},
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  // Cache detail per sesi (detail + chapterList = 1 fetch).
  final _detailCache = <String, (SeriesInfo, List<ChapterRef>)>{};

  Future<html_dom.Document> _doc(String path) async {
    final res = await _dio.get(path);
    if (res.statusCode != 200) {
      throw StateError('KS ${res.statusCode} $path');
    }
    return html_parser.parse(res.data as String);
  }

  static String _abs(String href) =>
      href.startsWith('http') ? href : '$baseUrl$href';

  /// "-chapter-278-4" -> 278.4 ; "-chapter-628" -> 628.
  static double ksNumber(String url) {
    final m =
        RegExp(r'-chapter-(\d+(?:-\d+)*)').firstMatch(url.toLowerCase());
    if (m == null) return -1;
    return double.tryParse(m.group(1)!.replaceAll('-', '.')) ?? -1;
  }

  /// "/manga/lookism/" -> "lookism".
  static String slugOf(String seriesUrl) {
    final m = RegExp(r'/manga/([^/]+)/').firstMatch(seriesUrl);
    return m?.group(1) ?? '';
  }

  /// "abc-chapter-12" -> "abc" (untuk grouping sitemap).
  static String seriesPart(String chapterSlug) =>
      chapterSlug.replaceAll(RegExp(r'-chapter-\d.*$'), '');

  static String _text(html_dom.Element? e) => e?.text.trim() ?? '';

  @override
  Future<List<SeriesInfo>> allSeries() async {
    final out = <SeriesInfo>[];
    for (var i = 1; i <= 10; i++) {
      final res = await _dio.get('/manga-sitemap$i.xml');
      if (res.statusCode != 200) break;
      final locs = RegExp(r'<loc>([^<]+)</loc>')
          .allMatches(res.data as String)
          .map((m) => m.group(1)!);
      var any = false;
      for (final loc in locs) {
        final slug = slugOf(loc);
        if (slug.isEmpty) continue;
        any = true;
        final lm = RegExp(r'<lastmod>([^<]+)</lastmod>')
            .firstMatch(res.data as String);
        out.add(SeriesInfo(
          src: 'ks',
          label: slug,
          title: prettifySlug(slug),
          cover: '',
          status: '',
          type: '',
          genres: const [],
          synopsis: '',
          projectUrl: loc,
          updated: lm == null ? null : DateTime.tryParse(lm.group(1)!),
        ));
      }
      if (!any) break;
    }
    return out;
  }

  @override
  Future<List<ChapterRef>> recentChapters({int limit = 25}) async {
    // post-sitemap1 = ~1000 postingan terbaru. Kelompokkan per series.
    final res = await _dio.get('/post-sitemap1.xml');
    if (res.statusCode != 200) return const [];
    final xml = res.data as String;
    final urls = RegExp(r'<url>(.*?)</url>', dotAll: true)
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .toList();
    final latest = <String, ChapterRef>{};
    for (final block in urls) {
      final loc =
          RegExp(r'<loc>([^<]+)</loc>').firstMatch(block)?.group(1) ?? '';
      if (!loc.contains('-chapter-')) continue;
      final slug = loc.split('/').where((s) => s.isNotEmpty).last;
      final series = seriesPart(slug);
      if (series.isEmpty || latest.containsKey(series)) continue;
      final lm = RegExp(r'<lastmod>([^<]+)</lastmod>')
          .firstMatch(block)
          ?.group(1);
      final n = ksNumber(slug);
      latest[series] = ChapterRef(
        src: 'ks',
        series: series,
        title: n < 0 ? 'Chapter ?' : 'Chapter ${_fmtNum(n)}',
        number: n,
        url: loc,
        published: lm == null ? null : DateTime.tryParse(lm),
      );
      if (latest.length >= limit) break;
    }
    final out = latest.values.toList()
      ..sort((a, b) => (b.published ?? DateTime(2000))
          .compareTo(a.published ?? DateTime(2000)));
    return out;
  }

  static String _fmtNum(double n) =>
      n == n.truncateToDouble() ? n.toInt().toString() : n.toString();

  @override
  Future<List<SeriesInfo>> popular() async {
    final doc = await _doc('/manga/');
    final out = <SeriesInfo>[];
    final seen = <String>{};
    for (final range in ['weekly', 'monthly', 'alltime']) {
      final blocks = doc.querySelectorAll('.wpop-$range li');
      for (final li in blocks) {
        final a = li.querySelector('a.series');
        final href = a?.attributes['href'] ?? '';
        final slug = slugOf(href);
        if (slug.isEmpty || !seen.add(slug)) continue;
        // Judul: teks anchor minus markup noscript (lazy-load).
        final rawTitle =
            _text(a).replaceAll(RegExp(r'<[^>]*>'), '').trim();
        out.add(SeriesInfo(
          src: 'ks',
          label: slug,
          title: rawTitle.isEmpty ? prettifySlug(slug) : rawTitle,
          cover: _nsCover(li),
          status: '',
          type: '',
          genres: const [],
          synopsis: '',
          projectUrl: _abs(href),
          updated: null,
        ));
      }
    }
    return out;
  }

  /// Cover asli ada di dalam <noscript> (img lazy di luar cuma placeholder).
  static String _nsCover(html_dom.Element li) {
    final m = RegExp(r'<noscript>(.*?)</noscript>', dotAll: true)
        .firstMatch(li.innerHtml);
    if (m != null) {
      final src =
          RegExp('src="([^"]+)"').firstMatch(m.group(1)!);
      if (src != null && src.group(1)!.startsWith('http')) {
        return src.group(1)!;
      }
    }
    final lazy = li.querySelector('img.lazy');
    final ds = lazy?.attributes['data-src'] ?? '';
    if (ds.startsWith('http') && !ds.startsWith('data:')) return ds;
    return '';
  }

  @override
  Future<List<SeriesInfo>> searchSeries(String query) async {
    // Lokal di atas indeks sitemap (full, tanpa cover).
    final q = query.trim();
    if (q.isEmpty) return const [];
    final all = await allSeries();
    final starts = <SeriesInfo>[];
    final contains = <SeriesInfo>[];
    for (final s in all) {
      final hit = matchTitle(s.title, q) > 0 ||
          s.label.toLowerCase().contains(q.toLowerCase());
      if (!hit) continue;
      if (matchTitle(s.title, q) == 2) {
        starts.add(s);
      } else {
        contains.add(s);
      }
    }
    return [...starts, ...contains].take(20).toList();
  }

  @override
  Future<SeriesInfo> seriesDetail(String label, {String src = 'ks'}) async {
    final cached = _detailCache[label];
    if (cached != null) return cached.$1;
    final doc = await _doc('/manga/$label/');
    final h1 = doc.querySelector('h1');
    var title = _text(h1).replaceAll(RegExp(r'bahasa indonesia', caseSensitive: false), '').trim();
    if (title.isEmpty) {
      title = doc
              .querySelector('meta[property="og:title"]')
              ?.attributes['content'] ??
          prettifySlug(label);
      title = title.split(' - ').first.trim();
    }
    final cover = doc
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        '';
    final genres = [
      for (final a in doc.querySelectorAll('a[href*="/genres/"]'))
        _text(a)
    ].where((g) => g.isNotEmpty && g.length < 30).toSet().toList();
    final body = doc.body?.text ?? '';
    final status = RegExp(r'\b(Completed|Tamat)\b').hasMatch(body)
        ? 'Completed'
        : 'Ongoing';
    final desc = doc
            .querySelector('meta[property="og:description"]')
            ?.attributes['content'] ??
        '';
    final info = SeriesInfo(
      src: 'ks',
      label: label,
      title: title,
      cover: cover,
      status: status,
      type: genres.contains('Manhua')
          ? 'Manhua'
          : genres.contains('Manga')
              ? 'Manga'
              : 'Manhwa',
      genres: genres,
      synopsis: desc,
      projectUrl: '$baseUrl/manga/$label/',
      updated: null,
    );
    _detailCache[label] = (info, _parseChapters(doc, label));
    return info;
  }

  static List<ChapterRef> _parseChapters(
      html_dom.Document doc, String label) {
    final out = <ChapterRef>[];
    for (final li in doc.querySelectorAll('#chapterlist li')) {
      final a = li.querySelector('.eph-num a');
      final href = a?.attributes['href'] ?? '';
      if (href.isEmpty || !href.contains('chapter')) continue;
      final title = _text(a?.querySelector('.chapternum'));
      final date = _text(a?.querySelector('.chapterdate'));
      final name = title.isEmpty ? _text(a) : title;
      out.add(ChapterRef(
        src: 'ks',
        series: label,
        title: name.isEmpty ? 'Chapter ?' : name,
        number: ksNumber(href),
        url: _abs(href),
        published: idDate(date),
      ));
    }
    out.sort((a, b) => b.number.compareTo(a.number));
    return out;
  }

  @override
  Future<List<ChapterRef>> chapterList(String label, {String src = 'ks'}) async {
    final cached = _detailCache[label];
    if (cached != null) return cached.$2;
    await seriesDetail(label);
    return _detailCache[label]?.$2 ?? const [];
  }

  @override
  Future<ChapterPages> chapterPages(ChapterRef chapter) async {
    final res = await _dio.getUri(Uri.parse(chapter.url));
    final doc = html_parser.parse(res.data as String);
    final pages = <PageImage>[];
    for (final img in doc.querySelectorAll('#readerarea img')) {
      final page = ksPageOf(img);
      if (page != null) pages.add(page);
    }
    return ChapterPages(chapter: chapter, images: pages);
  }

  /// Pure (testable): data-src dulu (lazyload), tolak gif/iklan.
  static PageImage? ksPageOf(html_dom.Element img) {
    final src =
        img.attributes['data-src'] ?? img.attributes['src'] ?? '';
    if (!src.contains('klikcdn')) return null;
    if (src.endsWith('.gif')) return null;
    return PageImage(url: src, aspect: null);
  }
}
