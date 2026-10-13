import '../models/comic_models.dart';

/// Skor cocok judul: 2 = awalan, 1 = mengandung, 0 = tidak.
/// Abaikan tanda baca/spasi ("solo-max-level" cocok "solo max level").
int matchTitle(String title, String query) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final t = norm(title);
  final q = norm(query);
  if (q.isEmpty || t.isEmpty) return 0;
  if (t.startsWith(q)) return 2;
  if (t.contains(q)) return 1;
  return 0;
}

/// "ks:lookism" -> ("ks","lookism"). Tanpa prefix = kp (data lama).
(String, String) splitKey(String key) {
  final i = key.indexOf(':');
  if (i < 0) return ('kp', key);
  return (key.substring(0, i), key.substring(i + 1));
}

/// "solo-max-level-newbie" -> "Solo Max Level Newbie".
/// Buang prefix angka ala Komiku ("131241-solo-..." -> "Solo ...").
String prettifySlug(String slug) {
  var s = slug.replaceAll('_', '-');
  s = s.replaceAll(RegExp(r'^\d+-'), '');
  return s
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w.length <= 2
          ? w.toUpperCase()
          : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

const _idMonths = {
  'januari': 1, 'jan': 1,
  'februari': 2, 'feb': 2,
  'maret': 3, 'mar': 3,
  'april': 4, 'apr': 4,
  'mei': 5,
  'juni': 6, 'jun': 6,
  'juli': 7, 'jul': 7,
  'agustus': 8, 'agu': 8, 'ags': 8,
  'september': 9, 'sep': 9, 'sept': 9,
  'oktober': 10, 'okt': 10, 'oct': 10,
  'november': 11, 'nov': 11,
  'desember': 12, 'des': 12, 'dec': 12,
};

/// "Oktober 9, 2026" (KomikStation) -> DateTime. null kalau gagal.
DateTime? idDate(String text) {
  final m =
      RegExp(r'(\w+)\s+(\d{1,2}),?\s+(\d{4})').firstMatch(text.trim());
  if (m == null) return null;
  final mo = _idMonths[m.group(1)!.toLowerCase()];
  if (mo == null) return null;
  return DateTime(int.parse(m.group(3)!), mo, int.parse(m.group(2)!));
}

/// "10 menit lalu" / "2 jam lalu" / "kemarin" (Komiku) -> DateTime.
DateTime? idRelative(String text) {
  final t = text.trim().toLowerCase();
  final now = DateTime.now();
  var m = RegExp(r'(\d+)\s*menit').firstMatch(t);
  if (m != null) return now.subtract(Duration(minutes: int.parse(m.group(1)!)));
  m = RegExp(r'(\d+)\s*jam').firstMatch(t);
  if (m != null) return now.subtract(Duration(hours: int.parse(m.group(1)!)));
  m = RegExp(r'(\d+)\s*hari').firstMatch(t);
  if (m != null) return now.subtract(Duration(days: int.parse(m.group(1)!)));
  if (t.startsWith('kemarin')) return now.subtract(const Duration(days: 1));
  if (t.startsWith('baru')) return now;
  return null;
}

// Daftar editorial "Populer di Komikpedia" (mengikuti Hot Manga situs).
// Cocok by label ATAU judul (case-insensitive) biar tahan beda label.
const popularTitles = [
  'Lookism',
  'Eleceed',
  'Solo Leveling: Ragnarok',
  'Reality Quest',
  'Manager Kim',
  'Solo Max-Level Newbie',
  'Study Group',
  'True Education',
  'Bad Guy',
  'Ticket Hero (S2)',
];

List<SeriesInfo> popularOf(List<SeriesInfo> all) {
  final out = <SeriesInfo>[];
  for (final t in popularTitles) {
    final low = t.toLowerCase();
    for (final s in all) {
      if (s.label.toLowerCase() == low || s.title.toLowerCase() == low) {
        out.add(s);
        break;
      }
    }
  }
  return out;
}

/// Series baru = project page terbit paling akhir.
List<SeriesInfo> newestOf(List<SeriesInfo> all, [int limit = 10]) {
  final c = all.where((s) => s.label.isNotEmpty).toList();
  c.sort((a, b) => _upd(b).compareTo(_upd(a)));
  return c.take(limit).toList();
}

int _upd(SeriesInfo s) =>
    s.updated?.millisecondsSinceEpoch ?? 0;

/// Kumpulan genre dari series yg disuka (riwayat/bookmark).
/// keys = "src:label" (atau label polos = kp).
Set<String> genresOf(List<SeriesInfo> all, Iterable<String> keys) {
  final want = <String>{};
  for (final k in keys) {
    final i = k.indexOf(':');
    want.add(i < 0 ? 'kp:$k' : k);
  }
  final out = <String>{};
  for (final s in all) {
    if (want.contains('${s.src}:${s.label}')) {
      out.addAll(s.genres.map((g) => g.toLowerCase()));
    }
  }
  return out;
}

/// Rekomendasi: skor = jumlah genre cocok. Seri = update terbaru.
/// exclude = "src:label" (label polos dianggap kp).
List<SeriesInfo> recommend(
  List<SeriesInfo> all, {
  Set<String> likedGenres = const {},
  Set<String> exclude = const {},
  int limit = 10,
}) {
  final ex = <String>{};
  for (final k in exclude) {
    ex.add(k.contains(':') ? k : 'kp:$k');
  }
  final c = all
      .where((s) =>
          s.label.isNotEmpty && !ex.contains('${s.src}:${s.label}'))
      .toList();
  int score(SeriesInfo s) {
    if (likedGenres.isEmpty) return 0;
    var n = 0;
    for (final g in s.genres) {
      if (likedGenres.contains(g.toLowerCase())) n++;
    }
    return n;
  }

  c.sort((a, b) {
    final d = score(b) - score(a);
    return d != 0 ? d : _upd(b).compareTo(_upd(a));
  });
  return c.take(limit).toList();
}
