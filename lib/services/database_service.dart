import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/receipt.dart';

/// Service für die lokale SQLite-Datenbank.
///
/// Kapselt alle Datenbankoperationen für [Receipt]-Objekte:
///   - Initialisierung der Datenbank
///   - Einfügen eines neuen Belegs
///   - Laden aller Belege
///   - Löschen eines Belegs
class DatabaseService {
  static const _dbName = 'belegscanner.db';
  static const _tableName = 'receipts';
  static const _dbVersion = 2;

  Database? _db;

  /// Gibt die geöffnete Datenbankinstanz zurück.
  /// Öffnet die Datenbank beim ersten Aufruf (Lazy Initialization).
  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            totalAmount REAL NOT NULL,
            items TEXT NOT NULL,
            imagePath TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Version 1 hatte imagePath TEXT NOT NULL.
          // SQLite unterstützt kein direktes ALTER COLUMN,
          // daher Tabelle neu erstellen und Daten übertragen.
          await db.execute('''
            CREATE TABLE ${_tableName}_new (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              totalAmount REAL NOT NULL,
              items TEXT NOT NULL,
              imagePath TEXT
            )
          ''');
          await db.execute('''
            INSERT INTO ${_tableName}_new
              SELECT id, date, totalAmount, items, imagePath
              FROM $_tableName
          ''');
          await db.execute('DROP TABLE $_tableName');
          await db.execute(
            'ALTER TABLE ${_tableName}_new RENAME TO $_tableName',
          );
        }
      },
    );
  }

  /// Speichert einen [Receipt] in der Datenbank.
  ///
  /// Bereits vorhandene Einträge mit derselben ID werden ersetzt.
  Future<void> insertReceipt(Receipt receipt) async {
    final db = await database;
    await db.insert(
      _tableName,
      receipt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Gibt alle gespeicherten Belege zurück, absteigend nach Datum sortiert.
  Future<List<Receipt>> getAllReceipts() async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      orderBy: 'date DESC',
    );
    return maps.map(Receipt.fromMap).toList();
  }

  /// Löscht einen Beleg anhand seiner [id] aus der Datenbank.
  Future<void> deleteReceipt(String id) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Gibt den vollständigen Pfad zur Datenbankdatei zurück.
  Future<String> getDatabaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, _dbName);
  }

  /// Gibt das Verzeichnis zurück, in dem die Datenbank gespeichert ist.
  ///
  /// Dieses Verzeichnis ist app-privat und beschreibbar – geeignet für
  /// temporäre Export-Dateien.
  Future<String> getDatabasesDirectory() async {
    return getDatabasesPath();
  }

  /// Schließt die Datenbankverbindung.
  Future<void> close() async {
    try {
      await _db?.close();
    } finally {
      _db = null;
    }
  }
}
