import '../models/comic_models.dart';

// Kontrak 1 sumber. Tambah sumber baru = implement class ini.
// label/series = id LOKAL sumber itu; asal sumber selalu di field `src`.
abstract class KomikSource {
  String get id; // kp | ks | km | mix
  String get name; // nama tampil: Komikpedia, ...

  /// Chapter terbaru lintas series (Beranda). Newest first.
  Future<List<ChapterRef>> recentChapters({int limit = 25});

  /// Cari series by judul. Returns project pages only.
  Future<List<SeriesInfo>> searchSeries(String query);

  /// Detail 1 series (cover, sinopsis, status).
  Future<SeriesInfo> seriesDetail(String label, {String src = 'kp'});

  /// Semua chapter 1 series. Newest first.
  Future<List<ChapterRef>> chapterList(String label, {String src = 'kp'});

  /// URL gambar full-size 1 chapter, urut halaman.
  Future<ChapterPages> chapterPages(ChapterRef chapter);

  /// Semua series (fondasi indeks lokal: cover, search, baru).
  Future<List<SeriesInfo>> allSeries();

  /// Series populer sumber ini (ranking asli situs). Urut rank.
  Future<List<SeriesInfo>> popular();
}
