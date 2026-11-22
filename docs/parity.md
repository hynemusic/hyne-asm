# Mac / Windows parity checklist

Every user-facing feature of HYNE ASM with its status on both platforms. Windows status values:
**core done** = the logic is ported to `windows/HyneAsm.Core` and checked against the shared fixtures in
`spec/fixtures` (Plan 1); **Plan 2/3/4** = still to build (OS integration, UI, packaging, ...); **n/a** = not applicable.

## Rules

- A feature isn't done until both columns are ticked, or the gap is written down here with a reason.
- New Mac feature -> a Windows to-do row here the same day. `win-v1.0.0` ships when no Windows gap is open against the
  then-current Mac release.
- Fixtures first: new logic gets its cases in `spec/fixtures` before it is implemented, then both sides are built
  against them (`swift test` and `dotnet test` run the same files).
- Platform-only behaviour (a Mac-only or Windows-only system quirk) is allowed but listed below, with the reason.
- Shortcuts in files stay in the Mac format (`KeyCombo`: macOS key code + Mac modifiers); Windows translates at runtime
  (`KeyTranslation`).

## Features

| Feature | Mac | Windows | Notes |
|---|---|---|---|
| Panel: grid / list, paging, resize grip | ✅ | core done (grid, paging, state) / Plan 3 (UI) | `PanelGrid`, `PanelState` |
| Panel: categories as tabs, folders | ✅ | core done / Plan 3 | |
| Panel: typing filters all plugins | ✅ | core done (`TextInput`, search) / Plan 3 | |
| Panel: rebindable panel keys | ✅ | core done / Plan 3 | `PanelKeyBindings` |
| Panel: digit keys by position | ✅ | core done / Plan 3 | `DigitKeys` |
| Double right-click opens the panel | ✅ | core done (detector) / Plan 2 (mouse hook) | `DoubleRightClickDetector` |
| Quick search (ranking, most-used / Favorites when empty) | ✅ | core done / Plan 3 (window), Plan 2 (hotkey) | default key differs, see below |
| Item shortcuts | ✅ | core done / Plan 2 (keyboard hook) | `ItemShortcuts`, `ShortcutMatcher` |
| Close plugin windows (focused / all), never the main window | ✅ | core done (`MainWindowGuard`) / Plan 2 (Win32/UIA) | |
| Settings: Library (browser, drag & drop, multi-edit, color labels, icon picker, chains, value actions) | ✅ | core done (logic) / Plan 3 (UI) | icon ids map to a bundled Windows set, Plan 3 |
| Settings: Profiles | ✅ | core done / Plan 3 | |
| Settings: Shortcuts, keyboard overview, conflict warnings | ✅ | core done (`KnownShortcuts`) / Plan 3 (UI) | tables differ by design (own Live 12 Windows and Windows tables) |
| Settings: Behavior (insert target, multi-track, Stream Deck) | ✅ | core done / Plan 3 | |
| Settings: Shape Search | ✅ | core done (search) / Plan 3 | |
| Settings: Stats (counts, export / import / reset, new & rarely used) | ✅ | core done / Plan 3 | `UsageStats`, `UsageStore`, `NewAndRare` |
| Menu versions | ✅ | core done / Plan 3 | `MenuVersions` |
| `.hmlmenu` share (export / import) | ✅ | core done / Plan 3 | same JSON on both |
| LES import | ✅ | core done (parser) / Plan 2 (default path) | confirm LES's Windows location on a real PC |
| Own presets, incl. copying unknown presets into `User Library/Presets/HYNE ASM` | ✅ | core done (matching) / Plan 2 (file copy) | confirm Windows User Library path (see below) |
| Five themes (Original, Ableton, HYNE, Light, Retro PS1), HYNE theme from the Live theme | ✅ | core done (`AppTheme`) / Plan 3 | |
| Onboarding | ✅ | core done (steps) / Plan 3 | "Allow Accessibility" becomes "hook works" |
| Tray / menu bar menu (introduction, install Live script, quit ...) | ✅ | Plan 3 | |
| Install the Live script (ASMbridge) | ✅ | Plan 2 | User Library path, `Library.cfg` |
| Bridge connection (TCP 127.0.0.1:47820) | ✅ | core done (`BridgeClient`) / Plan 2 | |
| German / English | ✅ | core done (`Loc`) / Plan 3 | |
| `hyneasm://` links | ✅ | core done (`RemoteCommand`) / Plan 2 (registration, single instance) | |
| Stream Deck endpoint (127.0.0.1:47821, off by default) | ✅ | core done (commands) / Plan 2 | copy the link with `Link().OriginalString` |
| Live in front detection | ✅ | Plan 2 | `SetWinEventHook`, `Ableton Live 12*.exe` |
| Windows installer + portable zip, `win-v*` release workflow | n/a | Plan 4 | |
| Windows acceptance checklist (`windows/ACCEPTANCE.md`) | n/a | Plan 4 | |

## Platform-only behaviour and facts learned

- **Known-shortcut tables differ by design.** `KnownShortcuts.swift` lists Live 12 Mac and macOS defaults;
  `KnownShortcuts.cs` lists Live 12 Windows (from the Live 12 manual's keyboard-shortcut chapter) and Windows defaults
  (Win+..., Alt+Tab, Ctrl+Esc, input switch ...). Same structure, no shared fixture; plain xUnit tests.
  (The Mac "Close Window" and "Hide Live" have no Windows entry in the manual, so they are not in the table.)
- **Default quick search (Ctrl+Space on Mac) becomes Win+Space on Windows**, which is the input-language switch.
  `Default_shortcuts_conflict_report` prints the conflict list; Plan 2 chooses Windows defaults from it. The default
  close-all combos give Ctrl+Win+W (no conflict) and Ctrl+Esc (opens the Start menu).
- Keypad Enter, keypad = and keypad Clear have no Windows translation in `KeyTranslation` (such combos are skipped).
- The Windows default paths for the User Library (`%USERPROFILE%\Documents\Ableton\User Library`, or the one in Live's
  `Library.cfg`) and for LES's config are unconfirmed; check them on a real PC.
- **A store file that exists but can't be read is not treated as missing** (Windows: antivirus, OneDrive/Dropbox and
  editors lock files). `ConfigStore.Load` retries briefly, then throws `ConfigUnreadableException` and leaves the file
  alone; the app must show it (retry / quit) and must not save a default over it. `UsageStore` and `SeenStore` become
  `IsReadOnly` (counts and dates change in memory only). On the Mac such a file counts as missing.
- UI language: `LanguageExtensions.Resolve` uses the Windows display language (`CultureInfo.CurrentUICulture`) where the
  Mac uses `Locale.preferredLanguages`.
- `hyneasm://` and Stream Deck links: copy `Link().OriginalString` to the clipboard (not `ToString()`, which unescapes).
