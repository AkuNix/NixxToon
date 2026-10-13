import 'package:flutter/material.dart';

import '../theme.dart';

// Wordmark NixxToon: N amber + sisanya putih. Satu-satunya identitas teks.
class NixxWordmark extends StatelessWidget {
  final double size;
  const NixxWordmark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w800),
        children: const [
          TextSpan(text: 'N', style: TextStyle(color: NixxTheme.accent)),
          TextSpan(text: 'ixxToon', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
