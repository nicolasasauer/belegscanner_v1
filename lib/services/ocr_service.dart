import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/receipt.dart';

/// Service-Klasse für OCR-Texterkennung und Beleg-Parsing.
///
/// Kapselt die gesamte Logik für:
///   - Bildaufnahme via Kamera
///   - Texterkennung mit Google ML Kit
///   - Parsing des erkannten Textes (Betrag, Artikel)
class OcrService {
  final ImagePicker _picker = ImagePicker();
  final _uuid = const Uuid();

  /// Öffnet die Kamera, nimmt ein Bild auf und erkennt den Text per OCR.
  ///
  /// Gibt einen [Receipt] zurück oder `null`, wenn der Vorgang abgebrochen wurde.
  Future<Receipt?> scanReceipt() async {
    // Kamera öffnen und Foto aufnehmen
    final XFile? imageFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (imageFile == null) {
      // Benutzer hat den Vorgang abgebrochen
      return null;
    }

    return _processImage(imageFile.path);
  }

  /// Verarbeitet ein Bild und erstellt einen [Receipt] aus dem erkannten Text.
  Future<Receipt> _processImage(String imagePath) async {
    // Text via Google ML Kit erkennen
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    final RecognizedText recognizedText;
    try {
      recognizedText = await textRecognizer.processImage(inputImage);
    } finally {
      // Ressourcen freigeben
      await textRecognizer.close();
    }

    final fullText = recognizedText.text;

    // Betrag aus dem erkannten Text extrahieren
    final double totalAmount = _parseAmount(fullText);

    // Einzelzeilen als Artikel-Liste verwenden
    final List<String> items = _parseItems(fullText);

    return Receipt(
      id: _uuid.v4(),
      date: DateTime.now(),
      totalAmount: totalAmount,
      items: items,
      imagePath: imagePath,
    );
  }

  /// Extrahiert den Gesamtbetrag aus dem OCR-Text.
  ///
  /// Sucht nach Schlüsselwörtern wie "Total", "Summe", "Gesamt" oder dem
  /// Euro-Zeichen und parst den zugehörigen Betrag.
  double _parseAmount(String text) {
    // Regex: Schlüsselwörter gefolgt von optionalem Whitespace und einem Betrag
    // Unterstützt: "Total 12,50", "Summe: 8.99 €", "Gesamt 100,00 EUR"
    final RegExp amountRegex = RegExp(
      r'(?:total|summe|gesamt|betrag|amount|€|eur)\D*'
      r'(\d{1,6}[.,]\d{2})',
      caseSensitive: false,
    );

    final match = amountRegex.firstMatch(text);
    if (match != null) {
      final rawAmount = match.group(1)!.replaceAll(',', '.');
      return double.tryParse(rawAmount) ?? 0.0;
    }

    // Fallback: größten Betrag im Text suchen
    final RegExp fallbackRegex = RegExp(r'(\d{1,6}[.,]\d{2})');
    double maxAmount = 0.0;
    for (final m in fallbackRegex.allMatches(text)) {
      final value = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0.0;
      if (value > maxAmount) {
        maxAmount = value;
      }
    }
    return maxAmount;
  }

  /// Zerlegt den OCR-Text in Einzelzeilen und filtert leere Zeilen heraus.
  List<String> _parseItems(String text) {
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.length > 1)
        .toList();
  }

  /// Prüft, ob die Bilddatei noch auf dem Gerät vorhanden ist.
  bool imageExists(String imagePath) {
    return File(imagePath).existsSync();
  }
}
