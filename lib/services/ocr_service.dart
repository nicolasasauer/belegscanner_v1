import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/receipt.dart';

// ---------------------------------------------------------------------------
// Top-level Parsing-Funktionen (erforderlich für compute-Isolate)
// ---------------------------------------------------------------------------

/// Extrahiert den Gesamtbetrag aus dem OCR-Text.
///
/// Sucht nach deutschen Schlüsselwörtern wie "Summe", "Gesamtbetrag",
/// "Zahlbetrag", "Total", "Bar" sowie dem Euro-Zeichen und parst den
/// zugehörigen Betrag. Unterstützt Punkt und Komma als Dezimaltrenner
/// (z. B. 14,95 und 14.95).
double _parseAmountImpl(String text) {
  // Erweiterte Schlüsselwörter für deutsche Belege
  final RegExp amountRegex = RegExp(
    r'(?:gesamtbetrag|zahlbetrag|total|summe|gesamt|betrag|amount|bar|€|eur)\D*'
    r'(\d{1,6}[.,]\d{2})',
    caseSensitive: false,
  );

  final match = amountRegex.firstMatch(text);
  if (match != null) {
    // Komma als Dezimaltrenner (z. B. 14,95) in Punkt umwandeln
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
List<String> _parseItemsImpl(String text) {
  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && line.length > 1)
      .toList();
}

/// Top-level-Funktion für [compute]: Parst OCR-Text und gibt Betrag und
/// Artikel-Liste zurück.
Map<String, dynamic> _parseOcrText(String text) {
  return {
    'amount': _parseAmountImpl(text),
    'items': _parseItemsImpl(text),
  };
}

// ---------------------------------------------------------------------------
// OcrService
// ---------------------------------------------------------------------------

/// Service-Klasse für OCR-Texterkennung und Beleg-Parsing.
///
/// Kapselt die gesamte Logik für:
///   - Bildaufnahme via Kamera
///   - Texterkennung mit Google ML Kit
///   - Parsing des erkannten Textes (Betrag, Artikel) im Background-Isolate
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
    // Text via Google ML Kit erkennen (muss auf dem Haupt-Isolate laufen,
    // da Platform Channels verwendet werden)
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

    // Parsing im Background-Isolate ausführen, damit der UI-Thread
    // (insbesondere der CircularProgressIndicator) nicht blockiert wird
    final result = await compute(_parseOcrText, fullText);

    return Receipt(
      id: _uuid.v4(),
      date: DateTime.now(),
      totalAmount: result['amount'] as double,
      items: List<String>.from(result['items'] as List),
      imagePath: imagePath,
    );
  }

  /// Prüft, ob die Bilddatei noch auf dem Gerät vorhanden ist.
  bool imageExists(String imagePath) {
    return File(imagePath).existsSync();
  }
}
