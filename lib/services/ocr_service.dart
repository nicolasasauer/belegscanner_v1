import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
    r'(?:gesamtbetrag|zahlbetrag|total|summe|gesamt|betrag|amount|\bbar\b|€|eur)\D*'
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

/// Zerlegt den OCR-Text in Einzelzeilen, bereinigt OCR-Artefakte und
/// filtert Header-Daten, Zahlungszeilen, Summenzeilen sowie Junk-Text heraus.
///
/// Angewendete Schritte:
///   1. Header-, Meta-, Zahlungs- und Summenzeilen werden per Regex-
///      Ausschlussliste entfernt (z. B. GmbH, PLZ, Telefon, Summe, MwSt,
///      EUR, Zahlung, Visa, Payback, Werbe-Slogans).
///   2. OCR-Junk-Präfixe am Zeilenanfang (z. B. "CnBio", "unBio", "dnBio")
///      werden gestripped, sodass der Artikelname erhalten bleibt.
///   3. Paare aus [NAME] und [PREIS] werden erkannt:
///      - Zeilen mit Text + Preis am Ende → direkt als Artikel übernommen.
///      - Reine Preis-Zeilen nach einer Text-Zeile → zusammengeführt
///        (OCR-Toleranz: OCR schiebt Preis manchmal in die nächste Zeile).
///      - Standalone-Preis-Zeilen und reine Zahlen (z. B. MwSt-Sätze)
///        werden ignoriert.
List<String> _parseItemsImpl(String text) {
  // 1. Ausschlussmuster für typische Bon-Header, Meta-Daten, Summen- und
  //    Zahlungszeilen sowie Werbe-Slogans.
  final RegExp headerPattern = RegExp(
    // Rechtsformen / Firmenbezeichnungen
    r'GmbH|OHG|e\.K\.|'
    r'(?:^|\s)(?:AG|KG|eG)(?:\s|$)|e\.V\.|'
    // Adresse / Postleitzahl / Straße
    r'\b\d{5}\b|Str\.|Stra[ßs]e|Gasse|Platz|Marktgraben|'
    // Telefon / Fax / Internet
    r'Tel\.?:?\s*[\d\s\-/()]{5,}|Telefon|Fax|'
    r'www\.\S+|https?://|'
    // Steuer-IDs
    r'USt.{0,5}IdNr|Steuernummer|'
    // Datum / Uhrzeit
    r'\d{1,2}\.\d{1,2}\.\d{2,4}|'
    r'\d{1,2}:\d{2}\s*Uhr|'
    // Summen- und Gesamtbetragszeilen
    r'\bSumme\b|\bGesamtbetrag\b|\bZwischensumme\b|\bEndbetrag\b|'
    r'\bZahlbetrag\b|\bRestbetrag\b|\bZu zahlen\b|'
    // Steuer-Kennzeichen / MwSt-Zeilen
    r'\bMwSt\b|\bMWSt\b|\bUmSt\b|\bMehrwertsteuer\b|\bSteuer\b|'
    r'\bNetto\b|\bBrutto\b|'
    // Währungs-Zeilen (z. B. "EUR 14,95")
    r'\bEUR\b|'
    // Zahlungsmittel
    r'\bZahlung\b|\bBargeld\b|\bBar\b|\bGegeben\b|'
    r'\bRückgeld\b|\bWechselgeld\b|'
    r'\bVisa\b|\bMastercard\b|\bMaestro\b|\bEC-Karte\b|\bKartenzahlung\b|'
    // Kundenbindungsprogramme
    r'\bPayback\b|\bBonus\b|\bPunkte\b|\bCoupon\b|\bGutschein\b|'
    // Kasseninformationen
    r'\bKassennummer\b|\bBonnummer\b|\bKassenbon\b|\bBon-Nr\b|\bKassen-ID\b|'
    // Grußformeln / Werbe-Slogans
    r'Hier bin ich Mensch|'
    r'\bVielen Dank\b|\bAuf Wiedersehen\b|'
    r'\bGuten\s+(?:Morgen|Tag|Abend)\b|'
    r'\bWillkommen\b',
    caseSensitive: false,
  );

  // 2. OCR-Junk-Präfixe (z. B. 'CnBio', 'unBio', 'dnBio', 'xnBio')
  final RegExp junkPrefixPattern = RegExp(r'^[A-Za-z]nBio\s+');

  // 3a. Preis-Only-Muster: die ganze Zeile ist nur ein Preis
  //     (z. B. "1,65", "2.99", "14,95 A")
  final RegExp priceOnlyPattern = RegExp(
    r'^\d{1,4}[.,]\d{2}\s*[A-Za-z0-9]?\s*$',
  );

  // 3b. Vollständiges Artikel-Muster: Zeile hat Namenstext + Preis am Ende
  //     (z. B. "dmBio Tofu Rosso 200g 1,65", "Brot 750g 2,49 A").
  //     Lookahead stellt sicher, dass mindestens ein Buchstabe im Namensteil
  //     enthalten ist, um reine Zahlenzeilen auszuschließen.
  final RegExp itemWithPricePattern = RegExp(
    r'(?=.*[A-Za-zÄÖÜäöüß]).+\s+\d{1,4}[.,]\d{2}\s*[A-Za-z0-9]?\s*$',
  );

  // Schritt 1: Zeilen säubern und Header-/Meta-Zeilen entfernen
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !headerPattern.hasMatch(l))
      .map((l) => l.replaceFirst(junkPrefixPattern, '').trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // Schritt 2: Artikel-Paare (Name + Preis) erkennen und zusammenführen
  final result = <String>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // Standalone-Preis-Zeile (kein Namenstext davor in dieser Iteration)
    if (priceOnlyPattern.hasMatch(line)) {
      i++;
      continue;
    }

    // Vollständiger Artikel: Name + Preis auf derselben Zeile
    if (itemWithPricePattern.hasMatch(line)) {
      result.add(line);
      i++;
      continue;
    }

    // Reine Text-Zeile: Prüfen ob die nächste Zeile ein Preis ist
    // (OCR-Toleranz für zeilengetrennten Namen und Preis).
    // Bedingung: die aktuelle Zeile muss mindestens einen Buchstaben enthalten,
    // damit reine Zahlenzeilen (z. B. MwSt-Prozentsätze) nicht als Namen
    // behandelt werden.
    final bool nameHasLetter =
        RegExp(r'[A-Za-zÄÖÜäöüß]').hasMatch(line);
    if (nameHasLetter &&
        i + 1 < lines.length &&
        priceOnlyPattern.hasMatch(lines[i + 1])) {
      result.add('$line  ${lines[i + 1].trim()}');
      i += 2;
      continue;
    }

    // Text-Zeile ohne zugehörigen Preis → ignorieren
    i++;
  }

  return result;
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
    return _pickAndProcess(ImageSource.camera);
  }

  /// Öffnet die Galerie, wählt ein Bild aus und erkennt den Text per OCR.
  ///
  /// Gibt einen [Receipt] zurück oder `null`, wenn der Vorgang abgebrochen wurde.
  Future<Receipt?> importFromGallery() async {
    return _pickAndProcess(ImageSource.gallery);
  }

  /// Gemeinsame Implementierung für Kamera- und Galerie-Import.
  ///
  /// Öffnet die angegebene [source] (Kamera oder Galerie), gibt `null` zurück,
  /// wenn der Vorgang abgebrochen wird, und delegiert die Verarbeitung an
  /// [_processImage]. Beide Quellen durchlaufen identisch die OCR-Pipeline
  /// und die Thumbnail-Speicherlogik.
  Future<Receipt?> _pickAndProcess(ImageSource source) async {
    final XFile? imageFile = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );

    if (imageFile == null) {
      // Benutzer hat den Vorgang abgebrochen
      return null;
    }

    return _processImage(imageFile.path);
  }

  /// Verarbeitet ein Bild und erstellt einen [Receipt] aus dem erkannten Text.
  Future<Receipt> _processImage(String tempImagePath) async {
    // Text via Google ML Kit erkennen (muss auf dem Haupt-Isolate laufen,
    // da Platform Channels verwendet werden)
    final inputImage = InputImage.fromFilePath(tempImagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    final RecognizedText recognizedText;
    try {
      recognizedText = await textRecognizer.processImage(inputImage);
    } finally {
      // Ressourcen freigeben
      await textRecognizer.close();
    }

    final fullText = recognizedText.text;

    // Bild permanent speichern: aus dem temporären Cache-Verzeichnis in das
    // app-private Dokumenten-Verzeichnis kopieren, damit es auch nach dem
    // App-Neustart noch vorhanden ist.
    final String? permanentImagePath = await _persistImage(tempImagePath);

    // Parsing im Background-Isolate ausführen, damit der UI-Thread
    // (insbesondere der CircularProgressIndicator) nicht blockiert wird
    final result = await compute(_parseOcrText, fullText);

    return Receipt(
      id: _uuid.v4(),
      date: DateTime.now(),
      totalAmount: result['amount'] as double,
      items: List<String>.from(result['items'] as List),
      imagePath: permanentImagePath,
    );
  }

  /// Kopiert das Bild von [tempPath] in das permanente App-Dokumenten-
  /// Verzeichnis und gibt den neuen Pfad zurück.
  ///
  /// Gibt `null` zurück, wenn der Kopiervorgang fehlschlägt, sodass der
  /// Beleg ohne Bild gespeichert werden kann.
  Future<String?> _persistImage(String tempPath) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(docsDir.path, 'receipt_images'));
      if (!imagesDir.existsSync()) {
        await imagesDir.create(recursive: true);
      }
      // UUID als Dateiname, um Kollisionen zuverlässig zu vermeiden
      final fileName = '${_uuid.v4()}${p.extension(tempPath)}';
      final permanentFile = File(p.join(imagesDir.path, fileName));
      await File(tempPath).copy(permanentFile.path);
      return permanentFile.path;
    } catch (e, st) {
      // Fehler beim Kopieren: Beleg wird ohne Bild gespeichert
      debugPrint('[OcrService] Bild konnte nicht persistiert werden: $e\n$st');
      return null;
    }
  }

  /// Prüft, ob die Bilddatei noch auf dem Gerät vorhanden ist.
  bool imageExists(String imagePath) {
    return File(imagePath).existsSync();
  }
}
