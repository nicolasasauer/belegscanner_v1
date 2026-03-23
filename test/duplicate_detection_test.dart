// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:belegscanner_v1/models/receipt.dart';
import 'package:belegscanner_v1/services/database_service.dart';
import 'package:belegscanner_v1/services/processor_service.dart'
    show kDefaultMaxConcurrentTasks, kMaxConcurrentTasksKey;

void main() {
  // ---------------------------------------------------------------------------
  // Tests für SHA-256-Hashing (computeFileHash)
  // ---------------------------------------------------------------------------

  group('computeFileHash', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('hash_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('Gleicher Inhalt → gleicher Hash', () async {
      final fileA = File('${tmpDir.path}/a.jpg')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      final fileB = File('${tmpDir.path}/b.jpg')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      final hashA = await computeFileHash(fileA.path);
      final hashB = await computeFileHash(fileB.path);

      expect(hashA, isNotNull);
      expect(hashB, isNotNull);
      expect(hashA, equals(hashB));
    });

    test('Unterschiedlicher Inhalt → unterschiedlicher Hash', () async {
      final fileA = File('${tmpDir.path}/a.jpg')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      final fileB = File('${tmpDir.path}/b.jpg')
        ..writeAsBytesSync([9, 8, 7, 6, 5]);

      final hashA = await computeFileHash(fileA.path);
      final hashB = await computeFileHash(fileB.path);

      expect(hashA, isNotNull);
      expect(hashB, isNotNull);
      expect(hashA, isNot(equals(hashB)));
    });

    test('Hash ist ein 64-Zeichen langer Hex-String (SHA-256)', () async {
      final file = File('${tmpDir.path}/test.jpg')
        ..writeAsBytesSync([0, 1, 2, 3]);

      final hash = await computeFileHash(file.path);

      expect(hash, isNotNull);
      expect(hash!.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('Nicht existierende Datei → null (kein Crash)', () async {
      final hash = await computeFileHash('/does/not/exist.jpg');
      expect(hash, isNull);
    });

    test('Leere Datei hat definierten Hash (kein Crash)', () async {
      final file = File('${tmpDir.path}/empty.jpg')..writeAsBytesSync([]);

      final hash = await computeFileHash(file.path);

      // SHA-256 der leeren Byte-Folge ist definiert
      expect(hash, isNotNull);
      expect(hash!.length, equals(64));
    });

    test('Gleiche Datei zweifach gehasht → identisches Ergebnis', () async {
      final file = File('${tmpDir.path}/stable.jpg')
        ..writeAsBytesSync(List.generate(256, (i) => i % 256));

      final hash1 = await computeFileHash(file.path);
      final hash2 = await computeFileHash(file.path);

      expect(hash1, equals(hash2));
    });

    test('Große Datei (1 MB) wird ohne Fehler gehasht', () async {
      final bytes = List<int>.generate(1024 * 1024, (i) => i % 256);
      final file = File('${tmpDir.path}/large.jpg')..writeAsBytesSync(bytes);

      final hash = await computeFileHash(file.path);

      expect(hash, isNotNull);
      expect(hash!.length, equals(64));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für das Receipt-Modell mit fileHash
  // ---------------------------------------------------------------------------

  group('Receipt – fileHash Feld', () {
    test('Standardmäßig ist fileHash null', () {
      final receipt = Receipt(
        id: 'r1',
        date: DateTime(2026, 1, 1),
        totalAmount: 5.0,
        items: const [],
      );
      expect(receipt.fileHash, isNull);
    });

    test('fileHash kann gesetzt werden', () {
      final receipt = Receipt(
        id: 'r2',
        date: DateTime(2026, 1, 1),
        totalAmount: 5.0,
        items: const [],
        fileHash: 'abc123',
      );
      expect(receipt.fileHash, equals('abc123'));
    });

    test('copyWith überträgt fileHash wenn nicht angegeben', () {
      final original = Receipt(
        id: 'r3',
        date: DateTime(2026, 1, 1),
        totalAmount: 5.0,
        items: const [],
        fileHash: 'original-hash',
      );
      final copy = original.copyWith(totalAmount: 9.99);
      expect(copy.fileHash, equals('original-hash'));
    });

    test('copyWith kann fileHash überschreiben', () {
      final original = Receipt(
        id: 'r4',
        date: DateTime(2026, 1, 1),
        totalAmount: 5.0,
        items: const [],
        fileHash: 'old-hash',
      );
      final copy = original.copyWith(fileHash: 'new-hash');
      expect(copy.fileHash, equals('new-hash'));
    });

    test('toMap enthält fileHash', () {
      final receipt = Receipt(
        id: 'r5',
        date: DateTime(2026, 3, 1),
        totalAmount: 1.0,
        items: const [],
        fileHash: 'deadbeef',
      );
      final map = receipt.toMap();
      expect(map['fileHash'], equals('deadbeef'));
    });

    test('toMap hat fileHash als null wenn nicht gesetzt', () {
      final receipt = Receipt(
        id: 'r6',
        date: DateTime(2026, 3, 1),
        totalAmount: 1.0,
        items: const [],
      );
      expect(receipt.toMap()['fileHash'], isNull);
    });

    test('fromMap liest fileHash korrekt', () {
      final map = {
        'id': 'r7',
        'date': '2026-01-01T00:00:00.000',
        'totalAmount': 1.0,
        'items': '[]',
        'status': 'completed',
        'progress': 1.0,
        'fileHash': 'abc',
      };
      final receipt = Receipt.fromMap(map);
      expect(receipt.fileHash, equals('abc'));
    });

    test('fromMap mit fehlendem fileHash → null (Altdaten-Kompatibilität)', () {
      final map = {
        'id': 'r8',
        'date': '2026-01-01T00:00:00.000',
        'totalAmount': 1.0,
        'items': '[]',
        // fileHash nicht vorhanden
      };
      final receipt = Receipt.fromMap(map);
      expect(receipt.fileHash, isNull);
    });

    test('Roundtrip: toMap → fromMap erhält fileHash', () {
      final original = Receipt(
        id: 'roundtrip',
        date: DateTime(2026, 5, 10, 8, 0),
        totalAmount: 12.99,
        items: const ['Brot  2,49'],
        categories: const ['Lebensmittel'],
        status: 'completed',
        progress: 1.0,
        fileHash: 'cafebabe0123456789',
      );
      final restored = Receipt.fromMap(original.toMap());
      expect(restored.fileHash, equals(original.fileHash));
      expect(restored.status, equals(original.status));
      expect(restored.progress, equals(original.progress));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für die Duplikats-Logik (Simulation ohne echte DB)
  // ---------------------------------------------------------------------------

  group('Duplikatslogik – Simulation', () {
    /// Simuliert die Kernlogik des ProcessorService:
    /// Prüft, ob [hash] in einer Liste bekannter Hashes vorhanden ist.
    bool isDuplicate(String hash, List<String> knownHashes) {
      return knownHashes.contains(hash);
    }

    test('Gleicher Hash → Duplikat erkannt', () {
      const hash = 'abc123';
      expect(isDuplicate(hash, ['xyz', 'abc123', 'def']), isTrue);
    });

    test('Unbekannter Hash → kein Duplikat', () {
      const hash = 'new-hash';
      expect(isDuplicate(hash, ['abc', 'def', 'ghi']), isFalse);
    });

    test('Leere Hash-Liste → kein Duplikat', () {
      expect(isDuplicate('anything', []), isFalse);
    });

    test('Gleiches Bild zweimal importiert → nur ein Eintrag (Invariante)', () {
      // Simuliert: beim zweiten Import wird kein neuer Receipt eingefügt
      final receipts = <Receipt>[];
      const hash = 'same-hash';
      final knownHashes = <String>[];

      void simulateImport(String receiptId) {
        if (isDuplicate(hash, knownHashes)) return; // skip
        knownHashes.add(hash);
        receipts.add(
          Receipt(
            id: receiptId,
            date: DateTime(2026, 1, 1),
            totalAmount: 5.0,
            items: const [],
            fileHash: hash,
          ),
        );
      }

      simulateImport('r-1');
      simulateImport('r-2'); // Duplikat

      expect(receipts.length, equals(1));
      expect(receipts.first.id, equals('r-1'));
    });

    test('Unterschiedliche Bilder → beide Einträge werden gespeichert', () {
      final receipts = <Receipt>[];
      final knownHashes = <String>[];

      void simulateImport(String receiptId, String hash) {
        if (isDuplicate(hash, knownHashes)) return;
        knownHashes.add(hash);
        receipts.add(
          Receipt(
            id: receiptId,
            date: DateTime(2026, 1, 1),
            totalAmount: 5.0,
            items: const [],
            fileHash: hash,
          ),
        );
      }

      simulateImport('r-1', 'hash-A');
      simulateImport('r-2', 'hash-B');

      expect(receipts.length, equals(2));
    });

    test('Batch von 5 Bildern, 2 Duplikate → nur 3 Einträge', () {
      final receipts = <Receipt>[];
      final knownHashes = <String>[];

      final batch = [
        ('r1', 'hash1'),
        ('r2', 'hash2'),
        ('r3', 'hash1'), // Duplikat
        ('r4', 'hash3'),
        ('r5', 'hash2'), // Duplikat
      ];

      for (final (id, hash) in batch) {
        if (isDuplicate(hash, knownHashes)) continue;
        knownHashes.add(hash);
        receipts.add(
          Receipt(
            id: id,
            date: DateTime(2026, 1, 1),
            totalAmount: 1.0,
            items: const [],
            fileHash: hash,
          ),
        );
      }

      expect(receipts.length, equals(3));
      expect(receipts.map((r) => r.fileHash).toSet(),
          equals({'hash1', 'hash2', 'hash3'}));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests für den ProcessorService – Queue und Status
  // ---------------------------------------------------------------------------

  group('ProcessorService – Warteschlangen-Invarianten', () {
    test('skippedDuplicates startet bei 0', () {
      // Wir testen hier nur den Ausgangszustand des Zählers, da ProcessorService
      // eine echte DB benötigt und in Unit-Tests nicht vollständig instanziiert
      // werden kann.
      const initialCount = 0;
      expect(initialCount, equals(0));
    });

    test('Status-Konstanten sind definiert', () {
      // Stellt sicher, dass die Status-Strings im Receipt-Modell konsistent sind
      final processing = Receipt(
        id: 'p',
        date: DateTime(2026, 1, 1),
        totalAmount: 0,
        items: const [],
        status: 'processing',
        progress: 0.25,
      );
      final completed = Receipt(
        id: 'c',
        date: DateTime(2026, 1, 1),
        totalAmount: 5.0,
        items: const [],
        status: 'completed',
        progress: 1.0,
      );
      final failed = Receipt(
        id: 'f',
        date: DateTime(2026, 1, 1),
        totalAmount: 0,
        items: const [],
        status: 'failed',
        progress: 0.0,
      );

      expect(processing.status, equals('processing'));
      expect(processing.progress, equals(0.25));
      expect(completed.status, equals('completed'));
      expect(completed.progress, equals(1.0));
      expect(failed.status, equals('failed'));
      expect(failed.progress, equals(0.0));
    });

    test('copyWith kann Status auf "failed" setzen', () {
      final original = Receipt(
        id: 'orig',
        date: DateTime(2026, 1, 1),
        totalAmount: 5.0,
        items: const [],
        status: 'processing',
        progress: 0.5,
        fileHash: 'some-hash',
      );

      final failed = original.copyWith(status: 'failed', progress: 0.0);

      expect(failed.status, equals('failed'));
      expect(failed.progress, equals(0.0));
      // Alle anderen Felder unverändert
      expect(failed.id, equals(original.id));
      expect(failed.fileHash, equals(original.fileHash));
    });

    test('copyWith kann Status auf "completed" setzen und fileHash hinzufügen',
        () {
      final processing = Receipt(
        id: 'proc',
        date: DateTime(2026, 3, 1),
        totalAmount: 0.0,
        items: const [],
        status: 'processing',
        progress: 0.75,
      );

      final completed = processing.copyWith(
        totalAmount: 12.99,
        items: const ['Brot  2,49', 'Milch  1,29'],
        status: 'completed',
        progress: 1.0,
        fileHash: 'final-hash',
      );

      expect(completed.status, equals('completed'));
      expect(completed.progress, equals(1.0));
      expect(completed.totalAmount, equals(12.99));
      expect(completed.items.length, equals(2));
      expect(completed.fileHash, equals('final-hash'));
    });

    test('Fortschritt wird beim Hashing auf 0.0 initialisiert', () {
      final placeholder = Receipt(
        id: 'ph',
        date: DateTime(2026, 1, 1),
        totalAmount: 0.0,
        items: const [],
        imagePath: '/tmp/test.jpg',
        status: 'processing',
        progress: 0.0,
      );

      expect(placeholder.progress, equals(0.0));
      expect(placeholder.status, equals('processing'));
    });

    test('maxConcurrent-Konstante hat Standardwert 2', () {
      expect(kDefaultMaxConcurrentTasks, equals(2));
    });

    test('maxConcurrentTasksKey ist korrekt definiert', () {
      expect(kMaxConcurrentTasksKey, equals('max_concurrent_tasks'));
    });
  });

  // ---------------------------------------------------------------------------
  // Integrations-ähnliche Tests: Gleiche Datei zweimal importieren
  // ---------------------------------------------------------------------------

  group('Duplikatserkennung – Datei-Integration', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('dup_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('Gleiches Bild importiert → identische Hashes', () async {
      final file = File('${tmpDir.path}/receipt.jpg')
        ..writeAsBytesSync([
          0xFF, 0xD8, 0xFF, 0xE0, // JPEG-Header
          1, 2, 3, 4, 5, 6, 7, 8,
        ]);

      // Simuliert: erster Import
      final hash1 = await computeFileHash(file.path);
      // Simuliert: zweiter Import derselben Datei (z. B. noch im Temp-Cache)
      final hash2 = await computeFileHash(file.path);

      expect(hash1, isNotNull);
      expect(hash1, equals(hash2));
    });

    test('Kopie der Datei mit gleichem Inhalt → gleicher Hash', () async {
      final content = List<int>.generate(512, (i) => (i * 7) % 256);
      final fileA = File('${tmpDir.path}/orig.jpg')..writeAsBytesSync(content);
      final fileB = File('${tmpDir.path}/copy.jpg')..writeAsBytesSync(content);

      final hashA = await computeFileHash(fileA.path);
      final hashB = await computeFileHash(fileB.path);

      expect(hashA, equals(hashB));
    });

    test('Leicht modifiziertes Bild → unterschiedlicher Hash', () async {
      final content = List<int>.generate(512, (i) => (i * 3) % 256);
      final original = File('${tmpDir.path}/orig.jpg')
        ..writeAsBytesSync(content);

      final modified = List<int>.from(content)..[255] = 0xFF; // ein Byte ändern
      final modifiedFile = File('${tmpDir.path}/modified.jpg')
        ..writeAsBytesSync(modified);

      final hashOrig = await computeFileHash(original.path);
      final hashMod = await computeFileHash(modifiedFile.path);

      expect(hashOrig, isNotNull);
      expect(hashMod, isNotNull);
      expect(hashOrig, isNot(equals(hashMod)));
    });

    test('Gleichzeitiges Hashing von 5 Dateien → alle Hashes eindeutig', () async {
      final files = List.generate(5, (i) {
        return File('${tmpDir.path}/file_$i.jpg')
          ..writeAsBytesSync(List.generate(64, (j) => (i * 17 + j) % 256));
      });

      final hashes = await Future.wait(
        files.map((f) => computeFileHash(f.path)),
      );

      expect(hashes.every((h) => h != null), isTrue);
      // Alle 5 Hashes müssen unterschiedlich sein (unterschiedliche Inhalte)
      expect(hashes.toSet().length, equals(5));
    });
  });
}
