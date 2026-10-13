import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../store/downloader.dart';
import '../store/library_store.dart';
import '../theme.dart';

// Pengaturan ala reader app (Mihon/Webtoon), versi ramping:
// Reader, Download, Data, Perpus, Tentang. Dark-only.
class SettingsScreen extends StatefulWidget {
  final LibraryStore store;
  final DownloadCenter dl;
  const SettingsScreen({super.key, required this.store, required this.dl});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _bytes = '';

  @override
  void initState() {
    super.initState();
    _refreshBytes();
  }

  Future<void> _refreshBytes() async {
    final b = await widget.store.downloadBytes();
    if (!mounted) return;
    setState(() => _bytes = _fmt(b));
  }

  static String _fmt(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<bool> _confirm(String title, String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NixxTheme.surface,
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal',
                style: TextStyle(color: NixxTheme.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: NixxTheme.accent,
                foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: AnimatedBuilder(
        animation: s,
        builder: (_, __) => ListView(
          children: [
            _head('Reader'),
            _segBg(s),
            _segQuality(s),
            SwitchListTile(
              title: const Text('Tampilkan nomor halaman'),
              value: s.showPageNum,
              activeThumbColor: NixxTheme.accent,
              onChanged: (v) => s.setSetting('showPageNum', v),
            ),
            SwitchListTile(
              title: const Text('Layar tetap menyala saat baca'),
              value: s.keepScreenOn,
              activeThumbColor: NixxTheme.accent,
              onChanged: (v) => s.setSetting('keepScreenOn', v),
            ),
            SwitchListTile(
              title: const Text('Mode fullscreen saat baca'),
              subtitle: const Text('Sembunyikan status bar',
                  style: TextStyle(color: NixxTheme.textDim, fontSize: 12)),
              value: s.fullscreen,
              activeThumbColor: NixxTheme.accent,
              onChanged: (v) => s.setSetting('fullscreen', v),
            ),
            _head('Download'),
            SwitchListTile(
              title: const Text('Download hanya via WiFi'),
              value: s.wifiOnly,
              activeThumbColor: NixxTheme.accent,
              onChanged: (v) => s.setSetting('wifiOnly', v),
            ),
            SwitchListTile(
              title: const Text('Auto-download saat baca'),
              subtitle: const Text('Unduh chapter berikutnya di background',
                  style: TextStyle(color: NixxTheme.textDim, fontSize: 12)),
              value: s.autoDownload,
              activeThumbColor: NixxTheme.accent,
              onChanged: (v) => s.setSetting('autoDownload', v),
            ),
            ListTile(
              title: const Text('Hapus semua download'),
              subtitle: Text(_bytes.isEmpty ? '…' : 'Pakai $_bytes',
                  style: const TextStyle(
                      color: NixxTheme.textDim, fontSize: 12)),
              trailing: const Icon(Icons.delete_outline,
                  color: NixxTheme.textDim),
              onTap: () async {
                if (await _confirm('Hapus download?',
                    'Semua chapter offline dihapus dari HP.')) {
                  await s.clearDownloads();
                  _refreshBytes();
                }
              },
            ),
            _head('Data'),
            ListTile(
              title: const Text('Hapus cache gambar'),
              trailing: const Icon(Icons.cleaning_services_outlined,
                  color: NixxTheme.textDim),
              onTap: () async {
                await DefaultCacheManager().emptyCache();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache dibersihkan')),
                  );
                }
              },
            ),
            ListTile(
              title: const Text('Hapus riwayat baca'),
              trailing: const Icon(Icons.history_toggle_off,
                  color: NixxTheme.textDim),
              onTap: () async {
                if (await _confirm(
                    'Hapus riwayat?', 'Rail Lanjut Baca ikut kosong.')) {
                  await s.clearHistory();
                }
              },
            ),
            ListTile(
              title: const Text('Reset semua data'),
              subtitle: const Text('Bookmark, riwayat, setting kembali awal',
                  style: TextStyle(color: NixxTheme.textDim, fontSize: 12)),
              trailing: const Icon(Icons.restart_alt_outlined,
                  color: Colors.redAccent),
              onTap: () async {
                if (await _confirm('Reset total?',
                    'Semua data NixxToon dihapus. Tidak bisa dibatalkan.')) {
                  await s.resetAll();
                  _refreshBytes();
                }
              },
            ),
            _head('Perpus'),
            SwitchListTile(
              title: const Text('Cek update otomatis'),
              subtitle: const Text('Saat aplikasi dibuka',
                  style: TextStyle(color: NixxTheme.textDim, fontSize: 12)),
              value: s.autoCheckUpdate,
              activeThumbColor: NixxTheme.accent,
              onChanged: (v) => s.setSetting('autoCheckUpdate', v),
            ),
            _head('Tentang'),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (_, snap) => ListTile(
                title: const Text('NixxToon'),
                subtitle: Text(
                    'v${snap.data?.version ?? '…'} • Sumber: Komikpedia (mirror)\nBaca versi resmi di Webtoon untuk dukung kreator.',
                    style: const TextStyle(
                        color: NixxTheme.textDim, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t,
            style: const TextStyle(
                color: NixxTheme.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      );

  Widget _segBg(LibraryStore s) {
    const opts = {'black': 'Hitam', 'gray': 'Abu', 'white': 'Putih'};
    return ListTile(
      title: const Text('Background reader'),
      trailing: SegmentedButton<String>(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: NixxTheme.accent,
          selectedForegroundColor: Colors.black,
          visualDensity: VisualDensity.compact,
        ),
        segments: [
          for (final e in opts.entries)
            ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {s.readerBg},
        onSelectionChanged: (v) => s.setSetting('readerBg', v.first),
      ),
    );
  }

  // Kualitas gambar: server kirim sesuai pilihan (hemat kuota + RAM).
  Widget _segQuality(LibraryStore s) {
    const opts = {
      's720': 'Hemat',
      's1080': 'Standar',
      's1600': 'Tajam',
      'asli': 'Asli',
    };
    return ListTile(
      title: const Text('Kualitas gambar'),
      subtitle: const Text('Berlaku mulai chapter berikutnya',
          style: TextStyle(color: NixxTheme.textDim, fontSize: 12)),
      trailing: SegmentedButton<String>(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: NixxTheme.accent,
          selectedForegroundColor: Colors.black,
          visualDensity: VisualDensity.compact,
        ),
        segments: [
          for (final e in opts.entries)
            ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {s.imgQuality},
        onSelectionChanged: (v) => s.setSetting('imgQuality', v.first),
      ),
    );
  }
}
