// Waktu relatif Bahasa Indonesia. Pure Dart.
String timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final d = DateTime.now().difference(dt.toLocal());
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  if (d.inDays == 1) return 'kemarin';
  if (d.inDays < 30) return '${d.inDays} hari lalu';
  final m = (d.inDays / 30).floor();
  if (m < 12) return '$m bln lalu';
  return '${(m / 12).floor()} thn lalu';
}
