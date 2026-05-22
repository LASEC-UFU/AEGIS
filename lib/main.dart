import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ffi/aegis_library.dart';

void main() {
  // Attempt to load the C++ native library. Only meaningful on native targets;
  // silently skipped on web (dart:io / DynamicLibrary unavailable there).
  if (!kIsWeb) {
    AegisLibrary.tryLoad();
  }
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
