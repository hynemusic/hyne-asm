# Shared fixtures

These JSON files prove that the Windows core (`windows/HyneAsm.Core`, C#) behaves exactly like the
Swift core (`Sources/HMLauncherCore`). Both `swift test` and `dotnet test` run every file here.

## Format

```json
{ "area": "<area>", "cases": [ { "name": "<unique within the area>", "input": <json>, "expected": <json> } ] }
```

An optional top-level `"reference": "hand"` marks a file whose `expected` values are written by hand
(not produced by Swift). The Swift recorder never rewrites such a file; in normal mode Swift still runs
its handler for that area, if one is registered, to validate it.

## Swift is the reference

`expected` comes from the Swift implementation. Change Swift behaviour first, re-record, then make the
C# side match.

## Recording

```
HM_RECORD_FIXTURES=1 swift test --filter SharedFixtureTests
```

Record mode runs the Swift handler for every case and rewrites `expected` in place. Files are written
by `JSONValue.pretty()` in `SharedFixtureTests.swift` (a small hand-written serializer, not
`JSONSerialization`, because Foundation's pretty printing emits `"key" : value`): 2-space indent, keys
sorted, `"key": value`, integral numbers without a decimal point, and a trailing newline. Fixture files
should be committed in that canonical form. Record mode fails if an area has no Swift handler.
Files with `"reference": "hand"` are never rewritten.

## Every area needs a handler on both sides

- Swift: add an entry to `SharedFixtureTests.handlers` (`Tests/HMLauncherCoreTests/SharedFixtureTests.swift`).
- C#: add an entry to `Fixtures.Handlers` (`windows/HyneAsm.Core.Tests/Fixtures.cs`).

A fixture area with no C# handler fails `Every_fixture_area_has_a_handler`, so a Mac-side fixture
without a Windows implementation fails CI.
