import 'dart:io';

import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';
import 'ocr_service.dart';

/// Stellt statische Hilfsmethoden für den Export und das Teilen von
/// Belegen bereit (Belegbild-Sharing, Galerie-Speicherung, CSV-Export).
class ExportService {
  // Nur statische Methoden – keine Instanz nötig.
  ExportService._();

  // ---------------------------------------------------------------------------
  // Dateinamen
  // ---------------------------------------------------------------------------

  /// Generiert einen sprechenden Dateinamen für den Export des Belegbilds.
  ///
  /// Format: `YYYY-MM-DD_Händler_Betrag.jpg`
  /// Beispiel: `2026-03-23_Spar_10.76.jpg`
  ///
  /// Verbotene Zeichen (`/ \ : * ? " < > |`) und Leerzeichen werden aus dem
  /// Händlernamen entfernt; Dezimalkomma wird durch Punkt ersetzt.
  static String getExportFileName(Receipt receipt) {
    final dateStr = DateFormat('yyyy-MM-dd').format(receipt.date);
    final rawMerchant = receipt.items.isNotEmpty
        ? parseLineItem(receipt.items.first).name
        : 'Unbekannt';
    final sanitizedMerchant =
        rawMerchant.replaceAll(RegExp(r'[ /\\:*?"<>|]'), '');
    final merchant =
        sanitizedMerchant.isNotEmpty ? sanitizedMerchant : 'Unbekannt';
    final totalStr =
        receipt.totalAmount.toStringAsFixed(2).replaceAll(',', '.');
    return '${dateStr}_${merchant}_$totalStr.jpg';
  }

  // ---------------------------------------------------------------------------
  // Belegbild-Export
  // ---------------------------------------------------------------------------

  /// Erstellt eine temporäre Kopie des Belegbilds mit dem Smart-Dateinamen
  /// und öffnet das native Share-Sheet.
  ///
  /// Wirft eine Exception, wenn etwas schiefläuft (kein imagePath, I/O-Fehler).
  static Future<void> shareImage(Receipt receipt) async {
    final imagePath = receipt.imagePath;
    if (imagePath == null) return;

    final fileName = getExportFileName(receipt);
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, fileName);
    await File(imagePath).copy(tempPath);

    await Share.shareXFiles([XFile(tempPath)]);

    // Temporäre Datei nach dem Teilen aufräumen.
    final tempFile = File(tempPath);
    if (await tempFile.exists()) await tempFile.delete();
  }

  /// Speichert das Belegbild mit dem Smart-Dateinamen in der Gerätegalerie.
  ///
  /// Gibt `true` zurück, wenn [ImageGallerySaver] Erfolg meldet, sonst
  /// `false`. Wirft eine Exception bei I/O- oder API-Fehlern.
  static Future<bool> saveImageToGallery(Receipt receipt) async {
    final imagePath = receipt.imagePath;
    if (imagePath == null) return false;

    final fileName = getExportFileName(receipt);
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, fileName);
    await File(imagePath).copy(tempPath);

    final result = await ImageGallerySaver.saveFile(tempPath);

    // Temporäre Datei nach dem Speichern aufräumen.
    final tempFile = File(tempPath);
    if (await tempFile.exists()) await tempFile.delete();

    return result is Map && result['isSuccess'] == true;
  }

  // ---------------------------------------------------------------------------
  // CSV-Export
  // ---------------------------------------------------------------------------

  /// Maskiert ein CSV-Feld gemäß RFC 4180.
  ///
  /// Enthält das Feld ein Semikolon oder Anführungszeichen, wird es in
  /// doppelte Anführungszeichen eingeschlossen.
  static String escapeCsvField(String value) {
    final cleaned = value.replaceAll('\n', ' ').replaceAll('\r', '');
    if (cleaned.contains(';') || cleaned.contains('"')) {
      return '"${cleaned.replaceAll('"', '""')}"';
    }
    return cleaned;
  }

  /// Baut den CSV-Inhalt für die übergebene Belegliste auf.
  ///
  /// Spalten: `Datum;Händler;Gesamtbetrag (EUR);Artikel`
  static String buildCsvContent(List<Receipt> receipts) {
    final buffer = StringBuffer();
    buffer.writeln('Datum;Händler;Gesamtbetrag (EUR);Artikel');

    final amountFormat = NumberFormat('#,##0.00', 'de_DE');
    final exportDateFormat = DateFormat('yyyy-MM-dd', 'de_DE');

    for (final receipt in receipts) {
      final date = exportDateFormat.format(receipt.date);
      final merchant = receipt.items.isNotEmpty
          ? escapeCsvField(receipt.items.first)
          : '';
      final amount = amountFormat.format(receipt.totalAmount);
      final items = receipt.items.length > 1
          ? escapeCsvField(receipt.items.sublist(1).join(' | '))
          : '';
      buffer.writeln('$date;$merchant;$amount;$items');
    }
    return buffer.toString();
  }

  /// Schreibt den CSV-Export in [cacheDir] und teilt ihn über das native
  /// Share-Sheet.
  static Future<void> shareCsv(
    List<Receipt> receipts,
    String cacheDir,
  ) async {
    final content = buildCsvContent(receipts);
    final file = File(p.join(cacheDir, 'belege_export.csv'));
    await file.writeAsString(content, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Bong-Scanner Export',
      text: 'Exportierte Belege aus der Bong-Scanner-App.',
    );
  }
}
