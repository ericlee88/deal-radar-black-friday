import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/dashboard_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: DealRadarApp(),
    ),
  );
}

class DealRadarApp extends StatelessWidget {
  const DealRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deal Radar — Polymorphic Shopping Mission Engine',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
        colorSchemeSeed: const Color(0xFF0EA5E9),
        scaffoldBackgroundColor: const Color(0xFF090C10),
      ),
      home: const DealDashboardScreen(),
    );
  }
}
