#!/bin/bash
# The same public-behaviour checks must pass now and fail on the fixed baseline.
set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE=c7efdc2d57052c6418b55d236be2c808d89c8a32
mkdir -p .build
PROBE_ROOT="$(mktemp -d "$PWD/.build/readiness-regressions.XXXXXX")"
git archive "$BASELINE" Sources/Core | tar -x -C "$PROBE_ROOT"

cat > "$PROBE_ROOT/main.swift" <<'SWIFT'
import Foundation

enum SelfTest {
    static var scratchDirectories: [URL] = []
    static func scratchDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-selftest-\(UUID().uuidString)", isDirectory: true)
        scratchDirectories.append(directory)
        return directory
    }
}

let tests = MidnightDayChecks.tests + RecoveryAuditChecks.tests
var passed = 0
for test in tests {
    let problems = test.1()
    if problems.isEmpty { passed += 1 }
    print("[\(problems.isEmpty ? "PASS" : "FAIL")] \(test.0)")
    for problem in problems { print("  \(problem)") }
}
for directory in SelfTest.scratchDirectories {
    try? FileManager.default.removeItem(at: directory)
}
print("\(passed)/\(tests.count) passed")
exit(passed == tests.count ? 0 : 1)
SWIFT

compile_probe() {
  local directory="$1" output="$2"
  local sources=()
  while IFS= read -r -d '' file; do sources+=("$file"); done \
    < <(find "$directory" -name '*.swift' -print0)
  swiftc -swift-version 5 -warnings-as-errors -whole-module-optimization \
    -target "$(uname -m)-apple-macos14.0" "${sources[@]}" \
    Sources/Verification/TestKit.swift Sources/Verification/MidnightDayChecks.swift \
    Sources/Verification/RecoveryAuditChecks.swift "$PROBE_ROOT/main.swift" -o "$output"
}

compile_probe Sources/Core "$PROBE_ROOT/current"
"$PROBE_ROOT/current" | tee "$PROBE_ROOT/current.log"
grep -qx '7/7 passed' "$PROBE_ROOT/current.log"

compile_probe "$PROBE_ROOT/Sources/Core" "$PROBE_ROOT/baseline"
set +e
"$PROBE_ROOT/baseline" > "$PROBE_ROOT/baseline.log" 2>&1
status=$?
set -e
cat "$PROBE_ROOT/baseline.log"
test "$status" -eq 1
grep -qx '0/7 passed' "$PROBE_ROOT/baseline.log"
test "$(grep -c '^\[FAIL\]' "$PROBE_ROOT/baseline.log")" -eq 7
echo 'Core regression proof: current 7/7; historical baseline 0/7.'
