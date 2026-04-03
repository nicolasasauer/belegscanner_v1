import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/receipt.dart';
import 'database_service.dart';
import 'ocr_service.dart';

// ---------------------------------------------------------------------------
// Shared-Preferences-Schlüssel
// ---------------------------------------------------------------------------

/// Schlüssel für die maximale Anzahl gleichzeitiger Verarbeitungsjobs.
const String kMaxConcurrentTasksKey = 'max_concurrent_tasks';

/// Standard-Wert für [kMaxConcurrentTasksKey].
const int kDefaultMaxConcurrentTasks = 2;

// ---------------------------------------------------------------------------
// ProcessorService
// ---------------------------------------------------------------------------

/// Verwaltet eine Warteschlange von OCR-Verarbeitungsaufgaben.
///
/// Verarbeitet Belege parallel bis zu [maxConcurrent] gleichzeitig.
/// Neue Aufgaben werden sofort in die Warteschlange aufgenommen; sobald ein
/// Slot frei wird, startet der nächste Job automatisch.
///
/// **Duplikatserkennung:** Vor dem Start jedes Jobs wird ein SHA-256-Hash
/// der Bilddatei berechnet (in einem Background-Isolate via [compute]).
/// Existiert bereits ein Beleg mit demselben Hash, wird der Job übersprungen
/// und der Zähler [skippedDuplicates] erhöht.
///
/// Benachrichtigungen über Statusänderungen werden über [onReceiptUpdated]
/// weitergeleitet.
class ProcessorService {
  ProcessorService({
    required DatabaseService databaseService,
    this.maxConcurrent = kDefaultMaxConcurrentTasks,
  }) : _databaseService = databaseService;

  final DatabaseService _databaseService;

  /// Maximale Anzahl gleichzeitig laufender Verarbeitungsjobs.
  int maxConcurrent;

  /// Callback, der aufgerufen wird, wenn ein Beleg aktualisiert wurde.
  ///
  /// Wird mit dem aktualisierten [Receipt] aufgerufen, sobald sich dessen
  /// Status oder Fortschritt ändert.
  ValueChanged<Receipt>? onReceiptUpdated;

  /// Anzahl der übersprungenen Duplikate seit dem letzten Batch-Start.
  int skippedDuplicates = 0;

  final Queue<_ProcessorTask> _queue = Queue();
  int _activeJobs = 0;
  final _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // Öffentliche API
  // ---------------------------------------------------------------------------

  /// Liest [maxConcurrent] aus den [SharedPreferences] und aktualisiert den Wert.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    maxConcurrent =
        prefs.getInt(kMaxConcurrentTasksKey) ?? kDefaultMaxConcurrentTasks;
  }

  /// Speichert [maxConcurrent] in den [SharedPreferences].
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kMaxConcurrentTasksKey, maxConcurrent);
  }

  /// Fügt einen neuen Verarbeitungsjob für [receipt] in die Warteschlange ein.
  ///
  /// Der übergebene [receipt] muss bereits mit `status: 'processing'` in der
  /// Datenbank gespeichert worden sein.
  void enqueue(Receipt receipt) {
    _queue.add(_ProcessorTask(receipt: receipt));
    _tryStartNext();
  }

  /// Markiert alle `'processing'`-Belege als `'failed'`.
  ///
  /// Sollte beim App-Start aufgerufen werden, um unterbrochene Jobs
  /// nach einem Absturz oder erzwungenem App-Neustart zu bereinigen.
  Future<void> markInterruptedAsFailed() async {
    final interrupted = await _databaseService.getProcessingReceipts();
    for (final receipt in interrupted) {
      final updated = receipt.copyWith(status: 'failed', progress: 0.0);
      await _databaseService.updateReceipt(updated);
      onReceiptUpdated?.call(updated);
    }
  }

  // ---------------------------------------------------------------------------
  // Interne Verarbeitungslogik
  // ---------------------------------------------------------------------------

  void _tryStartNext() {
    while (_activeJobs < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _activeJobs++;
      _processTask(task).then((_) {
        _activeJobs--;
        _tryStartNext();
      });
    }
  }

  Future<void> _processTask(_ProcessorTask task) async {
    final receipt = task.receipt;
    final tempPath = receipt.imagePath;

    if (tempPath == null || !File(tempPath).existsSync()) {
      // Kein Bild vorhanden → als fehlgeschlagen markieren
      final failed = receipt.copyWith(status: 'failed', progress: 0.0);
      await _databaseService.updateReceipt(failed);
      onReceiptUpdated?.call(failed);
      return;
    }

    try {
      // ── Schritt 1: SHA-256-Hash im Background-Isolate berechnen ──────────
      // Wir verwenden `compute` für alle Dateien – Isolate-Overhead ist für
      // Bilddateien (typisch 1–10 MB) vernachlässigbar gegenüber dem
      // UI-Jank durch synchrones Lesen im Haupt-Isolate.
      final hash = await compute(computeFileHash, tempPath);

      if (hash != null) {
        // ── Schritt 2: Duplikatsprüfung in der Datenbank ──────────────────
        final existingId =
            await _databaseService.findReceiptIdByFileHash(hash);
        if (existingId != null && existingId != receipt.id) {
          // Duplikat gefunden → Platzhalter aus der DB löschen und Zähler
          // erhöhen, damit die UI den Nutzer informieren kann.
          debugPrint(
              '[ProcessorService] Duplikat erkannt (hash=$hash, '
              'existingId=$existingId) – überspringe ${receipt.id}');
          await _databaseService.deleteReceipt(receipt.id);
          skippedDuplicates++;
          onReceiptUpdated?.call(receipt.copyWith(status: 'duplicate'));
          return;
        }
      }

      // ── Schritt 3: Fortschritt aktualisieren (25 %) ───────────────────────
      await _updateProgress(receipt, 0.25);

      // ── Schritt 4: OCR auf dem Haupt-Isolate ─────────────────────────────
      // ML Kit benötigt Platform Channels und kann nicht in einem Isolate
      // laufen. Die Fortschrittsanzeige sorgt dennoch für UI-Feedback.
      final inputImage = InputImage.fromFilePath(tempPath);
      final textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText;
      try {
        recognizedText = await textRecognizer.processImage(inputImage);
      } finally {
        await textRecognizer.close();
      }

      final fullText = recognizedText.text;

      // ── Schritt 5: Bild permanent speichern (50 %) ───────────────────────
      await _updateProgress(receipt, 0.50);
      final permanentPath = await _persistImage(tempPath);

      // ── Schritt 6: Kategorien + Mappings laden + Parsing (75 %) ──────────
      await _updateProgress(receipt, 0.75);

      List<Map<String, dynamic>> categoryData = [];
      List<Map<String, dynamic>> productMappings = [];
      try {
        final cats = await _databaseService.getCategories();
        categoryData = cats.map((c) => c.toMap()).toList();
      } catch (e) {
        debugPrint(
            '[ProcessorService] Kategorien konnten nicht geladen werden: $e');
      }
      try {
        productMappings = await _databaseService.getProductMappings();
      } catch (e) {
        debugPrint(
            '[ProcessorService] Produkt-Mappings konnten nicht geladen werden: $e');
      }

      // Händler-Profil für die bevorzugte Parsing-Strategie laden.
      // Der Händlername wird vorläufig aus dem Rohtext ermittelt, damit das
      // Profil schon vor dem eigentlichen compute-Aufruf geladen werden kann.
      Map<String, dynamic>? vendorProfile;
      final preliminaryVendor = detectMerchant(fullText);
      if (preliminaryVendor != null) {
        try {
          vendorProfile =
              await _databaseService.getVendorProfile(preliminaryVendor);
        } catch (e) {
          debugPrint(
              '[ProcessorService] Vendor-Profil konnte nicht geladen werden: $e');
        }
      }

      // Räumliche Zeilendaten aus ML-Kit-Ergebnis extrahieren.
      final spatialLines = <Map<String, dynamic>>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final rect = line.boundingBox;
          spatialLines.add({
            'text': line.text,
            'top': rect.top.toDouble(),
            'bottom': rect.bottom.toDouble(),
            'left': rect.left.toDouble(),
            'right': rect.right.toDouble(),
            'centerY': ((rect.top + rect.bottom) / 2.0),
            'centerX': ((rect.left + rect.right) / 2.0),
          });
        }
      }

      // Text-Parsing in einem Background-Isolate
      final result = await compute(parseOcrText, {
        'text': fullText,
        'categoryData': categoryData,
        'productMappings': productMappings,
        'spatialLines': spatialLines,
        if (vendorProfile != null) 'vendorProfile': vendorProfile,
      });

      // ── Schritt 7: Abgeschlossenen Beleg speichern ───────────────────────
      final dateStr = result['date'] as String?;
      final parsedDate = dateStr != null ? DateTime.tryParse(dateStr) : null;

      final completed = receipt.copyWith(
        date: parsedDate ?? receipt.date,
        totalAmount: result['amount'] as double,
        items: List<String>.from(result['items'] as List),
        categories: List<String>.from(result['categories'] as List),
        imagePath: permanentPath ?? tempPath,
        storeName: result['storeName'] as String?,
        spatialData: result['spatialData'] as String?,
        rawText: fullText.isEmpty ? null : fullText,
        status: 'completed',
        progress: 1.0,
        fileHash: hash,
      );

      await _databaseService.updateReceipt(completed);
      onReceiptUpdated?.call(completed);

      // ── Schritt 8: Vendor-Profil nach erfolgreichem Parsing aktualisieren ─
      final detectedVendor = result['storeName'] as String?;
      final parsedItems = result['items'] as List?;
      final usedStrategy = result['usedStrategy'] as String?;
      if (detectedVendor != null &&
          parsedItems != null &&
          parsedItems.isNotEmpty &&
          usedStrategy != null) {
        try {
          await _databaseService.upsertVendorProfile(
            detectedVendor,
            preferredStrategy: usedStrategy,
            incrementSuccess: true,
          );
        } catch (e) {
          debugPrint(
              '[ProcessorService] Vendor-Profil konnte nicht gespeichert werden: $e');
        }
      }
    } catch (e, st) {
      debugPrint('[ProcessorService] Fehler bei der Verarbeitung: $e\n$st');
      final failed = receipt.copyWith(status: 'failed', progress: 0.0);
      await _databaseService.updateReceipt(failed);
      onReceiptUpdated?.call(failed);
    }
  }

  Future<void> _updateProgress(Receipt receipt, double progress) async {
    final updated = receipt.copyWith(status: 'processing', progress: progress);
    await _databaseService.updateReceipt(updated);
    onReceiptUpdated?.call(updated);
  }

  /// Kopiert das Bild von [tempPath] in das permanente App-Dokumenten-
  /// Verzeichnis und gibt den neuen Pfad zurück.
  Future<String?> _persistImage(String tempPath) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(docsDir.path, 'receipt_images'));
      if (!imagesDir.existsSync()) {
        await imagesDir.create(recursive: true);
      }
      // Wenn das Bild bereits im Dokumenten-Verzeichnis liegt, nicht kopieren
      if (tempPath.startsWith(docsDir.path)) {
        return tempPath;
      }
      final fileName = '${_uuid.v4()}${p.extension(tempPath)}';
      final permanentFile = File(p.join(imagesDir.path, fileName));
      await File(tempPath).copy(permanentFile.path);
      return permanentFile.path;
    } catch (e) {
      debugPrint(
          '[ProcessorService] Bild konnte nicht persistiert werden: $e');
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Interne Hilfsklassen
// ---------------------------------------------------------------------------

class _ProcessorTask {
  _ProcessorTask({required this.receipt});
  final Receipt receipt;
}
