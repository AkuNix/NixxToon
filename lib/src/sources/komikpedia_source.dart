import 'package:dio/dio.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/comic_models.dart';
import 'komik_source.dart';
import 'series_index.dart';

// Komikpedia = Blogger. List+d pencarian via Blogger feed JSON (stabil),
// HTML cuma buat gambar halaman chapter. Selector terpusat di sini (1 file).
class KomikpediaSource implements KomikSource {
  @override
  String get id => 'kp';
  @override
  String get name => 'Komikpedia';

  static const baseUrl = 'https://www.comic.komikpedia.com';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';

  // Label sistem Blogger yg BUKAN nama series/genre.
  static const _metaLabels = {'Chapter', 'Project', 'Series', 'Update'};
  static const _types = {'Manhwa', 'Manga', 'Manhua', 'Novel'};
  static const _statuses = {'Ongoing', 'Completed', 'Dropped', 'Upcoming'};
  // Daftar genre situs (dari filter homepage). Lowercase biar aman.
  static const _genres = {
    'action', 'adventurer', 'comedy', 'dementia', 'demons', 'drama', 'ecchi',
    'fantasy', 'game', 'harem', 'historical', 'horror', 'josei', 'magic',
    'martial arts', 'mecha', 'military', 'music', 'mystery', 'parody',
    'police', 'psychological', 'romance', 'samurai', 'school', 'sci-fi',
    'seinen', 'shoujo', 'shoujo ai', 'shounen', 'slice of life', 'space',
    'sports', 'super power', 'supernatural', 'thriller', 'vampire',
    'work life', 'yuri', 'school life', 'manga', 'manhwa', 'manhua',
    'indonesian', 'english',
  };

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'User-Agent': _ua, 'Referer': '$baseUrl/'},
    ),
  );

  // ---------- feed helpers ----------

  Future<List<Map<String, dynamic>>> _feedEntries(String path) async {
    final res = await _dio.get(path);
    final feed = (res.data as Map)['feed'] as Map?;
    final raw = feed?['entry'];
    if (raw is! List) return const [];
    return raw.cast<Map<String, dynamic>>();
  }

  static String _text(Map e) => (e['title'] as Map?)?['\$t'] as String? ?? '';
  static DateTime? _date(Map e) =>
      DateTime.tryParse((e['published'] as Map?)?['\$t'] as String? ?? '');
  static String _link(Map e) {
    final links = e['link'];
    if (links is List) {
      for (final l in links) {
        if ((l as Map)['rel'] == 'alternate') return l['href'] as String? ?? '';
      }
    }
    return '';
  }

  static List<String> _labels(Map e) {
    final cats = e['category'];
    if (cats is! List) return const [];
    return [for (final c in cats) (c as Map)['term'] as String? ?? ''];
  }

  /// "628.2" dari "Chapter 628.2". -1 kalau tidak ada angka.
  static double chapterNumber(String title) {
    final m = RegExp(r'chapter\s*([\d.]+)', caseSensitive: false).firstMatch(title);
    return double.tryParse(m?.group(1) ?? '') ?? -1;
  }

  static bool _isRating(String s) => RegExp(r'^\d+(\.\d+)?$').hasMatch(s);

  static bool _isName(String l) =>
      !_metaLabels.contains(l) &&
      !_isRating(l) &&
      !_types.contains(l) &&
      !_statuses.contains(l) &&
      !_genres.contains(l.toLowerCase());

  static String _seriesOf(List<String> labels) =>
      labels.firstWhere(_isName, orElse: () => '');

  /// Thumb Blogger s72-c -> s400 biar tajam di grid.
  static String upscale(String url) =>
      url.replaceAll(RegExp(r'/s\d+(-c)?/'), '/s400/');

  SeriesInfo _toSeries(Map e) {
    final labels = _labels(e);
    final label = _seriesOf(labels);
    final status = labels.contains('Completed') ? 'Completed' : 'Ongoing';
    final type = labels.firstWhere(
      _types.contains,
      orElse: () => 'Manhwa',
    );
    final genres = labels
        .where((l) => _genres.contains(l.toLowerCase()) && l != type)
        .toList();
    final thumb = (e['media\$thumbnail'] as Map?)?['url'] as String? ?? '';
    return SeriesInfo(
      label: label,
      title: _text(e),
      cover: thumb.isEmpty ? '' : upscale(thumb),
      status: status,
      type: type,
      genres: genres,
      synopsis: _synopsis((e['content'] as Map?)?['\$t'] as String? ?? ''),
      projectUrl: _link(e),
      updated: _date(e),
    );
  }

  /// Ambil 1-2 paragraf pertama konten project page sebagai sinopsis.
  static String _synopsis(String contentHtml) {
    if (contentHtml.isEmpty) return '';
    final doc = html_parser.parse(contentHtml);
    final ps = doc.querySelectorAll('p');
    final buf = <String>[];
    for (final p in ps) {
      final t = p.text.trim();
      if (t.length > 60) buf.add(t);
      if (buf.length == 2) break;
    }
    return buf.join('\n\n');
  }

  // ---------- KomikSource ----------

  @override
  Future<List<ChapterRef>> recentChapters({int limit = 25}) async {
    final entries = await _feedEntries(
        '/feeds/posts/summary?alt=json&max-results=$limit');
    final out = <ChapterRef>[];
    for (final e in entries) {
      final labels = _labels(e);
      if (!labels.contains('Chapter')) continue;
      final title = _text(e);
      out.add(ChapterRef(
        series: _seriesOf(labels),
        title: title,
        number: chapterNumber(title),
        url: _link(e),
        published: _date(e),
      ));
    }
    return out;
  }

  @override
  Future<List<SeriesInfo>> searchSeries(String query) async {
    // Lokal di atas indeks (lengkap, offline-capable). q= feed Blogger
    // cuma cocok judul post -> chapter tak pernah ketemu.
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
    return [...starts, ...contains];
  }

  @override
  Future<SeriesInfo> seriesDetail(String seriesLabel, {String src = 'kp'}) async {
    final l = Uri.encodeComponent(seriesLabel);
    final entries =
        await _feedEntries('/feeds/posts/default/-/$l?alt=json&max-results=10');
    for (final e in entries) {
      if (_labels(e).contains('Series')) return _toSeries(e);
    }
    throw StateError('Series "$seriesLabel" tidak ketemu');
  }

  @override
  Future<List<ChapterRef>> chapterList(String seriesLabel, {String src = 'kp'}) async {
    final l = Uri.encodeComponent(seriesLabel);
    final out = <ChapterRef>[];
    var start = 1;
    const page = 150;
    while (true) {
      final entries = await _feedEntries(
          '/feeds/posts/summary/-/$l?alt=json&max-results=$page&start-index=$start');
      if (entries.isEmpty) break;
      for (final e in entries) {
        if (!_labels(e).contains('Chapter')) continue;
        final title = _text(e);
        out.add(ChapterRef(
          series: seriesLabel,
          title: title,
          number: chapterNumber(title),
          url: _link(e),
          published: _date(e),
        ));
      }
      if (entries.length < page) break;
      start += page;
    }
    out.sort((a, b) => b.number.compareTo(a.number));
    return out;
  }

  @override
  Future<List<SeriesInfo>> popular() async =>
      popularOf(await allSeries());

  @override
  Future<List<SeriesInfo>> allSeries() async {
    final out = <SeriesInfo>[];
    var start = 1;
    const page = 150;
    while (true) {
      final entries = await _feedEntries(
          '/feeds/posts/default/-/Series?alt=json&max-results=$page&start-index=$start');
      if (entries.isEmpty) break;
      for (final e in entries) {
        if (_labels(e).contains('Series')) out.add(_toSeries(e));
      }
      if (entries.length < page) break;
      start += page;
    }
    return out;
  }

  /// Ukuran gambar yg diminta ke server Blogger (s720|s1080|s1600|asli).
  /// Cara Webtoon: jangan unduh monster, minta pas ukuran layar.
  String imgSize = 's1080';

  @override
  Future<ChapterPages> chapterPages(ChapterRef chapter) async {
    final res = await _dio.get(chapter.url);
    final doc = html_parser.parse(res.data as String);
    final imgs = doc.querySelectorAll('.check-box .separator img');
    final pages = <PageImage>[];
    for (final img in imgs) {
      final page = pageOf(img);
      if (page == null) continue;
      pages.add(PageImage(
        url: resized(page.url, imgSize),
        aspect: page.aspect,
        fallbackUrl: page.fallbackUrl == null
            ? null
            : resized(page.fallbackUrl!, imgSize),
      ));
    }
    return ChapterPages(chapter: chapter, images: pages);
  }

  /// "…/s16000/x.png" -> "…/s1080/x.png". "asli" = tanpa ubah.
  /// Pure (testable).
  static String resized(String url, String size) {
    if (size == 'asli') return url;
    return url.replaceFirst(
        RegExp(r'/(s\d+[^/]*|w\d+[^/]*)/'), '/$size/');
  }

  /// Satu <img> -> PageImage. null kalau bukan gambar konten Blogger.
  /// Pure (testable): rasio dari data-original-*, null bila tak ada.
  static PageImage? pageOf(html_dom.Element img) {
    final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
    if (!src.contains('blogger.googleusercontent.com')) return null;
    final w = int.tryParse(img.attributes['data-original-width'] ?? '') ?? 0;
    final h = int.tryParse(img.attributes['data-original-height'] ?? '') ?? 0;
    return PageImage(
        url: src, aspect: (w > 0 && h > 0) ? w / h : null);
  }
}
