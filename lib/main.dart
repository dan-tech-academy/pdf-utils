import 'package:flutter/material.dart';

import 'home_screen.dart';

void main() {
  runApp(const PdfUtilsApp());
}

class PdfUtilsApp extends StatelessWidget {
  const PdfUtilsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0D47A1);
    return MaterialApp(
      title: 'PDF Utils',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
