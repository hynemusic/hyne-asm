# HYNE Ableton Shortcuts Manager (ASM)

Plugins, Presets und Live-Befehle in Sekunden einfügen: doppelter Rechtsklick in Live öffnet dein eigenes Menü,
⌃Leertaste öffnet die Schnellsuche. / Insert plugins, presets and Live commands in seconds: double right-click in
Live opens your own menu, ⌃Space opens the quick search.

## Installieren (Deutsch)

Voraussetzungen: macOS 13 oder neuer, Ableton Live 12.

1. **HYNE Ableton Shortcuts Manager.app** in den Ordner **Programme** ziehen.
2. Beim ersten Öffnen blockiert macOS die App, weil sie nicht von Apple geprüft ist. Einmal freigeben:
   - **macOS 15 und neuer:** App öffnen, Meldung schließen, dann **Systemeinstellungen → Datenschutz & Sicherheit**,
     ganz unten bei HYNE ASM auf **„Trotzdem öffnen“** klicken und bestätigen.
   - **macOS 13–14:** **Rechtsklick auf die App → Öffnen → Öffnen**.
3. Das Willkommensfenster führt durch den Rest: Bedienungshilfen erlauben, das Live-Script ASMbridge installieren,
   Live neu starten und ASMbridge als Control Surface wählen, dein erstes Menü anlegen.

Die Einführung lässt sich jederzeit über das Menüleisten-Symbol → **Einführung zeigen …** wieder öffnen.

## Install (English)

Requirements: macOS 13 or later, Ableton Live 12.

1. Drag **HYNE Ableton Shortcuts Manager.app** into **Applications**.
2. The first time, macOS blocks the app because Apple hasn't checked it. Allow it once:
   - **macOS 15 and later:** open the app, close the message, then **System Settings → Privacy & Security**, at the
     bottom next to HYNE ASM click **"Open Anyway"** and confirm.
   - **macOS 13–14:** **right-click the app → Open → Open**.
3. The welcome window walks you through the rest: allow Accessibility, install the Live script ASMbridge, restart
   Live and choose ASMbridge as the Control Surface, set up your first menu.

You can reopen the introduction any time from the menu bar icon → **Show Introduction …**.

---

## For developers

Plugin quick launcher for Ableton Live 12: double-right-click in Live → panel with your own categories → the plugin is loaded onto the selected track. Plus shortcuts to close plugin windows.

- Spec: `docs/superpowers/specs/2026-11-16-ableton-quick-launcher-design.md`
- Plan: `docs/superpowers/plans/2026-11-16-hm-launcher.md`

### Tests

```bash
swift test
python3 -m unittest discover -s bridge/tests
HM_LIVE_TEST=1 swift test --filter LiveIntegrationTests   # needs Live running with ASMbridge selected
```

### Signing (one time)

The app needs a stable signature, otherwise macOS drops the Accessibility permission after every build.

1. Xcode → Settings → Accounts → add your Apple ID (free, "Personal Team").
2. Under "Manage Certificates…" → "+" → "Apple Development".
3. Check: `security find-identity -v -p codesigning` shows "Apple Development: …".

### Build & install

```bash
HM_SIGN_IDENTITY="Apple Development: <Name> (<ID>)" scripts/build-app.sh --install
```

Then in the HYNE ASM menu bar menu → "Live-Script installieren…", restart Live, and select "ASMbridge" as the control surface (Input/Output: None).
