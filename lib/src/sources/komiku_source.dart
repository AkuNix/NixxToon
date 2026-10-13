import 'package:dio/dio.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/comic_models.dart';
import 'komik_source.dart';
import 'series_index.dart';

// Komiku = custom WP. Semua static HTML:
// ranking + terbaru di homepage (cover di data-src),
// katalog /daftar-komik/ (158 hlm, crawl background),
// series /manga/<slug>/, chapter #Baca_Komik (webp langsung, tanpa lazy).
class KomikuSource implements KomikSource {
  @override
  String get id => 'km';
  @override
  String get name => 'Komiku';

  static const baseUrl = 'https://komiku.org';
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

  final _detailCache = <String, (SeriesInfo, List<ChapterRef>)>{};

  Future<html_dom.Document> _doc(String path) async {
    final res = await _dio.get(path);
    if (res.statusCode != 200) {
      throw StateError('KM ${res.statusCode} $path');
    }
    return html_parser.parse(res.data as String);
  }

  static String _abs(String href) =>
      href.startsWith('http') ? href : '$baseUrl$href';

  static String _text(html_dom.Element? e) => e?.text.trim() ?? '';

  static String _cover(html_dom.Element root) {
    final img = root.querySelector('img.lazy');
    var u = img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';
    if (u.startsWith('/')) u = '$baseUrl$u';
    if (u.contains('lazy.jpg')) return '';
    return u;
  }

  static String _slug(String seriesHref) {
    final m = RegExp(r'/manga/([^/]+)/').firstMatch(seriesHref);
    return m?.group(1) ?? '';
  }

  /// "-chapter-278-4" -> 278.4 ; "/x-chapter-628/" -> 628.
  static double kmNumber(String url) {
    final m =
        RegExp(r'-chapter-(\d+(?:-\d+)*)').firstMatch(url.toLowerCase());
    if (m == null) return -1;
    return double.tryParse(m.group(1)!.replaceAll('-', '.')) ?? -1;
  }

  static String _fmtNum(double n) =>
      n == n.truncateToDouble() ? n.toInt().toString() : n.toString();

  @override
  Future<List<SeriesInfo>> popular() async {
    final doc = await _doc('/');
    final out = <SeriesInfo>[];
    final seen = <String>{};
    for (final panel in ['#rank-harian', '#rank-mingguan']) {
      for (final art in doc.querySelectorAll('$panel article.ls4')) {
        final a = art.querySelector('h4 a');
        final slug = _slug(a?.attributes['href'] ?? '');
        if (slug.isEmpty || !seen.add(slug)) continue;
        out.add(SeriesInfo(
          src: 'km',
          label: slug,
          title: _text(a).isEmpty ? prettifySlug(slug) : _text(a),
          cover: _cover(art),
          status: '',
          type: '',
          genres: const [],
          synopsis: '',
          projectUrl: _abs('/manga/$slug/'),
          updated: null,
        ));
      }
    }
    return out;
  }

  @override
  Future<List<ChapterRef>> recentChapters({int limit = 40}) async {
    final doc = await _doc('/');
    final out = <ChapterRef>[];
    final sec = doc.querySelector('section#Terbaru');
    if (sec == null) return const [];
    for (final art in sec.querySelectorAll('article.ls2')) {
      final seriesA = art.querySelector('a[href*="/manga/"]');
      final slug = _slug(seriesA?.attributes['href'] ?? '');
      html_dom.Element? chA;
      for (final a in art.querySelectorAll('a')) {
        if ((a.attributes['href'] ?? '').contains('-chapter-')) {
          chA = a;
          break;
        }
      }
      if (slug.isEmpty || chA == null) continue;
      final curl = _abs(chA.attributes['href']!);
      final n = kmNumber(curl);
      final timeM = RegExp(
              r'(\d+\s*(?:menit|jam|hari|minggu|bulan|tahun)[^<·]*lalu|kemarin|baru saja)',
              caseSensitive: false)
          .firstMatch(art.innerHtml);
      out.add(ChapterRef(
        src: 'km',
        series: slug,
        title: _text(chA).isEmpty ? 'Chapter ${_fmtNum(n)}' : _text(chA),
        number: n,
        url: curl,
        published: timeM == null ? null : idRelative(timeM.group(1)!),
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<List<SeriesInfo>> allSeries(
      {void Function(int page)? onProgress}) async {
    // 158 halaman @ ~50-100 judul. Batch paralel 8.
    final slugs = <String>{};
    final out = <SeriesInfo>[];
    var page = 1;
    while (true) {
      final batch = <Future<List<SeriesInfo>>>[];
      for (var i = 0; i < 8; i++) {
        batch.add(_daftarPage(page + i).catchError((_) => <SeriesInfo>[]));
      }
      final results = await Future.wait(batch);
      var fresh = 0;
      for (final list in results) {
        for (final s in list) {
          if (slugs.add(s.label)) {
            out.add(s);
            fresh++;
          }
        }
      }
      page += 8;
      onProgress?.call(page);
      if (fresh == 0 || page > 200) break;
    }
    return out;
  }

  Future<List<SeriesInfo>> _daftarPage(int page) async {
    final doc = await _doc(
        page <= 1 ? '/daftar-komik/' : '/daftar-komik/page/$page/');
    final out = <SeriesInfo>[];
    for (final a in doc.querySelectorAll('a[href*="/manga/"]')) {
      final slug = _slug(a.attributes['href']!);
      if (slug.isEmpty) continue;
      final t = _text(a);
      if (t.isEmpty) continue;
      out.add(SeriesInfo(
        src: 'km',
        label: slug,
        title: t,
        cover: '',
        status: '',
        type: '',
        genres: const [],
        synopsis: '',
        projectUrl: _abs('/manga/$slug/'),
        updated: null,
      ));
    }
    // dedup urutan stabil
    final seen = <String>{};
    return out.where((s) => seen.add(s.label)).toList();
  }

  @override
  Future<List<SeriesInfo>> searchSeries(String query) async {
    // Tak ada search server-side -> filter lokal dari crawl daftar.
    // (Dipanggil facade hanya saat indeks KM kosong.)
    final q = query.trim();
    if (q.isEmpty) return const [];
    final all = await allSeries();
    final starts = <SeriesInfo>[];
    final contains = <SeriesInfo>[];
    for (final s in all) {
      switch (matchTitle(s.title, q)) {
        case 2:
          starts.add(s);
        case 1:
          contains.add(s);
      }
    }
    return [...starts, ...contains].take(20).toList();
  }

  @override
  Future<SeriesInfo> seriesDetail(String label, {String src = 'km'}) async {
    final cached = _detailCache[label];
    if (cached != null) return cached.$1;
    final doc = await _doc('/manga/$label/');
    var title = doc
            .querySelector('meta[property="og:title"]')
            ?.attributes['content'] ??
        '';
    title = title.split('|').first.split('-').first.trim();
    if (title.isEmpty) title = prettifySlug(label);
    final cover = doc
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        '';
    final genres = [
      for (final a in doc.querySelectorAll('a[href*="/genre/"]')) _text(a)
    ].where((g) => g.isNotEmpty && g.length < 30).toSet().toList();
    final body = doc.body?.text ?? '';
    final status = RegExp(r'\b(Tamat|Completed)\b').hasMatch(body)
        ? 'Completed'
        : 'Ongoing';
    final desc = doc
            .querySelector('meta[property="og:description"]')
            ?.attributes['content'] ??
        doc.querySelector('meta[name="description"]')?.attributes['content'] ??
        '';
    final info = SeriesInfo(
      src: 'km',
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
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('-chapter-')) continue;
      final url = href.startsWith('http') ? href : '$baseUrl$href';
      if (!seen.add(url)) continue;
      final n = kmNumber(url);
      final t = _text(a);
      out.add(ChapterRef(
        src: 'km',
        series: label,
        title: t.isEmpty ? 'Chapter ${_fmtNum(n)}' : t,
        number: n,
        url: url,
        published: null,
      ));
    }
    out.sort((a, b) => b.number.compareTo(a.number));
    return out;
  }

  @override
  Future<List<ChapterRef>> chapterList(String label, {String src = 'km'}) async {
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
    for (final img in doc.querySelectorAll('#Baca_Komik img')) {
      final page = kmPageOf(img);
      if (page != null) pages.add(page);
    }
    return ChapterPages(chapter: chapter, images: pages);
  }

  /// Pure (testable): src langsung, pola /upload, tolak promosi.
  /// fallbackUrl meniru onerror situs (tukar host image2 <-> img).
  static PageImage? kmPageOf(html_dom.Element img) {
    final src = img.attributes['src'] ?? '';
    if (!src.contains('/upload')) return null;
    if (src.contains('promosi')) return null;
    String? fb;
    if (src.contains('image2.komiku.to')) {
      fb = src.replaceAll('image2.komiku.to', 'img.komiku.org');
    } else if (src.contains('img.komiku.org')) {
      fb = src.replaceAll('img.komiku.org', 'image2.komiku.to');
    }
    return PageImage(url: src, aspect: null, fallbackUrl: fb);
  }
}
