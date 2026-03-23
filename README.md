# Bong-Scanner 📷

Eine Flutter-App für Android zum **Einscannen**, **Speichern**, **Durchsuchen** und **Exportieren** von Kassenbons – vollständig On-Device, ohne Cloud.

---

## Screenshots

| Leere Startseite | Beleg-Liste | Beleg-Detail |
|:---:|:---:|:---:|
| ![Leere Startseite](https://github.com/user-attachments/assets/16902a92-0bb3-4263-9ec2-9509956fc4aa) | ![Beleg-Liste](https://github.com/user-attachments/assets/6d3c4bc8-3570-4b74-b7de-98005410f16d) | ![Beleg-Detail](https://github.com/user-attachments/assets/355493cb-3996-48d5-a021-cb206d5d00a4) |
| Startbildschirm ohne Belege | Gefilterte Beleg-Liste mit Datum-FilterChips | Detail-BottomSheet mit erkannten Positionen und Einzelpreisen |

---

## Features

| # | Feature | Beschreibung |
|---|---|---|
| 📷 | **On-Device OCR** | Belege per Kamera fotografieren – Text wird lokal mit Google ML Kit erkannt, kein Bild verlässt das Gerät |
| 🗄️ | **SQLite-Persistenz** | Alle Belege (Datum, Betrag, Artikel, Bildpfad) werden dauerhaft in einer lokalen SQLite-Datenbank gespeichert und überleben jeden App-Neustart |
| 🖼️ | **Bild-Thumbnail** | Das Originalbild jedes Belegs wird permanent im App-eigenen Dokumenten-Verzeichnis gespeichert und als Thumbnail direkt in der Liste angezeigt |
| 💶 | **Automatische Betragserkennung** | Regex-basiertes Parsing nach `Summe`, `Gesamtbetrag`, `Zahlbetrag`, `Total` und `€` – mit intelligentem Fallback |
| 🧾 | **Verbesserte Artikelerkennung** | Header-Daten (GmbH, PLZ, Adresse, Telefon, Datum, Uhrzeit) werden gefiltert; OCR-Artefakte wie Junk-Präfixe (z. B. „CnBio") werden automatisch bereinigt |
| 🔍 | **Volltextsuche** | Belege nach Händlername, Betrag oder Stichwörtern in den Einzelpositionen durchsuchen |
| 🗂️ | **Datum-Filter** | Belege nach Tag, Monat und Jahr filtern – kombinierbare FilterChips |
| 📤 | **CSV-Export** | Alle Belege als RFC-4180-konforme CSV-Datei exportieren und per Share-Sheet (E-Mail, Messenger, Cloud) teilen |
| 📥 | **Galerie-Import** | Vorhandene Bonfotos aus der Gerätegalerie importieren – identische OCR-Pipeline wie Kamera-Scan |
| 🗑️ | **Sicheres Löschen** | Belege per Wisch-Geste löschen – Datenbankeintrag UND Bilddatei werden vollständig entfernt |
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

---

## Architektur

```
lib/
├── main.dart                      # App-Einstiegspunkt, BongScannerApp, Material-3-Theme
├── models/
│   └── receipt.dart               # Receipt-Datenmodell (id, date, totalAmount, items, imagePath)
├── services/
│   ├── ocr_service.dart           # OCR-Logik: Kamera/Galerie → ML Kit → Parsing (Background-Isolate)
│   └── database_service.dart      # SQLite-Persistenz: CRUD-Operationen für Belege
└── pages/
    └── home_page.dart             # Haupt-Screen: Filter-Bar, ListView, FAB Speed-Dial, CSV-Export
```

### Datenfluss

```
App-Start
    └─► _loadReceipts()
            └─► DatabaseService.getAllReceipts()  ──► SQLite (sqflite)
                    └─► Receipt-Liste → setState → ListView

FAB → Kamera / Galerie
    └─► OcrService.scanReceipt() / importFromGallery()
            ├─► ImagePicker (Kamera oder Galerie)
            ├─► GoogleMlKit TextRecognizer  (Haupt-Isolate, on-device)
            ├─► compute(_parseOcrText)      (Background-Isolate)
            │       ├─► _parseAmount()   (Schlüsselwort-Regex + Fallback)
            │       └─► _parseItems()    (Header-Filter, Junk-Stripping,
            │                             Mindestlänge, Zeichentyp-Filter)
            ├─► _persistImage()            (Bild dauerhaft im App-Verzeichnis)
            └─► Receipt-Objekt
                    └─► DatabaseService.insertReceipt()  ──► SQLite
                            └─► setState → ListView

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
- Erstellung und `copyWith` des `Receipt`-Datenmodells
- SQLite-Serialisierung (`toMap` / `fromMap`) mit Roundtrip-Test
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

