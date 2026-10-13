// Self-check Fase 1: scraper Komikpedia vs situs live.
// Run: dart run tool/verify_scraper.dart
import 'package:nixxtoon/src/sources/komikpedia_source.dart';
import 'package:nixxtoon/src/sources/series_index.dart';

void check(bool ok, String msg) {
  if (!ok) throw StateError('GAGAL: $msg');
  print('ok: $msg');
}

Future<void> main() async {
  final src = KomikpediaSource();

  final recent = await src.recentChapters();
  check(recent.isNotEmpty, 'recent ${recent.length} chapter');
  print('  latest: ${recent.first.series} - ${recent.first.title}');
  check(recent.first.url.startsWith('https://'), 'recent url absolut');

  final found = await src.searchSeries('lookism');
  check(found.isNotEmpty, 'search lookism ketemu ${found.length}');
  final lookism = found.firstWhere((s) => s.label == 'Lookism');
  check(lookism.cover.isNotEmpty, 'cover: ${lookism.cover}');
  check(lookism.synopsis.length > 60, 'sinopsis ${lookism.synopsis.length} char');
  check(lookism.status == 'Ongoing', 'status ${lookism.status}');

  final list = await src.chapterList('Lookism');
  check(list.length >= 10, 'chapter list ${list.length}');
  check(list.first.number >= 628, 'terbaru ${list.first.title}');
  final desc = list.first.number >= list.last.number;
  check(desc, 'urut desc ${list.first.title} .. ${list.last.title}');

  final pages = await src.chapterPages(list.first);
  check(pages.images.length >= 5, 'pages ${pages.images.length} gambar');
  check(
    pages.images.every((p) =>
        p.url.contains('blogger.googleusercontent.com') &&
        p.url.contains('/s1080/')),
    'semua gambar varian s1080 (hemat)',
  );
  check(pages.images.every((p) => (p.aspect ?? 0) > 0), 'semua punya rasio');
  print('  sample: ${pages.images.first.url.substring(0, 100)}...');

  final all = await src.allSeries();
  check(all.length >= 10, 'indeks series ${all.length}');
  check(all.every((s) => s.label.isNotEmpty), 'semua berlabel');
  check(all.where((s) => s.cover.isNotEmpty).length >= all.length ~/ 2,
      'mayoritas bercover');
  final pop = popularOf(all);
  check(pop.isNotEmpty && pop.first.label == 'Lookism',
      'populer #1 ${pop.isEmpty ? '-' : pop.first.title}');
  final baru = newestOf(all, 5);
  check(baru.length == 5, 'baru 5 series');
  final rec = recommend(all,
      likedGenres: {'action', 'supernatural'}, exclude: {'Lookism'});
  check(rec.isNotEmpty && rec.every((s) => s.label != 'Lookism'),
      'rekomendasi ${rec.length} tanpa Lookism');

  print('\nSEMUA CEK LOLOS');
}
