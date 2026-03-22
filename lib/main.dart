import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'pages/home_page.dart';

/// Einstiegspunkt der Belegscanner-App.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lokalisierungsdaten für Deutsch initialisieren
  await initializeDateFormatting('de_DE');

  runApp(const BelegscannerApp());
}

/// Root-Widget der App mit Material 3 Theme.
class BelegscannerApp extends StatelessWidget {
  const BelegscannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Belegscanner',
      debugShowCheckedModeBanner: false,
      // Material 3 aktivieren
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}
