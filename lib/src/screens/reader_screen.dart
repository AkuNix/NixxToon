import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/comic_models.dart';
import '../sources/komik_source.dart';
import '../store/library_store.dart';
import '../theme.dart';

// Reader long-strip vertikal, ala versi pertama (mulus):
// decode natural, tanpa preload, tanpa split, tanpa kerja background.
// Anti-lompat dipertahankan: AspectRatio + guard _busy + jumpTo pasca-layout.
class ReaderScreen extends StatefulWidget {
  final KomikSource source;
  final LibraryStore store;
  final String seriesSrc;
  final String seriesLabel;
  final String seriesTitle;
  final String cover;
  final List<ChapterRef> chapters; // desc: index 0 = terbaru
  final int initialIndex;
  final List<PageImage>? localPages; // offline, null = online
  const ReaderScreen({
    super.key,
    required this.source,
    required this.store,
    required this.seriesSrc,
    required this.seriesLabel,
    required this.seriesTitle,
    required this.cover,
    required this.chapters,
    required this.initialIndex,
    this.localPages,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _index = widget.initialIndex;
  final _netCache = <int, Future<List<PageImage>>>{};
  final _localCache = <int, List<PageImage>?>{};
  final _itemCtrl = ItemScrollController();
  final _posListener = ItemPositionsListener.create();
  final _visibleN = ValueNotifier<int>(0);
  bool _chrome = true;
  bool _busy = false;
  int _total = 0;

  // Setting dibaca sekali: perubahan berlaku saat buka chapter berikut.
  late final String _bgKey = widget.store.readerBg;
  late final bool _showNum = widget.store.showPageNum;

  ChapterRef get _chapter => widget.chapters[_index];

  Color get _bg => switch (_bgKey) {
        'white' => Colors.white,
        'gray' => const Color(0xFF2B2B2B),
        _ => Colors.black,
      };

  Color get _ph => switch (_bgKey) {
        'white' => const Color(0xFFE5E5E5),
        'gray' => const Color(0xFF3A3A3A),
        _ => const Color(0xFF0F0F1A),
      };

  @override
  void initState() {
    super.initState();
    _posListener.itemPositions.addListener(_onPos);
    _localCache[widget.initialIndex] = widget.localPages;
    if (widget.localPages != null) _total = widget.localPages!.length;
    if (widget.store.fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (widget.store.keepScreenOn) WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter(_index));
  }

  @override
  void dispose() {
    _posListener.itemPositions.removeListener(_onPos);
    _visibleN.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
  }

  void _onPos() {
    final pos = _posListener.itemPositions.value;
    if (pos.isEmpty) return;
    final first = pos.map((e) => e.index).reduce((a, b) => a < b ? a : b);
    widget.store.setProgress(_chapter.url, first);
    _visibleN.value = first; // tanpa setState
  }

  Future<List<PageImage>> _netPages(int i) => _netCache.putIfAbsent(
        i,
        () async {
          final p = await widget.source.chapterPages(widget.chapters[i]);
          return p.images;
        },
      );

  Future<void> _enter(int i) async {
    if (_busy) return; // cegah _enter ganda
    _busy = true;
    _index = i;
    final start = widget.store.progressOf(_chapter.url);
    _total = 0;
    _visibleN.value = start;
    setState(() {});
    await widget.store.recordHistory(
      src: widget.seriesSrc,
      series: widget.seriesLabel,
      seriesTitle: widget.seriesTitle,
      cover: widget.cover,
      chapter: _chapter,
    );
    // Offline dulu: file lokal kalau chapter ini terdownload.
    _localCache[i] ??= await widget.store.localPages(_chapter.url);
    final local = _localCache[i];
    if (!mounted) {
      _busy = false;
      return;
    }
    if (widget.chapters[_index].url != _chapter.url) {
      _busy = false;
      return;
    }
    if (local != null) {
      setState(() => _total = local.length);
      _jump(start, local.length);
      _busy = false;
      return;
    }
    try {
      final pages = await _netPages(i);
      if (!mounted || widget.chapters[_index].url != _chapter.url) {
        _busy = false;
        return;
      }
      setState(() => _total = pages.length);
      _jump(start, pages.length);
    } catch (_) {
      if (mounted) setState(() {});
    }
    _busy = false;
  }

  // Lompat hanya jika start>0, selalu pasca-layout.
  void _jump(int start, int total) {
    if (start <= 0 || total <= 0) return;
    final target = start.clamp(0, total - 1).toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _itemCtrl.jumpTo(index: target);
    });
  }

  void _go(int next) {
    if (_busy || next < 0 || next >= widget.chapters.length) return;
    _enter(next);
  }

  @override
  Widget build(BuildContext context) {
    final local = _localCache[_index];
    return Scaffold(
      backgroundColor: _bg,
      body: GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: Stack(
          children: [
            _ReaderBody(
              local: local,
              ph: _ph,
              netFuture: local != null ? null : _netPages(_index),
              itemCtrl: _itemCtrl,
              posListener: _posListener,
              onRetry: () {
                _netCache.remove(_index);
                _enter(_index);
              },
            ),
            if (_chrome) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppBar(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  title: Text('${widget.seriesTitle} • ${_chapter.title}',
                      style: const TextStyle(fontSize: 15)),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black54,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Chapter sebelumnya',
                        onPressed: (!_busy &&
                                _index + 1 < widget.chapters.length)
                            ? () => _go(_index + 1)
                            : null,
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white),
                      ),
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _visibleN,
                          builder: (_, v, __) => Text(
                            (_total == 0 || !_showNum)
                                ? _chapter.title
                                : '${v + 1} / $_total',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Chapter berikutnya',
                        onPressed: (!_busy && _index - 1 >= 0)
                            ? () => _go(_index - 1)
                            : null,
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Satu list untuk lokal & network. Decode natural (tajam, tanpa upscale),
// tiap item AspectRatio final bila rasio diketahui.
class _ReaderBody extends StatelessWidget {
  final List<PageImage>? local;
  final Color ph;
  final Future<List<PageImage>>? netFuture;
  final ItemScrollController itemCtrl;
  final ItemPositionsListener posListener;
  final VoidCallback onRetry;
  const _ReaderBody({
    required this.local,
    required this.ph,
    required this.netFuture,
    required this.itemCtrl,
    required this.posListener,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final files = local;
    if (files != null) {
      return _list(files, (p) {
        final img = Image.file(
          File(p.url),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: ph,
            alignment: Alignment.center,
            child:
                const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        );
        final a = p.aspect;
        if (a == null) return img;
        return AspectRatio(aspectRatio: a, child: img);
      });
    }
    return FutureBuilder<List<PageImage>>(
      future: netFuture,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: NixxTheme.accent));
        }
        if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Gambar gagal dimuat.',
                    style: TextStyle(color: Colors.grey)),
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
        final imgs = snap.data!;
        return _list(imgs, (p) {
          final img = _NetImage(page: p, ph: ph);
          final a = p.aspect;
          if (a == null) return img;
          return AspectRatio(aspectRatio: a, child: img);
        });
      },
    );
  }

  Widget _list(List<PageImage> pages, Widget Function(PageImage) item) {
    return ScrollablePositionedList.builder(
      itemCount: pages.length,
      itemScrollController: itemCtrl,
      itemPositionsListener: posListener,
      itemBuilder: (_, i) => item(pages[i]),
    );
  }
}

// Gambar network sekali-coba-cadangan (host Komiku ganda).
class _NetImage extends StatefulWidget {
  final PageImage page;
  final Color ph;
  const _NetImage({required this.page, required this.ph});

  @override
  State<_NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<_NetImage> {
  bool _fb = false;

  @override
  Widget build(BuildContext context) {
    final fb = widget.page.fallbackUrl;
    final url = (_fb && fb != null) ? fb : widget.page.url;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => Container(color: widget.ph),
      errorWidget: (_, __, ___) {
        if (!_fb && fb != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _fb = true);
          });
          return Container(color: widget.ph);
        }
        return Container(
          color: widget.ph,
          alignment: Alignment.center,
          child:
              const Icon(Icons.broken_image_outlined, color: Colors.grey),
        );
      },
    );
  }
}
