---
name: add-check
description: Add a headless self-check to FocusContinuity's suite. Use before changing behaviour, when fixing a bug (the check must fail on the old behaviour), or when asked to add a check or test.
---

# Add a self-check

## 1. Choose the file

- An area with its own group: add to `Sources/Verification/<Area>Checks.swift`.
- A new area: create `Sources/Verification/<Area>Checks.swift`.
- `Sources/Verification/SelfTest/SelfTest+*.swift` holds SelfTest's own
  numbered checks; extend those only when the change belongs there.

## 2. Write the suite

```swift
import Foundation

/// What this group guards, in one or two sentences.
enum ExampleChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The behaviour, stated as a sentence that is now true", behaviourHolds),
    ]

    private static func behaviourHolds() -> [String] {
        var problems: [String] = []
        // Arrange with the fixtures in step 4 (e.g. a TestClock and
        // SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })),
        // act, then for each outcome:
        // expect(actual == expected, "what should hold, got \(actual)", &problems)
        return problems
    }
}
```

- `expect(_:_:&problems)` comes from `CheckSuite` (`Sources/Verification/TestKit.swift`).
  For durations use `SelfTest.expectClose`.
- Each message says what should hold and includes the observed value.

## 3. Register it

Append `+ ExampleChecks.tests` at the end of `registeredTests` in
`Sources/Verification/SelfTest/SelfTest+Registry.swift`. Never insert it
earlier: a check's position is its number, and comments cite those numbers.

## 4. Keep it isolated

| Need | Use |
|---|---|
| Time | `TestClock`, moved with `advance(_:)`. Never `Date()` in the logic under test. |
| Today's real calendar | `SelfTest.anchoredNow()` (avoids both edges of midnight, DST-aware); `SelfTest.periodAnchor()` for week or month roll-ups |
| Files | `SelfTest.scratchDirectory()`, or `makeArchive`, `makeUsageArchive` and `makeEngine` in `SelfTest+Fixtures.swift` |
| Preferences | `UserDefaults(suiteName: "fc-selftest-<area>-\(UUID().uuidString)")`, then `UserDefaults.standard.removePersistentDomain(forName: suite)` at the end. Never `.standard` itself. |
| `SessionStore` or other `@MainActor` types | Wrap the body in `MainActor.assumeIsolated { … }` |
| An automatic session | After `engine.start(…, isAuto: true)`, take `engine.snapshot()`, set `isAuto = true` and call `engine.restore(from:)`: the persisted ownership is what marks it automatic. See `AutomaticNamingChecks.swift`. |

Day arithmetic goes through `Calendar` (a daylight-saving day is 23 or 25
hours), never multiples of 86 400 seconds.

## 5. Prove it bites

A check that cannot fail proves nothing. In a scratch copy, put the old
behaviour back and confirm the new check fails:

```bash
rsync -a --exclude .git --exclude .build --exclude FocusContinuity.app ./ "$TMPDIR/mutant/"
# edit the old behaviour back in under $TMPDIR/mutant, then:
(cd "$TMPDIR/mutant" && ./build.sh --check)   # sandbox disabled; the new check must fail
rm -rf "$TMPDIR/mutant"
```

## 6. Run the suite

Run `./build.sh --check` with the sandbox disabled and report the result as
`passed/total`.
