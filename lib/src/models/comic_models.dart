// NixxToon data models. Pure Dart (no Flutter) so the scraper stays testable.
class SeriesInfo {
  final String src; // id sumber: kp | ks | km
  final String label; // id lokal di sumber itu
  final String title;
  final String cover; // upscaled thumbnail url
  final String status; // Ongoing / Completed / ?
  final String type; // Manhwa / Manga / Manhua
  final List<String> genres;
  final String synopsis;
  final String projectUrl;
  final DateTime? updated;

  const SeriesInfo({
    this.src = 'kp',
    required this.label,
    required this.title,
    required this.cover,
    required this.status,
    required this.type,
    required this.genres,
    required this.synopsis,
    required this.projectUrl,
    required this.updated,
  });

  Map<String, dynamic> toCache() => {
        'src': src,
        'title': title,
        'cover': cover,
        'status': status,
        'type': type,
        'genres': genres,
        'updated': updated?.toIso8601String(),
        'projectUrl': projectUrl,
      };

  factory SeriesInfo.fromCache(String label, Map<String, dynamic> m) =>
      SeriesInfo(
        src: m['src'] as String? ?? 'kp',
        label: label,
        title: m['title'] as String? ?? label,
        cover: m['cover'] as String? ?? '',
        status: m['status'] as String? ?? '',
        type: m['type'] as String? ?? '',
        genres: [for (final g in (m['genres'] as List? ?? [])) g.toString()],
        synopsis: '',
        projectUrl: m['projectUrl'] as String? ?? '',
        updated: DateTime.tryParse(m['updated'] as String? ?? ''),
      );
}

class ChapterRef {
  final String src; // id sumber: kp | ks | km
  final String series; // label lokal series di sumber itu
  final String title; // e.g. "Chapter 628.2"
  final double number; // 628.2, -1 if unparseable
  final String url;
  final DateTime? published;

  const ChapterRef({
    this.src = 'kp',
    required this.series,
    required this.title,
    required this.number,
    required this.url,
    required this.published,
  });
}

class ChapterPages {
  final ChapterRef chapter;
  final List<PageImage> images;

  const ChapterPages({required this.chapter, required this.images});
}

// Satu halaman: url + rasio asli (null = tak diketahui -> tinggi natural).
// fallbackUrl: host cadangan (Komiku: image2 <-> img).
class PageImage {
  final String url;
  final double? aspect; // width / height
  final String? fallbackUrl;

  const PageImage({required this.url, required this.aspect, this.fallbackUrl});

  Map<String, dynamic> toCache() =>
      {'url': url, 'aspect': aspect, 'fallbackUrl': fallbackUrl};

  factory PageImage.fromCache(Map<String, dynamic> m) => PageImage(
        url: m['url'] as String? ?? '',
        aspect: (m['aspect'] as num?)?.toDouble(),
        fallbackUrl: m['fallbackUrl'] as String?,
      );
}
