# XploreD (vormals "Fog of War Explorer")

Eine Flutter-App, die die reale Welt als "Fog of War" wie in Videospielen
behandelt: du deckst die Karte auf, indem du dich durch die echte Welt bewegst.

## Setup

```bash
flutter create --org com.example --project-name xplored .
# (überschreibt KEINE bestehenden lib/-Dateien, ergänzt nur ios/, android/
#  und die für dieses Projekt fehlenden Plattform-Ordner)
flutter pub get
```

Danach manuell:

1. **iOS**: Inhalte aus `ios/Runner/Info.plist.additions.xml` in die generierte
   `ios/Runner/Info.plist` einfügen (innerhalb des äußeren `<dict>`).
2. **Android**: Inhalte aus
   `android/app/src/main/AndroidManifest.additions.xml` in die generierte
   `AndroidManifest.xml` einfügen (Permissions vor `<application>`), zusätzlich
   `android:label="XploreD"` im `<application>`-Tag setzen.
3. `flutter run` auf einem echten Gerät (GPS funktioniert im Simulator/
   Emulator nur mit simulierten Positionen).

## Funktionsumfang (Stand dieses Exports)

- Onboarding-Flow mit gestuften, erklärenden Permission-Anfragen (erst
  Intro, dann "When In Use", dann optional "Always") statt kommentarloser
  System-Dialoge
- Karte (OpenStreetMap via `flutter_map`), zoom- und verschiebbar
- Aktueller GPS-Standort als Marker
- Standort-Tracking: iOS über direkten `geolocator`-Stream +
  `UIBackgroundModes: location`; Android über `flutter_foreground_task`
  (eigener Isolate, überlebt App-Minimierung)
- Geohash-basierte Grid-Zellen (Präzision 7, ~150m) als erkundete Fläche,
  persistent in SQLite, mit Index für performante Bounds-Queries
- Viewport-basiertes Laden: nur Zellen im sichtbaren Kartenbereich (+50%
  Puffer) werden geladen/gezeichnet, debounced bei Pan/Zoom - bleibt
  performant unabhängig von der Gesamtgröße der erkundeten Fläche
- Fog-of-War-Overlay: `CustomPainter` mit `BlendMode.clear`, konfigurierbarer
  Aufdeckungsradius, weiche/verschmelzende Kreisränder
- Statistik: erkundete Fläche, Zellenanzahl, zurückgelegte Distanz,
  Erkundungstage, aktueller/längster Streak
- Achievement-System: 8 vordefinierte Achievements, animierter Toast beim
  Freischalten (eigene Queue statt SnackBar, damit mehrere Achievements
  sauber nacheinander angezeigt werden)
- Einstellungen: Hintergrund-Tracking an/aus, Aufdeckungsradius-Slider,
  GPS-Update-Distanz-Slider, Android-Battery-Optimization-Status
- Datenschutz-Screen mit Erklärungen und vollständiger Lösch-Funktion

## Bekannte offene Punkte

- **GPS-Update-Distanz aus den Settings wird geladen, aber noch nicht bis
  ins tatsächliche Sampling durchgereicht** (weder im iOS- noch im Android-
  Hintergrundpfad) - beide nutzen aktuell fest 50m. Siehe Kommentare in
  `location_service.dart` und `home_screen.dart` (`_startTracking`).
- **Löschen aller Daten löscht auch den Onboarding-Flag** (liegt technisch
  in derselben `app_state`-Tabelle wie alle anderen Settings) - nach einem
  Reset im Datenschutz-Screen durchläuft der Nutzer also automatisch erneut
  das Onboarding. Das ist unverändert so, seit die Löschfunktion gebaut
  wurde, hier aber nochmal explizit festgehalten, falls das nicht gewünscht
  ist.
- **Statistik- und Achievement-Screens laden ihre Daten einmalig beim
  Öffnen** (`Future` in `initState`), aktualisieren sich also nicht live,
  während der Screen offen ist.
- Kein Start/Stop-Button direkt auf der Kartenansicht - Tracking wird nur
  über den Settings-Screen umgeschaltet.

## Bekannte Plattform-Einschränkungen (wichtig zu verstehen)

**iOS:**
- Nach `Always`-Permission liefert iOS auch bei geschlossener App weiterhin
  Standort-Updates, solange `UIBackgroundModes: location` gesetzt ist und
  der Nutzer die App nicht aktiv aus dem App-Switcher wischt (Force-Quit).
- Nach einem Force-Quit stoppt iOS alle Background-Activity vollständig -
  eine harte, von keiner App umgehbare Grenze.

**Android:**
- Der Foreground Service mit permanenter Notification läuft auch nach
  App-Minimierung zuverlässig weiter.
- Nach "App aus der Übersicht entfernen" verhält sich Android herstellerabhängig:
  Stock Android lässt den Service meist weiterlaufen, aggressive
  Battery-Manager (Xiaomi MIUI, Huawei EMUI, OnePlus OxygenOS) können ihn
  trotzdem killen - die einzige Gegenmaßnahme ist die Battery-Optimization-
  Ausnahme im Settings-Screen.

## Architektur-Entscheidungen im Überblick

| Bereich | Entscheidung | Warum |
|---|---|---|
| Karte | `flutter_map` + OSM-Tiles | Volle Kontrolle über Custom-Fog-Overlay, keine API-Keys |
| Speicherung erkundeter Fläche | Geohash-Grid (Präzision 7, ~150m Zellen) in SQLite + Index | Trivial dedupliziert, O(1)-Lookup, bleibt bei großen Gebieten performant |
| Fog-Rendering | `CustomPainter` mit `BlendMode.clear` pro Zelle | Überlappende Kreise verschmelzen automatisch via GPU-Compositing |
| Rendering-Umfang | Viewport + 50% Puffer statt aller Zellen | Konstante Renderzeit unabhängig von der Gesamtfläche |
| Background Location | Plattform-spezifisch gekapselt in `LocationService` / `background_task_handler.dart` | iOS und Android haben grundlegend unterschiedliche Hintergrund-Modelle |
| Onboarding | Gestufte Permission-Requests mit vorgeschalteter Erklärung | Bessere Grant-Rate als kommentarlose System-Dialoge |
