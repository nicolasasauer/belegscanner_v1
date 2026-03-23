// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:belegscanner_v1/services/ocr_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Tests für parseItemsImpl – Artikel-Paar-Erkennung
  // ---------------------------------------------------------------------------

  group('parseItemsImpl – dm-Beleg', () {
    // Simulierter OCR-Output eines dm-Belegs:
    // Zwei Artikel auf derselben Zeile (Name + Preis), gefolgt von SUMME.
    const dmReceiptText =
        'dmBio Fruchtaufstr. Erdb. 250g 2,25 2\n'
        'dmBio Tofu Rosso 200g 1,65 2\n'
        'SUMME 3,90';

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
      expect(items.length, equals(1));
      final (:name, :price) = parseLineItem(items[0]);
      expect(name, equals('dmBio Milch 1L'));
      expect(price, equals(1.19));
    });

    test('MwSt-Zeilen werden ignoriert', () {
      const mwstText =
          'Brot 750g 2,49\n'
          'MwSt 19% 0,39\n'
          'MwSt 7% 0,16';
      final items = parseItemsImpl(mwstText);
      expect(items.length, equals(1));
    });

    test('Reine Zahlenzeilen (MwSt-Sätze) werden nicht als Artikelnamen verwendet',
        () {
      const vatText =
          '19\n'
          '2,49\n'
          '7\n'
          '1,19';
      final items = parseItemsImpl(vatText);
      // "19" und "7" haben keine Buchstaben → dürfen nicht als Namen matched werden
      expect(items, isEmpty);
    });

    test('Standalone Preis-Zeilen ohne vorherigen Artikelnamen werden ignoriert',
        () {
      const priceOnlyText = '2,49\n1,65\n3,90';
      final items = parseItemsImpl(priceOnlyText);
      expect(items, isEmpty);
    });

    test('Zahlungs-Zeilen (Visa, Bar) werden ignoriert', () {
      const paymentText =
          'Brot 750g 2,49\n'
          'Zahlung Visa 2,49\n'
          'Vielen Dank';
      final items = parseItemsImpl(paymentText);
      expect(items.length, equals(1));
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
}
