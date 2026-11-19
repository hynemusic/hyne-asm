# HYNE Ableton Shortcuts Manager (HYNE ASM)

Plugins, Presets und Live-Befehle in Sekunden einfügen: ein doppelter Rechtsklick in Ableton Live öffnet dein eigenes
Menü, ⌃Leertaste öffnet die Schnellsuche. Kostenlos und Open Source.

<img width="2000" height="400" alt="Untitled-3" src="https://github.com/user-attachments/assets/be17d8a1-90be-4a65-bc95-2fe0d95668f9" />

<img width="2000" height="400" alt="Untitled-4" src="https://github.com/user-attachments/assets/6a139f21-c309-42a2-b1af-ecd53e8674f6" />





Insert plugins, presets and Live commands in seconds: a double right-click in Ableton Live opens your own menu,
⌃Space opens the quick search. Free and open source.

**[⬇ Download (neueste Version / latest release)](https://github.com/hynemusic/hyne-asm/releases/latest)**

Voraussetzungen / Requirements: macOS 13 or later, Ableton Live 12.

---

## Installieren (Deutsch)

1. Lade die Datei **HYNE-ASM-….dmg** unter [Releases](https://github.com/hynemusic/hyne-asm/releases/latest) herunter
   und öffne sie.
2. Zieh **HYNE Ableton Shortcuts Manager** in den Ordner **Programme**.
3. Beim ersten Öffnen blockiert macOS die App, weil sie nicht über Apples kostenpflichtiges Programm geprüft ist.
   Einmal freigeben:
   - **macOS 15 und neuer:** App öffnen, Meldung schließen, dann **Systemeinstellungen → Datenschutz & Sicherheit**,
     ganz unten bei HYNE ASM auf **„Trotzdem öffnen“** klicken und bestätigen.
   - **macOS 13–14:** **Rechtsklick auf die App → Öffnen → Öffnen**.
4. Das Willkommensfenster führt durch den Rest: Bedienungshilfen erlauben, das Live-Script ASMbridge installieren,
   Live neu starten und ASMbridge als Control Surface wählen, dein erstes Menü anlegen.

Die Einführung lässt sich jederzeit über das Menüleisten-Symbol → **Einführung zeigen …** wieder öffnen.
Für ein Update lädst du einfach die neue DMG und ersetzt die App; deine Einstellungen bleiben erhalten.

## Install (English)

1. Download **HYNE-ASM-….dmg** from [Releases](https://github.com/hynemusic/hyne-asm/releases/latest) and open it.
2. Drag **HYNE Ableton Shortcuts Manager** into **Applications**.
3. The first time, macOS blocks the app because it isn't checked through Apple's paid program. Allow it once:
   - **macOS 15 and later:** open the app, close the message, then **System Settings → Privacy & Security**, at the
     bottom next to HYNE ASM click **"Open Anyway"** and confirm.
   - **macOS 13–14:** **right-click the app → Open → Open**.
4. The welcome window walks you through the rest: allow Accessibility, install the Live script ASMbridge, restart
   Live and choose ASMbridge as the Control Surface, set up your first menu.

You can reopen the introduction any time from the menu bar icon → **Show Introduction …**.
To update, download the new DMG and replace the app; your settings stay.

---

## Ist das sicher? / Is this safe?

**Deutsch**
- Der gesamte Code ist hier öffentlich. Jede Download-Version wird von GitHub selbst aus genau diesem Code gebaut und
  signiert, nicht auf einem privaten Rechner. Unter [Actions](https://github.com/hynemusic/hyne-asm/actions) siehst du
  zu jeder Version den Build, aus dem sie stammt.
- **Bedienungshilfen:** nötig, damit der doppelte Rechtsklick und die Tastenkürzel in Live funktionieren. Die App
  reagiert nur, während Live vorne ist.
- **Live-Script (ASMbridge):** ein kleines Python-Script im Ordner *User Library/Remote Scripts*, über das die App
  Plugins in Live einfügt.
- **Netzwerk:** keine Verbindung ins Internet. Die App spricht nur mit Live auf deinem Mac (127.0.0.1). Die optionale
  Stream-Deck-Verbindung ist standardmäßig aus und ebenfalls nur auf deinem Mac erreichbar.
- Deine Einstellungen liegen nur bei dir: `~/Library/Application Support/HYNE ASM`.

**English**
- All the code is public here. Every download is built and signed by GitHub itself from exactly this code, not on a
  private computer. Under [Actions](https://github.com/hynemusic/hyne-asm/actions) you can see the build each release
  came from.
- **Accessibility:** needed for the double right-click and the shortcuts in Live. The app only reacts while Live is in
  front.
- **Live script (ASMbridge):** a small Python script in *User Library/Remote Scripts* that the app uses to insert
  plugins in Live.
- **Network:** no internet connection. The app only talks to Live on your Mac (127.0.0.1). The optional Stream Deck
  link is off by default and also reachable from your Mac only.
- Your settings stay with you: `~/Library/Application Support/HYNE ASM`.

## Deinstallieren / Uninstall

1. Quit HYNE ASM (menu bar icon → Quit) and move the app from Applications to the Trash.
2. Delete `~/Library/Application Support/HYNE ASM` (your menu and settings).
3. Delete the folder `ASMbridge` in `~/Music/Ableton/User Library/Remote Scripts` and, in Live's preferences, set the
   Control Surface back to None.
4. Optional: remove HYNE ASM under System Settings → Privacy & Security → Accessibility.

---

## For developers

Swift package (macOS 13+, Swift 6) for the app, plus the Python Live script in `bridge/ASMbridge`.

### Tests

```bash
swift test
python3 -m unittest discover -s bridge/tests
HM_LIVE_TEST=1 swift test --filter LiveIntegrationTests   # needs Live running with ASMbridge selected
```

### Build & install from source

The app needs a stable code signature, otherwise macOS drops the Accessibility permission after every build. Any
code-signing identity in your keychain works, for example a free "Apple Development" certificate from Xcode
(Settings → Accounts → Manage Certificates) or a self-signed one. `security find-identity -p codesigning` lists them.

```bash
HM_SIGN_IDENTITY="<your identity name>" scripts/build-app.sh --install
```

Then in the HYNE ASM menu bar menu → "Install Live Script …", restart Live, and select "ASMbridge" as the control
surface (Input/Output: None).

### Releases

Pushing a tag `vX.Y.Z` runs `.github/workflows/release.yml`: it tests, builds with `HM_VERSION=X.Y.Z`, signs with the
project's "HYNE ASM" certificate (stored as repository secrets), checks tag, version, certificate fingerprint and
architectures with `scripts/verify-release.sh`, packages a DMG with `scripts/make-dmg.sh` and
publishes it with its SHA-256 checksum on the Releases page.

## License

MIT, see [LICENSE](LICENSE).
