import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:nixxtoon/src/models/comic_models.dart';
import 'package:nixxtoon/src/sources/komikpedia_source.dart';
import 'package:nixxtoon/src/sources/komikstation_source.dart';
import 'package:nixxtoon/src/sources/komiku_source.dart';
import 'package:nixxtoon/src/sources/series_index.dart';
import 'package:nixxtoon/src/utils/timeago.dart';

SeriesInfo _s(String label, List<String> genres, [int year = 2026]) =>
    SeriesInfo(
      label: label,
      title: label,
      cover: '',
      status: 'Ongoing',
      type: 'Manhwa',
      genres: genres,
      synopsis: '',
      projectUrl: '',
      updated: DateTime(year),
    );

void main() {
  test('chapterNumber parse judul chapter', () {
    expect(KomikpediaSource.chapterNumber('Chapter 628.2'), 628.2);
    expect(KomikpediaSource.chapterNumber('Chapter 604'), 604.0);
    expect(KomikpediaSource.chapterNumber('Lookism'), -1);
  });

  test('upscale thumb Blogger s72-c ke s400', () {
    const inUrl =
        'https://blogger.googleusercontent.com/img/b/R29vZ2xl/ABC/s72-c/x.webp';
    expect(KomikpediaSource.upscale(inUrl), contains('/s400/'));
  });

  test('timeAgo Indonesia', () {
    final now = DateTime.now();
    expect(timeAgo(now.subtract(const Duration(minutes: 5))), '5 mnt lalu');
    expect(timeAgo(now.subtract(const Duration(hours: 4))), '4 jam lalu');
    expect(timeAgo(now.subtract(const Duration(days: 1))), 'kemarin');
    expect(timeAgo(null), '');
  });

  test('rekomendasi: skor genre, exclude jalan', () {
    final all = [
      _s('Lookism', ['Action', 'Supernatural']),
      _s('Eleceed', ['Action', 'Supernatural']),
      _s('RomanceX', ['Romance']),
    ];
    final rec = recommend(all,
        likedGenres: {'action', 'supernatural'}, exclude: {'Lookism'});
    expect(rec.first.label, 'Eleceed');
    expect(rec.any((s) => s.label == 'Lookism'), false);
  });

  test('rekomendasi kosong tanpa riwayat: urut update', () {
    final all = [_s('A', ['X'], 2024), _s('B', ['Y'], 2026)];
    final rec = recommend(all);
    expect(rec.first.label, 'B');
  });

  test('newestOf urut terbit desc', () {
    final all = [_s('A', [], 2024), _s('B', [], 2026), _s('C', [], 2025)];
    expect(newestOf(all, 3).map((s) => s.label), ['B', 'C', 'A']);
  });

  test('popularOf cocok judul + Lookism #1', () {
    final all = [_s('Eleceed', []), _s('Lookism', [])];
    final pop = popularOf(all);
    expect(pop.first.label, 'Lookism');
  });

  test('pageOf: rasio dari data-original', () {
    final doc = html_parser.parse(
        '<img src="https://blogger.googleusercontent.com/img/x/s16000/1.png" data-original-width="800" data-original-height="2310">');
    final p = KomikpediaSource.pageOf(doc.querySelector('img')!);
    expect(p, isNotNull);
    expect(p!.aspect, closeTo(800 / 2310, 0.001));
  });

  test('pageOf: tanpa dimensi -> aspect null (tinggi natural)', () {
    final doc = html_parser.parse(
        '<img src="https://blogger.googleusercontent.com/img/x/s16000/1.png">'
        '<img src="https://ads.example.com/a.jpg" data-original-width="10" data-original-height="10">');
    final imgs = doc.querySelectorAll('img');
    expect(KomikpediaSource.pageOf(imgs[0])!.aspect, isNull);
    expect(KomikpediaSource.pageOf(imgs[1]), isNull);
  });

  test('PageImage cache round-trip', () {
    const p = PageImage(url: 'u', aspect: 0.5);
    final back = PageImage.fromCache(p.toCache());
    expect(back.url, 'u');
    expect(back.aspect, 0.5);
  });

  test('prettifySlug + buang prefix angka', () {
    expect(prettifySlug('solo-max-level-newbie'), 'Solo Max Level Newbie');
    expect(prettifySlug('131241-solo-max-level-newbie'),
        'Solo Max Level Newbie');
    expect(prettifySlug('lookism'), 'Lookism');
  });

  test('idDate bulan Indonesia', () {
    expect(idDate('Oktober 9, 2026'), DateTime(2026, 10, 9));
    expect(idDate('Januari 1, 2025'), DateTime(2025, 1, 1));
    expect(idDate('ngawur'), isNull);
  });

  test('idRelative Komiku', () {
    final now = DateTime.now();
    expect(
        idRelative('10 menit lalu')!
            .difference(now)
            .inMinutes
            .abs(),
        lessThanOrEqualTo(11));
    expect(idRelative('2 jam lalu')!.hour, now.subtract(const Duration(hours: 2)).hour);
    expect(idRelative('kemarin')!.day, now.subtract(const Duration(days: 1)).day);
    expect(idRelative('???'), isNull);
  });

  test('ksNumber + kmNumber dari slug chapter', () {
    expect(KomikStationSource.ksNumber('/tokyo-x-chapter-278-4/'), 278.4);
    expect(KomikStationSource.ksNumber('/lookism-chapter-628/'), 628.0);
    expect(KomikuSource.kmNumber('/solo-max-level-newbie-chapter-280/'), 280.0);
    expect(KomikuSource.kmNumber('/x-chapter-7-2/'), 7.2);
  });

  test('matchTitle abaikan tanda baca', () {
    expect(matchTitle('Solo Max-Level Newbie', 'solo max level newbie'), 2);
    expect(matchTitle('Lookism', 'look'), 2);
    expect(matchTitle('Eleceed', 'look'), 0);
  });

  test('resized: segmen ukuran Blogger diganti', () {
    const u = 'https://x/img/b/A/s16000/01.png';
    expect(KomikpediaSource.resized(u, 's1080'),
        'https://x/img/b/A/s1080/01.png');
    expect(KomikpediaSource.resized(u, 'asli'), u);
    const w = 'https://x/img/b/A/w1200-h300-p/01.png';
    expect(KomikpediaSource.resized(w, 's720'),
        'https://x/img/b/A/s720/01.png');
    expect(KomikpediaSource.resized('https://x/a.png', 's1080'),
        'https://x/a.png');
  });
}
