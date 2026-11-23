# Mac / Windows parity checklist

Every user-facing feature of HYNE ASM with its status on both platforms. The Windows app is `windows/HyneAsm.App`
(WPF) on top of `windows/HyneAsm.Core`, whose logic is checked against the Mac's through the shared fixtures in
`spec/fixtures`.

## Rules

- A feature isn't done until both columns are ticked, or the gap is written down here with a reason.
- New Mac feature -> a Windows to-do row here the same day (and the other way round).
- Fixtures first: new logic gets its cases in `spec/fixtures` before it is implemented, then both sides are built
  against them (`swift test` and `dotnet test` run the same files).
- Platform-only behaviour (a Mac-only or Windows-only system quirk) is allowed but listed below, with the reason.
- Shortcuts in files stay in the Mac format (`KeyCombo`: macOS key code + Mac modifiers); Windows translates at runtime
  (`KeyTranslation`).

## Features

| Feature | Mac | Windows | Notes |
|---|---|---|---|
| Panel: grid / list, paging, categories on top or left | ✅ | ✅ | |
| Panel: page turning at the edges, mouse wheel | ✅ | ✅ | |
| Panel: folders as a side list on hover | ✅ | ✅ | |
| Panel: typing filters all plugins, rebindable keys, digits by position | ✅ | ✅ | |
| Panel: drag pads to reorder, right-click (favorite, category, other formats) | ✅ | ✅ | |
| Double right-click opens the panel | ✅ | ✅ | low-level mouse hook |
| Quick search | ✅ | ✅ | default Ctrl+Space (see below) |
| Item shortcuts | ✅ | ✅ | |
| Close plugin windows (focused / all), never the main window | ✅ | ✅ | owned, captioned windows of Live's process |
| Open plugin windows: all of the track (shortcut), click in the X-Y field (Shift-selected plugins open together) | ✅ | ✅ | presses Live 12's `TrackView.Device[…].TitleBar.PluginEdit` buttons: Mac through the Accessibility API (AXIdentifier), Windows through UI Automation (AutomationId; not yet confirmed on a real PC) |
| Settings: Library (browser tree, drag & drop, multi-select, folders, colours, icon grid, chains, Live commands) | ✅ | ✅ | |
| Settings: Profiles, versions, LES import | ✅ | ✅ | |
| Settings: Shortcuts, keyboard overview, conflict warnings | ✅ | ✅ | own Live 12 Windows and Windows tables |
| Settings: Behavior (layout, size, insert target, multi-track, hints, Stream Deck) | ✅ | ✅ | |
| Settings: Shape Search | ✅ | ✅ | |
| Settings: Stats | ✅ | ✅ | |
| Undo in the settings | ✅ | ✅ | Ctrl+Z / Win+Z |
| Own presets: drop files, copy unknown ones into a preset folder | ✅ | ✅ | Windows: several folders (Behavior) |
| Five themes | ✅ | ✅ | |
| Welcome window | ✅ | ✅ | no Accessibility step on Windows |
| Menu bar / tray menu | ✅ | ✅ | tray icon on Windows |
| Install the Live script (ASMbridge) | ✅ | ✅ | User Library from Live's `Library.cfg` |
| German / English | ✅ | ✅ | |
| `hyneasm://` links, Stream Deck endpoint | ✅ | ✅ | |
| Download and install | DMG | setup (about 1 MB), adds the .NET Desktop Runtime when missing | `win-vX.Y.Z` tags, never marked "latest" |

## Platform-only behaviour and facts learned

- **Plugin-window settings live in an optional `pluginWindows` block** of the config, left out while it holds the
  defaults, so the shared `config.roundtrip` fixture didn't change. Both apps read it leniently (a damaged block means
  the defaults).
- **The X-Y click lookup waits at most 50 ms (Mac, event tap) / 60 ms (Windows, low-level mouse hook)**; past that the
  click goes to Live. Windows runs the UI Automation lookup on a pool thread (UI Automation wants MTA) and warms it up
  when Live comes to the front, because the first lookup in a process is slow. The field works as usual with ⌥ (Mac) or
  Alt/Ctrl (Windows) held.

- **Known-shortcut tables differ by design.** `KnownShortcuts.swift` lists Live 12 Mac and macOS defaults;
  `KnownShortcuts.cs` lists Live 12 Windows (from the Live 12 manual's keyboard-shortcut chapter) and Windows defaults
  (Win+..., Alt+Tab, Ctrl+Esc, input switch ...). Same structure, no shared fixture; plain xUnit tests.
  (The Mac "Close Window" and "Hide Live" have no Windows entry in the manual, so they are not in the table.)
- **Windows default shortcuts differ from the Mac's**: the Mac's ⌃Space would be Win+Space (the input-language switch)
  and ⌘Esc would be Ctrl+Esc (the Start menu). Windows uses Ctrl+Space (quick search), Ctrl+W (close the focused plugin
  window) and Ctrl+Shift+W (close all); a config still on the Mac defaults gets these on first start.
- **Win+G and Win+Z in the settings** (the Mac's ⌘G / ⌘Z) are taken from Windows by the keyboard hook while the settings
  window is in front (Windows would open the Game Bar for Win+G).
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
- **Dates with a UTC offset or fractional seconds in `.hmlmenu`/`.hmlusage`** (only in hand-edited files; both apps
  write whole seconds with `Z`): the Mac's answer depends on the macOS version (macOS 26 reads
  `2026-03-01T13:30:00.75+01:00`, macOS 15 rejects it), so it is not a shared fixture. Windows reads it. Out-of-range
  fields such as hour 25 are rejected on Windows, while the Mac rolls them over.
