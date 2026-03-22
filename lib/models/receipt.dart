import 'dart:convert';

/// Datenmodell für einen gescannten Beleg.
class Receipt {
  /// Eindeutige ID des Belegs (UUID).
  final String id;

  /// Datum des Belegs.
  final DateTime date;

  /// Gesamtbetrag in Euro.
  final double totalAmount;

  /// Liste der erkannten Einzelposten.
  final List<String> items;

  /// Permanenter Dateipfad zum gespeicherten Bild des Belegs.
  ///
  /// Kann `null` sein, wenn für diesen Beleg kein Bild vorhanden ist
  /// (z. B. bei Altdaten oder nach einem fehlgeschlagenen Kopiervorgang).
  final String? imagePath;

  const Receipt({
    required this.id,
    required this.date,
    required this.totalAmount,
    required this.items,
    this.imagePath,
  });

  /// Erstellt eine Kopie des Belegs mit optionalen geänderten Feldern.
  Receipt copyWith({
    String? id,
    DateTime? date,
    double? totalAmount,
    List<String>? items,
    String? imagePath,
  }) {
    return Receipt(
      id: id ?? this.id,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      items: items ?? this.items,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  /// Konvertiert den Beleg in eine Map für die SQLite-Datenbank.
  ///
  /// Die Artikel-Liste wird als JSON-String gespeichert.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'totalAmount': totalAmount,
      'items': jsonEncode(items),
      'imagePath': imagePath,
    };
  }

  /// Erstellt einen [Receipt] aus einer SQLite-Datenbankzeile.
  factory Receipt.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as String;
    final decoded = jsonDecode(rawItems) as List<dynamic>;
    return Receipt(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      totalAmount: (map['totalAmount'] as num).toDouble(),
      items: decoded.cast<String>(),
      imagePath: map['imagePath'] as String?,
    );
  }

  @override
  String toString() {
    return 'Receipt(id: $id, date: $date, totalAmount: $totalAmount, '
        'items: $items, imagePath: $imagePath)';
  }
}
