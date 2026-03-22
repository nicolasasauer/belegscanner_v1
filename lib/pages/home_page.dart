import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/ocr_service.dart';

/// Hauptseite der Belegscanner-App.
///
/// Zeigt eine gefilterte Liste der gescannten Belege und ermöglicht
/// das Starten eines neuen Scans über den FloatingActionButton.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---------------------------------------------------------------------------
  // Zustand
  // ---------------------------------------------------------------------------

  /// Alle gespeicherten Belege.
  final List<Receipt> _receipts = [];

  /// Gibt an, ob aktuell ein Scan läuft.
  bool _isScanning = false;

  /// Ausgewählter Tag für den Filter (null = kein Filter).
  int? _selectedDay;

  /// Ausgewählter Monat für den Filter (null = kein Filter).
  int? _selectedMonth;

  /// Ausgewähltes Jahr für den Filter (null = kein Filter).
  int? _selectedYear;

  // ---------------------------------------------------------------------------
  // Services & Formatter
  // ---------------------------------------------------------------------------

  final OcrService _ocrService = OcrService();

  /// Formatter für Euro-Beträge (z. B. "12,50 €").
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'de_DE',
    symbol: '€',
  );

  /// Formatter für das Anzeigedatum (z. B. "22. März 2026").
  final DateFormat _dateFormat = DateFormat('d. MMMM yyyy', 'de_DE');

  // ---------------------------------------------------------------------------
  // Berechnete Eigenschaften
  // ---------------------------------------------------------------------------

  /// Gibt die gefilterte Beleg-Liste zurück.
  List<Receipt> get _filteredReceipts {
    return _receipts.where((receipt) {
      if (_selectedDay != null && receipt.date.day != _selectedDay) {
        return false;
      }
      if (_selectedMonth != null && receipt.date.month != _selectedMonth) {
        return false;
      }
      if (_selectedYear != null && receipt.date.year != _selectedYear) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Eindeutige Tage, für die Belege vorhanden sind.
  List<int> get _availableDays {
    return _receipts.map((r) => r.date.day).toSet().toList()..sort();
  }

  /// Eindeutige Monate, für die Belege vorhanden sind.
  List<int> get _availableMonths {
    return _receipts.map((r) => r.date.month).toSet().toList()..sort();
  }

  /// Eindeutige Jahre, für die Belege vorhanden sind.
  List<int> get _availableYears {
    return _receipts.map((r) => r.date.year).toSet().toList()..sort();
  }

  // ---------------------------------------------------------------------------
  // Aktionen
  // ---------------------------------------------------------------------------

  /// Startet den Scan-Vorgang:
  /// 1. Kamera öffnen → Foto aufnehmen
  /// 2. Text per OCR erkennen
  /// 3. Beleg aus Text parsen und in Liste speichern
  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    try {
      final receipt = await _ocrService.scanReceipt();

      if (receipt != null) {
        setState(() {
          _receipts.add(receipt);
        });

        // Hinweis anzeigen, wenn kein Betrag erkannt wurde
        if (receipt.totalAmount == 0.0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Betrag konnte nicht automatisch erkannt werden. '
                'Bitte manuell prüfen.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Fehler dem Benutzer anzeigen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan fehlgeschlagen: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() => _isScanning = false);
    }
  }

  /// Setzt alle Filter zurück.
  void _clearFilters() {
    setState(() {
      _selectedDay = null;
      _selectedMonth = null;
      _selectedYear = null;
    });
  }

  /// Zeigt die Detail-Ansicht eines Belegs in einem BottomSheet.
  void _showReceiptDetails(Receipt receipt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ReceiptDetailSheet(
        receipt: receipt,
        dateFormat: _dateFormat,
        currencyFormat: _currencyFormat,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredReceipts;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Belegscanner'),
        centerTitle: true,
        actions: [
          // Filter zurücksetzen
          if (_selectedDay != null ||
              _selectedMonth != null ||
              _selectedYear != null)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Filter zurücksetzen',
              onPressed: _clearFilters,
            ),
        ],
        // Ladeindikator direkt unter der AppBar während des Scans
        bottom: _isScanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: Column(
        children: [
          // ------------------------------------------------------------------
          // Filter-Bar
          // ------------------------------------------------------------------
          _FilterBar(
            availableDays: _availableDays,
            availableMonths: _availableMonths,
            availableYears: _availableYears,
            selectedDay: _selectedDay,
            selectedMonth: _selectedMonth,
            selectedYear: _selectedYear,
            onDayChanged: (v) => setState(() => _selectedDay = v),
            onMonthChanged: (v) => setState(() => _selectedMonth = v),
            onYearChanged: (v) => setState(() => _selectedYear = v),
          ),

          // ------------------------------------------------------------------
          // Beleg-Liste
          // ------------------------------------------------------------------
          Expanded(
            child: Stack(
              children: [
                filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final receipt = filtered[index];
                          return _ReceiptListTile(
                            receipt: receipt,
                            dateFormat: _dateFormat,
                            currencyFormat: _currencyFormat,
                            onTap: () => _showReceiptDetails(receipt),
                          );
                        },
                      ),

                // Scan-Overlay: Glassmorphism-Effekt mit Unschärfe
                if (_isScanning)
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      color: colorScheme.scrim.withOpacity(0.15),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Scan l\u00E4uft...',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: colorScheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _startScan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Beleg scannen'),
        tooltip: 'Neuen Beleg scannen',
      ),
    );
  }

  /// Zeigt einen Hinweis, wenn keine Belege vorhanden sind.
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _receipts.isEmpty
                  ? 'Noch keine Belege vorhanden.\nTippe auf „Beleg scannen", um loszulegen.'
                  : 'Keine Belege für den gewählten Filter.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Filter-Bar Widget
// =============================================================================

/// Filter-Leiste mit FilterChips für Tag, Monat und Jahr.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.availableDays,
    required this.availableMonths,
    required this.availableYears,
    required this.selectedDay,
    required this.selectedMonth,
    required this.selectedYear,
    required this.onDayChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  final List<int> availableDays;
  final List<int> availableMonths;
  final List<int> availableYears;
  final int? selectedDay;
  final int? selectedMonth;
  final int? selectedYear;
  final ValueChanged<int?> onDayChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<int?> onYearChanged;

  @override
  Widget build(BuildContext context) {
    // Filter-Leiste ausblenden, wenn noch keine Belege vorhanden sind
    if (availableDays.isEmpty &&
        availableMonths.isEmpty &&
        availableYears.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Tag-FilterChips
              if (availableDays.isNotEmpty) ...[
                _ChipGroupLabel(label: 'Tag'),
                ...availableDays.map(
                  (d) => _buildChip(
                    context: context,
                    label: d.toString().padLeft(2, '0'),
                    isSelected: selectedDay == d,
                    onSelected: (sel) => onDayChanged(sel ? d : null),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Monat-FilterChips
              if (availableMonths.isNotEmpty) ...[
                _ChipGroupLabel(label: 'Monat'),
                ...availableMonths.map(
                  (m) => _buildChip(
                    context: context,
                    label: _monthName(m),
                    isSelected: selectedMonth == m,
                    onSelected: (sel) => onMonthChanged(sel ? m : null),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Jahr-FilterChips
              if (availableYears.isNotEmpty) ...[
                _ChipGroupLabel(label: 'Jahr'),
                ...availableYears.map(
                  (y) => _buildChip(
                    context: context,
                    label: y.toString(),
                    isSelected: selectedYear == y,
                    onSelected: (sel) => onYearChanged(sel ? y : null),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: onSelected,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// Gibt den deutschen Monatsnamen für einen Monatswert (1–12) zurück.
  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'M\u00E4r', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
    ];
    return names[month - 1];
  }
}

/// Kleines Beschriftungs-Widget für eine Chip-Gruppe in der Filter-Leiste.
class _ChipGroupLabel extends StatelessWidget {
  const _ChipGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// =============================================================================
// Beleg-ListTile Widget
// =============================================================================

/// Listeneintrags-Widget für einen Beleg.
class _ReceiptListTile extends StatelessWidget {
  const _ReceiptListTile({
    required this.receipt,
    required this.dateFormat,
    required this.currencyFormat,
    required this.onTap,
  });

  final Receipt receipt;
  final DateFormat dateFormat;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.0),
      ),
      elevation: 0.5,
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.receipt_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          // Betrag fett hervorheben
          currencyFormat.format(receipt.totalAmount),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(dateFormat.format(receipt.date)),
        trailing: Text(
          '${receipt.items.length} Pos.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: onTap,
      ),
    );
  }
}

// =============================================================================
// Hilfsfunktionen für Einzelposten-Preiserkennung
// =============================================================================

/// Compiled Regex: Preis am Ende einer OCR-Einzelposten-Zeile.
///
/// Erkennt z. B. "BROT 750G  2,99" oder "MILCH 1L 1,49 A".
final _lineItemPriceRegex = RegExp(r'\s+(\d{1,4}[.,]\d{2})\s*[A-Za-z]?\s*$');

/// Parst eine OCR-Zeile in einen Artikelnamen und einen optionalen Preis.
///
/// Gibt einen Named-Record `(name, price)` zurück. Wenn kein Preis erkannt
/// wird, enthält [name] die ursprüngliche [line] und [price] ist `null`.
({String name, double? price}) _parseLineItem(String line) {
  final match = _lineItemPriceRegex.firstMatch(line);
  if (match == null) return (name: line, price: null);
  final price = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  final name = line.substring(0, match.start).trim();
  return (name: name, price: price);
}

// =============================================================================
// Beleg-Detail BottomSheet Widget
// =============================================================================

/// Detail-Ansicht eines Belegs als BottomSheet.
class _ReceiptDetailSheet extends StatelessWidget {
  const _ReceiptDetailSheet({
    required this.receipt,
    required this.dateFormat,
    required this.currencyFormat,
  });

  final Receipt receipt;
  final DateFormat dateFormat;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag-Handle
            Center(
              child: Container(
                width: 48,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Betrag und Datum
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currencyFormat.format(receipt.totalAmount),
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  dateFormat.format(receipt.date),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),

            const Divider(height: 24),

            // Artikel-Liste
            Text(
              'Erkannte Positionen',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: receipt.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final (:name, :price) =
                      _parseLineItem(receipt.items[index]);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text('\u2022 $name')),
                        if (price != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            currencyFormat.format(price),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
