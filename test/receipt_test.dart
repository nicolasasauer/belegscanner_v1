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
    });

    test('copyWith übernimmt alle unveränderten Felder', () {
      final original = Receipt(
        id: 'abc',
        date: DateTime(2026, 1, 1),
        totalAmount: 10.0,
        items: const ['Artikel A'],
        imagePath: '/tmp/a.jpg',
      );

      final copy = original.copyWith(totalAmount: 99.99);

      expect(copy.id, equals('abc'));
      expect(copy.date, equals(DateTime(2026, 1, 1)));
      expect(copy.totalAmount, equals(99.99));
      expect(copy.items, equals(['Artikel A']));
      expect(copy.imagePath, equals('/tmp/a.jpg'));
    });

    test('copyWith kann einzelne Felder überschreiben', () {
      final original = Receipt(
        id: 'orig',
        date: DateTime(2026, 6, 15),
        totalAmount: 5.0,
        items: const [],
        imagePath: '/tmp/orig.jpg',
      );

      final updated = original.copyWith(
        id: 'updated',
        items: ['Neuer Artikel'],
      );

      expect(updated.id, equals('updated'));
      expect(updated.items, equals(['Neuer Artikel']));
      // Unveränderte Felder bleiben erhalten
      expect(updated.date, equals(DateTime(2026, 6, 15)));
      expect(updated.totalAmount, equals(5.0));
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
