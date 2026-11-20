# Apple Intelligence probe, 19 November 2026

Purpose: confirm Phase C's requirement (macOS 26 and Apple's on-device model)
holds on the owner's Mac before building the category pick. Plan Task 0.

## Method

A standalone `main.swift` in a fresh `mktemp -d` folder, compiled with
`swiftc -swift-version 5 -target arm64-apple-macos26.0`. It prints
`SystemLanguageModel.default.availability` and, when available, sends one
fixed neutral prompt ("Answer with the word ready.") through a fresh
`LanguageModelSession` with the instructions "Answer in one word." and prints
the reply and the wall-clock latency. Daybook was not built or launched, and
no personal data was read or sent.

## Result

| Item | Observed |
|---|---|
| macOS | 27.3 |
| `availability` | `available` |
| Reply | `ready` |
| Latency, first call | 2.86 s |

## What it settles

- The live model path is usable on this Mac, so the `ModelGate` check passes
  here and Phase C's model questions can run for real.
- The 10 s timeout in ruling C5 leaves room over a first-call latency of about
  3 s.
- Self-checks still never reach the live model (ruling C22): they use the
  injected responder.
