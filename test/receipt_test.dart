import 'package:flutter_test/flutter_test.dart';
import 'package:belegscanner_v1/models/receipt.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Tests für das Receipt-Datenmodell
  // ---------------------------------------------------------------------------

  group('Receipt Datenmodell', () {
    test('Erstellt ein Receipt mit allen Pflichtfeldern', () {
      final receipt = Receipt(
        id: 'test-id-123',
        date: DateTime(2026, 3, 22),
        totalAmount: 42.50,
        items: ['Milch 1,29 €', 'Brot 2,49 €'],
        imagePath: '/tmp/test_receipt.jpg',
      );

      expect(receipt.id, equals('test-id-123'));
      expect(receipt.date, equals(DateTime(2026, 3, 22)));
      expect(receipt.totalAmount, equals(42.50));
      expect(receipt.items.length, equals(2));
      expect(receipt.imagePath, equals('/tmp/test_receipt.jpg'));
      expect(receipt.rawText, isNull);
    });

    test('Erstellt ein Receipt ohne imagePath (null)', () {
      final receipt = Receipt(
        id: 'no-image',
        date: DateTime(2026, 3, 22),
        totalAmount: 5.00,
        items: [],
      );

      expect(receipt.imagePath, isNull);
      expect(receipt.rawText, isNull);
    });

    test('Erstellt ein Receipt mit rawText', () {
      final receipt = Receipt(
        id: 'raw-text-test',
        date: DateTime(2026, 3, 22),
        totalAmount: 5.00,
        items: ['Milch 1,29'],
        rawText: 'dm Bio\n22.03.2026 10:30\nMilch 1,29 A\nSUMME 5,00',
      );

      expect(receipt.rawText, isNotNull);
      expect(receipt.rawText, contains('SUMME 5,00'));
    });

    test('copyWith übernimmt alle unveränderten Felder', () {
      final original = Receipt(
        id: 'abc',
        date: DateTime(2026, 1, 1),
        totalAmount: 10.0,
        items: const ['Artikel A'],
        categories: const ['Lebensmittel'],
        imagePath: '/tmp/a.jpg',
      );

      final copy = original.copyWith(totalAmount: 99.99);

      expect(copy.id, equals('abc'));
      expect(copy.date, equals(DateTime(2026, 1, 1)));
      expect(copy.totalAmount, equals(99.99));
      expect(copy.items, equals(['Artikel A']));
      expect(copy.categories, equals(['Lebensmittel']));
      expect(copy.imagePath, equals('/tmp/a.jpg'));
    });

    test('copyWith kann einzelne Felder überschreiben', () {
      final original = Receipt(
        id: 'orig',
        date: DateTime(2026, 6, 15),
        totalAmount: 5.0,
        items: const [],
        categories: const [],
        imagePath: '/tmp/orig.jpg',
      );

      final updated = original.copyWith(
        id: 'updated',
        items: ['Neuer Artikel'],
        categories: ['Sonstiges'],
      );

      expect(updated.id, equals('updated'));
      expect(updated.items, equals(['Neuer Artikel']));
      expect(updated.categories, equals(['Sonstiges']));
      // Unveränderte Felder bleiben erhalten
      expect(updated.date, equals(DateTime(2026, 6, 15)));
      expect(updated.totalAmount, equals(5.0));
    });

    test('categoryAt gibt die richtige Kategorie zurück', () {
      final receipt = Receipt(
        id: 'cat-test',
        date: DateTime(2026, 3, 22),
        totalAmount: 5.0,
        items: const ['Milch 1,29', 'Brot 2,49', 'Unbekannt 1,22'],
        categories: const ['Lebensmittel', 'Lebensmittel'],
      );
      expect(receipt.categoryAt(0), equals('Lebensmittel'));
      expect(receipt.categoryAt(1), equals('Lebensmittel'));
      // Index 2 existiert nicht in categories → Fallback "Sonstiges"
      expect(receipt.categoryAt(2), equals('Sonstiges'));
    });

    test('toString enthält alle relevanten Felder', () {
      final receipt = Receipt(
        id: 'str-test',
        date: DateTime(2026, 3, 22),
        totalAmount: 7.49,
        items: const ['Test'],
        imagePath: '/tmp/str.jpg',
      );

      final str = receipt.toString();
      expect(str, contains('str-test'));
      expect(str, contains('7.49'));
    });

    // -------------------------------------------------------------------------
    // Tests für toMap / fromMap (Datenbankpersistenz)
    // -------------------------------------------------------------------------

    test('toMap enthält alle Felder in der richtigen Form', () {
      final date = DateTime(2026, 3, 22, 10, 30);
      final receipt = Receipt(
        id: 'map-test',
        date: date,
        totalAmount: 14.95,
        items: ['Brot 2,49', 'Milch 1,29'],
        categories: ['Lebensmittel', 'Lebensmittel'],
        imagePath: '/tmp/scan.jpg',
        rawText: 'Bäckerei\n22.03.2026\nBrot 2,49\nSUMME 14,95',
        status: 'completed',
        progress: 1.0,
        fileHash: 'deadbeef01234567',
      );

      final map = receipt.toMap();

      expect(map['id'], equals('map-test'));
      expect(map['date'], equals(date.toIso8601String()));
      expect(map['totalAmount'], equals(14.95));
      expect(map['items'], equals('["Brot 2,49","Milch 1,29"]'));
      expect(map['categories'], equals('["Lebensmittel","Lebensmittel"]'));
      expect(map['imagePath'], equals('/tmp/scan.jpg'));
      expect(map['rawText'], equals('Bäckerei\n22.03.2026\nBrot 2,49\nSUMME 14,95'));
      expect(map['status'], equals('completed'));
      expect(map['progress'], equals(1.0));
      expect(map['fileHash'], equals('deadbeef01234567'));
    });

    test('toMap hat rawText als null wenn nicht gesetzt', () {
      final receipt = Receipt(
        id: 'no-raw',
        date: DateTime(2026, 1, 1),
        totalAmount: 1.0,
        items: [],
      );
      expect(receipt.toMap()['rawText'], isNull);
      expect(receipt.toMap()['categories'], equals('[]'));
      expect(receipt.toMap()['fileHash'], isNull);
      expect(receipt.toMap()['status'], equals('completed'));
      expect(receipt.toMap()['progress'], equals(1.0));
    });

    test('fromMap erstellt einen korrekten Receipt', () {
      final map = {
        'id': 'from-map-test',
        'date': '2026-03-22T10:30:00.000',
        'totalAmount': 9.99,
        'items': '["Käse","Butter"]',
        'categories': '["Lebensmittel","Lebensmittel"]',
        'imagePath': '/tmp/img.jpg',
        'rawText': 'Supermarkt\n22.03.2026\nKäse 5,99\nButter 3,99\nSUMME 9,99',
      };

      final receipt = Receipt.fromMap(map);

      expect(receipt.id, equals('from-map-test'));
      expect(receipt.date, equals(DateTime(2026, 3, 22, 10, 30)));
      expect(receipt.totalAmount, equals(9.99));
      expect(receipt.items, equals(['Käse', 'Butter']));
      expect(receipt.categories, equals(['Lebensmittel', 'Lebensmittel']));
      expect(receipt.imagePath, equals('/tmp/img.jpg'));
      expect(receipt.rawText, contains('SUMME 9,99'));
    });

    test('fromMap mit null rawText (Altdaten ohne OCR-Rohtext)', () {
      final map = {
        'id': 'legacy',
        'date': '2026-01-01T00:00:00.000',
        'totalAmount': 5.0,
        'items': '[]',
        'imagePath': null,
        'rawText': null,
      };
      final receipt = Receipt.fromMap(map);
      expect(receipt.rawText, isNull);
    });

    test('toMap und fromMap sind inverse Operationen (Roundtrip)', () {
      final original = Receipt(
        id: 'roundtrip',
        date: DateTime(2026, 5, 1, 12, 0),
        totalAmount: 23.45,
        items: ['Artikel A', 'Artikel B', 'Artikel C'],
        categories: ['Lebensmittel', 'Getränke', 'Sonstiges'],
        imagePath: '/tmp/roundtrip.jpg',
        rawText: 'Shop\n01.05.2026 12:00\nArtikel A 10,00\nSUMME 23,45',
        status: 'completed',
        progress: 1.0,
        fileHash: 'abc123def456',
      );

      final restored = Receipt.fromMap(original.toMap());

      expect(restored.id, equals(original.id));
      expect(restored.date, equals(original.date));
      expect(restored.totalAmount, equals(original.totalAmount));
      expect(restored.items, equals(original.items));
      expect(restored.categories, equals(original.categories));
      expect(restored.imagePath, equals(original.imagePath));
      expect(restored.rawText, equals(original.rawText));
      expect(restored.status, equals(original.status));
      expect(restored.progress, equals(original.progress));
      expect(restored.fileHash, equals(original.fileHash));
    });

    test('fromMap mit leerer Artikel-Liste', () {
      final map = {
        'id': 'empty-items',
        'date': '2026-01-01T00:00:00.000',
        'totalAmount': 0.0,
        'items': '[]',
        'imagePath': '/tmp/empty.jpg',
      };

      final receipt = Receipt.fromMap(map);
      expect(receipt.items, isEmpty);
    });

    test('fromMap mit null imagePath (Altdaten ohne Bild)', () {
      final map = {
        'id': 'no-image',
        'date': '2026-01-01T00:00:00.000',
        'totalAmount': 0.0,
        'items': '[]',
        'imagePath': null,
      };

      final receipt = Receipt.fromMap(map);
      expect(receipt.imagePath, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für die Filter-Logik (isoliert ohne Flutter-Widget)
  // ---------------------------------------------------------------------------

  group('Filter-Logik', () {
    final receipts = [
      Receipt(
        id: '1',
        date: DateTime(2026, 3, 22),
        totalAmount: 12.50,
        items: const ['Milch'],
        imagePath: '/tmp/1.jpg',
      ),
      Receipt(
        id: '2',
        date: DateTime(2026, 3, 15),
        totalAmount: 8.00,
        items: const ['Brot'],
        imagePath: '/tmp/2.jpg',
      ),
      Receipt(
        id: '3',
        date: DateTime(2026, 2, 10),
        totalAmount: 5.50,
        items: const ['Käse'],
        imagePath: '/tmp/3.jpg',
      ),
    ];

    /// Hilfsfunktion, die die Filter-Logik der HomePage nachbildet.
    List<Receipt> applyFilter(
      List<Receipt> list, {
      int? day,
      int? month,
      int? year,
    }) {
      return list.where((r) {
        if (day != null && r.date.day != day) return false;
        if (month != null && r.date.month != month) return false;
        if (year != null && r.date.year != year) return false;
        return true;
      }).toList();
    }

    test('Kein Filter gibt alle Belege zurück', () {
      final result = applyFilter(receipts);
      expect(result.length, equals(3));
    });

    test('Filter nach Monat März gibt 2 Belege zurück', () {
      final result = applyFilter(receipts, month: 3);
      expect(result.length, equals(2));
      expect(result.every((r) => r.date.month == 3), isTrue);
    });

    test('Filter nach Tag 22 gibt 1 Beleg zurück', () {
      final result = applyFilter(receipts, day: 22);
      expect(result.length, equals(1));
      expect(result.first.id, equals('1'));
    });

    test('Filter nach Monat Februar gibt 1 Beleg zurück', () {
      final result = applyFilter(receipts, month: 2);
      expect(result.length, equals(1));
      expect(result.first.id, equals('3'));
    });

    test('Kombinierter Filter (Monat + Tag) filtert korrekt', () {
      final result = applyFilter(receipts, month: 3, day: 15);
      expect(result.length, equals(1));
      expect(result.first.id, equals('2'));
    });

    test('Filter ohne Treffer gibt leere Liste zurück', () {
      final result = applyFilter(receipts, month: 12);
      expect(result, isEmpty);
    });
  });
}
