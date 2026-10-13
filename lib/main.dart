import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/sources/komik_source.dart';
import 'src/sources/komikpedia_source.dart';
import 'src/sources/komikstation_source.dart';
import 'src/sources/komiku_source.dart';
import 'src/sources/multi_source.dart';
import 'src/store/downloader.dart';
import 'src/store/library_store.dart';
import 'src/theme.dart';
import 'src/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LibraryStore();
  await store.load();
  final KomikSource source = MultiSource({
    'kp': KomikpediaSource(),
    'ks': KomikStationSource(),
    'km': KomikuSource(),
  }, store);
  (source as MultiSource).syncSettings();
  final dl = DownloadCenter(source, store);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(NixxToonApp(source: source, store: store, dl: dl));
}

class NixxToonApp extends StatelessWidget {
  final KomikSource source;
  final LibraryStore store;
  final DownloadCenter dl;
  const NixxToonApp(
      {super.key, required this.source, required this.store, required this.dl});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NixxToon',
      debugShowCheckedModeBanner: false,
      theme: NixxTheme.dark(),
      home: HomeScreen(source: source, store: store, dl: dl),
    );
  }
}
