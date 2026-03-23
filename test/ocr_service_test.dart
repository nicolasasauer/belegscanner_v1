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
}
