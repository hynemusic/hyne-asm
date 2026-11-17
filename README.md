# HYNE Ableton Shortcuts Manager (ASM)

Plugin quick launcher for Ableton Live 12: double-right-click in Live → panel with your own categories → the plugin is loaded onto the selected track. Plus shortcuts to close plugin windows.

- Spec: `docs/superpowers/specs/2026-11-16-ableton-quick-launcher-design.md`
- Plan: `docs/superpowers/plans/2026-11-16-hm-launcher.md`

## Tests

```bash
swift test
python3 -m unittest discover -s bridge/tests
HM_LIVE_TEST=1 swift test --filter LiveIntegrationTests   # needs Live running with HMLauncherBridge selected
```

## Signing (one time)

The app needs a stable signature, otherwise macOS drops the Accessibility permission after every build.

1. Xcode → Settings → Accounts → add your Apple ID (free, "Personal Team").
2. Under "Manage Certificates…" → "+" → "Apple Development".
3. Check: `security find-identity -v -p codesigning` shows "Apple Development: …".

## Build & install

```bash
HM_SIGN_IDENTITY="Apple Development: <Name> (<ID>)" scripts/build-app.sh --install
```

Then in the HYNE ASM menu bar menu → "Live-Script installieren…", restart Live, and select "HMLauncherBridge" as the control surface (Input/Output: None).
