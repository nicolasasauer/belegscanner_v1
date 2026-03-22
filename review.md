# Security Audit – Belegscanner v1

**Datum:** 22. März 2026  
**Auditor:** GitHub Copilot Coding Agent  
**Repository:** `nicolasasauer/belegscanner_v1`  
**Technologie:** Flutter (Dart) · Android · iOS  

---

## Übersicht

Dieser Bericht dokumentiert eine vollständige Sicherheitsüberprüfung des Quellcodes der App **Belegscanner v1**. Untersucht wurden alle Dart-Quelldateien, Plattformkonfigurationen (Android/iOS), Build-Skripte, CI/CD-Konfiguration sowie verwendete Abhängigkeiten.

**Geprüfte Dateien:**
- `lib/main.dart`
- `lib/models/receipt.dart`
- `lib/services/ocr_service.dart`
- `lib/pages/home_page.dart`
- `android/app/build.gradle`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/xml/file_paths.xml`
- `android/app/proguard-rules.pro`
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`
- `pubspec.yaml`
- `.github/workflows/main.yml`
- `test/receipt_test.dart`

---

## Befunde nach Schweregrad

### 🔴 KRITISCH

#### K-01 – Release-APK wird mit Debug-Keystore signiert
**Datei:** `android/app/build.gradle`, Zeile 55  
**Code:**
```groovy
release {
    signingConfig signingConfigs.debug   // ← Kritisch!
    minifyEnabled true
    ...
}
```
**Beschreibung:**  
Die Release-Build-Konfiguration verwendet explizit `signingConfigs.debug` – also denselben Keystore, der beim Entwickeln genutzt wird. Der Android-Debug-Keystore hat ein öffentlich bekanntes Passwort (`android`/`android`) und befindet sich üblicherweise unter `~/.android/debug.keystore`. Eine produktiv veröffentlichte App, die mit diesem Keystore signiert ist, kann von jedem Angreifer mit demselben Keystore re-signiert oder als Update vorgetäuscht werden.

**Risiko:** Ein Angreifer kann eine manipulierte APK mit demselben Debug-Keystore signieren. Android-Geräte, auf denen die Original-App installiert ist, würden dieses manipulierte Update akzeptieren.

**Empfehlung:** Einen eigenen Release-Keystore erstellen und die Credentials als verschlüsselte CI/CD-Secrets ablegen. Niemals den Debug-Keystore für Produktions-Releases verwenden.

---

### 🟠 MITTEL

#### M-01 – FileProvider gibt das gesamte Cache-Verzeichnis frei
**Datei:** `android/app/src/main/res/xml/file_paths.xml`, Zeile 5  
**Code:**
```xml
<cache-path name="cache" path="/"/>
```
**Beschreibung:**  
Der Pfad `/` im `<cache-path>`-Element bedeutet, dass der FileProvider Zugriff auf das gesamte App-interne Cache-Verzeichnis gewährt. Damit sind nicht nur Kamerabilder, sondern alle gecachten Dateien der App über den FileProvider erreichbar. Falls eine andere App (oder ein Angreifer über eine manipulierte Intent-Abfrage) Zugriff auf diesen FileProvider erhält, kann sie potenziell alle gecachten Inhalte der App lesen.

**Empfehlung:** Den Pfad auf das konkrete Verzeichnis einschränken, in dem Kamerabilder gecacht werden (z. B. `path="images/"`).

#### M-02 – `applicationId` und `namespace` mit `com.example`-Prefix
**Datei:** `android/app/build.gradle`, Zeilen 31 und 45  
**Code:**
```groovy
namespace "com.example.belegscanner_v1"
...
applicationId "com.example.belegscanner_v1"
```
**Beschreibung:**  
Der `com.example`-Namespace ist ein Platzhalter und sollte niemals in einer Produktions-App verwendet werden. Auf Google Play Store wäre diese App gar nicht publizierbar, da der `com.example`-Namespace gesperrt ist. Im Sideloading-Kontext kann es zu Namespace-Kollisionen mit anderen Apps kommen. Außerdem erleichtert der generische Name die Identifikation als Entwickler-/Test-App.

**Empfehlung:** Den `applicationId` auf einen eigenen, umgekehrten Domain-Namen umstellen (z. B. `com.asauer.belegscanner`).

---

### 🟡 NIEDRIG

#### N-01 – Fehlermeldungen geben interne Exception-Details an den Benutzer weiter
**Datei:** `lib/pages/home_page.dart`, Zeile 126  
**Code:**
```dart
SnackBar(
  content: Text('Scan fehlgeschlagen: $e'),
  ...
)
```
**Beschreibung:**  
Bei einem Fehler während des Scans wird die vollständige Dart-Exception inklusive internem Stack-Trace oder Systempfaden direkt als Benutzertext angezeigt. Das kann bei Platform Exceptions interne Dateipfade, Gerätemodelle, OS-Versionen oder ML-Kit-Fehlermeldungen preisgeben.

**Empfehlung:** In der Produktionsumgebung eine generische, benutzerfreundliche Fehlermeldung anzeigen und die technischen Details nur in einen Logging-Service (z. B. Firebase Crashlytics) schreiben.

#### N-02 – Irreführende iOS-Berechtigungsbeschreibung
**Datei:** `ios/Runner/Info.plist`, Zeilen 53–54  
**Code:**
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Diese App speichert gescannte Belegbilder in Ihrer Fotobibliothek.</string>
```
**Beschreibung:**  
Der App-Code enthält keinerlei Logik, um Bilder in die iOS-Fotobibliothek zu schreiben. Die Berechtigungsanfrage `NSPhotoLibraryAddUsageDescription` ist daher funktional nicht notwendig. Apple bewertet dies bei einer App-Store-Überprüfung als problematisch und könnte die App ablehnen. Aus Datenschutzsicht gilt: nicht angeforderte Berechtigungen sollten nicht deklariert werden.

**Empfehlung:** Den `NSPhotoLibraryAddUsageDescription`-Eintrag aus der `Info.plist` entfernen, solange die App keine Bilder in die Fotobibliothek schreibt.

---

### 🔵 INFORMELL / BEST PRACTICE

#### I-01 – INTERNET-Berechtigung und Google-ML-Kit-Telemetrie
**Datei:** `android/app/src/main/AndroidManifest.xml`, Zeile 6  
**Beschreibung:**  
Die App deklariert die `INTERNET`-Berechtigung, die für den initialen Download des ML-Kit-Modells benötigt wird. Die README behauptet explizit, dass „alles lokal" bleibt. Das ist jedoch nicht vollständig korrekt: Google ML Kit ist ein Google-eigenes Framework und kann auch nach dem Modell-Download Nutzungstelemetrie oder Performance-Metriken an Google-Server übertragen. Dieser Datentransfer geschieht nicht durch expliziten App-Code, sondern durch das Framework selbst.

**Risiko:** Belege enthalten finanzielle Informationen. Obwohl OCR on-device erfolgt, kann nicht ausgeschlossen werden, dass ML Kit-Framework-Metadaten an Google übertragen werden.

**Empfehlung:** Dies in der Datenschutzerklärung der App transparent kommunizieren und ggf. eine datenschutzfreundlichere On-Device-OCR-Alternative (z. B. Tesseract über `flutter_tesseract_ocr`) evaluieren.

#### I-02 – Kein persistenter Datenspeicher
**Datei:** `lib/pages/home_page.dart`, Zeile 26  
**Code:**
```dart
final List<Receipt> _receipts = [];
```
**Beschreibung:**  
Alle Belege werden ausschließlich im Arbeitsspeicher gehalten. Bei einem App-Neustart, einem Absturz oder einem Systemkill (z. B. durch den Android Activity-Lifecycle) gehen alle gescannten Belege verloren. Das Belegbild bleibt zwar als Datei auf dem Gerät, der zugehörige OCR-Text und der erkannte Betrag sind jedoch nicht wiederherstellbar.

**Hinweis:** Dies ist primär ein funktionaler Mangel. Aus Sicherheitsperspektive positiv: Es existiert keine lokale Datenbank, die ohne Verschlüsselung auf dem Gerät persistiert.

**Update I-02 [REFINED]:** Bild-Persistenz ist jetzt aktiv. Belegbilder werden beim Scan aus dem temporären Kamera-Cache in das permanente App-Dokumenten-Verzeichnis (`getApplicationDocumentsDirectory()/receipt_images/`) kopiert. Der Dateipfad wird im `imagePath`-Feld der SQLite-Datenbank gespeichert. Beim Löschen eines Belegs wird auch die Bilddatei entfernt. Die Beleg-Daten (Betrag, Datum, Artikel) sind ebenfalls dauerhaft in SQLite persistiert und überleben App-Neustarts.

#### I-03 – Keine Funktion zum Löschen von Belegen oder Bildern
**Datei:** `lib/pages/home_page.dart`  
**Beschreibung:**  
Die App bietet keine Möglichkeit, einzelne Belege aus der Liste zu entfernen oder die zugehörigen Bilddateien vom Gerät zu löschen. Aus Datenschutzsicht (DSGVO, Recht auf Löschung) ist dies problematisch, wenn die App für echte Finanzdaten genutzt wird. Die Belegbilder verbleiben im App-Cache bzw. externem Speicher, auch wenn der Benutzer sie nicht mehr benötigt.

**Empfehlung:** Eine Löschfunktion implementieren, die sowohl den Receipt-Eintrag aus der Liste als auch die Bilddatei (`File(imagePath).delete()`) entfernt.

#### I-04 – Keine Verschlüsselung gespeicherter Bilddateien
**Dateien:** `lib/services/ocr_service.dart`, `android/app/src/main/res/xml/file_paths.xml`  
**Beschreibung:**  
Belegbilder werden im Klartext im App-Verzeichnis oder externen Speicher abgelegt. Belege können hochsensible Informationen enthalten (Kaufverhalten, Beträge, Händler, Medikamentenkäufe). Auf einem nicht-gerooteten Android-Gerät sind App-interne Dateien vor anderen Apps geschützt. Auf einem gerooteten Gerät oder bei Geräteverlust (ohne Bildschirmsperre) ist der Zugriff möglich.

**Empfehlung:** Für produktive Anwendungen die Bildverschlüsselung über die Android Keystore API oder Flutter Secure Storage in Betracht ziehen.

**Update I-04 [REFINED]:** Bild-Persistenz ist jetzt aktiv. Belegbilder werden permanent im App-eigenen Dokumenten-Verzeichnis (`getApplicationDocumentsDirectory()`) gespeichert – einem App-privaten, nicht öffentlich zugänglichen Verzeichnis. Auf einem nicht-gerooteten Gerät sind diese Dateien vor anderen Apps geschützt. Die Bilder sind weiterhin unverschlüsselt. Für produktive Anwendungen mit sensiblen Finanzdaten bleibt die Empfehlung zur Bildverschlüsselung bestehen.

#### I-05 – Nicht gepinnte GitHub Actions (Supply-Chain-Risiko)
**Datei:** `.github/workflows/main.yml`  
**Code:**
```yaml
uses: actions/checkout@v4
uses: actions/setup-java@v4
uses: subosito/flutter-action@v2
uses: actions/upload-artifact@v4
```
**Beschreibung:**  
Alle verwendeten GitHub Actions werden über ihren Tag (z. B. `@v4`) referenziert, nicht über einen spezifischen Commit-SHA. Im Falle einer Kompromittierung des Action-Repositories könnte ein Angreifer den Tag auf eine manipulierte Version zeigen lassen und so schadhaften Code im Build-Prozess ausführen (Supply-Chain-Angriff).

**Empfehlung:** Actions auf spezifische Commit-SHAs pinnen (z. B. `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`).

#### I-06 – APK-Builds für alle Branches
**Datei:** `.github/workflows/main.yml`, Zeilen 4–6  
**Code:**
```yaml
on:
  push:
    branches:
      - '**'
```
**Beschreibung:**  
Der Workflow baut und veröffentlicht eine Release-APK für jeden Push auf jedem beliebigen Branch. Das bedeutet, dass Feature-Branches und experimentelle Codeänderungen ohne Review ebenfalls als signierte APK-Artifact hochgeladen werden.

**Empfehlung:** Den Release-Build auf den Haupt-Branch (z. B. `main`) beschränken. Feature-Branches sollten maximal einen Debug-Build produzieren.

#### I-07 – Unnötige `camera`-Abhängigkeit
**Datei:** `pubspec.yaml`, Zeile 14  
**Code:**
```yaml
camera: ^0.10.5+9
```
**Beschreibung:**  
Das `camera`-Package wird in `pubspec.yaml` deklariert, jedoch wird die eigentliche Kamerafunktionalität ausschließlich über das `image_picker`-Package realisiert. Die `camera`-Abhängigkeit ist nicht in einem Import im Dart-Code nachzuweisen. Jede unnötige Abhängigkeit vergrößert die Angriffsfläche und erhöht das Risiko durch Sicherheitslücken in Drittbibliotheken.

**Empfehlung:** Die `camera`-Abhängigkeit aus `pubspec.yaml` entfernen.

#### I-08 – OCR-Fallback-Logik kann fehlerhafte Beträge liefern
**Datei:** `lib/services/ocr_service.dart`, Zeilen 36–44  
**Code:**
```dart
// Fallback: größten Betrag im Text suchen
final RegExp fallbackRegex = RegExp(r'(\d{1,6}[.,]\d{2})');
double maxAmount = 0.0;
for (final m in fallbackRegex.allMatches(text)) {
    final value = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0.0;
    if (value > maxAmount) maxAmount = value;
}
return maxAmount;
```
**Beschreibung:**  
Der Fallback-Algorithmus gibt einfach den *größten* erkannten numerischen Wert zurück, der dem Muster `\d{1,4}[.,]\d{2}` entspricht. Auf echten Kassenbons können Artikelnummern (z. B. `1234.56`) oder interne Codes größer als der Gesamtbetrag sein, was zu systematisch falschen Betragserkennungen führt. Dies ist kein Sicherheitsproblem im engeren Sinne, kann aber bei falschen Beträgen zu finanziellen Fehlentscheidungen führen.

**Update I-08 [REFINED]:** Die Parsing-Logik in `_parseItemsImpl` wurde überarbeitet, um Header-Daten (GmbH/OHG, PLZ, Str./Straße, Telefon, USt-IdNr., Datum, Uhrzeit) per Regex-Ausschlussliste zu filtern, OCR-Junk-Präfixe wie „CnBio"/„unBio" zu strippen sowie Zeilen mit zu wenigen Buchstaben oder einem zu hohen Anteil an Ziffern/Sonderzeichen auszuschließen.

---

## Prüfung auf Backdoors, Viren und Datenabflüsse

| Prüfpunkt | Befund |
|---|---|
| Versteckter Netzwerkcode | ✅ Nicht gefunden |
| Externe API-Aufrufe durch App-Code | ✅ Nicht gefunden |
| Dateiexfiltration | ✅ Nicht gefunden |
| Obfuskierter / verschleierter Code | ✅ Nicht gefunden |
| Hartcodierte Credentials / Secrets / API-Keys | ✅ Nicht gefunden |
| Backdoor-artige Intent-Filter | ✅ Nicht gefunden |
| Schadhafte Nativ-Bibliotheken | ✅ Nicht gefunden |
| Verdächtige Berechtigungen (über App-Zweck hinaus) | ✅ Keine exzessiven Berechtigungen |
| Verdächtige Drittanbieter-SDKs | ℹ️ Nur Google ML Kit (Framework-Telemetrie möglich) |
| Datenbank mit verschlüsseltem Inhalt | ℹ️ SQLite-Datenbank vorhanden, unverschlüsselt (für persönlichen Gebrauch akzeptabel) |
| Ungewöhnliche JNI-/NDK-Aufrufe | ✅ Nicht gefunden |

**Ergebnis:** Es wurden **keine Backdoors, kein Virencode und keine aktiven Datenabflüsse** im Quellcode gefunden. Der gesamte Dart-Code verhält sich entsprechend der beschriebenen App-Funktionalität.

---

## Zusammenfassung der Befunde

| ID | Schweregrad | Titel |
|---|---|---|
| K-01 | 🔴 Kritisch | Release-APK mit Debug-Keystore signiert |
| M-01 | 🟠 Mittel | FileProvider gibt gesamtes Cache-Verzeichnis frei |
| M-02 | 🟠 Mittel | `com.example`-Namespace in Produktionskonfiguration |
| N-01 | 🟡 Niedrig | Interne Exception-Details in Benutzersnackbar |
| N-02 | 🟡 Niedrig | Irreführende iOS-Fotobibliothek-Schreibberechtigung |
| I-01 | 🔵 Informell | ML-Kit-Telemetrie nicht dokumentiert |
| I-02 | 🔵 Informell | Keine Persistenz – Datenverlust bei Neustart |
| I-03 | 🔵 Informell | Fehlende Löschfunktion für Belege und Bilder |
| I-04 | 🔵 Informell | Unverschlüsselte Bilddateien auf Gerät |
| I-05 | 🔵 Informell | Ungepinnte GitHub Actions (Supply-Chain) |
| I-06 | 🔵 Informell | Release-Build auf allen Branches |
| I-07 | 🔵 Informell | Unnötige `camera`-Abhängigkeit |
| I-08 | 🔵 Informell | Fehleranfälliger OCR-Fallback-Algorithmus |

---

## Fazit

Der Code der **Belegscanner v1**-App zeigt keine Anzeichen von Backdoors, Schadsoftware oder gezielten Datenabflüssen. Der Dart-Quellcode ist übersichtlich strukturiert, gut kommentiert und folgt gängigen Flutter-Konventionen. Es wurden keine hartcodierten Credentials, keine obfuskierten Code-Passagen und keine versteckten Netzwerkaufrufe gefunden.

**Für den persönlichen Gebrauch und als Lernprojekt ist die App vertretbar sicher.** Vor einem Produktions-Release oder einer Veröffentlichung im App Store / Play Store bestehen jedoch folgende Handlungsfelder:

1. **Dringend (vor jeder Veröffentlichung):** Das Release-Signing (K-01) muss auf einen eigenen, privaten Keystore umgestellt werden – dies ist die einzige Lücke mit wirklich kritischem Schweregrad.

2. **Empfohlen:** Die FileProvider-Konfiguration (M-01) und der `com.example`-Namespace (M-02) sollten vor einem Play-Store-Upload behoben werden.

3. **Datenschutz:** Da Kassenbons sensible Finanzdaten enthalten, sollte eine Datenschutzerklärung die ML-Kit-Telemetrie (I-01) transparent offenlegen. Eine Löschfunktion (I-03) und ggf. Bildverschlüsselung (I-04) erhöhen das Vertrauen der Nutzer erheblich.

4. **CI/CD-Hygiene:** Die GitHub-Actions-Pinning-Strategie (I-05) und die Branch-Einschränkung für Release-Builds (I-06) sind einfach umzusetzen und reduzieren das Supply-Chain-Risiko deutlich.

Die App ist ein solides Lernprojekt ohne erkennbare Schadfunktionen. Mit den oben beschriebenen Maßnahmen – insbesondere K-01 – wäre sie auch für einen produktiven Einsatz besser geeignet.
