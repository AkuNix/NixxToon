import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/comic_models.dart';
import '../sources/komik_source.dart';
import '../sources/multi_source.dart';
import '../sources/series_index.dart';
import '../store/downloader.dart';
import '../store/library_store.dart';
import '../theme.dart';
import '../utils/timeago.dart';
import '../widgets/brand.dart';
import '../widgets/cover.dart';
import 'detail_screen.dart';
import 'reader_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

// 3 tab: Beranda / Perpus / Riwayat. Tanpa menu lain.
// SeriesInfo minimal dari key "src:label" (data lama polos = kp).
SeriesInfo _minimal(String key, {String title = '', String cover = ''}) {
  final (src, label) = splitKey(key);
  return SeriesInfo(
    src: src,
    label: label,
    title: title.isEmpty ? label : title,
    cover: cover,
    status: '',
    type: '',
    genres: const [],
    synopsis: '',
    projectUrl: '',
    updated: null,
  );
}

class HomeScreen extends StatefulWidget {
  final KomikSource source;
  final LibraryStore store;
  final DownloadCenter dl;
  const HomeScreen(
      {super.key, required this.source, required this.store, required this.dl});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  Future<List<ChapterRef>>? _recent;
  Future<void>? _index;
  Future<List<SeriesInfo>>? _popular;

  @override
  void initState() {
    super.initState();
    if (widget.store.autoCheckUpdate) _refreshAll();
  }

  MultiSource get _mix => widget.source as MultiSource;

  void _refreshAll() {
    _recent = widget.source.recentChapters();
    _popular = _mix.refreshPopular().catchError((_) => <SeriesInfo>[]);
    // Ringan saja (KP+KS). KM berat hanya dari Jelajah bila perlu.
    _index = _mix.refreshIndex();
    setState(() {});
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          source: widget.source,
          store: widget.store,
          onPick: _openDetail,
        ),
      ),
    );
  }

  void _openDetail(SeriesInfo s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          source: widget.source,
          store: widget.store,
          dl: widget.dl,
          series: s,
        ),
      ),
    ).then((_) => setState(() {})); // refresh badge/riwayat sekembalinya
  }

  @override
  Widget build(BuildContext context) {
    // Dorong setting kualitas ke adapter (idempoten, murah).
    _mix.syncSettings();
    return Scaffold(
      appBar: AppBar(
        title: const NixxWordmark(),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  store: widget.store,
                  dl: widget.dl,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
        ],
      ),
      body: switch (_tab) {
        0 => _beranda(),
        1 => _perpus(),
        2 => _riwayat(),
        _ => _offline(),
      },
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Beranda'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_outline), label: 'Perpus'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
          BottomNavigationBarItem(icon: Icon(Icons.download_outlined), label: 'Offline'),
        ],
      ),
    );
  }

  // ---------- Beranda ----------

  // Spotlight: chapter terbaru semua sumber. Backdrop blur + tombol Lanjut.
  Widget _spotlight() {
    if (_recent == null) return const SizedBox.shrink();
    return FutureBuilder<List<ChapterRef>>(
      future: _recent,
      builder: (_, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        final c = items.first;
        final title = widget.store.titleOf(c.src, c.series);
        final cover = widget.store.coverOf(c.src, c.series);
        return GestureDetector(
          onTap: () => _openDetail(
              _minimal('${c.src}:${c.series}', title: title, cover: cover)),
          child: Container(
            height: 210,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            decoration: BoxDecoration(
              color: NixxTheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: cover.isEmpty
                      ? const SizedBox.shrink()
                      : CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: NixxTheme.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('TERBARU',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 6),
                          SrcChip(src: c.src),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('${c.title} • ${timeAgo(c.published)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                      const SizedBox(height: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: NixxTheme.accent,
                            foregroundColor: Colors.black,
                            visualDensity: VisualDensity.compact),
                        onPressed: () => _openDetail(_minimal(
                            '${c.src}:${c.series}',
                            title: title,
                            cover: cover)),
                        child: const Text('Lanjut Baca'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _beranda() {
    if (_recent == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tarik ke bawah untuk memuat update.',
                style: TextStyle(color: NixxTheme.textDim)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: NixxTheme.accent,
                  foregroundColor: Colors.black),
              onPressed: _refreshAll,
              child: const Text('Muat'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: NixxTheme.accent,
      onRefresh: () async {
        _refreshAll();
        await Future.wait([_recent!, _index!, _popular!]);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _spotlight(),
          _continueRail(),
          _popularRail(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Text('Chapter Baru',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: _openSearch,
                  child: const Text('Jelajah ›',
                      style:
                          TextStyle(fontSize: 12, color: NixxTheme.accent)),
                ),
              ],
            ),
          ),
          FutureBuilder<List<ChapterRef>>(
            future: _recent,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _SkeletonRows();
              }
              if (snap.hasError) {
                return _ErrorBox(
                  msg: 'Sumber berubah / offline. Tarik ke bawah untuk coba lagi.',
                  onRetry: _refreshAll,
                );
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) return const _EmptyBox(msg: 'Belum ada update.');
              return Column(
                children: [for (final c in items) _chapterRow(c)],
              );
            },
          ),
        ],
      ),
    );
  }

  // Rail "Populer": ranking bernomor ala Webtoon, gabungan 3 sumber.
  Widget _popularRail() {
    if (_popular == null) return const SizedBox.shrink();
    return FutureBuilder<List<SeriesInfo>>(
      future: _popular,
      builder: (_, snap) {
        final pop = snap.data ?? widget.store.cachedPopular();
        if (pop.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text('Populer',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _openSearch,
                    child: const Text('Lihat Semua ›',
                        style: TextStyle(
                            fontSize: 12, color: NixxTheme.accent)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 224,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: pop.length.clamp(0, 15),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final s = pop[i];
                  return GestureDetector(
                    onTap: () => _openDetail(s),
                    child: SizedBox(
                      width: 120,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              CoverThumb(
                                  url: s.cover,
                                  width: 120,
                                  fallback: s.title,
                                  heroTag: 'cover-${s.src}-${s.label}'),
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: Text('${i + 1}',
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = 2
                                        ..color = i == 0
                                            ? NixxTheme.accent
                                            : Colors.white70,
                                    )),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: SrcChip(src: s.src),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _continueRail() {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final h = widget.store.history;
        if (h.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Lanjut Baca',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: h.length.clamp(0, 10),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final e = h[i];
                  return GestureDetector(
                    onTap: () => _openDetail(_minimal(
                      e['series'] as String? ?? '',
                      title: e['seriesTitle'] as String? ?? '',
                      cover: e['cover'] as String? ?? '',
                    )),
                    child: SizedBox(
                      width: 104,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverThumb(
                              url: e['cover'] as String? ?? '',
                              width: 104,
                              fallback: e['seriesTitle'] as String? ?? ''),
                          const SizedBox(height: 6),
                          Text(e['seriesTitle'] as String? ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(e['chapter'] as String? ?? '',
                              style: const TextStyle(
                                  fontSize: 11, color: NixxTheme.accent)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chapterRow(ChapterRef c) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final title = widget.store.titleOf(c.src, c.series);
        return ListTile(
          dense: true,
          leading: CoverThumb(
              url: widget.store.coverOf(c.src, c.series),
              width: 56,
              fallback: title),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
              '[${c.src.toUpperCase()}] ${c.title} • ${timeAgo(c.published)}',
              style: const TextStyle(color: NixxTheme.textDim, fontSize: 12)),
          trailing:
              const Icon(Icons.chevron_right, color: NixxTheme.textDim),
          onTap: () => _openDetail(_minimal('${c.src}:${c.series}',
              title: title,
              cover: widget.store.coverOf(c.src, c.series))),
        );
      },
    );
  }

  // ---------- Perpus ----------

  Widget _perpus() {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final marks = widget.store.bookmarks;
        if (marks.isEmpty) {
          return const _EmptyBox(
              msg: 'Perpus kosong.\nCari Lookism lalu ketuk bookmark.');
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 3 / 4.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: marks.length,
          itemBuilder: (_, i) => _bookmarkCell(marks[i]),
        );
      },
    );
  }

  Widget _bookmarkCell(SeriesInfo s) {
    return GestureDetector(
      onTap: () => _openDetail(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              CoverThumb(url: s.cover, fallback: s.title),
              Positioned(
                right: 4,
                top: 4,
                child: _NewBadge(
                  source: widget.source,
                  store: widget.store,
                  series: s,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------- Riwayat ----------

  Widget _riwayat() {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final h = widget.store.history;
        if (h.isEmpty) {
          return const _EmptyBox(msg: 'Belum ada riwayat baca.');
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: h.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: NixxTheme.surface2),
          itemBuilder: (_, i) {
            final e = h[i];
            final at = DateTime.tryParse(e['at'] as String? ?? '');
            return ListTile(
              leading: CoverThumb(
                  url: e['cover'] as String? ?? '',
                  width: 44,
                  fallback: e['seriesTitle'] as String? ?? ''),
              title: Text(e['seriesTitle'] as String? ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${e['chapter']} • ${timeAgo(at)}',
                  style: const TextStyle(
                      color: NixxTheme.textDim, fontSize: 12)),
              onTap: () => _openDetail(_minimal(
                e['series'] as String? ?? '',
                title: e['seriesTitle'] as String? ?? '',
                cover: e['cover'] as String? ?? '',
              )),
            );
          },
        );
      },
    );
  }

  // ---------- Offline ----------

  Widget _offline() {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.dl]),
      builder: (_, __) {
        final items = widget.store.downloads;
        final active = widget.dl.running.entries.toList();
        if (items.isEmpty && active.isEmpty) {
          return const _EmptyBox(
              msg: 'Belum ada download.\nKetuk ikon ⬇ di tiap chapter.');
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final e in active)
              ListTile(
                dense: true,
                leading: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: NixxTheme.accent),
                    ),
                  ),
                ),
                title: Text(widget.dl.titleOf(e.key),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    'Mengunduh ${(e.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: NixxTheme.textDim, fontSize: 12)),
              ),
            for (final d in items)
              Builder(builder: (_) {
                final src = d['src'] as String? ?? 'kp';
                final series = d['series'] as String? ?? '';
                final cover = widget.store.coverOf(src, series);
                final title = widget.store.titleOf(src, series);
                return Dismissible(
                  key: ValueKey(d['url']),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.redAccent,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) =>
                      widget.store.removeDownload(d['url'] as String),
                  child: ListTile(
                    dense: true,
                    leading: CoverThumb(
                        url: cover, width: 44, fallback: title),
                    title: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '[${src.toUpperCase()}] ${d['title'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: NixxTheme.textDim, fontSize: 12)),
                    trailing: const Icon(Icons.play_arrow,
                        color: NixxTheme.accent),
                    onTap: () async {
                      final local = await widget.store
                          .localPages(d['url'] as String);
                      if (!context.mounted) return;
                      if (local == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'File tak lengkap. Unduh ulang dari detail.')),
                        );
                        return;
                      }
                      // Langsung reader offline (tanpa network detail).
                      final ch = ChapterRef(
                        src: src,
                        series: series,
                        title: d['title'] as String? ?? '',
                        number: -1,
                        url: d['url'] as String,
                        published: null,
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReaderScreen(
                            source: widget.source,
                            store: widget.store,
                            seriesSrc: src,
                            seriesLabel: series,
                            seriesTitle: title,
                            cover: cover,
                            chapters: [ch],
                            initialIndex: 0,
                            localPages: local,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

// Chip sumber kecil: KP / KS / KM.
class SrcChip extends StatelessWidget {
  final String src;
  const SrcChip({super.key, required this.src});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(src.toUpperCase(),
          style: const TextStyle(
              color: NixxTheme.accent,
              fontSize: 9,
              fontWeight: FontWeight.w800)),
    );
  }
}

// Badge "+N BARU": bandingkan chapter terbaru server vs terakhir dilihat.
class _NewBadge extends StatefulWidget {
  final KomikSource source;
  final LibraryStore store;
  final SeriesInfo series;
  const _NewBadge(
      {required this.source, required this.store, required this.series});

  @override
  State<_NewBadge> createState() => _NewBadgeState();
}

class _NewBadgeState extends State<_NewBadge> {
  late final Future<int> _n = _count();

  Future<int> _count() async {
    try {
      final s = widget.series;
      final list =
          await widget.source.chapterList(s.label, src: s.src);
      if (list.isEmpty) return 0;
      final seen = widget.store.latestSeen(s.src, s.label);
      return list.where((c) => c.number > seen).length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _n,
      builder: (_, snap) {
        final n = snap.data ?? 0;
        if (n <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: NixxTheme.accent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('+$n',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        );
      },
    );
  }
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: NixxTheme.surface,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
      ],
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final String msg;
  const _EmptyBox({required this.msg});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: NixxTheme.textDim)),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _ErrorBox({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: NixxTheme.textDim)),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: NixxTheme.accent,
                foregroundColor: Colors.black),
            onPressed: onRetry,
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}
