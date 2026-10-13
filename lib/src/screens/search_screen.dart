import 'package:flutter/material.dart';

import '../models/comic_models.dart';
import '../sources/komik_source.dart';
import '../sources/multi_source.dart';
import '../sources/series_index.dart';
import '../store/library_store.dart';
import '../theme.dart';
import '../widgets/cover.dart';

// Jelajah: cari lokal di atas indeks + genre + Baru + Rekomendasi + Semua.
// Tanpa query feed — hasil selalu lengkap & bisa offline.
class SearchScreen extends StatefulWidget {
  final KomikSource source;
  final LibraryStore store;
  final void Function(SeriesInfo) onPick;
  const SearchScreen(
      {super.key, required this.source, required this.store, required this.onPick});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  String? _genre;
  Future<void>? _index;

  @override
  void initState() {
    super.initState();
    final mix = widget.source as MultiSource;
    if (!widget.store.hasSeriesIndex) {
      _index = mix.refreshIndex();
    }
    // KM berat (158 hlm) hanya dari sini, background + banner progres.
    if (widget.store.cachedSeriesOf('km').isEmpty) {
      mix.refreshIndex(full: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<SeriesInfo> get _all => widget.store.cachedSeries();

  List<String> get _genres {
    final g = <String>{};
    for (final s in _all) {
      g.addAll(s.genres);
    }
    final l = g.toList()..sort();
    return l;
  }

  List<SeriesInfo> _filtered() {
    var list = _all;
    if (_genre != null) {
      final gl = _genre!.toLowerCase();
      list = list
          .where((s) => s.genres.any((g) => g.toLowerCase() == gl))
          .toList();
    }
    final q = _q.trim();
    if (q.isEmpty) return list;
    final starts = <SeriesInfo>[];
    final contains = <SeriesInfo>[];
    for (final s in list) {
      switch (matchTitle(s.title, q)) {
        case 2:
          starts.add(s);
        case 1:
          contains.add(s);
      }
    }
    return [...starts, ...contains];
  }

  List<SeriesInfo> _rekomendasi() {
    final seen = <String>{
      for (final h in widget.store.history) (h['series'] as String? ?? ''),
      for (final b in widget.store.bookmarks) '${b.src}:${b.label}',
    }..remove('');
    final liked = genresOf(_all, seen);
    return recommend(_all, likedGenres: liked, exclude: seen, limit: 10);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _q = v),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Cari judul…',
            hintStyle: TextStyle(color: NixxTheme.textDim),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_q.isNotEmpty || _genre != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() {
                _ctrl.clear();
                _q = '';
                _genre = null;
              }),
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (_, __) {
          if (_index != null && !widget.store.hasSeriesIndex) {
            return FutureBuilder(
              future: _index,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: NixxTheme.accent));
                }
                if (snap.hasError) {
                  return const Center(
                      child: Text('Gagal memuat indeks.',
                          style: TextStyle(color: NixxTheme.textDim)));
                }
                return _body();
              },
            );
          }
          return _body();
        },
      ),
    );
  }

  Widget _body() {
    final browsing = _q.trim().isEmpty && _genre == null;
    if (!browsing) return _grid(_filtered(), emptyMsg: 'Tidak ketemu.');
    final baru = newestOf(_all, 10);
    final rek = _rekomendasi();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _indexBanner(),
        _genreChips(),
        _rail('Baru Ditambahkan', baru),
        _rail('Rekomendasi Untukmu', rek, subtitle: _rekSubtitle()),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Semua Series',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        _grid(_all, shrink: true),
      ],
    );
  }

  // Banner progres crawl indeks Komiku (background, bisa dipakai sambil jalan).
  Widget _indexBanner() {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final st = widget.store.indexStatus;
        if (!st.startsWith('km:')) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: NixxTheme.surface2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: NixxTheme.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Menyiapkan indeks Komiku… hlm $st'.replaceFirst('km:', ''),
                    style: const TextStyle(
                        fontSize: 12, color: NixxTheme.textDim)),
              ),
            ],
          ),
        );
      },
    );
  }

  String? _rekSubtitle() {
    if (widget.store.history.isEmpty && widget.store.bookmarks.isEmpty) {
      return null;
    }
    final last = widget.store.history.isNotEmpty
        ? widget.store.history.first['seriesTitle'] as String? ?? ''
        : widget.store.bookmarks.first.title;
    return last.isEmpty ? null : 'Karena kamu baca $last';
  }

  Widget _genreChips() {
    final genres = _genres;
    if (genres.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final g = genres[i];
          final sel = _genre == g;
          return ChoiceChip(
            label: Text(g, style: const TextStyle(fontSize: 12)),
            selected: sel,
            selectedColor: NixxTheme.accent,
            backgroundColor: NixxTheme.surface2,
            labelStyle: TextStyle(
                color: sel ? Colors.black : Colors.white,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400),
            onSelected: (_) => setState(() => _genre = sel ? null : g),
          );
        },
      ),
    );
  }

  Widget _rail(String title, List<SeriesInfo> items, {String? subtitle}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: NixxTheme.textDim)),
            ],
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _coverCell(items[i]),
          ),
        ),
      ],
    );
  }

  Widget _coverCell(SeriesInfo s) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        widget.onPick(s);
      },
      child: SizedBox(
        width: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverThumb(url: s.cover, width: 104, fallback: s.title),
            const SizedBox(height: 6),
            Text(s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            Text(s.status,
                style:
                    const TextStyle(fontSize: 11, color: NixxTheme.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<SeriesInfo> items,
      {bool shrink = false, String emptyMsg = 'Belum ada series.'}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(emptyMsg,
              style: const TextStyle(color: NixxTheme.textDim)),
        ),
      );
    }
    final grid = GridView.builder(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 3 / 4.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _coverCell(items[i]),
    );
    return grid;
  }
}
