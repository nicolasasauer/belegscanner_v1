import 'dart:convert';

/// Datenmodell für einen gescannten Beleg.
class Receipt {
  /// Eindeutige ID des Belegs (UUID).
  final String id;

  /// Datum des Belegs.
  final DateTime date;

  /// Gesamtbetrag in Euro.
  final double totalAmount;

  /// Liste der erkannten Einzelposten (Format: "Name  Preis").
  final List<String> items;

  /// Kategorien der Einzelposten (parallele Liste zu [items]).
  ///
  /// Wenn kürzer als [items], erhalten fehlende Einträge die Kategorie
  /// „Sonstiges" als Standard. Kann leer sein (Altdaten).
  final List<String> categories;

  /// Permanenter Dateipfad zum gespeicherten Bild des Belegs.
  ///
  /// Kann `null` sein, wenn für diesen Beleg kein Bild vorhanden ist
  /// (z. B. bei Altdaten oder nach einem fehlgeschlagenen Kopiervorgang).
  final String? imagePath;

  /// Ungefilterte Rohausgabe des OCR-Scans (kompletter Text-Dump).
  ///
  /// Dient als Debugging-Gedächtnis: enthält alles, was die KI auf dem Bon
  /// erkannt hat, bevor der Filter-Algorithmus greift. Kann `null` sein
  /// bei Altdaten oder wenn die OCR keinen Text zurückgegeben hat.
  final String? rawText;

  const Receipt({
    required this.id,
    required this.date,
    required this.totalAmount,
    required this.items,
    this.categories = const [],
    this.imagePath,
    this.rawText,
  });

  /// Gibt die Kategorie für den Artikel an Index [i] zurück.
  ///
  /// Fällt auf „Sonstiges" zurück, wenn [categories] keinen Eintrag
  /// für diesen Index enthält.
  String categoryAt(int i) =>
      i < categories.length ? categories[i] : 'Sonstiges';

  /// Erstellt eine Kopie des Belegs mit optionalen geänderten Feldern.
  Receipt copyWith({
    String? id,
    DateTime? date,
    double? totalAmount,
    List<String>? items,
    List<String>? categories,
    String? imagePath,
    String? rawText,
  }) {
    return Receipt(
      id: id ?? this.id,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      items: items ?? this.items,
      categories: categories ?? this.categories,
      imagePath: imagePath ?? this.imagePath,
      rawText: rawText ?? this.rawText,
    );
  }

  /// Konvertiert den Beleg in eine Map für die SQLite-Datenbank.
  ///
  /// Die Artikel-Liste und die Kategorien-Liste werden je als JSON-String
  /// gespeichert.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'totalAmount': totalAmount,
      'items': jsonEncode(items),
      'categories': jsonEncode(categories),
      'imagePath': imagePath,
      'rawText': rawText,
    };
  }

  /// Erstellt einen [Receipt] aus einer SQLite-Datenbankzeile.
  ///
  /// Verarbeitet Altdaten ohne `categories`-Spalte, indem fehlende Einträge
  /// auf eine leere Liste fallen.
  factory Receipt.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as String;
    final decoded = jsonDecode(rawItems) as List<dynamic>;

    final rawCategories = map['categories'] as String?;
    final categories = rawCategories != null
        ? (jsonDecode(rawCategories) as List<dynamic>).cast<String>()
        : <String>[];

    return Receipt(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      totalAmount: (map['totalAmount'] as num).toDouble(),
      items: decoded.cast<String>(),
      categories: categories,
      imagePath: map['imagePath'] as String?,
      rawText: map['rawText'] as String?,
    );
  }

  @override
  String toString() {
    return 'Receipt(id: $id, date: $date, totalAmount: $totalAmount, '
        'items: $items, categories: $categories, imagePath: $imagePath, '
        'rawText: ${rawText != null ? "${rawText!.length} chars" : "null"})';
  }
}
