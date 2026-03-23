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
      // Fortschritt: OCR startet (25 %)
      await _updateProgress(receipt, 0.25);

      // OCR auf dem Haupt-Isolate durchführen (ML Kit benötigt Platform Channels)
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

      // Fortschritt: OCR abgeschlossen, Parsing startet (50 %)
      await _updateProgress(receipt, 0.50);

      // Bild permanent speichern (falls tempPath noch ein Cache-Pfad ist)
      final permanentPath = await _persistImage(tempPath);

      // Fortschritt: Bild gespeichert (75 %)
      await _updateProgress(receipt, 0.75);

      // Kategorien laden
      List<Map<String, dynamic>> categoryData = [];
      try {
        final cats = await _databaseService.getCategories();
        categoryData = cats.map((c) => c.toMap()).toList();
      } catch (e) {
        debugPrint('[ProcessorService] Kategorien konnten nicht geladen werden: $e');
      }

      // Text-Parsing im Background-Isolate
      final result = await compute(_parseOcrText, {
        'text': fullText,
        'categoryData': categoryData,
      });

      // Abgeschlossenen Beleg speichern
      final completed = receipt.copyWith(
        totalAmount: result['amount'] as double,
        items: List<String>.from(result['items'] as List),
        categories: List<String>.from(result['categories'] as List),
        imagePath: permanentPath ?? tempPath,
        rawText: fullText.isEmpty ? null : fullText,
        status: 'completed',
        progress: 1.0,
      );

      await _databaseService.updateReceipt(completed);
      onReceiptUpdated?.call(completed);
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
      debugPrint('[ProcessorService] Bild konnte nicht persistiert werden: $e');
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
