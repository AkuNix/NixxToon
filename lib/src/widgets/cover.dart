import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

// Cover 3:4 via AspectRatio (lebar ikut parent) — tidak pernah infinite.
// Fallback monogram huruf, bukan kotak abu generik.
class CoverThumb extends StatelessWidget {
  final String url;
  final double? width;
  final String fallback;
  final String? heroTag;
  const CoverThumb(
      {super.key, required this.url, this.width, this.fallback = '', this.heroTag});

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    final tag = heroTag;
    final body = SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          decoration: BoxDecoration(
            color: NixxTheme.surface2,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: u.isEmpty
              ? _fallback()
              : CachedNetworkImage(
                  imageUrl: u,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _fallback(ghost: true),
                  errorWidget: (_, __, ___) => _fallback(),
                ),
        ),
      ),
    );
    if (tag == null) return body;
    return Hero(tag: tag, child: body);
  }

  Widget _fallback({bool ghost = false}) {
    final ch = fallback.trim().isEmpty
        ? null
        : fallback.trim().characters.first.toUpperCase();
    if (ch == null) {
      return const Icon(Icons.book_outlined, color: NixxTheme.textDim);
    }
    return Center(
      child: Text(ch,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: ghost
                ? NixxTheme.textDim.withValues(alpha: 0.5)
                : NixxTheme.accent,
          )),
    );
  }
}
