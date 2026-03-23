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

/// Fallback-Name für Artikel, bei denen kein Name aus dem OCR-Text
/// ermittelt werden kann (Preis-Anker-Logik).
const String kUnknownItemName = 'Unbekannter Artikel';

// ---------------------------------------------------------------------------
// Normalisierung und Kategorisierung
// ---------------------------------------------------------------------------

/// Normalisiert einen Artikelnamen:
///   - Überflüssige Leerzeichen werden entfernt.
///   - Der Name wird in „Title Case" umgewandelt (erster Buchstabe jedes
///     Wortes groß, Rest klein).
///
/// Beispiele:
/// - "  RED   BULL  " → "Red Bull"
/// - "dmBio Tofu Rosso 200g" → "Dmbio Tofu Rosso 200g"
/// - "VOLLKORNBROT 750G" → "Vollkornbrot 750g"
@visibleForTesting
String normalizeName(String name) {
  final trimmed = name.trim().replaceAll(_whitespaceRunRegex, ' ');
  return trimmed.split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

/// Hilfs-Regex: erkennt aufeinanderfolgende Leerzeichen (für [normalizeName]).
final RegExp _whitespaceRunRegex = RegExp(r'\s+');

/// Schlüsselwort-zu-Kategorie-Zuordnung für die automatische Kategorisierung.
///
/// Der Vergleich ist nicht case-sensitiv. Wenn ein Artikelname eines dieser
/// Schlüsselwörter enthält, wird die entsprechende Kategorie gesetzt.
const Map<String, String> categoryMap = {
  'Bio': 'Lebensmittel',
  'Tofu': 'Lebensmittel',
  'Milch': 'Lebensmittel',
  'Brot': 'Lebensmittel',
  'Obst': 'Lebensmittel',
  'Gemüse': 'Lebensmittel',
  'Shampoo': 'Drogerie',
  'Zahnpasta': 'Drogerie',
  'Duschgel': 'Drogerie',
  'Balea': 'Drogerie',
  'Hygiene': 'Drogerie',
  'Pfand': 'Pfand',
  'Leergut': 'Pfand',
  'Red Bull': 'Getränke',
  'Cola': 'Getränke',
  'Wasser': 'Getränke',
  'Saft': 'Getränke',
};

/// Ermittelt die Kategorie eines Artikelnamens anhand von [categoryMap].
///
/// Gibt „Sonstiges" zurück, wenn kein Schlüsselwort übereinstimmt.
///
/// Beispiele:
/// - "Dmbio Tofu Rosso 200g" → "Lebensmittel"
/// - "Pfand 0,25" → "Pfand"
/// - "Red Bull" → "Getränke"
/// - "Kugelschreiber" → "Sonstiges"
@visibleForTesting
String categorizeItem(String name) {
  final lowerName = name.toLowerCase();
  for (final entry in categoryMap.entries) {
    if (lowerName.contains(entry.key.toLowerCase())) {
      return entry.value;
    }
  }
  return 'Sonstiges';
}

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

/// Formatiert einen Geldbetrag als String mit Komma als Dezimaltrenner
/// (z. B. 2.25 → "2,25"). Wird von [parseItemsHeuristic] verwendet.
String _formatPriceComma(double price) =>
    price.toStringAsFixed(2).replaceAll('.', ',');

/// Heuristische Artikel-Erkennung für OCR-Texte, bei denen Namen und Preise
/// vollständig getrennt in unterschiedlichen Textbereichen erscheinen
/// (z. B. OCR hat alle Namen gesammelt und alle Preise an anderer Stelle).
///
/// Diese Funktion wird von [parseItemsImpl] als Fallback aufgerufen, wenn
/// die primäre Look-Ahead-Logik keine Artikel gefunden hat.
///
/// Algorithmus (Heuristik-Queue-Logik):
///   1. Jede Zeile wird durch einen aggressiven Junk-Filter geleitet
///      (ATU, EFSTA, Buchung, Contactless, GmbH, Payback, Hash-Codes, …).
///   2. Preiszahlen (X,XX) werden in [tempPrices] gesammelt; Duplikate,
///      negative Beträge und MwSt-Beträge (Preis direkt nach MwSt-Label)
///      werden ignoriert.
///   3. Produktzeilen (Zeilen mit Buchstaben, die nicht Junk sind) werden
///      in [tempNames] gesammelt.
///   4. Match-Maker:
///      - Gleich lang → paarweise Zuordnung in Reihenfolge des Erscheinens.
///      - Mehr Preise als Namen → letzte N Preise nehmen (Summen/Terminal-
///        beträge stehen oft am Ende) und den N Namen zuordnen.
///      - Mehr Namen als Preise → so viele Paare wie möglich bilden.
@visibleForTesting
List<String> parseItemsHeuristic(String text) {
  // ─── Aggressiver Junk-Filter ─────────────────────────────────────────────
  // Enthält alle bekannten Nicht-Artikel-Schlüsselwörter aus dm-Kassenbons.
  // Hinweis: „öffnungszeiten" enthält das deutsche Sonderzeichen „ö", das
  // kein ASCII-\w-Zeichen ist; \b würde hier nicht korrekt greifen, daher
  // wird dieses Wort ohne Wortgrenzen als Substring-Muster eingesetzt.
  final junkLinePattern = RegExp(
    r'\bATU\b'                  // österreichische Steuernummer
    r'|\bEFSTA\b'               // EFSTA-Finanzamt-Hash
    r'|\bBuchung\b'             // Buchungs-/Zahlungszeile
    r'|\b[Cc]ontactless\b'      // kontaktloses Zahlen
    r'|\bZahlung\b'             // Zahlungszeile
    r'|\bPayback\b|\bPAYBACK\b' // Treuepunkte
    r'|\bVisa\b|\bMastercard\b' // Zahlungsarten
    r'|\bGmbH\b'                // Firmenbezeichnung
    r'|\bMarktgraben\b'         // dm-spezifische Adresszeile
    r'|\bInnsbruck\b'           // Ortsname
    r'|\bDanke\b'               // Grußformel
    r'|\bEinkauf\b'             // Kassentext (z. B. "Für diesen Einkauf")
    r'|\bMensch\b'              // dm-Slogan "Hier bin ich Mensch"
    r'|öffnungszeiten'          // Öffnungszeiten-Hinweis
    r'|\bNettobetr\b'           // Netto-Betrag-Zeile
    r'|\bMWSt\b|\bMwSt\b'      // Steuersatz-Label (z. B. MWSt-Satz, MWSt)
    r'|\bPunkte\b'              // Payback-Punkte
    r'|\bDebit\b|\bCredit\b'    // Zahlungsart
    r'|\bEFT\b'                 // Electronic Funds Transfer
    r'|\bkauf\b'                // dm-Slogan-Wort ("Hier kauf ich ein")
    r'|#',                      // Hash-Codes (z. B. #31514283*…)
    caseSensitive: false,
  );

  // Preis-Only-Muster (identisch mit parseItemsImpl)
  final priceOnlyPattern = RegExp(r'^\d{1,4}[.,]\d{2}\s*[A-Za-z0-9]?\s*$');

  // Standalone-MwSt-Label: Preis auf der Folgezeile ist ein Steuerbetrag
  final mwstLabelPattern = RegExp(
    r'^\s*(?:MWSt|MwSt)\s*$',
    caseSensitive: false,
  );

  // Kurze Einzelzahl (1–2 Ziffern ohne Buchstaben, z. B. "2", "19")
  final pureShortNumberPattern = RegExp(r'^\d{1,2}$');

  final allLines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final tempNames = <String>[];
  final tempPrices = <double>[];
  final seenPrices = <double>{};

  for (int idx = 0; idx < allLines.length; idx++) {
    final line = allLines[idx];
    final prevLine = idx > 0 ? allLines[idx - 1] : '';

    // Junk-Filter: Zeile enthält bekannte Nicht-Artikel-Schlüsselwörter
    if (junkLinePattern.hasMatch(line)) continue;

    // Prozentsatz-Zeilen (z. B. "2=10,00%")
    if (line.contains('%')) continue;

    // Negative Beträge (z. B. "-3,90")
    if (line.startsWith('-')) continue;

    // Zeilen, die mit einem Datum beginnen (z. B. "21.03.2026 13:45 …")
    if (RegExp(r'^\d{1,2}\.\d{1,2}\.').hasMatch(line)) continue;

    // Kartenummer-artige Zeichenketten (z. B. "1/1/1227**", "XXX9471")
    if (RegExp(r'\*{3,}|[Xx]{3,}|\d{10,}').hasMatch(line)) continue;

    // Kurze Einzelzahlen ("2", "19")
    if (pureShortNumberPattern.hasMatch(line)) continue;

    // Allein stehende Schlüsselwörter ohne Produktbezug
    if (RegExp(r'^(?:SUMME|TOTAL|GESAMT|EUR|€)$', caseSensitive: false)
        .hasMatch(line)) continue;

    // Preis-Zeile: Betrag in tempPrices aufnehmen
    if (priceOnlyPattern.hasMatch(line)) {
      // Steuerbeträge überspringen: Preis direkt nach einem MwSt-Label
      if (mwstLabelPattern.hasMatch(prevLine)) continue;

      final rawPrice = line.split(RegExp(r'\s+'))[0].replaceAll(',', '.');
      final price = double.tryParse(rawPrice);
      if (price != null && price > 0 && !seenPrices.contains(price)) {
        seenPrices.add(price);
        tempPrices.add(price);
      }
      continue;
    }

    // Produktzeile: muss mindestens einen Buchstaben enthalten
    if (!RegExp(r'[A-Za-zÄÖÜäöüß]').hasMatch(line)) continue;

    // Reine Codes/Kürzel ohne Leerzeichen (z. B. "XXX9471", "O503") filtern
    if (RegExp(r'^[A-Z0-9]{4,12}$').hasMatch(line)) continue;

    // Reine Zeitangaben (z. B. "13:46:00") filtern
    if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(line)) continue;

    tempNames.add(line);
  }

  debugPrint(
      '[OCR-Heuristic] tempNames=$tempNames, tempPrices=$tempPrices');

  if (tempNames.isEmpty || tempPrices.isEmpty) return [];

  // ─── Match-Maker: Namen und Preise zusammenführen ────────────────────────
  final result = <String>[];
  if (tempNames.length == tempPrices.length) {
    // Perfekte Übereinstimmung: paarweise in Reihenfolge des Erscheinens
    for (int i = 0; i < tempNames.length; i++) {
      result.add('${tempNames[i]}  ${_formatPriceComma(tempPrices[i])}');
    }
  } else if (tempPrices.length > tempNames.length) {
    // Mehr Preise als Namen: letzte N Preise nehmen
    // (Summen/Terminalbeträge erscheinen typischerweise früh in der Liste,
    // die Artikel-Preise am Ende)
    final n = tempNames.length;
    final pricesSlice = tempPrices.sublist(tempPrices.length - n);
    for (int i = 0; i < n; i++) {
      result.add('${tempNames[i]}  ${_formatPriceComma(pricesSlice[i])}');
    }
  } else {
    // Mehr Namen als Preise: so viele Paare wie möglich bilden
    for (int i = 0; i < tempPrices.length; i++) {
      result.add('${tempNames[i]}  ${_formatPriceComma(tempPrices[i])}');
    }
  }

  for (final r in result) {
    final (:name, :price) = parseLineItem(r);
    debugPrint('[OCR-Heuristic] Matched: Name=$name, Price=${price ?? "–"}');
  }

  return result;
}

/// Zerlegt den OCR-Text in Einzelzeilen und extrahiert Artikel per
/// Look-Ahead-Logik.
///
/// Algorithmus (ladenunabhängig / generisch):
///   1. Vorbereitung: Leere Zeilen und Strich-Trennlinien werden entfernt.
///   2. Header-Cut: Alle Zeilen vor dem ersten Datum (TT.MM.JJJJ) oder der
///      ersten Uhrzeit (HH:MM) werden übersprungen. Ist kein Anker vorhanden,
///      werden alle Zeilen verarbeitet. Zusätzlich werden typische
///      Header-Zeilen (z. B. mit „GmbH", „UID-Nr", Telefonnummern) ignoriert.
///   3. Footer-Cut: Sobald SUMME, TOTAL, GESAMT oder ZAHLBETRAG erscheint,
///      wird die Artikel-Suche beendet. Terminal-Daten, Payback und
///      Grußformeln dahinter werden vollständig ignoriert.
///   4. Müll-Muster: Herausgefiltert werden Zeilen mit mehr als 15
///      aufeinanderfolgenden Ziffern (Terminal-IDs/IBANs), Zeilen aus
///      ausschließlich Sonderzeichen (z. B. "------") sowie Zeilen mit
///      URLs oder E-Mail-Adressen.
///   5. OCR-Junk-Präfixe am Zeilenanfang (z. B. "CnBio", "unBio") werden
///      gestripped, sodass der Artikelname erhalten bleibt.
///   6. Look-Ahead-Erkennung (Artikel-Paar-Logik):
///      - Zeilen mit Text + Preis am Ende → direkt als Artikel übernommen.
///      - Reine Text-Zeilen gefolgt von einer Mengenberechnung
///        (z. B. "4 X 1,59") und dann einer Preis-Zeile →
///        zusammengeführt (Multi-Line-Artikel).
///      - Reine Text-Zeilen gefolgt von einer Preis-Zeile (Look-Ahead) →
///        zusammengeführt; aus der Preis-Zeile wird nur die erste Zahl
///        extrahiert (z. B. „2,25 2" → Preis 2,25).
///      - Standalone-Preis-Zeilen ohne vorherigen Namenstext erhalten den
///        Fallback-Namen „Unbekannter Artikel".
///      - Mengenberechnungs-Zeilen (z. B. "4 X 1,59") und reine
///        Zahlen ohne Dezimaltrenner werden ignoriert.
///   7. Heuristik-Fallback: Wenn Schritt 6 keine Artikel liefert (z. B.
///      weil der OCR-Text Namen und Preise vollständig getrennt darstellt),
///      wird [parseItemsHeuristic] als Fallback aufgerufen.
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

  // Sperrliste für Header-Zeilen: Typische Bestandteile des Bon-Headers,
  // die als Artikel ignoriert werden sollen (GmbH, UID-Nr., Straßenangaben,
  // Telefonnummern). Diese Muster werden nur auf Header-Zeilen (vor dem
  // Date-Anchor) angewendet; innerhalb der Artikelsektion bleiben sie
  // unberührt.
  // Hinweis: „Marktgraben" ist eine typische Adresszeile im dm-Bon-Header
  // und wird daher explizit in die Sperrliste aufgenommen.
  final RegExp headerBlocklistPattern = RegExp(
    r'\bGmbH\b|UID-Nr|Marktgraben|\bTel\.?\s*\d|\b\d{3,}\s*[-/]\s*\d{3,}\b',
    caseSensitive: false,
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

  // ─── 3. OCR-Artefakt-Bereinigung ─────────────────────────────────────────
  // Bekannte OCR-Junk-Präfixe (z. B. 'CnBio', 'unBio', 'dnBio').
  final RegExp junkPrefixPattern = RegExp(r'^[A-Za-z]nBio\s+');

  // ─── 4. Artikel-Erkennungs-Muster ────────────────────────────────────────

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
  // Zeilen vor dem Anker, die auf die Sperrliste passen (GmbH, UID-Nr,
  // Marktgraben, Telefonnummern), werden ebenfalls explizit ignoriert.
  int startIndex = 0;
  int headerAnchorIndex = -1;
  for (int i = 0; i < allLines.length; i++) {
    if (headerCutPattern.hasMatch(allLines[i])) {
      headerAnchorIndex = i;
      startIndex = i;
      break;
    }
  }
  // Sperrliste: Wenn kein Datum-Anker gefunden wurde, überspringe
  // führende Zeilen, die Header-Begriffe wie „GmbH", „UID-Nr", „Marktgraben"
  // oder Telefonnummern enthalten.
  if (headerAnchorIndex == -1) {
    while (startIndex < allLines.length &&
        headerBlocklistPattern.hasMatch(allLines[startIndex])) {
      startIndex++;
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

  // ─── Schritt 4: Müll filtern, OCR-Artefakte bereinigen ───────────────────
  final lines = allLines
      .sublist(startIndex, endIndex)
      .where((l) => !manyDigitsPattern.hasMatch(l))
      .where((l) => !specialCharsOnlyPattern.hasMatch(l))
      .where((l) => !urlEmailPattern.hasMatch(l))
      .map((l) => l.replaceFirst(junkPrefixPattern, '').trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // ─── Schritt 5: Artikel per Look-Ahead-Logik erkennen ───────────────────
  final result = <String>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

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

    // Look-Ahead: Reine Text-Zeile mit Preis auf einer der Folgezeilen.
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

      // Fall B (Look-Ahead): Name | Preis-Zeile (beginnt mit X,XX).
      // Preis-Extraktion: Aus der Preis-Zeile wird nur die erste Zahl
      // verwendet (z. B. aus „2,25 2" wird Preis 2,25).
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

    // Standalone-Preis-Zeile (kein Namenstext in dieser Iteration):
    // Preis-First-Logik: Preis wird als Artikel mit Fallback-Name gewertet.
    if (priceOnlyPattern.hasMatch(line)) {
      final merged = '$kUnknownItemName  ${line.trim()}';
      result.add(merged);
      final (:name, :price) = parseLineItem(merged);
      debugPrint('[OCR-Match] Found (fallback): Name=$name, Price=${price ?? "–"}');
      i++;
      continue;
    }

    // Text-Zeile ohne zugehörigen Preis → ignorieren
    i++;
  }

  // ─── Schritt 6: Heuristik-Fallback für scrambled Receipts ────────────────
  // Wenn die primäre Look-Ahead-Logik keine Artikel gefunden hat (z. B. weil
  // der OCR-Text Namen und Preise vollständig getrennt darstellt und SUMME
  // sehr früh im Text erscheint), greift die Heuristik-Queue-Logik.
  if (result.isEmpty) {
    return parseItemsHeuristic(text);
  }

  return result;
}

/// Top-level-Funktion für [compute]: Parst OCR-Text und gibt Betrag,
/// normalisierte Artikel-Liste und Kategorien zurück.
///
/// Nach dem Extrahieren der Artikel werden [normalizeName] und
/// [categorizeItem] auf jeden Artikel angewendet, sodass die zurückgegebenen
/// Items bereits normalisierte Namen tragen und die Kategorien-Liste parallel
/// befüllt ist.
Map<String, dynamic> _parseOcrText(String text) {
  final rawItems = parseItemsImpl(text);
  final normalizedItems = <String>[];
  final categories = <String>[];

  for (final item in rawItems) {
    final (:name, :price) = parseLineItem(item);
    final normalizedName = normalizeName(name);
    categories.add(categorizeItem(normalizedName));
    if (price != null) {
      normalizedItems.add('$normalizedName  ${_formatPriceComma(price)}');
    } else {
      normalizedItems.add(normalizedName);
    }
  }

  return {
    'amount': parseAmountImpl(text),
    'items': normalizedItems,
    'categories': categories,
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
      categories: List<String>.from(result['categories'] as List),
      imagePath: permanentImagePath,
      rawText: fullText.isEmpty ? null : fullText,
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
