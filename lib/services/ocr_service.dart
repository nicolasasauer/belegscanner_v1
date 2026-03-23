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

/// Compiled Regex: Preis am Ende einer OCR-Einzelposten-Zeile.
///
/// Erkennt z. B. "BROT 750G  2,99", "MILCH 1L 1,49 A" oder
/// "dmBio Tofu Rosso 200g 1,65 2" (Tax-Code am Ende ist Buchstabe oder Ziffer).
/// Das führende `\s+` stellt sicher, dass der Preis durch mindestens ein
/// Leerzeichen vom Artikelnamen getrennt ist.
final RegExp lineItemPriceRegex =
    RegExp(r'\s+(\d{1,4}[.,]\d{2})\s*[A-Za-z0-9]?\s*$');

/// Parst eine OCR-Zeile in einen Artikelnamen und einen optionalen Preis.
///
/// Gibt einen Named-Record `(name, price)` zurück. Wenn kein Preis erkannt
/// wird, enthält [name] die ursprüngliche [line] und [price] ist `null`.
///
/// Dynamische Bereinigung: Einzelne Großbuchstaben am Ende des extrahierten
/// Namens (Steuerklassen-Kennzeichen wie "A", "B", "C"), die durch ein
/// Leerzeichen vom eigentlichen Namen getrennt sind, werden automatisch
/// entfernt (z. B. "BROT A" → "BROT").
///
/// Beispiele:
/// - "dmBio Tofu Rosso 200g 1,65 2" → name: "dmBio Tofu Rosso 200g", price: 1.65
/// - "Brot 750g  2,49" → name: "Brot 750g", price: 2.49
/// - "Apfelstrudel A 2,50" → name: "Apfelstrudel", price: 2.50
/// - "1,65" → name: "1,65", price: null
@visibleForTesting
({String name, double? price}) parseLineItem(String line) {
  final match = lineItemPriceRegex.firstMatch(line);
  if (match == null) return (name: line, price: null);
  final price = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  var name = line.substring(0, match.start).trim();
  // Dynamische Bereinigung: Steuerklassen-Buchstaben (A, B, C …) am Ende
  // des Artikelnamens entfernen – erkennbar als einzelner Großbuchstabe
  // nach einem Leerzeichen (z. B. "ARTIKEL A" → "ARTIKEL").
  name = name.replaceAll(RegExp(r'\s+[A-Z]$'), '');
  return (name: name, price: price);
}

/// Extrahiert den Gesamtbetrag aus dem OCR-Text.
///
/// Sucht bevorzugt nach "SUMME" oder "TOTAL" (direkt daneben oder darunter),
/// dann nach anderen deutschen Schlüsselwörtern wie "Gesamtbetrag",
/// "Zahlbetrag", "Bar", und zuletzt nach EUR/€-Zeilen.
/// Unterstützt Punkt und Komma als Dezimaltrenner (z. B. 14,95 und 14.95).
@visibleForTesting
double parseAmountImpl(String text) {
  final pricePattern = RegExp(r'(\d{1,6}[.,]\d{2})');

  // Priorität 1: SUMME oder TOTAL – zeilenweise suchen, damit
  // Terminal-Daten (EUR 23,03) mit niedrigerer Priorität behandelt werden.
  final lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (RegExp(r'\b(?:SUMME|TOTAL)\b', caseSensitive: false).hasMatch(line)) {
      // Preis direkt auf derselben Zeile
      final sameLine = pricePattern.firstMatch(line);
      if (sameLine != null) {
        final value =
            double.tryParse(sameLine.group(1)!.replaceAll(',', '.'));
        if (value != null && value > 0) return value;
      }
      // Preis auf der nächsten Zeile
      if (i + 1 < lines.length) {
        final nextLine = pricePattern.firstMatch(lines[i + 1].trim());
        if (nextLine != null) {
          final value =
              double.tryParse(nextLine.group(1)!.replaceAll(',', '.'));
          if (value != null && value > 0) return value;
        }
      }
    }
  }

  // Priorität 2: Weitere Gesamtbetrag-Schlüsselwörter (ohne EUR/€,
  // da diese auch in Terminal-Daten vorkommen).
  final RegExp amountKeywordRegex = RegExp(
    r'(?:gesamtbetrag|zahlbetrag|gesamt|betrag|amount|\bbar\b)\D*'
    r'(\d{1,6}[.,]\d{2})',
    caseSensitive: false,
  );
  final match2 = amountKeywordRegex.firstMatch(text);
  if (match2 != null) {
    final value =
        double.tryParse(match2.group(1)!.replaceAll(',', '.'));
    if (value != null && value > 0) return value;
  }

  // Priorität 3: EUR / €-Zeilen (niedrigere Priorität, da auch in
  // Terminal-Daten vorhanden sein können).
  final RegExp euroRegex = RegExp(
    r'(?:€|eur)\D*(\d{1,6}[.,]\d{2})',
    caseSensitive: false,
  );
  final match3 = euroRegex.firstMatch(text);
  if (match3 != null) {
    final value =
        double.tryParse(match3.group(1)!.replaceAll(',', '.'));
    if (value != null && value > 0) return value;
  }

  // Fallback: größten Betrag im Text suchen
  double maxAmount = 0.0;
  for (final m in pricePattern.allMatches(text)) {
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
/// Algorithmus (ladenunabhängig / generisch):
///   1. Header-Cut: Alle Zeilen vor dem ersten Datum (TT.MM.JJJJ) oder der
///      ersten Uhrzeit (HH:MM) werden übersprungen. Ist kein Anker vorhanden,
///      werden alle Zeilen verarbeitet.
///   2. Footer-Cut: Sobald SUMME, TOTAL, GESAMT oder ZAHLBETRAG erscheint,
///      wird die Artikel-Suche beendet. Terminal-Daten, Payback und
///      Grußformeln dahinter werden vollständig ignoriert.
///   3. Müll-Muster: Herausgefiltert werden Zeilen mit mehr als 15
///      aufeinanderfolgenden Ziffern (Terminal-IDs/IBANs), Zeilen aus
///      ausschließlich Sonderzeichen (z. B. "------") sowie Zeilen mit
///      URLs oder E-Mail-Adressen.
///   4. Generischer Metadaten-Filter: Zeilen mit MwSt-Angaben, Zahlungs-
///      mitteln (Visa, Bar, Zahlung) und Kundenbindungs-Programmen werden
///      gefiltert, da sie trotz Preis-Muster keine Artikel sind.
///   5. OCR-Junk-Präfixe am Zeilenanfang (z. B. "CnBio", "unBio") werden
///      gestripped, sodass der Artikelname erhalten bleibt.
///   6. Artikel-Paare aus [NAME] und [PREIS] werden erkannt:
///      - Zeilen mit Text + Preis am Ende → direkt als Artikel übernommen.
///      - Reine Text-Zeilen gefolgt von einer reinen Preis-Zeile →
///        zusammengeführt (OCR-Split).
///      - Reine Text-Zeilen gefolgt von einer Mengenberechnung
///        (z. B. "4 X 1,59") und dann einer Preis-Zeile →
///        zusammengeführt (Multi-Line-Artikel).
///      - Standalone-Preis-Zeilen, Mengenberechnungs-Zeilen und reine
///        Zahlen werden ignoriert.
///
/// Jeder erkannte Treffer wird per [debugPrint] mit
/// `[OCR-Match] Found: Name=… Price=…` protokolliert.
@visibleForTesting
List<String> parseItemsImpl(String text) {
  // ─── 1. Strukturelle Muster (Anker) ──────────────────────────────────────

  // Header-Cut: Datum (TT.MM.JJJJ) oder Uhrzeit (HH:MM) markiert das Ende
  // des Bon-Headers. Alle Zeilen davor werden übersprungen.
  final RegExp headerCutPattern = RegExp(
    r'\b\d{1,2}\.\d{1,2}\.\d{2,4}\b|\b\d{1,2}:\d{2}\b',
  );

  // Footer-Cut: Diese Schlüsselwörter markieren das Ende der Artikel-Sektion.
  // Alles ab dieser Zeile (Terminal-Daten, Payback, Grußformeln) wird ignoriert.
  final RegExp footerPattern = RegExp(
    r'\b(?:SUMME|TOTAL|GESAMT|ZAHLBETRAG)\b',
    caseSensitive: false,
  );

  // ─── 2. Müll-Muster ──────────────────────────────────────────────────────

  // Mehr als 15 aufeinanderfolgende Ziffern (Terminal-IDs, IBANs)
  final RegExp manyDigitsPattern = RegExp(r'\d{15,}');

  // Nur Sonderzeichen (Trennlinien wie "------", "====="):
  // Zeilen ohne einen einzigen Buchstaben oder eine einzige Ziffer.
  final RegExp specialCharsOnlyPattern = RegExp(r'^[^A-Za-z0-9äöüÄÖÜß]+$');

  // URLs oder E-Mail-Adressen.
  // Das TLD-Muster [A-Za-z][A-Za-z0-9-]*\.(de|at|…) erfordert, dass der
  // Domain-Name mit einem Buchstaben beginnt, um Preismuster (z. B. "1,99")
  // nicht fälschlich zu treffen.
  final RegExp urlEmailPattern = RegExp(
    r'www\.|https?://|\S+@\S+|\b[A-Za-z][A-Za-z0-9-]*\.(de|at|com|org)\b',
    caseSensitive: false,
  );

  // ─── 3. Generischer Metadaten-Filter ─────────────────────────────────────
  // Zeilen, die trotz Preis-Muster KEINE Artikel sind (universell für
  // deutschsprachige Kassenbons).
  final RegExp metaPattern = RegExp(
    // Steuer / MwSt
    r'\bMwSt\b|\bMWSt\b|\bUmSt\b|\bMehrwertsteuer\b|\bSteuer\b|'
    r'\bNetto\b|\bBrutto\b|'
    // Zahlungsmittel
    r'\bZahlung\b|\bBargeld\b|\bBar\b|\bGegeben\b|'
    r'\bRückgeld\b|\bWechselgeld\b|'
    r'\bVisa\b|\bMastercard\b|\bMaestro\b|\bEC-Karte\b|\bKartenzahlung\b|'
    r'\bDEBIT\b|\bCREDIT\b|'
    // Terminal-Daten
    r'\bAcq-?Id\b|\bTrm-?Id\b|\bAID\b|\bVerarbeitung\s+OK\b|'
    r'\bKundenbeleg\b|\bcontactless\b|\bPAN\b|\bTrack2?\b|'
    // Kundenbindung
    r'\bPayback\b|\bBonus\b|\bPunkte\b|\bCoupon\b|\bGutschein\b|'
    // Kasseninfo
    r'\bKassennummer\b|\bBonnummer\b|\bKassenbon\b|\bBon-Nr\b|\bKassen-ID\b',
    caseSensitive: false,
  );

  // ─── 4. OCR-Artefakt-Bereinigung ─────────────────────────────────────────
  // Bekannte OCR-Junk-Präfixe (z. B. 'CnBio', 'unBio', 'dnBio').
  final RegExp junkPrefixPattern = RegExp(r'^[A-Za-z]nBio\s+');

  // ─── 5. Artikel-Erkennungs-Muster ────────────────────────────────────────

  // Preis-Only: die ganze Zeile ist nur ein Preis (z. B. "1,65", "2.99 A")
  final RegExp priceOnlyPattern = RegExp(
    r'^\d{1,4}[.,]\d{2}\s*[A-Za-z0-9]?\s*$',
  );

  // Vollständiges Artikel-Muster: Text + Preis am Ende.
  // Lookahead stellt sicher, dass mindestens ein Buchstabe im Namensteil
  // enthalten ist, um reine Zahlenzeilen auszuschließen.
  final RegExp itemWithPricePattern = RegExp(
    r'(?=.*[A-Za-zÄÖÜäöüß]).+\s+\d{1,4}[.,]\d{2}\s*[A-Za-z0-9]?\s*$',
  );

  // Mengenberechnungs-Muster: z. B. "4 X 1,59" oder "2x0,99"
  // Nur im Kontext von Multi-Line-Artikeln ausgewertet.
  final RegExp qtyCalcPattern = RegExp(
    r'^\d+\s*[xX]\s*\d{1,4}[.,]\d{2}',
  );

  // ─── Schritt 1: Zeilen aufteilen ─────────────────────────────────────────
  final allLines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // ─── Schritt 2: Header-Cut ───────────────────────────────────────────────
  // Überspringe alle Zeilen vor dem ersten Datum / der ersten Uhrzeit.
  // Wenn kein Anker gefunden wird, beginne von vorne (kein Header-Cut).
  int startIndex = 0;
  for (int i = 0; i < allLines.length; i++) {
    if (headerCutPattern.hasMatch(allLines[i])) {
      startIndex = i;
      break;
    }
  }

  // ─── Schritt 3: Footer-Cut ───────────────────────────────────────────────
  // Beende die Artikel-Suche sobald SUMME / TOTAL / GESAMT / ZAHLBETRAG
  // erscheint. Alles danach wird vollständig ignoriert.
  int endIndex = allLines.length;
  for (int i = startIndex; i < allLines.length; i++) {
    if (footerPattern.hasMatch(allLines[i])) {
      endIndex = i;
      break;
    }
  }

  // ─── Schritt 4: Müll und Metadaten filtern, OCR-Artefakte bereinigen ─────
  final lines = allLines
      .sublist(startIndex, endIndex)
      .where((l) => !manyDigitsPattern.hasMatch(l))
      .where((l) => !specialCharsOnlyPattern.hasMatch(l))
      .where((l) => !urlEmailPattern.hasMatch(l))
      .where((l) => !metaPattern.hasMatch(l))
      .map((l) => l.replaceFirst(junkPrefixPattern, '').trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // ─── Schritt 5: Artikel-Paare erkennen und zusammenführen ────────────────
  final result = <String>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // Standalone-Preis-Zeile (kein Namenstext davor in dieser Iteration)
    if (priceOnlyPattern.hasMatch(line)) {
      i++;
      continue;
    }

    // Mengenberechnungs-Zeile (z. B. "4 X 1,59") ohne vorherigen
    // Artikel-Kontext → überspringen, damit "4 X" nicht als Name landet.
    if (qtyCalcPattern.hasMatch(line)) {
      i++;
      continue;
    }

    // Vollständiger Artikel: Name + Preis auf derselben Zeile
    if (itemWithPricePattern.hasMatch(line)) {
      result.add(line);
      final (:name, :price) = parseLineItem(line);
      debugPrint('[OCR-Match] Found: Name=$name, Price=${price ?? "–"}');
      i++;
      continue;
    }

    // Reine Text-Zeile: Prüfen ob folgende Zeilen einen Preis liefern.
    // Bedingung: die aktuelle Zeile muss mindestens einen Buchstaben enthalten,
    // damit reine Zahlenzeilen (z. B. MwSt-Prozentsätze) nicht als Namen
    // behandelt werden.
    final bool nameHasLetter = RegExp(r'[A-Za-zÄÖÜäöüß]').hasMatch(line);
    if (nameHasLetter) {
      // Fall A: Name | Mengenberechnung (z. B. "4 X 1,59") | Gesamtpreis
      //         → Multi-Line-Artikel: Name mit Gesamtpreis zusammenführen.
      if (i + 2 < lines.length &&
          qtyCalcPattern.hasMatch(lines[i + 1]) &&
          priceOnlyPattern.hasMatch(lines[i + 2])) {
        final merged = '$line  ${lines[i + 2].trim()}';
        result.add(merged);
        final (:name, :price) = parseLineItem(merged);
        debugPrint(
            '[OCR-Match] Found (multi-line): Name=$name, Price=${price ?? "–"}');
        i += 3;
        continue;
      }

      // Fall B: Name | Preis (OCR hat Preis auf die nächste Zeile verschoben)
      if (i + 1 < lines.length &&
          priceOnlyPattern.hasMatch(lines[i + 1])) {
        final merged = '$line  ${lines[i + 1].trim()}';
        result.add(merged);
        final (:name, :price) = parseLineItem(merged);
        debugPrint('[OCR-Match] Found: Name=$name, Price=${price ?? "–"}');
        i += 2;
        continue;
      }
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
    'amount': parseAmountImpl(text),
    'items': parseItemsImpl(text),
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
