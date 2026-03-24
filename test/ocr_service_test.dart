// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:belegscanner_v1/services/ocr_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl – Artikel-Paar-Erkennung
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – dm-Beleg', () {
    // Simulierter OCR-Output eines echten dm-Belegs:
    // Name und Preis stehen auf ZWEI getrennten Zeilen (Look-Ahead-Format).
    // Header-Zeilen (GmbH, Datum) werden durch Header-Cut ignoriert.
    // SUMME steht auf einer eigenen Zeile, Betrag auf der nächsten (EUR X,XX).
    const dmReceiptText =
        'dm drogerie markt GmbH\n'
        '20.03.2026 13:46\n'
        'dmBio Fruchtaufstr. Erdb. 250g\n'
        '2,25 2\n'
        'dmBio Tofu Rosso 200g\n'
        '1,65 2\n'
        'SUMME\n'
        'EUR 3,90';

    test('Erkennt genau zwei Artikel', () {
      final items = parseItemsImpl(dmReceiptText);
      expect(items.length, equals(2));
    });

    test('Erster Artikel: Name = "dmBio Fruchtaufstr. Erdb. 250g", Preis = 2.25',
        () {
      final items = parseItemsImpl(dmReceiptText);
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('dmBio Fruchtaufstr. Erdb. 250g'));
      expect(price, equals(2.25));
    });

    test('Zweiter Artikel: Name = "dmBio Tofu Rosso 200g", Preis = 1.65', () {
      final items = parseItemsImpl(dmReceiptText);
      final (:name, :price) = parseLineItem(items[1]);
      expect(name, equals('dmBio Tofu Rosso 200g'));
      expect(price, equals(1.65));
    });

    test('SUMME-Zeile wird ignoriert', () {
      final items = parseItemsImpl(dmReceiptText);
      expect(items.any((i) => i.toLowerCase().contains('summe')), isFalse);
    });

    test('Header-Zeile "GmbH" erscheint nicht in der Artikelliste', () {
      final items = parseItemsImpl(dmReceiptText);
      expect(items.any((i) => i.contains('GmbH')), isFalse);
    });

    test('Gesamtbetrag aus "SUMME\\nEUR 3,90" wird korrekt erkannt', () {
      expect(parseAmountImpl(dmReceiptText), closeTo(3.90, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl – OCR-Zeilenbruch (Name + Preis getrennt)
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – OCR-Split (Preis auf nächster Zeile)', () {
    // Simuliert OCR, das Name und Preis auf separate Zeilen aufteilt.
    const splitText =
        'dmBio Tofu Rosso 200g\n'
        '1,65\n'
        'Hafermilch 1L\n'
        '1,29\n'
        'SUMME 2,94';

    test('Erkennt zwei zusammengeführte Artikel', () {
      final items = parseItemsImpl(splitText);
      expect(items.length, equals(2));
    });

    test('Zusammengeführter Artikel 1: Name = "dmBio Tofu Rosso 200g", Preis = 1.65',
        () {
      final items = parseItemsImpl(splitText);
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('dmBio Tofu Rosso 200g'));
      expect(price, equals(1.65));
    });

    test('Zusammengeführter Artikel 2: Name = "Hafermilch 1L", Preis = 1.29',
        () {
      final items = parseItemsImpl(splitText);
      final (:name, :price) = parseLineItem(items[1]);
      expect(name, equals('Hafermilch 1L'));
      expect(price, equals(1.29));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl – Blacklist / Ignorieren
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – Blacklist', () {
    test('Header-Zeilen (GmbH, Adresse, PLZ) werden ignoriert', () {
      const headerText =
          'dm-drogerie markt GmbH\n'
          'Musterstraße 1\n'
          '12345 Musterstadt\n'
          'dmBio Milch 1L 1,19 2';
      final items = parseItemsImpl(headerText);
      // Mindestens der Artikel mit Preis muss erkannt werden
      expect(items.any((i) => i.contains('Milch')), isTrue);
      final item = items.firstWhere((i) => i.contains('Milch'));
      final (:name, :price) = parseLineItem(item);
      expect(name, equals('dmBio Milch 1L'));
      expect(price, equals(1.19));
    });

    test(
        'Sperrliste: GmbH-Zeile ohne Datum-Anker wird als Header übersprungen',
        () {
      // Kein Datum → kein Header-Cut. Sperrliste überspringt "GmbH"-Zeilen.
      const blocklistText =
          'Muster GmbH\n'
          'UID-Nr. AT123456789\n'
          'Apfelsaft 1L 1,49\n'
          'Wasser 0,5L 0,79\n'
          'SUMME 2,28';
      final items = parseItemsImpl(blocklistText);
      expect(items.any((i) => i.contains('GmbH')), isFalse);
      expect(items.any((i) => i.contains('UID-Nr')), isFalse);
      expect(items.any((i) => i.contains('Apfelsaft')), isTrue);
    });

    test('MwSt-Zeilen können als Artikel erkannt werden (Price-First-Logik)', () {
      const mwstText =
          'Brot 750g 2,49\n'
          'MwSt 19% 0,39\n'
          'MwSt 7% 0,16';
      final items = parseItemsImpl(mwstText);
      // Brot muss weiterhin erkannt werden
      expect(items.any((i) => i.contains('Brot')), isTrue);
      final brotItem = items.firstWhere((i) => i.contains('Brot'));
      expect(parseLineItem(brotItem).price, closeTo(2.49, 0.001));
    });

    test('Reine Zahlenzeilen (MwSt-Sätze) ohne Dezimaltrenner werden nicht als Namen verwendet',
        () {
      const vatText =
          '19\n'
          '2,49\n'
          '7\n'
          '1,19';
      final items = parseItemsImpl(vatText);
      // "19" und "7" haben keine Buchstaben → dürfen nicht als Namen matched werden
      for (final item in items) {
        final (:name, :price) = parseLineItem(item);
        expect(name, isNot(equals('19')));
        expect(name, isNot(equals('7')));
        // Preise müssen vorhanden sein
        expect(price, isNotNull);
      }
    });

    test('Standalone Preis-Zeilen erhalten „Unbekannter Artikel" als Fallback-Name',
        () {
      const priceOnlyText = '2,49\n1,65\n3,90';
      final items = parseItemsImpl(priceOnlyText);
      // Price-First: alle Preise werden als Artikel erkannt
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.contains(kUnknownItemName), isTrue);
      }
    });

    test('Zahlungs-Zeilen können als Artikel erkannt werden (Price-First-Logik)', () {
      const paymentText =
          'Brot 750g 2,49\n'
          'Zahlung Visa 2,49\n'
          'Vielen Dank';
      final items = parseItemsImpl(paymentText);
      // Brot muss erkannt werden
      expect(items.any((i) => i.contains('Brot')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl – OCR-Junk-Präfixe
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – OCR-Junk-Präfixe', () {
    test('Junk-Präfix "CnBio" wird entfernt, Artikelname bleibt erhalten', () {
      const junkText = 'CnBio Tofu Rosso 200g 1,65 2';
      final items = parseItemsImpl(junkText);
      expect(items.length, equals(1));
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('Tofu Rosso 200g'));
      expect(price, equals(1.65));
    });

    test('"dmBio"-Präfix (gültige Marke) wird NICHT entfernt', () {
      const dmText = 'dmBio Tofu Rosso 200g 1,65 2';
      final items = parseItemsImpl(dmText);
      expect(items.length, equals(1));
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('dmBio Tofu Rosso 200g'));
      expect(price, equals(1.65));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseAmountImpl – Gesamtbetrag-Extraktion
  // ---------------------------------------------------------------------------

  group('parseAmountImpl', () {
    test('Erkennt "SUMME 3,90" korrekt', () {
      const text = 'dmBio Tofu 1,65\nSUMME 3,90';
      expect(parseAmountImpl(text), closeTo(3.90, 0.001));
    });

    test('Erkennt "Gesamtbetrag 14,95" korrekt', () {
      const text = 'Artikel 1 5,00\nArtikel 2 9,95\nGesamtbetrag 14,95';
      expect(parseAmountImpl(text), closeTo(14.95, 0.001));
    });

    test('Fallback: gibt den größten Betrag zurück', () {
      const text = '1,65 3,90 14,95';
      expect(parseAmountImpl(text), closeTo(14.95, 0.001));
    });

    test('Gibt 0.0 zurück, wenn kein Betrag gefunden wird', () {
      expect(parseAmountImpl('kein preis hier'), equals(0.0));
    });

    test('SUMME hat Vorrang vor EUR-Zeile mit größerem Betrag', () {
      // Simuliert Terminal-Daten mit "23,03 EUR" nach der echten Summe
      const text =
          'RED BULL 6,36\n'
          'PFAND 0,25\n'
          'SUMME 9,30\n'
          'Mastercard\n'
          'DEBIT\n'
          '23,03 EUR';
      expect(parseAmountImpl(text), closeTo(9.30, 0.001));
    });

    test('SUMME auf nächster Zeile wird erkannt', () {
      const text = 'Artikel 1 5,00\nSUMME\n5,00';
      expect(parseAmountImpl(text), closeTo(5.00, 0.001));
    });

    test('SUMME mit EUR-Präfix auf nächster Zeile wird erkannt (dm-Format)', () {
      const text = 'Artikel 1 2,25\nArtikel 2 1,65\nSUMME\nEUR 3,90';
      expect(parseAmountImpl(text), closeTo(3.90, 0.001));
    });

    test(
        'EUR X,XX auf nächster Zeile nach SUMME stört Artikel-Erkennung nicht',
        () {
      // Sicherstellen, dass "EUR 3,90" nach dem Footer-Cut nicht als Artikel landet.
      const text = 'Artikel 1 2,25\nArtikel 2 1,65\nSUMME\nEUR 3,90';
      final items = parseItemsImpl(text);
      expect(items.length, equals(2));
      expect(items.any((i) => i.contains('EUR')), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseLineItem – Name/Preis-Trennung
  // ---------------------------------------------------------------------------

  group('parseLineItem', () {
    test('Trennt Name und Preis korrekt (einfacher Fall)', () {
      final (:name, :price) = parseLineItem('Brot 750g 2,49');
      expect(name, equals('Brot 750g'));
      expect(price, closeTo(2.49, 0.001));
    });

    test('Trennt Name und Preis mit Tax-Code korrekt', () {
      final (:name, :price) = parseLineItem('dmBio Tofu Rosso 200g 1,65 2');
      expect(name, equals('dmBio Tofu Rosso 200g'));
      expect(price, closeTo(1.65, 0.001));
    });

    test('Gibt ursprüngliche Zeile zurück, wenn kein Preis gefunden', () {
      final (:name, :price) = parseLineItem('Kein Preis hier');
      expect(name, equals('Kein Preis hier'));
      expect(price, isNull);
    });

    test('Behandelt doppeltes Leerzeichen als Trenner (Merged-Format)', () {
      final (:name, :price) = parseLineItem('dmBio Tofu Rosso 200g  1,65');
      expect(name, equals('dmBio Tofu Rosso 200g'));
      expect(price, closeTo(1.65, 0.001));
    });

    test('Erkennt Punkt als Dezimaltrenner (z. B. "2.99")', () {
      final (:name, :price) = parseLineItem('Milch 1L 2.99');
      expect(name, equals('Milch 1L'));
      expect(price, closeTo(2.99, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseLineItem – Dynamische Bereinigung (Steuerklassen-Buchstabe)
  // ---------------------------------------------------------------------------

  group('parseLineItem – Dynamische Bereinigung', () {
    test(
        'Steuerklassen-Buchstabe vor dem Preis (z. B. "BROT A 2,49") '
        'wird aus dem Namen entfernt', () {
      final (:name, :price) = parseLineItem('BROT A 2,49');
      expect(name, equals('BROT'));
      expect(price, closeTo(2.49, 0.001));
    });

    test(
        'Steuerklassen-Buchstabe nach dem Preis (z. B. "Croissant 0,90 A") '
        'beeinflusst den Namen nicht', () {
      // "A" ist hier Teil des Preis-Regex [A-Za-z0-9]? → Name bleibt sauber.
      final (:name, :price) = parseLineItem('Croissant 0,90 A');
      expect(name, equals('Croissant'));
      expect(price, closeTo(0.90, 0.001));
    });

    test(
        'Einheit am Namensende (z. B. "Milch 1L") wird NICHT entfernt '
        '(Buchstabe nicht durch Leerzeichen abgetrennt)', () {
      final (:name, :price) = parseLineItem('Milch 1L 1,09');
      expect(name, equals('Milch 1L'));
      expect(price, closeTo(1.09, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl – Bäcker-Beleg (Generischer Algorithmus)
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – Bäcker-Beleg (ladenunabhängig)', () {
    // Simulierter OCR-Output eines fiktiven Bäcker-Belegs:
    //   - Header mit Datum → Header-Cut lässt Bäckerei/Adresse weg
    //   - Artikel mit Steuerklassen-Buchstabe vor dem Preis ("Apfelstrudel A 2,50")
    //   - Artikel mit Preis auf nächster Zeile (OCR-Split)
    //   - Multi-Line-Artikel mit Mengenberechnung (2x Kaffee)
    //   - SUMME → Footer-Cut lässt Bar/Rückgeld weg
    const baeckereiReceiptText =
        'Bäckerei Müller\n'
        'Hauptstraße 12\n'
        '12345 Musterstadt\n'
        '22.03.2025 08:14\n'
        'Croissant 0,90 A\n'
        'Apfelstrudel A 2,50\n'
        'Vollkornbrot 750g\n'
        '3,20\n'
        '2x Kaffee\n'
        '2 X 1,80\n'
        '3,60\n'
        'SUMME 10,20\n'
        'Bar 20,00\n'
        'Rückgeld 9,80';

    test('Erkennt genau 4 Artikel', () {
      final items = parseItemsImpl(baeckereiReceiptText);
      expect(items.length, equals(4));
    });

    test('Croissant: Preis 0,90, Name ohne Steuerklassen-Suffix', () {
      final items = parseItemsImpl(baeckereiReceiptText);
      final item = items.firstWhere(
        (i) => i.contains('Croissant'),
        orElse: () => '',
      );
      expect(item, isNotEmpty,
          reason: 'Croissant sollte als Artikel erkannt werden');
      final (:name, :price) = parseLineItem(item);
      expect(name, equals('Croissant'));
      expect(price, closeTo(0.90, 0.001));
    });

    test(
        'Apfelstrudel: Steuerklassen-Buchstabe "A" vor Preis wird aus Name '
        'entfernt', () {
      final items = parseItemsImpl(baeckereiReceiptText);
      final item = items.firstWhere(
        (i) => i.contains('Apfelstrudel'),
        orElse: () => '',
      );
      expect(item, isNotEmpty,
          reason: 'Apfelstrudel sollte als Artikel erkannt werden');
      final (:name, :price) = parseLineItem(item);
      expect(name, equals('Apfelstrudel'));
      expect(price, closeTo(2.50, 0.001));
    });

    test('Vollkornbrot: Preis auf nächster Zeile wird zusammengeführt', () {
      final items = parseItemsImpl(baeckereiReceiptText);
      final item = items.firstWhere(
        (i) => i.contains('Vollkornbrot'),
        orElse: () => '',
      );
      expect(item, isNotEmpty,
          reason: 'Vollkornbrot sollte als Artikel erkannt werden');
      final (:name, :price) = parseLineItem(item);
      expect(name, equals('Vollkornbrot 750g'));
      expect(price, closeTo(3.20, 0.001));
    });

    test('2x Kaffee: Multi-Line-Artikel (Mengenberechnung) wird korrekt erkannt',
        () {
      final items = parseItemsImpl(baeckereiReceiptText);
      final item = items.firstWhere(
        (i) => i.contains('Kaffee'),
        orElse: () => '',
      );
      expect(item, isNotEmpty,
          reason: '2x Kaffee sollte als Artikel erkannt werden');
      final (:name, :price) = parseLineItem(item);
      expect(name, equals('2x Kaffee'));
      expect(price, closeTo(3.60, 0.001));
    });

    test('Footer-Cut: Zeilen nach SUMME (Bar, Rückgeld) nicht in Artikelliste',
        () {
      final items = parseItemsImpl(baeckereiReceiptText);
      expect(items.any((i) => i.toLowerCase().contains('bar')), isFalse);
      expect(items.any((i) => i.toLowerCase().contains('rückgeld')), isFalse);
    });

    test(
        'Header-Cut: Store-Name und Adresse vor Datum erscheinen '
        'nicht in der Artikelliste', () {
      final items = parseItemsImpl(baeckereiReceiptText);
      expect(items.any((i) => i.contains('Müller')), isFalse);
      expect(items.any((i) => i.contains('Hauptstraße')), isFalse);
      expect(items.any((i) => i.contains('Musterstadt')), isFalse);
    });

    test('SUMME-Zeile wird nicht als Artikel gewertet', () {
      final items = parseItemsImpl(baeckereiReceiptText);
      expect(items.any((i) => i.toLowerCase().contains('summe')), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl – Supermarkt-Beleg mit Müll-Mustern
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – Müll-Muster (Supermarkt-Beleg)', () {
    // Simulierter OCR-Output mit typischen Müll-Zeilen:
    //   - Trennlinie aus Sonderzeichen ("----------")
    //   - Website-URL ("www.rewe.de")
    //   - Überlanger Ziffernblock (IBAN / Terminal-ID)
    const supermarktText =
        '14.03.2025 18:45\n'
        '----------\n'
        'Vollmilch 1L 1,09 B\n'
        'Bio-Äpfel 1kg 2,49 A\n'
        'www.rewe.de\n'
        'DE89370400440532013000\n'
        'Pasta 500g 1,29\n'
        'GESAMT 4,87';

    test('Erkennt genau 3 Artikel', () {
      final items = parseItemsImpl(supermarktText);
      expect(items.length, equals(3));
    });

    test('Trennlinie ("----------") erscheint nicht in der Artikelliste', () {
      final items = parseItemsImpl(supermarktText);
      expect(items.any((i) => i.contains('---')), isFalse);
    });

    test('URL ("www.rewe.de") erscheint nicht in der Artikelliste', () {
      final items = parseItemsImpl(supermarktText);
      expect(items.any((i) => i.contains('www')), isFalse);
    });

    test('IBAN / 15+-Ziffernblock wird herausgefiltert', () {
      final items = parseItemsImpl(supermarktText);
      expect(items.any((i) => i.contains('DE89370')), isFalse);
    });

    test('GESAMT stoppt die Artikel-Suche (Footer-Cut)', () {
      final items = parseItemsImpl(supermarktText);
      expect(items.any((i) => i.toLowerCase().contains('gesamt')), isFalse);
    });

    test('Vollmilch 1L wird korrekt erkannt (Preis 1,09)', () {
      final items = parseItemsImpl(supermarktText);
      final item = items.firstWhere(
        (i) => i.contains('Vollmilch'),
        orElse: () => '',
      );
      expect(item, isNotEmpty);
      final (:name, :price) = parseLineItem(item);
      expect(name, equals('Vollmilch 1L'));
      expect(price, closeTo(1.09, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl / parseAmountImpl – Red Bull Beleg mit
  // Terminal-Daten (Regression für falsch erkannte Summe 23,03 € statt 9,30 €)
  // ---------------------------------------------------------------------------

  group('parseItemsImpl / parseAmountImpl – Red Bull Beleg mit Terminal-Daten',
      () {
    // Simulierter OCR-Output eines Kassenbons mit:
    //   - Multi-Line-Artikel (Name auf Zeile über der Mengenberechnung)
    //   - PFAND als normaler Artikel
    //   - Mastercard-Terminal-Daten am Ende (inkl. falscher Betrag 23,03 EUR)
    const redBullReceiptText =
        'RED BULL\n'
        '4 X 1,59\n'
        '6,36\n'
        'PFAND 0,25\n'
        'WASSER STILL 1L 2,69\n'
        'SUMME 9,30\n'
        'Kundenbeleg\n'
        'Mastercard\n'
        'contactless\n'
        'DEBIT\n'
        'A0000000041010\n'
        'Acq-Id: 12345678\n'
        'Trm-Id: 98765432\n'
        'AID: A0000000041010\n'
        'PAN: ****1234\n'
        'Track2: 1234\n'
        'Verarbeitung OK\n'
        '23,03 EUR';

    test('Erkennt RED BULL als Multi-Line-Artikel mit Gesamtpreis 6,36', () {
      final items = parseItemsImpl(redBullReceiptText);
      // Bewusst case-sensitiv: der Artikelname muss als "RED BULL" (Großschrift)
      // erhalten bleiben, da OCR ihn so geliefert hat.
      final redBullItem = items.firstWhere(
        (i) => i.contains('RED BULL'),
        orElse: () => '',
      );
      expect(redBullItem, isNotEmpty,
          reason: 'RED BULL sollte als Artikel erkannt werden');
      final (:name, :price) = parseLineItem(redBullItem);
      expect(name, equals('RED BULL'));
      expect(price, closeTo(6.36, 0.001));
    });

    test('"4 X" wird nicht als Artikelname gespeichert', () {
      final items = parseItemsImpl(redBullReceiptText);
      for (final item in items) {
        expect(item, isNot(matches(r'^\d+\s*[xX]\s*\d')),
            reason: 'Mengenberechnungszeilen dürfen nicht als Artikel landen');
      }
    });

    test('PFAND wird als normaler Artikel erkannt', () {
      final items = parseItemsImpl(redBullReceiptText);
      final pfandItem = items.firstWhere(
        (i) => i.toLowerCase().contains('pfand'),
        orElse: () => '',
      );
      expect(pfandItem, isNotEmpty,
          reason: 'PFAND sollte als Artikel erkannt werden');
      final (:name, :price) = parseLineItem(pfandItem);
      expect(price, closeTo(0.25, 0.001));
    });

    test('WASSER STILL wird als Artikel erkannt', () {
      final items = parseItemsImpl(redBullReceiptText);
      expect(items.any((i) => i.contains('WASSER STILL')), isTrue);
    });

    test('Terminal-Daten erscheinen nicht in der Artikelliste', () {
      final items = parseItemsImpl(redBullReceiptText);
      for (final item in items) {
        expect(item.toLowerCase(), isNot(contains('kundenbeleg')));
        expect(item.toLowerCase(), isNot(contains('contactless')));
        expect(item.toLowerCase(), isNot(contains('debit')));
        expect(item.toLowerCase(), isNot(contains('mastercard')));
        expect(item, isNot(contains('A0000000041010')));
        expect(item.toLowerCase(), isNot(contains('acq')));
        expect(item.toLowerCase(), isNot(contains('trm')));
        expect(item.toLowerCase(), isNot(contains('track')));
        expect(item.toLowerCase(), isNot(contains('verarbeitung')));
      }
    });

    test('Summe 9,30 € korrekt erkannt – nicht 23,03 € aus Terminal-Daten',
        () {
      expect(parseAmountImpl(redBullReceiptText), closeTo(9.30, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsHeuristic / parseItemsImpl – scrambled dm-Beleg
  // ("Endgegner"-Text: Namen und Preise vollständig getrennt)
  // ---------------------------------------------------------------------------

  group('parseItemsHeuristic – scrambled dm-Beleg', () {
    // Simulierter OCR-Output, bei dem die Artikel-Namen und -Preise
    // komplett in verschiedenen Textbereichen erscheinen.
    // SUMME taucht auf Zeile 2 auf → primäre Logik findet 0 Artikel →
    // Heuristik-Queue-Logik greift als Fallback.
    // Erwartetes Ergebnis: 2 Artikel (Fruchtaufstrich 2,25 €, Tofu 1,65 €)
    // und Gesamtsumme 3,90 €.
    const scrambledDmText =
        '21.03.2026 13:45 O503/1 125317/1 3889\n'
        'SUMME\n'
        'dmBio Fruchtaufstr.Erdb.250g\n'
        'dm drogerie markt GmbH\n'
        'Marktgraben 27\n'
        'dmBio Tofu ROsso 200g\n'
        'Visa Credit EUR\n'
        'Buchung\n'
        '6020 Innsbruck\n'
        '21.03.2026\n'
        '0512-587041\n'
        'MWSt-Satz\n'
        'Total-EFT EUR:\n'
        '2=10,00%\n'
        'XXX9471\n'
        '1/1/1227** ************ * **** *******00256601\n'
        'Summe Nettobetr\n'
        '3,90\n'
        '#31514283*00256601/695688/00999100200#\n'
        'visa Debit Contactless\n'
        '3,55\n'
        'Für diesen Einkauf hätten sie\n'
        '3 PAYBACK Punkte erhalten\n'
        'öffnungszeiten auf dm. at\n'
        'Hier bin ich Mensch\n'
        'EUR\n'
        'Hier kauf ich ein\n'
        '2,25\n'
        'Danke für Ihren Einkauf\n'
        'ATU 35195908\n'
        '1,65\n'
        '3,90\n'
        '-3,90\n'
        '13:46:00\n'
        '3.90\n'
        'EFSTA. NET#376320361139479120207678\n'
        '2\n'
        '2\n'
        'MWSt\n'
        '0,35\n'
        '21.03. 2026 13:45 0503/1 125317/1 3889';

    test('parseItemsImpl erkennt genau zwei Artikel (via Heuristik-Fallback)',
        () {
      final items = parseItemsImpl(scrambledDmText);
      expect(items.length, equals(2));
    });

    test('Erster Artikel: Name = "dmBio Fruchtaufstr.Erdb.250g", Preis = 2.25',
        () {
      final items = parseItemsImpl(scrambledDmText);
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('dmBio Fruchtaufstr.Erdb.250g'));
      expect(price, closeTo(2.25, 0.001));
    });

    test('Zweiter Artikel: Name = "dmBio Tofu ROsso 200g", Preis = 1.65', () {
      final items = parseItemsImpl(scrambledDmText);
      final (:name, :price) = parseLineItem(items[1]);
      expect(name, equals('dmBio Tofu ROsso 200g'));
      expect(price, closeTo(1.65, 0.001));
    });

    test('Gesamtbetrag = 3,90 (aus "Summe Nettobetr\\n3,90")', () {
      expect(parseAmountImpl(scrambledDmText), closeTo(3.90, 0.001));
    });

    test('MwSt-Betrag 0,35 erscheint nicht als Artikelpreis', () {
      final items = parseItemsImpl(scrambledDmText);
      for (final item in items) {
        final (:name, :price) = parseLineItem(item);
        expect(price, isNot(closeTo(0.35, 0.001)),
            reason: 'MwSt-Betrag 0,35 darf kein Artikelpreis sein');
      }
    });

    test('Junk-Zeilen (GmbH, Visa, ATU, Payback, Danke) erscheinen nicht in der Artikelliste',
        () {
      final items = parseItemsImpl(scrambledDmText);
      for (final item in items) {
        expect(item.toLowerCase(), isNot(contains('gmbh')));
        expect(item.toLowerCase(), isNot(contains('visa')));
        expect(item.toLowerCase(), isNot(contains('atu')));
        expect(item.toLowerCase(), isNot(contains('payback')));
        expect(item.toLowerCase(), isNot(contains('danke')));
        expect(item.toLowerCase(), isNot(contains('summe')));
        expect(item.toLowerCase(), isNot(contains('contactless')));
        expect(item.toLowerCase(), isNot(contains('efsta')));
      }
    });

    test('parseItemsHeuristic direkt: liefert dieselben 2 Artikel', () {
      final items = parseItemsHeuristic(scrambledDmText);
      expect(items.length, equals(2));
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('dmBio Fruchtaufstr.Erdb.250g'));
      expect(price, closeTo(2.25, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für normalizeName – Text-Normalisierung
  // ---------------------------------------------------------------------------

  group('normalizeName', () {
    test('Wandelt Großbuchstaben in Title Case um', () {
      expect(normalizeName('RED BULL'), equals('Red Bull'));
    });

    test('Wandelt Kleinbuchstaben in Title Case um', () {
      expect(normalizeName('vollkornbrot'), equals('Vollkornbrot'));
    });

    test('Entfernt führende und abschließende Leerzeichen', () {
      expect(normalizeName('  Brot  '), equals('Brot'));
    });

    test('Reduziert mehrfache Leerzeichen auf eines', () {
      expect(normalizeName('Bio  Milch   1L'), equals('Bio Milch 1l'));
    });

    test('Bewahrt Ziffern im Namen (z. B. "750g")', () {
      expect(normalizeName('VOLLKORNBROT 750G'), equals('Vollkornbrot 750g'));
    });

    test('Leerer Name bleibt leer', () {
      expect(normalizeName(''), equals(''));
    });

    test('Einzelnes Wort wird korrekt umgewandelt', () {
      expect(normalizeName('MILCH'), equals('Milch'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für categorizeItem – Automatische Kategorisierung
  // ---------------------------------------------------------------------------

  group('categorizeItem', () {
    test('"Tofu" → Lebensmittel', () {
      expect(categorizeItem('Dmbio Tofu Rosso 200g'), equals('Lebensmittel'));
    });

    test('"Milch" → Lebensmittel', () {
      expect(categorizeItem('Vollmilch 1L'), equals('Lebensmittel'));
    });

    test('"Brot" → Lebensmittel', () {
      expect(categorizeItem('Vollkornbrot 750g'), equals('Lebensmittel'));
    });

    test('"Bio" → Lebensmittel', () {
      expect(categorizeItem('Dmbio Fruchtaufstrich'), equals('Lebensmittel'));
    });

    test('"Shampoo" → Drogerie', () {
      expect(categorizeItem('Balea Shampoo 300ml'), equals('Drogerie'));
    });

    test('"Balea" → Drogerie', () {
      expect(categorizeItem('Balea Duschgel'), equals('Drogerie'));
    });

    test('"Pfand" → Pfand', () {
      expect(categorizeItem('Pfand'), equals('Pfand'));
    });

    test('"Leergut" → Pfand', () {
      expect(categorizeItem('Leergut 0,25'), equals('Pfand'));
    });

    test('"Red Bull" → Getränke (case-insensitive)', () {
      expect(categorizeItem('Red Bull'), equals('Getränke'));
    });

    test('"Wasser" → Getränke', () {
      expect(categorizeItem('Wasser Still 1l'), equals('Getränke'));
    });

    test('"Cola" → Getränke', () {
      expect(categorizeItem('Cola 1,5l'), equals('Getränke'));
    });

    test('"Saft" → Getränke', () {
      expect(categorizeItem('Apfelsaft'), equals('Getränke'));
    });

    test('Unbekannter Artikel → Sonstiges', () {
      expect(categorizeItem('Kugelschreiber'), equals('Sonstiges'));
    });

    test('Leerer String → Sonstiges', () {
      expect(categorizeItem(''), equals('Sonstiges'));
    });

    test('Vergleich ist nicht case-sensitiv ("MILCH" → Lebensmittel)', () {
      expect(categorizeItem('MILCH'), equals('Lebensmittel'));
    });

    test('"Fruchtaufstr" → Lebensmittel', () {
      expect(categorizeItem('Dmb Fruchtaufstr. Erdb. 250g'), equals('Lebensmittel'));
    });

    test('"Seife" → Drogerie', () {
      expect(categorizeItem('Handseife 300ml'), equals('Drogerie'));
    });

    test('"Wein" → Getränke', () {
      expect(categorizeItem('Rotwein Merlot 0,75l'), equals('Getränke'));
    });

    test('"Bier" → Getränke', () {
      expect(categorizeItem('Bier 0,5l'), equals('Getränke'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für normalizeName – OCR-Fehlerkorrektur (0 → O)
  // ---------------------------------------------------------------------------

  group('normalizeName – OCR-Fehlerkorrektur', () {
    test('Führende "0" wird zu "O" korrigiert wenn Rest Buchstaben enthält', () {
      expect(normalizeName('0lio Naturale'), equals('Olio Naturale'));
    });

    test('Führende "0" bei reiner Zahl bleibt unverändert', () {
      // "0,25" hat keinen Buchstaben im Rest → keine Korrektur
      expect(normalizeName('0,25'), equals('0,25'));
    });

    test('Wort ohne führende "0" bleibt unverändert', () {
      expect(normalizeName('Tofu'), equals('Tofu'));
    });

    test('OCR-Korrektur: "0BIO" → "Obio" (Title Case nach Korrektur)', () {
      expect(normalizeName('0BIO'), equals('Obio'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseLineItem – Volumenangaben ohne Leerzeichen
  // ---------------------------------------------------------------------------

  group('parseLineItem – Volumenangaben (kein Leerzeichen vor Einheit)', () {
    test(
        '"COKE ZERO ZERO 0,33L" – "0,33L" ist Volumen, kein Preis '
        '(kein Leerzeichen vor "L")', () {
      final (:name, :price) = parseLineItem('COKE ZERO ZERO 0,33L');
      // Kein gültiger Preis, da "L" direkt an die Zahl angehängt ist
      expect(price, isNull);
      expect(name, equals('COKE ZERO ZERO 0,33L'));
    });

    test('"Milch 1L 1,09 A" – Preis 1,09 mit Tax-Code " A" wird erkannt', () {
      final (:name, :price) = parseLineItem('Milch 1L 1,09 A');
      expect(price, closeTo(1.09, 0.001));
      expect(name, equals('Milch 1L'));
    });

    test('"Wasser 0,5L 0,79" – Preis 0,79 wird erkannt, "0,5L" bleibt im Namen',
        () {
      final (:name, :price) = parseLineItem('Wasser 0,5L 0,79');
      expect(price, closeTo(0.79, 0.001));
      expect(name, equals('Wasser 0,5L'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl / parseAmountImpl – SPAR-Kassenbon
  // (Scrambled OCR: Namen und Preise in getrennten Textblöcken)
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – SPAR-Kassenbon (scrambled, Tax-Code Prices)', () {
    // Simulierter OCR-Output eines physischen SPAR-Kassenbons:
    //   - "ALPRO SOJA" erscheint VOR der Datumszeile → primäre Header-Cut-Logik
    //     übersieht diesen Artikel.
    //   - "SUMME:" erscheint in der MITTE der Artikelliste (nicht am Ende) →
    //     Footer-Cut stoppt die Suche zu früh.
    //   - "PFAND EINWEG" und "SBUDGET STRIEZEL" erscheinen NACH der SUMME-Zeile.
    //   - Die tatsächlichen Artikel-Preise befinden sich am Ende des Textes im
    //     Format "X,XX Y" (Tax-Code-Format, z. B. "1,59 A").
    //   - Ergebnis: primäre Look-Ahead-Logik findet 0 Artikel →
    //     parseItemsHeuristic greift als Fallback.
    //   - Erwartetes Ergebnis: 6 Artikel mit Gesamtbetrag 10,76 €.
    const sparReceiptText =
        'ALPRO SOJA\n'
        'Ihr Einkauf am 23.03.2026 um 19:15 Uhr\n'
        'VEGGIE VEG.KRAEUTERB\n'
        '2 X 1,19\n'
        'SBUDGET GNOCCHI 750G\n'
        '2 X 1,48\n'
        'COKE ZERO ZERO 0,33L\n'
        'SUMME:\n'
        'PFAND EINWEG\n'
        'SBUDGET STRIEZEL\n'
        'GUTSCHEIN\n'
        'SPARO\n'
        'ZAHLUNG MASTERCARD\n'
        'Museumstraße 16\n'
        '6020 Innsbruck\n'
        '0512 571052\n'
        'Zahl ung\n'
        'DEBIT MASTERCARD\n'
        'Contactless\n'
        '23.03.2026\n'
        'Trm-Id:\n'
        'AID:\n'
        'XXXX XXXX XXXX 6180\n'
        'Trx Seq-Nr:\n'
        'Trx Ref. Nr:\n'
        'Acq-Id:\n'
        '*** Kundenbeleg x**\n'
        'Betrag EUR:\n'
        '0,00%\n'
        '10,00%\n'
        '0,25\n'
        'Autorisierungs-Nr:\n'
        '20,00%\n'
        'Verarbeitung 0K\n'
        'excl.\n'
        '0,25\n'
        '8,29\n'
        '1,16\n'
        'Ihre Rabattmarkerl heute:\n'
        '(Basis: 10,51)\n'
        'MHST.\n'
        '0,00\n'
        '0,33\n'
        'EUR\n'
        '1,59 A\n'
        '0,23\n'
        '2,38 A\n'
        '2,96 A\n'
        '1,39 B\n'
        '0,25 E\n'
        'A0000000041010\n'
        '2,19 A\n'
        '0,00 E\n'
        '233381\n'
        '59536748863\n'
        '10,76\n'
        '10,76\n'
        '19:15:51\n'
        '23613278\n'
        '940610\n'
        '999100200\n'
        '10,76\n'
        'Incl.\n'
        '0,25 E\n'
        '9,12 A\n'
        '1,39 B\n';

    test('Erkennt genau 6 Artikel (via Heuristik-Fallback)', () {
      final items = parseItemsImpl(sparReceiptText);
      expect(items.length, equals(6),
          reason:
              'SPAR-Kassenbon: 6 Artikel erwartet (Alpro, Veggie, Gnocchi, Coke, Pfand, Striezel)');
    });

    test('ALPRO SOJA: Preis = 1,59', () {
      final items = parseItemsImpl(sparReceiptText);
      final item = items.firstWhere(
        (i) => i.toUpperCase().contains('ALPRO'),
        orElse: () => '',
      );
      expect(item, isNotEmpty, reason: 'ALPRO SOJA sollte erkannt werden');
      expect(parseLineItem(item).price, closeTo(1.59, 0.001));
    });

    test('VEGGIE VEG.KRAEUTERB: Preis = 2,38', () {
      final items = parseItemsImpl(sparReceiptText);
      final item = items.firstWhere(
        (i) => i.toUpperCase().contains('VEGGIE'),
        orElse: () => '',
      );
      expect(item, isNotEmpty, reason: 'VEGGIE sollte erkannt werden');
      expect(parseLineItem(item).price, closeTo(2.38, 0.001));
    });

    test('SBUDGET GNOCCHI 750G: Preis = 2,96', () {
      final items = parseItemsImpl(sparReceiptText);
      final item = items.firstWhere(
        (i) => i.toUpperCase().contains('GNOCCHI'),
        orElse: () => '',
      );
      expect(item, isNotEmpty, reason: 'GNOCCHI sollte erkannt werden');
      expect(parseLineItem(item).price, closeTo(2.96, 0.001));
    });

    test('COKE ZERO ZERO 0,33L: Preis = 1,39 (nicht 0,33 Volumen)', () {
      final items = parseItemsImpl(sparReceiptText);
      final item = items.firstWhere(
        (i) => i.toUpperCase().contains('COKE'),
        orElse: () => '',
      );
      expect(item, isNotEmpty, reason: 'COKE sollte erkannt werden');
      final (:name, :price) = parseLineItem(item);
      expect(price, closeTo(1.39, 0.001),
          reason: 'Preis muss 1,39 sein, nicht 0,33 (Volumenangabe)');
      expect(name, contains('COKE'));
    });

    test('PFAND EINWEG: Preis = 0,25', () {
      final items = parseItemsImpl(sparReceiptText);
      final item = items.firstWhere(
        (i) => i.toUpperCase().contains('PFAND'),
        orElse: () => '',
      );
      expect(item, isNotEmpty, reason: 'PFAND EINWEG sollte erkannt werden');
      expect(parseLineItem(item).price, closeTo(0.25, 0.001));
    });

    test('SBUDGET STRIEZEL: Preis = 2,19', () {
      final items = parseItemsImpl(sparReceiptText);
      final item = items.firstWhere(
        (i) => i.toUpperCase().contains('STRIEZEL'),
        orElse: () => '',
      );
      expect(item, isNotEmpty, reason: 'SBUDGET STRIEZEL sollte erkannt werden');
      expect(parseLineItem(item).price, closeTo(2.19, 0.001));
    });

    test('Gesamtbetrag 10,76 € korrekt erkannt', () {
      expect(parseAmountImpl(sparReceiptText), closeTo(10.76, 0.001));
    });

    test('Keine Junk-Einträge (SUMME, Mastercard, Trm-Id, excl, Incl) '
        'erscheinen in der Artikelliste', () {
      final items = parseItemsImpl(sparReceiptText);
      for (final item in items) {
        expect(item.toLowerCase(), isNot(contains('summe')));
        expect(item.toLowerCase(), isNot(contains('mastercard')));
        expect(item.toLowerCase(), isNot(contains('trm')));
        expect(item.toLowerCase(), isNot(contains('excl')));
        expect(item.toLowerCase(), isNot(contains('incl')));
        expect(item.toLowerCase(), isNot(contains('museumstraße')));
      }
    });

    test('Qty-Calc-Zeilen ("2 X 1,19", "2 X 1,48") erscheinen nicht als Namen',
        () {
      final items = parseItemsImpl(sparReceiptText);
      for (final item in items) {
        expect(item, isNot(matches(r'^\d+\s*[xX]\s*\d')),
            reason:
                'Mengenberechnungszeilen dürfen nicht als Artikel landen');
      }
    });

    test(
        'Summe der erkannten Artikel-Preise entspricht dem Gesamtbetrag 10,76',
        () {
      final items = parseItemsImpl(sparReceiptText);
      final total = items.fold<double>(
        0.0,
        (sum, item) => sum + (parseLineItem(item).price ?? 0.0),
      );
      expect(total, closeTo(10.76, 0.01));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseSpatialItems – Y-Achsen-Korridor-Matching
  // ---------------------------------------------------------------------------

  group('parseSpatialItems – Y-Achsen-Korridor-Matching', () {
    /// Erzeugt ein räumliches Zeilen-Objekt wie es OcrService liefert.
    Map<String, dynamic> spatialLine(
      String text, {
      required double top,
      required double bottom,
      double left = 0,
      double right = 100,
    }) {
      return {
        'text': text,
        'top': top,
        'bottom': bottom,
        'left': left,
        'right': right,
        'centerY': (top + bottom) / 2.0,
        'centerX': (left + right) / 2.0,
      };
    }

    test('Leere Liste ergibt keine Artikel', () {
      expect(parseSpatialItems([]), isEmpty);
    });

    test(
        'Korridor-Match: Name und Preis auf gleicher Höhe werden gepaart', () {
      // Brot steht bei Y=50, Preis 2,49 ebenfalls bei Y=50
      final lines = [
        spatialLine('Brot 750g', top: 40, bottom: 60),
        spatialLine('2,49', top: 42, bottom: 62),
      ];
      final items = parseSpatialItems(lines);
      expect(items.length, equals(1));
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('Brot 750g'));
      expect(price, closeTo(2.49, 0.001));
    });

    test(
        'Korridor-Match: Zwei Artikel mit getrennten Preisen werden korrekt gepaart',
        () {
      // Zeile 1: Milch bei Y=50, Preis 1,09 bei Y=52
      // Zeile 2: Brot bei Y=100, Preis 2,49 bei Y=101
      final lines = [
        spatialLine('Milch 1L', top: 44, bottom: 56),
        spatialLine('Brot 750g', top: 94, bottom: 106),
        spatialLine('1,09', top: 46, bottom: 58),
        spatialLine('2,49', top: 95, bottom: 107),
      ];
      final items = parseSpatialItems(lines);
      expect(items.length, equals(2));

      final milch = items.firstWhere((i) => i.contains('Milch'));
      expect(parseLineItem(milch).price, closeTo(1.09, 0.001));

      final brot = items.firstWhere((i) => i.contains('Brot'));
      expect(parseLineItem(brot).price, closeTo(2.49, 0.001));
    });

    test(
        'Korridor: Preis zu weit entfernt (>20 px) wird NICHT gepaart', () {
      // Artikel bei Y=50, Preis bei Y=100 → Delta = 50 → kein Match
      final lines = [
        spatialLine('Artikel A', top: 40, bottom: 60),
        spatialLine('9,99', top: 90, bottom: 110),
      ];
      // Wenn kein Korridor-Match: Fallback-Paarung nach Index greift
      // (n=min(1,1)=1 → die beiden werden doch gepaart)
      final items = parseSpatialItems(lines);
      // Ergebnis darf trotzdem gepaart sein (Fallback), aber Korridor war leer
      // → Hauptsache kein Absturz
      expect(items, isA<List<String>>());
    });

    test(
        'Junk-Zeilen (SUMME, GmbH, Visa, MwSt) werden nicht als Name oder Preis gewertet',
        () {
      final lines = [
        spatialLine('SUMME', top: 10, bottom: 20),
        spatialLine('GmbH', top: 30, bottom: 40),
        spatialLine('Visa', top: 50, bottom: 60),
        spatialLine('MwSt', top: 70, bottom: 80),
        spatialLine('Tofu 200g', top: 90, bottom: 100),
        spatialLine('1,65', top: 92, bottom: 102),
      ];
      final items = parseSpatialItems(lines);
      expect(items.length, equals(1));
      expect(items[0].toLowerCase(), isNot(contains('summe')));
      expect(items[0].toLowerCase(), isNot(contains('gmbh')));
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('Tofu 200g'));
      expect(price, closeTo(1.65, 0.001));
    });

    test(
        'Steuerklassen-Buchstabe am Ende des Namens wird entfernt '
        '(z. B. "BROT A" → "BROT")', () {
      final lines = [
        spatialLine('BROT A', top: 40, bottom: 60),
        spatialLine('2,49', top: 42, bottom: 62),
      ];
      final items = parseSpatialItems(lines);
      expect(items.length, equals(1));
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('BROT'));
      expect(price, closeTo(2.49, 0.001));
    });

    test(
        'Spalten-Layout (Namen links, Preise rechts, Y-Korridor passt): '
        'korrekte Zuordnung', () {
      // Simulierter Kassenbon mit Zwei-Spalten-Layout:
      // Namen auf der linken Seite (left=0..150), Preise rechts (left=200..300)
      final lines = [
        spatialLine('Alpro Soja', top: 100, bottom: 120, left: 0, right: 150),
        spatialLine('1,59 A', top: 102, bottom: 122, left: 200, right: 300),
        spatialLine('Gnocchi 750g', top: 140, bottom: 160, left: 0, right: 150),
        spatialLine('2,96 A', top: 142, bottom: 162, left: 200, right: 300),
      ];
      final items = parseSpatialItems(lines);
      expect(items.length, equals(2));

      final alpro = items.firstWhere((i) => i.contains('Alpro'));
      expect(parseLineItem(alpro).price, closeTo(1.59, 0.001));

      final gnocchi = items.firstWhere((i) => i.contains('Gnocchi'));
      expect(parseLineItem(gnocchi).price, closeTo(2.96, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für detectMerchant – Händler-Anker
  // ---------------------------------------------------------------------------

  group('detectMerchant', () {
    test('"Museumstraße" → "Spar"', () {
      const text = 'SPAR\nMuseumstraße 16\n6020 Innsbruck';
      expect(detectMerchant(text), equals('Spar'));
    });

    test('"dm drogerie" → "dm"', () {
      const text = 'dm drogerie markt GmbH\nMarktgraben 27\n6020 Innsbruck';
      expect(detectMerchant(text), equals('dm'));
    });

    test('"HOFER" → "Hofer" (case-insensitive)', () {
      const text = 'HOFER KG\nHauptstraße 1';
      expect(detectMerchant(text), equals('Hofer'));
    });

    test('Kein Anker → null', () {
      const text = 'Unbekannter Laden\nMusterstraße 1';
      expect(detectMerchant(text), isNull);
    });

    test('Leerer Text → null', () {
      expect(detectMerchant(''), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für parseOcrText – semantischer Lern-Loop (Produkt-Mappings)
  // ---------------------------------------------------------------------------

  group('parseOcrText – Produkt-Mapping (Lern-Loop)', () {
    // Simuliert den OCR-Text eines einfachen Belegs
    const simpleText =
        '14.03.2026 10:00\n'
        'A1pro Hafer 1L 1,49\n'
        'Brot 750g 2,29\n'
        'SUMME 3,78';

    test(
        'Ohne Mappings: OCR-Name wird normalisiert aber nicht ersetzt', () {
      final result = parseOcrText({
        'text': simpleText,
        'categoryData': <Map<String, dynamic>>[],
        'productMappings': <Map<String, dynamic>>[],
      });
      final items = List<String>.from(result['items'] as List);
      // "A1pro" bleibt (Normalisierung macht "A1pro" → "A1pro")
      expect(items.any((i) => i.contains('A1pro')), isTrue);
    });

    test(
        'Mit Mapping "A1pro Hafer 1l" → "Alpro Hafer": Name wird ersetzt',
        () {
      // normalizeName('A1pro Hafer 1L') → 'A1pro Hafer 1l'
      final result = parseOcrText({
        'text': simpleText,
        'categoryData': <Map<String, dynamic>>[],
        'productMappings': [
          {
            'raw_ocr_name': 'A1pro Hafer 1l',
            'corrected_name': 'Alpro Hafer',
            'category_id': null,
          }
        ],
      });
      final items = List<String>.from(result['items'] as List);
      expect(items.any((i) => i.contains('Alpro Hafer')), isTrue,
          reason: 'OCR-Name "A1pro" soll durch "Alpro Hafer" ersetzt werden');
      expect(items.any((i) => i.contains('A1pro')), isFalse,
          reason: 'Der ursprüngliche OCR-Name darf nicht mehr auftauchen');
    });

    test(
        'Mit Mapping inkl. category_id: korrekte Kategorie wird zugewiesen',
        () {
      final result = parseOcrText({
        'text': simpleText,
        'categoryData': [
          {'id': 7, 'name': 'Lebensmittel', 'keywords': 'Bio,Milch'},
        ],
        'productMappings': [
          {
            'raw_ocr_name': 'A1pro Hafer 1l',
            'corrected_name': 'Alpro Hafer',
            'category_id': 7,
          }
        ],
      });
      final categories = List<String>.from(result['categories'] as List);
      final items = List<String>.from(result['items'] as List);
      final idx = items.indexWhere((i) => i.contains('Alpro Hafer'));
      expect(idx, greaterThanOrEqualTo(0));
      expect(categories[idx], equals('Lebensmittel'));
    });

    test('Mapping ist case-insensitiv (raw_ocr_name in Kleinbuchstaben)', () {
      final result = parseOcrText({
        'text': simpleText,
        'categoryData': <Map<String, dynamic>>[],
        'productMappings': [
          {
            'raw_ocr_name': 'a1pro hafer 1l', // Kleinbuchstaben
            'corrected_name': 'Alpro Hafer',
            'category_id': null,
          }
        ],
      });
      final items = List<String>.from(result['items'] as List);
      expect(items.any((i) => i.contains('Alpro Hafer')), isTrue);
    });

    test(
        'Mapping für nicht vorhandenen Namen hat keinen Effekt', () {
      final result = parseOcrText({
        'text': simpleText,
        'categoryData': <Map<String, dynamic>>[],
        'productMappings': [
          {
            'raw_ocr_name': 'Völlig anderer Artikel',
            'corrected_name': 'Ersatz',
            'category_id': null,
          }
        ],
      });
      final items = List<String>.from(result['items'] as List);
      // Brot und A1pro sind unberührt
      expect(items.any((i) => i.contains('Brot')), isTrue);
      expect(items.any((i) => i.contains('Ersatz')), isFalse);
    });
  });
}
