import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';

/// Hauptseite der Bong-Scanner-App.
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

  /// Alle gespeicherten Belege (Master-Liste – wird nie direkt angezeigt).
  final List<Receipt> _receipts = [];

  /// Gibt an, ob aktuell ein Scan/Import läuft.
  bool _isScanning = false;

  /// Ausgewählter Tag für den Filter (null = kein Filter).
  int? _selectedDay;

  /// Ausgewählter Monat für den Filter (null = kein Filter).
  int? _selectedMonth;

  /// Ausgewähltes Jahr für den Filter (null = kein Filter).
  int? _selectedYear;

  /// Controller für die Suchleiste.
  final TextEditingController _searchController = TextEditingController();

  /// Aktueller Suchbegriff (leer = kein Suchfilter).
  String _searchQuery = '';

  /// Gibt an, ob die Suchleiste in der AppBar aktiv ist.
  bool _isSearching = false;

  /// Gibt an, ob das FAB-Geschwindigkeitsdial-Menü geöffnet ist.
  bool _isFabExpanded = false;

  // ---------------------------------------------------------------------------
  // Services & Formatter
  // ---------------------------------------------------------------------------

  final OcrService _ocrService = OcrService();
  final DatabaseService _databaseService = DatabaseService();

  /// Formatter für Euro-Beträge (z. B. "12,50 €").
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'de_DE',
    symbol: '€',
  );

  /// Formatter für das Anzeigedatum (z. B. "22. März 2026").
  final DateFormat _dateFormat = DateFormat('d. MMMM yyyy', 'de_DE');

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Android 16 killt Apps, die im ersten Frame zu viel CPU beanspruchen.
    // Kleine Verzögerung gibt dem Framework Zeit, den ersten Frame zu rendern,
    // bevor Datenbank und ML Kit initialisiert werden.
    Future.delayed(const Duration(milliseconds: 500), _loadReceipts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Lädt alle gespeicherten Belege aus der lokalen Datenbank.
  Future<void> _loadReceipts() async {
    final receipts = await _databaseService.getAllReceipts();
    if (mounted) {
      setState(() {
        _receipts
          ..clear()
          ..addAll(receipts);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Berechnete Eigenschaften
  // ---------------------------------------------------------------------------

  /// Gibt die gefilterte Beleg-Liste zurück.
  ///
  /// Kombiniert Datum-Filter (Tag/Monat/Jahr) mit dem Volltext-Suchfilter.
  /// Der Suchfilter prüft Händlername (erster Artikel), Gesamtbetrag und
  /// alle Stichwörter in den erkannten Einzelpositionen.
  List<Receipt> get _filteredReceipts {
    return _receipts.where((receipt) {
      // Datum-Filter
      if (_selectedDay != null && receipt.date.day != _selectedDay) {
        return false;
      }
      if (_selectedMonth != null && receipt.date.month != _selectedMonth) {
        return false;
      }
      if (_selectedYear != null && receipt.date.year != _selectedYear) {
        return false;
      }

      // Volltext-Suchfilter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();

        // Händlername: erste OCR-Zeile als Heuristik
        final matchesMerchant = receipt.items.isNotEmpty &&
            receipt.items.first.toLowerCase().contains(q);

        // Gesamtbetrag: Zahl und formatierter String
        final matchesAmount =
            receipt.totalAmount.toString().contains(q) ||
                _currencyFormat.format(receipt.totalAmount).contains(q);

        // Stichwörter in allen erkannten Einzelpositionen
        final matchesItems =
            receipt.items.any((item) => item.toLowerCase().contains(q));

        if (!matchesMerchant && !matchesAmount && !matchesItems) {
          return false;
        }
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

      if (receipt != null && mounted) {
        await _databaseService.insertReceipt(receipt);
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
      // Freundliche Fehlermeldung ohne technische Details
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Hoppla, da ist beim Scannen etwas schiefgelaufen. '
              'Bitte versuche es erneut.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
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

  /// Schließt die Suchleiste und löscht den Suchbegriff.
  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _isSearching = false;
    });
  }

  /// Importiert einen Beleg aus der Gerätegalerie, führt OCR aus und speichert
  /// das Ergebnis – identische Pipeline wie [_startScan].
  Future<void> _importFromGallery() async {
    setState(() => _isScanning = true);

    try {
      final receipt = await _ocrService.importFromGallery();

      if (receipt != null && mounted) {
        await _databaseService.insertReceipt(receipt);
        setState(() {
          _receipts.add(receipt);
        });

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Hoppla, da ist beim Importieren etwas schiefgelaufen. '
              'Bitte versuche es erneut.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Löscht einen Beleg aus der Datenbank und entfernt ggf. die Bilddatei.
  Future<void> _deleteReceipt(Receipt receipt) async {
    await _databaseService.deleteReceipt(receipt.id);

    // Bilddatei vom Speicher entfernen, falls vorhanden
    if (receipt.imagePath != null) {
      final imageFile = File(receipt.imagePath!);
      if (imageFile.existsSync()) {
        try {
          await imageFile.delete();
        } catch (_) {
          // Datei konnte nicht gelöscht werden (z. B. fehlende Rechte) –
          // DB-Eintrag wurde bereits entfernt, daher trotzdem fortfahren.
        }
      }
    }

    if (mounted) {
      setState(() {
        _receipts.removeWhere((r) => r.id == receipt.id);
      });
    }
  }

  /// Exportiert alle Belege als CSV-Datei und teilt sie über das native Share-Sheet.
  ///
  /// Spalten: Datum, Händler (falls erkannt), Gesamtbetrag, Artikel (semikolon-getrennt).
  Future<void> _exportToCsv() async {
    if (_receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Belege zum Exportieren vorhanden.')),
      );
      return;
    }

    try {
      final buffer = StringBuffer();
      // CSV-Header
      buffer.writeln('Datum;Händler;Gesamtbetrag (EUR);Artikel');

      final amountFormat = NumberFormat('#,##0.00', 'de_DE');
      final exportDateFormat = DateFormat('yyyy-MM-dd', 'de_DE');

      for (final receipt in _receipts) {
        final date = exportDateFormat.format(receipt.date);
        // Händler: erste OCR-Zeile als best-effort-Näherungswert für den
        // Händlernamen. OCR-Text ist nicht immer in dieser Reihenfolge –
        // dies ist eine Heuristik ohne Garantie.
        final merchant = receipt.items.isNotEmpty
            ? _escapeCsvField(receipt.items.first)
            : '';
        final amount = amountFormat.format(receipt.totalAmount);
        // Artikel: alle Zeilen außer der ersten (Händler), durch Pipe getrennt
        final items = receipt.items.length > 1
            ? _escapeCsvField(receipt.items.sublist(1).join(' | '))
            : '';

        buffer.writeln('$date;$merchant;$amount;$items');
      }

      // Temporäre Datei im App-Cache-Verzeichnis anlegen
      final cacheDir = await _getCacheDirectory();
      final file = File(p.join(cacheDir, 'belege_export.csv'));
      await file.writeAsString(buffer.toString(), flush: true);

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Bong-Scanner Export',
        text: 'Exportierte Belege aus der Bong-Scanner-App.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Export fehlgeschlagen. Bitte versuche es erneut.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Gibt das app-private Verzeichnis zurück, das für temporäre Export-Dateien
  /// genutzt wird. Delegiert an [DatabaseService.getDatabasesDirectory].
  Future<String> _getCacheDirectory() async {
    return _databaseService.getDatabasesDirectory();
  }

  /// Maskiert ein CSV-Feld gemäß RFC 4180:
  /// Enthält das Feld ein Semikolon oder Anführungszeichen,
  /// wird es in doppelte Anführungszeichen eingeschlossen.
  String _escapeCsvField(String value) {
    // Zeilenumbrüche durch Leerzeichen ersetzen
    final cleaned = value.replaceAll('\n', ' ').replaceAll('\r', '');
    if (cleaned.contains(';') || cleaned.contains('"')) {
      return '"${cleaned.replaceAll('"', '""')}"';
    }
    return cleaned;
  }

  /// Zeigt die Detail-Ansicht eines Belegs in einem BottomSheet.
  void _showReceiptDetails(Receipt receipt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        // Keyboard-Padding: schiebt den Sheet-Inhalt nach oben, sobald die
        // Tastatur eingeblendet wird.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _ReceiptDetailSheet(
          receipt: receipt,
          dateFormat: _dateFormat,
          currencyFormat: _currencyFormat,
          databaseService: _databaseService,
          onSaved: (updatedReceipt) {
            setState(() {
              final idx =
                  _receipts.indexWhere((r) => r.id == updatedReceipt.id);
              if (idx != -1) _receipts[idx] = updatedReceipt;
            });
          },
        ),
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
        // Suche aktiv → Suchfeld im Titel; sonst normaler Titel
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Händler, Betrag, Stichwort…',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                style: TextStyle(color: colorScheme.onSurface),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Bong-Scanner'),
        centerTitle: !_isSearching,
        actions: [
          // Such-Icon / Schließen-Icon
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Suche schließen',
              onPressed: _clearSearch,
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Belege durchsuchen',
              onPressed: () => setState(() => _isSearching = true),
            ),
          // CSV-Export-Button (nur wenn nicht in Suche)
          if (_receipts.isNotEmpty && !_isSearching)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Belege als CSV exportieren',
              onPressed: _isScanning ? null : _exportToCsv,
            ),
          // Filter zurücksetzen (nur wenn nicht in Suche)
          if ((_selectedDay != null ||
                  _selectedMonth != null ||
                  _selectedYear != null) &&
              !_isSearching)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Filter zurücksetzen',
              onPressed: _clearFilters,
            ),
        ],
        // Ladeindikator direkt unter der AppBar während des Scans/Imports
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
                          return Dismissible(
                            key: ValueKey(receipt.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                            confirmDismiss: (_) async {
                              return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Beleg löschen?'),
                                  content: const Text(
                                    'Möchtest du diesen Beleg und das '
                                    'zugehörige Bild wirklich löschen?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Abbrechen'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: const Text('Löschen'),
                                    ),
                                  ],
                                ),
                              ) ??
                                  false;
                            },
                            onDismissed: (_) => _deleteReceipt(receipt),
                            child: _ReceiptListTile(
                              receipt: receipt,
                              dateFormat: _dateFormat,
                              currencyFormat: _currencyFormat,
                              onTap: () => _showReceiptDetails(receipt),
                            ),
                          );
                        },
                      ),

                // FAB-Menü-Hintergrund: schließt das Menü beim Antippen
                if (_isFabExpanded)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _isFabExpanded = false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        color: colorScheme.scrim.withOpacity(0.25),
                      ),
                    ),
                  ),

                // Scan/Import-Overlay: Glassmorphism-Effekt mit Unschärfe
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
                            'Verarbeitung läuft…',
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
      floatingActionButton: _buildFab(context),
    );
  }

  /// Baut den Speed-Dial FloatingActionButton.
  ///
  /// Zeigt zwei Mini-FABs (Kamera + Galerie), die sich animiert ein-/ausblenden.
  Widget _buildFab(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Galerie-Option
        AnimatedSlide(
          offset: _isFabExpanded ? Offset.zero : const Offset(0, 0.5),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _isFabExpanded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_isFabExpanded,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _FabMenuItem(
                    icon: Icons.photo_library_outlined,
                    label: 'Bilder Import',
                    onPressed: () {
                      setState(() => _isFabExpanded = false);
                      _importFromGallery();
                    },
                  ),
                  const SizedBox(height: 10),
                  _FabMenuItem(
                    icon: Icons.camera_alt_outlined,
                    label: 'Kamera Scan',
                    onPressed: () {
                      setState(() => _isFabExpanded = false);
                      _startScan();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        // Haupt-FAB
        FloatingActionButton(
          heroTag: 'mainFab',
          onPressed: _isScanning
              ? null
              : () => setState(() => _isFabExpanded = !_isFabExpanded),
          tooltip: _isFabExpanded ? 'Menü schließen' : 'Beleg hinzufügen',
          child: AnimatedRotation(
            turns: _isFabExpanded ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add),
          ),
        ),
      ],
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
                  ? 'Noch keine Belege vorhanden.\nTippe auf „Beleg hinzufügen", um loszulegen.'
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
// FAB-Menü-Element Widget
// =============================================================================

/// Ein Element im Speed-Dial FAB-Menü mit Label und Mini-FAB.
class _FabMenuItem extends StatelessWidget {
  const _FabMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ],
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
        leading: _buildThumbnail(context),
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

  /// Baut das Thumbnail-Widget links im ListTile.
  ///
  /// Zeigt das echte Belegbild (falls vorhanden) oder einen Platzhalter.
  /// Ein Tipp auf das Thumbnail öffnet die Vollbild-Ansicht mit Zoom.
  Widget _buildThumbnail(BuildContext context) {
    final path = receipt.imagePath;

    if (path != null) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => _FullscreenImageViewer(imagePath: path),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(path),
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(context),
          ),
        ),
      );
    }
    return _placeholder(context);
  }

  /// Grauer Platzhalter mit Beleg-Icon für Belege ohne Bild.
  Widget _placeholder(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        color: Theme.of(context).colorScheme.primaryContainer,
        alignment: Alignment.center,
        child: Icon(
          Icons.receipt_outlined,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

// =============================================================================
// Hilfsfunktionen für Einzelposten-Preiserkennung
// =============================================================================

/// Compiled Regex: Preis am Ende einer OCR-Einzelposten-Zeile.
///
/// Erkennt z. B. "BROT 750G  2,99", "MILCH 1L 1,49 A" oder
/// "dmBio Tofu Rosso 200g 1,65 2" (Tax-Code am Ende ist Buchstabe oder Ziffer).
final _lineItemPriceRegex = RegExp(r'\s+(\d{1,4}[.,]\d{2})\s*[A-Za-z0-9]?\s*$');

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

/// Detail-Ansicht eines Belegs als BottomSheet mit editierbaren Positionen.
class _ReceiptDetailSheet extends StatefulWidget {
  const _ReceiptDetailSheet({
    required this.receipt,
    required this.dateFormat,
    required this.currencyFormat,
    required this.databaseService,
    required this.onSaved,
  });

  final Receipt receipt;
  final DateFormat dateFormat;
  final NumberFormat currencyFormat;
  final DatabaseService databaseService;
  final ValueChanged<Receipt> onSaved;

  @override
  State<_ReceiptDetailSheet> createState() => _ReceiptDetailSheetState();
}

class _ReceiptDetailSheetState extends State<_ReceiptDetailSheet> {
  late List<TextEditingController> _nameControllers;
  late List<TextEditingController> _priceControllers;
  bool _isSaving = false;

  /// Gibt an, ob die Detailansicht im Bearbeitungs-Modus ist.
  ///
  /// `false` (Standard): Positionen werden als saubere Text-Labels angezeigt.
  /// `true`: Positionen werden als editierbare TextFields mit Lösch-Icons angezeigt.
  bool _isEditing = false;

  /// Formatiert Preise im deutschen Dezimalformat (z. B. "1,95") für die
  /// Eingabefelder – getrennt vom [widget.currencyFormat], das das €-Symbol
  /// enthält und für die Anzeige genutzt wird.
  final NumberFormat _deDecimalFormat = NumberFormat('#0.00', 'de_DE');

  @override
  void initState() {
    super.initState();
    _initControllers(widget.receipt.items);
  }

  /// Initialisiert je einen Name- und Preis-Controller pro Artikel.
  void _initControllers(List<String> items) {
    _nameControllers = [];
    _priceControllers = [];
    for (final item in items) {
      final (:name, :price) = _parseLineItem(item);
      _nameControllers.add(TextEditingController(text: name));
      _priceControllers.add(
        TextEditingController(
          text: price != null ? _deDecimalFormat.format(price) : '',
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _nameControllers) c.dispose();
    for (final c in _priceControllers) c.dispose();
    super.dispose();
  }

  /// Entfernt einen Artikel anhand seines Index aus der Liste.
  void _deleteItem(int index) {
    _nameControllers[index].dispose();
    _priceControllers[index].dispose();
    setState(() {
      _nameControllers.removeAt(index);
      _priceControllers.removeAt(index);
    });
  }

  /// Speichert die geänderten Positionen in der Datenbank.
  ///
  /// Jeder Artikel wird als "<Name>  <Preis>" gespeichert – das doppelte
  /// Leerzeichen dient als Trenner, da [_parseLineItem] `\s+` vor dem Preis
  /// am Zeilenende erkennt und die Rekonstruktion damit zuverlässig gelingt.
  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final newItems = <String>[];
      for (var i = 0; i < _nameControllers.length; i++) {
        final name = _nameControllers[i].text.trim();
        if (name.isEmpty) continue;
        final priceText = _priceControllers[i].text.trim();
        newItems.add(priceText.isNotEmpty ? '$name  $priceText' : name);
      }

      final updatedReceipt = widget.receipt.copyWith(items: newItems);
      await widget.databaseService.insertReceipt(updatedReceipt);

      if (mounted) {
        widget.onSaved(updatedReceipt);
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Änderungen gespeichert.')),
        );
      }
    } catch (e, st) {
      debugPrint('[_ReceiptDetailSheet] Save failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Speichern fehlgeschlagen. Bitte erneut versuchen.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) {
        final hasImage = widget.receipt.imagePath != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------------------------
            // Fixer Kopfbereich (nicht gescrollt)
            // ------------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Betrag, Datum und Edit/Save-Icon
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.currencyFormat.format(
                            widget.receipt.totalAmount,
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        widget.dateFormat.format(widget.receipt.date),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 8),
                      // Bearbeiten / Speichern-Icon
                      _isEditing
                          ? IconButton(
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check),
                              tooltip: 'Änderungen speichern',
                              onPressed: _isSaving ? null : _saveChanges,
                            )
                          : IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Bearbeiten',
                              onPressed: () =>
                                  setState(() => _isEditing = true),
                            ),
                    ],
                  ),

                  const Divider(height: 24),

                  // Belegbild (antippen → Vollbild)
                  if (hasImage) ...[
                    _buildImagePreview(context),
                    const Divider(height: 24),
                  ],

                  // Abschnittstitel
                  Text(
                    'Erkannte Positionen',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ------------------------------------------------------------------
            // Scrollbare Artikel-Liste
            // ------------------------------------------------------------------
            Expanded(
              child: _nameControllers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Keine Positionen erkannt.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _nameControllers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) => _isEditing
                          ? _buildEditItemRow(context, index)
                          : _buildViewItemRow(context, index),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Belegbild-Vorschau: Tipp öffnet die Vollbild-Ansicht.
  Widget _buildImagePreview(BuildContext context) {
    final path = widget.receipt.imagePath!;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => _FullscreenImageViewer(imagePath: path),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Image.file(
              File(path),
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            // Kleines Zoom-Hinweis-Icon
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.zoom_in_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Schreibgeschützte Zeile für einen Artikel (Name + Preis als Text-Labels).
  Widget _buildViewItemRow(BuildContext context, int index) {
    final name = _nameControllers[index].text;
    final priceText = _priceControllers[index].text.trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      trailing: priceText.isNotEmpty
          ? Text(
              '$priceText €',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            )
          : null,
    );
  }

  /// Editierbare Zeile für einen Artikel (Name + Preis + Löschen-Button).
  Widget _buildEditItemRow(BuildContext context, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Artikelname
          Expanded(
            flex: 3,
            child: TextField(
              controller: _nameControllers[index],
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Artikel',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Preis
          SizedBox(
            width: 90,
            child: TextField(
              controller: _priceControllers[index],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preis',
                isDense: true,
                border: OutlineInputBorder(),
                suffixText: '€',
              ),
            ),
          ),
          // Löschen-Button
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Position entfernen',
            color: Theme.of(context).colorScheme.error,
            onPressed: () => _deleteItem(index),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Vollbild-Bildanzeige mit Zoom
// =============================================================================

/// Vollbild-Ansicht eines Belegbilds mit Pinch-to-Zoom via [InteractiveViewer].
class _FullscreenImageViewer extends StatelessWidget {
  const _FullscreenImageViewer({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Belegbild'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
