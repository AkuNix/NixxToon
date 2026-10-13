// Self-check multi-sumber. Run: dart run tool/verify_multi.dart [ks|km|all]
import 'package:nixxtoon/src/sources/komikstation_source.dart';
import 'package:nixxtoon/src/sources/komiku_source.dart';

void check(bool ok, String msg) {
  if (!ok) throw StateError('GAGAL: $msg');
  print('ok: $msg');
}

Future<void> ks() async {
  final src = KomikStationSource();
  final pop = await src.popular();
  check(pop.length >= 5, 'ks populer ${pop.length}');
  for (final s in pop.take(3)) {
    print('  POP [${s.label}] t=${s.title.substring(0, s.title.length.clamp(0, 60))} c=${s.cover.substring(0, s.cover.length.clamp(0, 80))}');
  }
  check(pop.first.cover.isNotEmpty, 'ks populer cover: ${pop.first.title}');
  final list = await src.chapterList('lookism');
  check(list.length >= 100, 'ks lookism chapters ${list.length}');
  check(list.first.number >= 628, 'ks terbaru ${list.first.title}');
  check(list.every((c) => c.src == 'ks'), 'ks src flag');
  final pages = await src.chapterPages(list.first);
  check(pages.images.length >= 10, 'ks pages ${pages.images.length}');
  check(
    pages.images.every((p) =>
        p.url.contains('klikcdn') && !p.url.endsWith('.gif')),
    'ks gambar klikcdn non-iklan',
  );
  final recent = await src.recentChapters();
  check(recent.length >= 5, 'ks recent ${recent.length}');
  print('  latest: ${recent.first.series} - ${recent.first.title}');
}

Future<void> km() async {
  final src = KomikuSource();
  final pop = await src.popular();
  check(pop.length >= 5, 'km populer ${pop.length}');
  final recent = await src.recentChapters();
  check(recent.length >= 10, 'km recent ${recent.length}');
  print('  latest: ${recent.first.series} - ${recent.first.title}');
  final found = await src.searchSeries('solo max level newbie');
  check(found.isNotEmpty, 'km search ketemu ${found.length}');
  final slug = found.first.label;
  final list = await src.chapterList(slug);
  check(list.length >= 50, 'km $slug chapters ${list.length}');
  check(list.every((c) => c.src == 'km'), 'km src flag');
  final pages = await src.chapterPages(list.first);
  check(pages.images.length >= 5, 'km pages ${pages.images.length}');
  check(
    pages.images.every((p) =>
        p.url.contains('/upload') && !p.url.contains('promosi')),
    'km gambar upload komiku',
  );
}

Future<void> main(List<String> args) async {
  final which = args.isEmpty ? 'all' : args.first;
  if (which == 'all' || which == 'ks') await ks();
  if (which == 'all' || which == 'km') await km();
  print('\nSEMUA CEK LOLOS');
}
