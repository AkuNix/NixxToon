import 'dart:ui';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/comic_models.dart';
import '../sources/komik_source.dart';
import '../store/downloader.dart';
import '../store/library_store.dart';
import '../theme.dart';
import '../utils/timeago.dart';
import '../widgets/cover.dart';
import 'reader_screen.dart';

// Kiri cover kecil, kanan metadata. Bukan hero centered.
class DetailScreen extends StatefulWidget {
  final KomikSource source;
  final LibraryStore store;
  final DownloadCenter dl;
  final SeriesInfo series;
  const DetailScreen(
      {super.key,
      required this.source,
      required this.store,
      required this.dl,
      required this.series});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final Future<({SeriesInfo info, List<ChapterRef> chapters})> _data =
      _load();

  Future<({SeriesInfo info, List<ChapterRef> chapters})> _load() async {
    final info = widget.series.cover.isEmpty
        ? await widget.source
            .seriesDetail(widget.series.label, src: widget.series.src)
        : widget.series;
    final chapters =
        await widget.source.chapterList(info.label, src: info.src);
    if (chapters.isNotEmpty) {
      await widget.store
          .setLatestSeen(info.src, info.label, chapters.first.number);
    }
    return (info: info, chapters: chapters);
  }

  bool _opening = false; // F3: cegah double-push route reader

  void _openReader(SeriesInfo info, List<ChapterRef> chapters, int index) async {
    if (_opening) return;
    _opening = true;
    try {
      final c = chapters[index];
      if (widget.store.autoDownload &&
          !widget.store.isDownloaded(c.url) &&
          !widget.dl.running.containsKey(c.url)) {
        // F4 kenyamanan: unduh chapter BERIKUTNYA, bukan yg sedang dibuka
        // (hindari konten CPU/disk saat gambarnya didecode untuk dibaca).
        final next = index - 1 >= 0
            ? chapters[index - 1]
            : (index + 1 < chapters.length ? chapters[index + 1] : null);
        if (next != null &&
            !widget.store.isDownloaded(next.url) &&
            !widget.dl.running.containsKey(next.url)) {
          widget.dl.downloadChapter(next);
        }
      }
      final local = await widget.store.localPages(c.url);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            source: widget.source,
            store: widget.store,
            seriesSrc: info.src,
            seriesLabel: info.label,
            seriesTitle: info.title,
            cover: info.cover,
            chapters: chapters,
            initialIndex: index,
            localPages: local,
          ),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.title)),
      body: FutureBuilder<({SeriesInfo info, List<ChapterRef> chapters})>(
        future: _data,
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: NixxTheme.accent));
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Gagal memuat. Situs mungkin berubah.',
                      style: TextStyle(color: NixxTheme.textDim)),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: NixxTheme.accent,
                        foregroundColor: Colors.black),
                    onPressed: () => setState(() {}),
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            );
          }
          final info = snap.data!.info;
          final chapters = snap.data!.chapters;
          return Column(
            children: [
              _header(info, chapters),
              const Divider(height: 1, color: NixxTheme.surface2),
              Expanded(
                child: chapters.isEmpty
                    ? const Center(
                        child: Text('Belum ada chapter.',
                            style: TextStyle(color: NixxTheme.textDim)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: chapters.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, color: NixxTheme.surface2),
                        itemBuilder: (_, i) {
                          final c = chapters[i];
                          return ListTile(
                            dense: true,
                            title: Text(c.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(timeAgo(c.published),
                                style: const TextStyle(
                                    color: NixxTheme.textDim, fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _DlButton(
                                  dl: widget.dl,
                                  store: widget.store,
                                  seriesLabel: info.label,
                                  chapter: c,
                                ),
                                const Icon(Icons.chevron_right,
                                    color: NixxTheme.textDim),
                              ],
                            ),
                            onTap: () => _openReader(info, chapters, i),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(SeriesInfo info, List<ChapterRef> chapters) {
    return Stack(
      children: [
        if (info.cover.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter:
                  ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: CachedNetworkImage(
                imageUrl: info.cover,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  NixxTheme.bg.withValues(alpha: 0.55),
                  NixxTheme.bg.withValues(alpha: 0.94),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverThumb(
                  url: info.cover,
                  width: 104,
                  fallback: info.title,
                  heroTag: 'cover-${info.src}-${info.label}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${info.type} â€¢ ${info.status} â€¢ ${chapters.length} ch',
                    style: const TextStyle(
                        color: NixxTheme.textDim, fontSize: 12)),
                if (info.genres.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in info.genres.take(5))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: NixxTheme.surface2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(g,
                              style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (chapters.isNotEmpty)
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: NixxTheme.accent,
                              foregroundColor: Colors.black),
                          onPressed: () => _openReader(info, chapters, 0),
                          child: Text('Lanjut ${chapters.first.title}'),
                        ),
                      ),
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: widget.store,
                      builder: (_, __) {
                        final marked = widget.store
                            .isBookmarked(info.src, info.label);
                        final icon = marked ? Icons.bookmark : Icons.bookmark_outline;
                        final tint = marked ? NixxTheme.accent : Colors.white;
                        return IconButton.outlined(
                          onPressed: () =>
                              widget.store.toggleBookmark(info),
                          icon: Icon(icon, color: tint),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ],
);
  }
}

// Status download per chapter: unduh / berjalan / selesai / gagal.
class _DlButton extends StatelessWidget {
  final DownloadCenter dl;
  final LibraryStore store;
  final String seriesLabel;
  final ChapterRef chapter;
  const _DlButton(
      {required this.dl,
      required this.store,
      required this.seriesLabel,
      required this.chapter});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([dl, store]),
      builder: (_, __) {
        if (store.isDownloaded(chapter.url)) {
          return IconButton(
            tooltip: 'Tersimpan offline â€” ketuk lama untuk hapus',
            icon: const Icon(Icons.download_done,
                color: NixxTheme.accent, size: 20),
            onPressed: () {},
            onLongPress: () async {
              await store.removeDownload(chapter.url);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${chapter.title} dihapus')),
                );
              }
            },
          );
        }
        final p = dl.running[chapter.url];
        if (p != null) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  value: p <= 0 ? null : p,
                  strokeWidth: 2,
                  color: NixxTheme.accent),
            ),
          );
        }
        if (dl.failed.containsKey(chapter.url)) {
          return IconButton(
            tooltip: 'Gagal â€” ketuk untuk coba lagi',
            icon: const Icon(Icons.error_outline,
                color: Colors.redAccent, size: 20),
            onPressed: () =>
                dl.downloadChapter(chapter),
          );
        }
        return IconButton(
          tooltip: 'Download offline',
          icon: const Icon(Icons.download_outlined,
              color: NixxTheme.textDim, size: 20),
          onPressed: () => dl.downloadChapter(chapter),
        );
      },
    );
  }
}
