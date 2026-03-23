# Bong-Scanner 📷

Eine Flutter-App für Android zum **Einscannen**, **Speichern**, **Durchsuchen** und **Exportieren** von Kassenbons – vollständig On-Device, ohne Cloud.

---

## Screenshots

| Leere Startseite | Beleg-Liste | Scan-Vorgang | Beleg-Detail |
|:---:|:---:|:---:|:---:|
| ![Leere Startseite](screenshots/screenshot_01_empty.png) | ![Beleg-Liste](screenshots/screenshot_02_list.png) | ![Scan-Vorgang](screenshots/screenshot_03_scanning.png) | ![Beleg-Detail](screenshots/screenshot_04_detail.png) |
| Startbildschirm ohne Belege | Gefilterte Beleg-Liste mit Datum-FilterChips | Kamera-Scanner in Aktion | Detail-BottomSheet mit erkannten Positionen und Einzelpreisen |

---

## Features

| # | Feature | Beschreibung |
|---|---|---|
| 📷 | **On-Device OCR** | Belege per Kamera fotografieren – Text wird lokal mit Google ML Kit erkannt, kein Bild verlässt das Gerät |
| 🗄️ | **SQLite-Persistenz** | Alle Belege (Datum, Betrag, Artikel, Bildpfad, Kategorien, OCR-Rohtext) werden dauerhaft in einer lokalen SQLite-Datenbank gespeichert und überleben jeden App-Neustart |
| 🖼️ | **Bild-Thumbnail & Vollbild** | Das Originalbild jedes Belegs wird permanent im App-eigenen Dokumenten-Verzeichnis gespeichert; Thumbnail in der Liste, Vollbild-Ansicht per Antippen im Detail-Sheet |
| 💶 | **Automatische Betragserkennung** | 3-stufige Priorisierung: erst `SUMME`/`TOTAL` zeilenweise, dann andere Gesamt-Keywords per Regex, dann `EUR`/`€`-Muster – verhindert, dass Kassenbonendzeilen den Hauptbetrag überschreiben |
| 🧾 | **Verbesserte Artikelerkennung** | Header-Cut (erster Datums-/Uhrzeiteintrag), Footer-Cut (SUMME/TOTAL/GESAMT), Garbage-Filter (Sonderzeichen, URLs, 15+-stellige Zahlen); 3-Zeilen-Artikel (Name → Mengenberechnung → Preis) werden korrekt zusammengeführt |
| ✏️ | **Beleg bearbeiten** | Im Detail-BottomSheet können Artikelnamen und Preise direkt bearbeitet, neue Positionen hinzugefügt und einzelne Einträge gelöscht werden |
| 🏷️ | **Artikel-Kategorien** | Jede Einzelposition kann im Bearbeitungs-Modus einer Kategorie zugewiesen werden: *Lebensmittel*, *Drogerie*, *Freizeit*, *Transport*, *Sonstiges* – wird in der Datenbank persistent gespeichert |
| 🔢 | **Summe aus Artikeln berechnen** | Ein Knopfdruck im Bearbeitungs-Modus berechnet den Gesamtbetrag automatisch aus der Summe der eingetragenen Einzelpreise; eine Abweichungswarnung (🔶) weist auf Differenzen hin |
| 🔍 | **Volltextsuche** | Belege nach Händlername, Betrag oder Stichwörtern in den Einzelpositionen durchsuchen |
| 🗂️ | **Datum-Filter** | Belege nach Tag, Monat und Jahr filtern – kombinierbare FilterChips |
| 📤 | **CSV-Export** | Alle Belege als RFC-4180-konforme CSV-Datei exportieren und per Share-Sheet (E-Mail, Messenger, Cloud) teilen |
| 📥 | **Multi-Galerie-Import** | Mehrere Bonfotos gleichzeitig aus der Gerätegalerie importieren – alle Jobs laufen parallel in einer konfigurierbaren Concurrency-Queue |
| 🔒 | **SHA-256 Duplikatschutz** | Vor der OCR-Verarbeitung wird ein SHA-256-Hash des Bildes berechnet; identische Bilder werden erkannt und übersprungen |
| ⚡ | **Concurrency-Queue** | Maximal N OCR-Jobs laufen gleichzeitig (einstellbar 1–5); weitere Jobs warten in der Warteschlange |
| 📁 | **Smart-Export-Rename** | Belegbilder werden beim Galerie-Export automatisch nach `JJJJ-MM-TT_Händler_Betrag.jpg` umbenannt |
| 🗑️ | **Sicheres Löschen** | Belege per Wisch-Geste löschen – Datenbankeintrag UND Bilddatei werden vollständig entfernt |
| 🐛 | **Raw-OCR-Debug-Modus** | Easter Egg: 5-maliges schnelles Antippen (< 2 s) des Belegbilds öffnet ein BottomSheet mit dem vollständigen OCR-Rohtext – ideal zur Fehleranalyse, Rohtext lässt sich in die Zwischenablage kopieren |
| 🌙 | **Material 3** | Light- und Dark-Theme, dynamische Indigo-Farbpalette |
| 🌍 | **Deutsches Locale** | Euro-Formatierung (`42,50 €`) und deutsche Monatsnamen |

---

## 🔒 Datenschutz & Local-First

> **Alle deine Daten bleiben auf deinem Gerät. Immer. Ohne Ausnahme.**

Der Bong-Scanner wurde von Grund auf nach dem **Local-First**-Prinzip entwickelt:

- **Keine Cloud-Verbindung** durch App-eigenen Code – kein Backend, kein Server, keine Telemetrie durch die App
- **Keine Konten** – keine Registrierung, kein Login, keine E-Mail-Adresse notwendig
- **Alle Belegbilder** werden permanent im App-privaten Dokumenten-Verzeichnis (`getApplicationDocumentsDirectory()`) gespeichert – nicht im externen Speicher, nicht in der Galerie
- **Die SQLite-Datenbank** ist ausschließlich für die App zugänglich (Android-Sandbox)
- **OCR-Verarbeitung** findet vollständig on-device statt – das Belegbild und der erkannte Text verlassen das Gerät nicht durch App-Code
- **CSV-Export** öffnet nur das native Share-Sheet – du entscheidest, wohin die Datei geht
- **Beim Löschen** eines Belegs werden Datenbankeintrag UND Bilddatei unwiderruflich vom Gerät entfernt

> **Hinweis zu Google ML Kit:** Das verwendete OCR-Framework kann anonyme Performance-Metriken (Verarbeitungszeit, SDK-Version) an Google übertragen. Diese enthalten **keine** Bildinhalte, erkannten Texte oder Beträge. Für maximalen Datenschutz kann alternativ `flutter_tesseract_ocr` (vollständig offline) evaluiert werden.

---

## Technologie

| Komponente | Technologie |
|---|---|
| Framework | **Flutter** (Dart) – Material 3 |
| OCR-Engine | **Google ML Kit** (`google_mlkit_text_recognition`) – vollständig on-device |
| Datenbank | **sqflite** – lokale SQLite-Persistenz |
| Datei-Sharing | **share_plus** – natives OS Share-Sheet für CSV-Export |
| App-Verzeichnisse | **path_provider** – permanenter App-Speicher für Belegbilder |
| Bildauswahl | **image_picker** – Kamera & Galerie |
| Formatierung | **intl** – Datum & Währung (de_DE) |
| IDs | **uuid** v4 – kollisionsfreie Beleg-IDs |
| Duplikatserkennung | **crypto** – SHA-256-Hash vor OCR |
| Einstellungen | **shared_preferences** – persistente Nutzereinstellungen |

---

## Architektur

```
lib/
├── main.dart                           # App-Einstiegspunkt, BongScannerApp, Material-3-Theme
├── models/
│   ├── receipt.dart                    # Receipt-Datenmodell (id, date, totalAmount, items,
│   │                                   #   categories, imagePath, rawText, status, progress,
│   │                                   #   fileHash)
│   └── category.dart                   # Category-Modell für benutzerdefinierte Kategorien
├── services/
│   ├── ocr_service.dart                # OCR-Logik: Kamera/Galerie → ML Kit → Parsing
│   │                                   #   (Background-Isolate via compute())
│   ├── database_service.dart           # SQLite-Persistenz v7: CRUD für Belege & Kategorien
│   ├── processor_service.dart          # Concurrency-Queue: max. N parallele OCR-Jobs,
│   │                                   #   SHA-256-Duplikatsprüfung vor OCR
│   ├── export_service.dart             # CSV-Export, Bild-Sharing, Galerie-Speicherung
│   │                                   #   (Smart-Rename: YYYY-MM-DD_Merchant_Total.jpg)
│   └── category_service.dart          # Kategorisierungs-Logik (smartCategorize)
├── pages/
│   ├── home_page.dart                  # Haupt-Screen: Suche, Filter-Bar, ListView, FAB
│   │                                   #   Speed-Dial, CSV-Export, Detail-BottomSheet
│   ├── dashboard_page.dart             # Statistik-Dashboard mit fl_chart-Diagrammen
│   └── category_management_page.dart  # CRUD-Verwaltung benutzerdefinierter Kategorien
└── widgets/
    ├── receipt_detail_view.dart        # Detail-BottomSheet: Bearbeitung, Kategorien,
    │                                   #   Bild-Vorschau, Raw-OCR-Debug-Modus
    ├── receipt_list_tile.dart          # Kompakter Listeneintrag (Thumbnail, Betrag, Datum)
    ├── filter_bar.dart                 # Horizontale Datums-FilterChip-Leiste
    ├── processing_receipt_card.dart    # Shimmer-Platzhalter für laufende OCR-Jobs
    └── fab_menu_item.dart              # Speed-Dial-FAB-Menüeintrag (Label + kleiner FAB)
```

### Datenmodell `Receipt`

| Feld | Typ | Beschreibung |
|---|---|---|
| `id` | `String` | UUID v4 – kollisionsfreie Beleg-ID |
| `date` | `DateTime` | Erkanntes Belegdatum |
| `totalAmount` | `double` | Gesamtbetrag in Euro |
| `items` | `List<String>` | Erkannte Einzelposten (Format: `"Name  Preis"`) |
| `categories` | `List<String>` | Kategorien parallel zu `items`; Fallback: `"Sonstiges"` |
| `imagePath` | `String?` | Pfad zum gespeicherten Belegbild (kann `null` sein) |
| `rawText` | `String?` | Vollständiger OCR-Rohtext vor jeder Filterung (DB v7) |
| `status` | `String` | Verarbeitungsstatus: `completed`, `processing`, `failed`, `duplicate` |
| `progress` | `double` | Fortschritt 0.0–1.0 während der Hintergrundverarbeitung |
| `fileHash` | `String?` | SHA-256-Hash des Belegbildes für Duplikatserkennung |

### Datenfluss

```
App-Start
    └─► _loadReceipts()
            └─► DatabaseService.getAllReceipts()  ──► SQLite v7 (sqflite)
                    └─► Receipt-Liste → setState → ListView

FAB → Galerie-Import (Multi-Bild)
    └─► OcrService.pickMultipleImages()  ──► Platzhalter-Receipts (status: processing)
            └─► ProcessorService.enqueue(placeholder)
                    ├─► SHA-256-Hash berechnen → Duplikat? → status: duplicate → UI entfernen
                    ├─► GoogleMlKit TextRecognizer  (on-device)
                    ├─► compute(parseOcrText)        (Background-Isolate)
                    │       ├─► parseAmountImpl()  (3-stufig: SUMME/TOTAL → Keywords → EUR/€)
                    │       └─► parseItemsImpl()   (Header-Cut, Footer-Cut, Garbage-Filter)
                    └─► Receipt updaten → DatabaseService.insertReceipt() ──► SQLite
                            └─► onReceiptUpdated-Callback → setState → ListView

FAB → Kamera-Scan
    └─► OcrService.scanReceipt()  (direkter Scan ohne Queue)
            ├─► ImagePicker (Kamera)
            ├─► GoogleMlKit TextRecognizer + compute(parseOcrText)
            └─► DatabaseService.insertReceipt()  ──► SQLite → setState → ListView

Detail-BottomSheet (Bearbeitungs-Modus)
    └─► _saveChanges()
            ├─► Receipt.copyWith(items, categories, totalAmount)
            └─► DatabaseService.insertReceipt()  ──► SQLite (Upsert)
                    └─► onSaved-Callback → setState

Easter Egg: 5 Taps in < 2 s auf Belegbild
    └─► _showRawOcrSheet()  ──► Receipt.rawText als scrollbarer Monospace-Text

Wisch-zum-Löschen
    └─► _deleteReceipt()
            ├─► DatabaseService.deleteReceipt(id)  ──► SQLite
            └─► File(imagePath).delete()            ──► Dateisystem
```

---

## Installation

### Fertig gebaute APK (empfohlen)

Die App wird automatisch via **GitHub Actions** gebaut. Die fertige APK findest du unter:

> **GitHub Repository → Actions → letzter erfolgreicher Workflow-Run → Artifacts → `belegscanner-debug-apk`**

1. APK herunterladen und auf das Android-Gerät übertragen
2. In den Android-Einstellungen „Installation aus unbekannten Quellen" aktivieren
3. APK installieren

### Selbst bauen

```bash
# 1. Repository klonen
git clone https://github.com/nicolasasauer/belegscanner_v1.git
cd belegscanner_v1

# 2. Abhängigkeiten installieren
flutter pub get

# 3. Debug-Build
flutter run

# 4. Release-APK
flutter build apk --release
```

**Voraussetzungen:**
- Flutter SDK ≥ 3.0.0
- Android Studio / Android SDK
- Android-Gerät oder Emulator (Kamera-Unterstützung empfohlen)
- **Mindest-Android-SDK:** 21 (für Google ML Kit erforderlich)
- **Getestet auf:** Samsung Galaxy S23 (Android 14+), Android 16 kompatibel

---

## Tests ausführen

```bash
flutter test
```

Die Tests in `test/receipt_test.dart` prüfen:
- Erstellung und `copyWith` des `Receipt`-Datenmodells (inkl. `categories` und `rawText`)
- SQLite-Serialisierung (`toMap` / `fromMap`) mit Roundtrip-Test und Rückwärtskompatibilität für Altdaten
- Filter-Logik (nach Tag, Monat, Jahr und Kombinationen)

---

## 🤖 Vibe Coding – KI-Mensch-Kollaboration

> Diese App ist ein Produkt des **Vibe Coding** – einer Arbeitsweise, bei der Mensch und KI (GitHub Copilot) gemeinsam entwickeln.

Der Bong-Scanner entstand als iterative Zusammenarbeit: Der Mensch liefert Vision, Kontext und Qualitätskontrolle – die KI schreibt Code, schlägt Architekturen vor und führt Security-Reviews durch. Das Ergebnis ist eine funktionale, sichere und gut dokumentierte App, die in einem Bruchteil der klassischen Entwicklungszeit entstanden ist.

**Was Vibe Coding in diesem Projekt bedeutete:**
- 🧠 Architekturentscheidungen (Local-First, Background-Isolate für OCR, SQLite-Schema)
- 🔐 Security-Review mit 13 identifizierten und größtenteils behobenen Befunden
- ♻️ Iteratives Refactoring auf Profi-Niveau

> OCR ist gut, aber nicht perfekt – prüfe Beträge immer kurz nach! 🚀

---

## App-ID & Kompatibilität

| Eigenschaft | Wert |
|---|---|
| Android-Namespace | `com.nicolas.bong_scanner` |
| Android-AppID | `com.nicolas.bong_scanner` |
| Mindest-SDK | 21 |
| Ziel-SDK | 35 (Android 15/16 kompatibel) |
| iOS-Mindest-Version | 12.0 |

---

## Lizenz

MIT © 2026 Nicolas Asauer

