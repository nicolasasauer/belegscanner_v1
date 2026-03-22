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

  /// Dateipfad zum gespeicherten Bild des Belegs.
  final String imagePath;

  const Receipt({
    required this.id,
    required this.date,
    required this.totalAmount,
    required this.items,
    required this.imagePath,
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

  @override
  String toString() {
    return 'Receipt(id: $id, date: $date, totalAmount: $totalAmount, '
        'items: $items, imagePath: $imagePath)';
  }
}
