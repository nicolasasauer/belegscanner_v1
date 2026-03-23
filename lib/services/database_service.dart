import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/category.dart';
import '../models/receipt.dart';

/// Service für die lokale SQLite-Datenbank.
///
/// Kapselt alle Datenbankoperationen für [Receipt]- und [Category]-Objekte:
///   - Initialisierung der Datenbank
///   - Einfügen, Laden und Löschen von Belegen
///   - Einfügen, Laden, Aktualisieren und Löschen von Kategorien
class DatabaseService {
  static const _dbName = 'belegscanner.db';
  static const _tableName = 'receipts';
  static const _categoriesTable = 'user_categories';
  static const _dbVersion = 5;

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
            categories TEXT NOT NULL DEFAULT '[]',
            imagePath TEXT,
            rawText TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE $_categoriesTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            keywords TEXT NOT NULL DEFAULT '',
            color TEXT NOT NULL DEFAULT ''
          )
        ''');
        await _insertDefaultCategories(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Version 1 hatte imagePath TEXT NOT NULL.
          // SQLite unterstützt kein direktes ALTER COLUMN,
          // daher Tabelle neu erstellen und Daten übertragen.
          // Die neue Tabelle enthält bereits die categories-Spalte (v3).
          await db.execute('''
            CREATE TABLE ${_tableName}_new (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              totalAmount REAL NOT NULL,
              items TEXT NOT NULL,
              categories TEXT NOT NULL DEFAULT '[]',
              imagePath TEXT,
              rawText TEXT
            )
          ''');
          await db.execute('''
            INSERT INTO ${_tableName}_new
              SELECT id, date, totalAmount, items, '[]', imagePath, NULL
              FROM $_tableName
          ''');
          await db.execute('DROP TABLE $_tableName');
          await db.execute(
            'ALTER TABLE ${_tableName}_new RENAME TO $_tableName',
          );
        } else if (oldVersion < 3) {
          // Version 2 → Version 3: Kategorien-Spalte hinzufügen.
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN categories TEXT NOT NULL DEFAULT '[]'",
          );
          // Direkt weiter zu v4 (rawText-Spalte) wenn nötig
          if (newVersion >= 4) {
            await db.execute(
              'ALTER TABLE $_tableName ADD COLUMN rawText TEXT',
            );
          }
        } else if (oldVersion < 4) {
          // Version 3 → Version 4: Roh-OCR-Text-Spalte hinzufügen.
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN rawText TEXT',
          );
        }
        // Version 4 → Version 5: Kategorien-Tabelle hinzufügen.
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $_categoriesTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              keywords TEXT NOT NULL DEFAULT '',
              color TEXT NOT NULL DEFAULT ''
            )
          ''');
          await _insertDefaultCategories(db);
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

  // ---------------------------------------------------------------------------
  // Kategorie-CRUD
  // ---------------------------------------------------------------------------

  /// Gibt alle benutzerdefinierten Kategorien zurück.
  Future<List<Category>> getCategories() async {
    final db = await database;
    final maps = await db.query(_categoriesTable, orderBy: 'name ASC');
    return maps.map(Category.fromMap).toList();
  }

  /// Fügt eine neue [Category] ein und gibt die erzeugte ID zurück.
  Future<int> insertCategory(Category category) async {
    final db = await database;
    return db.insert(
      _categoriesTable,
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Aktualisiert eine bestehende [Category] (anhand ihrer [Category.id]).
  Future<void> updateCategory(Category category) async {
    assert(category.id != null, 'Kategorie muss eine ID haben');
    final db = await database;
    await db.update(
      _categoriesTable,
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  /// Löscht eine Kategorie anhand ihrer [id].
  Future<void> deleteCategory(int id) async {
    final db = await database;
    await db.delete(
      _categoriesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Hilfsmethoden
  // ---------------------------------------------------------------------------

  /// Fügt die Standard-Kategorien in die Datenbank ein.
  ///
  /// Wird beim ersten App-Start (onCreate) und bei der Migration auf Version 5
  /// aufgerufen. Doppelte Einträge werden per IGNORE-Konflikt-Algorithmus
  /// verhindert – falls die Tabelle bereits Einträge enthält, werden keine
  /// weiteren Standardkategorien hinzugefügt.
  static Future<void> _insertDefaultCategories(Database db) async {
    const defaults = [
      {
        'name': 'Lebensmittel',
        'keywords': 'Bio,Tofu,Milch,Brot,Obst,Gemüse,Fruchtaufstr',
        'color': '#4CAF50',
      },
      {
        'name': 'Drogerie',
        'keywords': 'Shampoo,Zahnpasta,Duschgel,Balea,Hygiene,Seife',
        'color': '#2196F3',
      },
      {
        'name': 'Getränke',
        'keywords': 'Red Bull,Cola,Wasser,Saft,Wein,Bier',
        'color': '#FF9800',
      },
      {
        'name': 'Pfand',
        'keywords': 'Pfand,Leergut',
        'color': '#FFC107',
      },
    ];

    for (final cat in defaults) {
      await db.insert(
        _categoriesTable,
        cat,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
