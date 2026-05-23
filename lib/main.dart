import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ffi/aegis_library.dart';

void main() {
  // Native: load the DLL. Web: check if WASM bridge is already ready.
  // Both are best-effort — failure silently falls back to the Dart engine.
  AegisLibrary.tryLoad();
  runApp(const ProviderScope(child: AegisApp()));
}

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AEGIS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
