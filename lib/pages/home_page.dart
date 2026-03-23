import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/ocr_service.dart';
import '../widgets/receipt_detail_view.dart';
import 'category_management_page.dart';

/// Hauptseite der Bong-Scanner-App.
///
/// Zeigt eine gefilterte Liste der gescannten Belege und ermöglicht
/// das Starten eines neuen Scans über den FloatingActionButton.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.databaseService});

  /// Optionaler gemeinsam genutzter Datenbankservice.
  final DatabaseService? databaseService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---------------------------------------------------------------------------
  // Zustand
  // ---------------------------------------------------------------------------

  final List<Receipt> _receipts = [];
  bool _isScanning = false;
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isFabExpanded = false;

  // ---------------------------------------------------------------------------
  // Services & Formatter
  // ---------------------------------------------------------------------------

  late final DatabaseService _databaseService;
  late final OcrService _ocrService;

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'de_DE',
    symbol: '€',
  );
  final DateFormat _dateFormat = DateFormat('d. MMMM yyyy', 'de_DE');

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _databaseService = widget.databaseService ?? DatabaseService();
    _ocrService = OcrService(databaseService: _databaseService);
    Future.delayed(const Duration(milliseconds: 500), _loadReceipts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesMerchant = receipt.items.isNotEmpty &&
            receipt.items.first.toLowerCase().contains(q);
        final matchesAmount =
            receipt.totalAmount.toString().contains(q) ||
                _currencyFormat.format(receipt.totalAmount).contains(q);
        final matchesItems =
            receipt.items.any((item) => item.toLowerCase().contains(q));
        if (!matchesMerchant && !matchesAmount && !matchesItems) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Aktionen
  // ---------------------------------------------------------------------------

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDay = picked.day;
        _selectedMonth = picked.month;
        _selectedYear = picked.year;
      });
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDay = null;
        _selectedMonth = picked.month;
        _selectedYear = picked.year;
      });
    }
  }

  Future<void> _pickYear() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDay = null;
        _selectedMonth = null;
        _selectedYear = picked.year;
      });
    }
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    try {
      final receipt = await _ocrService.scanReceipt();
      if (receipt != null && mounted) {
        await _databaseService.insertReceipt(receipt);
        setState(() => _receipts.add(receipt));
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

  void _clearFilters() {
    setState(() {
      _selectedDay = null;
      _selectedMonth = null;
      _selectedYear = null;
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _isSearching = false;
    });
  }

  Future<void> _importFromGallery() async {
    setState(() => _isScanning = true);
    try {
      final receipt = await _ocrService.importFromGallery();
      if (receipt != null && mounted) {
        await _databaseService.insertReceipt(receipt);
        setState(() => _receipts.add(receipt));
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

  Future<void> _deleteReceipt(Receipt receipt) async {
    await _databaseService.deleteReceipt(receipt.id);
    if (receipt.imagePath != null) {
      final imageFile = File(receipt.imagePath!);
      if (imageFile.existsSync()) {
        try {
          await imageFile.delete();
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() => _receipts.removeWhere((r) => r.id == receipt.id));
    }
  }

  // ---------------------------------------------------------------------------
  // Export / Sharing  (dünne UI-Wrapper um ExportService)
  // ---------------------------------------------------------------------------

  /// Teilt das Belegbild über das native Share-Sheet.
  Future<void> _shareReceipt(Receipt receipt) async {
    try {
      await ExportService.shareImage(receipt);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Teilen fehlgeschlagen. Bitte erneut versuchen.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Speichert das Belegbild in der Gerätegalerie.
  Future<void> _saveToGallery(Receipt receipt) async {
    try {
      final fileName = ExportService.getExportFileName(receipt);
      final success = await ExportService.saveImageToGallery(receipt);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Als $fileName in Galerie gespeichert')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Speichern in Galerie fehlgeschlagen. Bitte erneut versuchen.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Speichern in Galerie fehlgeschlagen. Bitte erneut versuchen.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Exportiert alle Belege als CSV und teilt sie über das Share-Sheet.
  Future<void> _exportToCsv() async {
    if (_receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine Belege zum Exportieren vorhanden.'),
        ),
      );
      return;
    }
    try {
      final cacheDir = await _databaseService.getDatabasesDirectory();
      await ExportService.shareCsv(_receipts, cacheDir);
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

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Zeigt die Detail-Ansicht eines Belegs in einem BottomSheet.
  void _showReceiptDetails(Receipt receipt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: ReceiptDetailView(
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
          onShare: _shareReceipt,
          onSaveToGallery: _saveToGallery,
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
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Händler, Betrag, Stichwort…',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                style: TextStyle(color: colorScheme.onSurface),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Bong-Scanner'),
        centerTitle: !_isSearching,
        actions: [
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
          if (_receipts.isNotEmpty && !_isSearching)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Belege als CSV exportieren',
              onPressed: _isScanning ? null : _exportToCsv,
            ),
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
        bottom: _isScanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: Column(
        children: [
          _FilterBar(
            hasReceipts: _receipts.isNotEmpty,
            selectedDay: _selectedDay,
            selectedMonth: _selectedMonth,
            selectedYear: _selectedYear,
            onPickDay: _pickDay,
            onPickMonth: _pickMonth,
            onPickYear: _pickYear,
            onClearAll: _clearFilters,
          ),
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
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

                // FAB-Menü-Hintergrund
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

                // Scan/Import-Overlay
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
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 40,
                      color:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bong-Scanner',
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Kategorien verwalten'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CategoryManagementPage(
                        databaseService: _databaseService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFab(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.hasReceipts,
    required this.selectedDay,
    required this.selectedMonth,
    required this.selectedYear,
    required this.onPickDay,
    required this.onPickMonth,
    required this.onPickYear,
    required this.onClearAll,
  });

  final bool hasReceipts;
  final int? selectedDay;
  final int? selectedMonth;
  final int? selectedYear;
  final VoidCallback onPickDay;
  final VoidCallback onPickMonth;
  final VoidCallback onPickYear;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final hasFilter =
        selectedDay != null || selectedMonth != null || selectedYear != null;
    if (!hasReceipts && !hasFilter) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildDateChip(
                context: context,
                label: selectedDay != null
                    ? 'Tag: ${selectedDay.toString().padLeft(2, '0')}.'
                        '${selectedMonth.toString().padLeft(2, '0')}.'
                        '$selectedYear'
                    : 'Tag',
                isSelected: selectedDay != null,
                onTap: onPickDay,
              ),
              const SizedBox(width: 8),
              _buildDateChip(
                context: context,
                label: selectedMonth != null && selectedDay == null
                    ? 'Monat: ${_monthName(selectedMonth!)} $selectedYear'
                    : 'Monat',
                isSelected: selectedMonth != null && selectedDay == null,
                onTap: onPickMonth,
              ),
              const SizedBox(width: 8),
              _buildDateChip(
                context: context,
                label: selectedYear != null &&
                        selectedMonth == null &&
                        selectedDay == null
                    ? 'Jahr: $selectedYear'
                    : 'Jahr',
                isSelected: selectedYear != null &&
                    selectedMonth == null &&
                    selectedDay == null,
                onTap: onPickYear,
              ),
              if (hasFilter) ...[
                const SizedBox(width: 12),
                ActionChip(
                  avatar: const Icon(Icons.clear, size: 16),
                  label: const Text('Alle anzeigen'),
                  onPressed: onClearAll,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildDateChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      avatar: isSelected ? null : const Icon(Icons.calendar_today, size: 14),
      visualDensity: VisualDensity.compact,
    );
  }

  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
    ];
    return names[month - 1];
  }
}

// =============================================================================
// Beleg-ListTile Widget
// =============================================================================

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

  Widget _buildThumbnail(BuildContext context) {
    final path = receipt.imagePath;
    if (path != null) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => FullscreenImageViewer(imagePath: path),
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
