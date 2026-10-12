"""Reintroduce one historical month-offset defect in an isolated build copy."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
(root / ".build").mkdir(exist_ok=True)
probe = Path(tempfile.mkdtemp(prefix="insight-calendar-regression-", dir=root / ".build"))
for name in ("Sources", "Assets", "scripts"):
    shutil.copytree(root / name, probe / name)
shutil.copy2(root / "build.sh", probe / "build.sh")
source = probe / "Sources/App/SessionStore+Insights.swift"
text = source.read_text()
fixed = """        guard let firstOrdinal = calendar.ordinality(of: .day, in: .era, for: currentBounds.start),
              let currentOrdinal = calendar.ordinality(of: .day, in: .era, for: currentDay) else { return nil }
        let dayOffset = currentOrdinal - firstOrdinal"""
historical = """        let dayOffset = calendar.dateComponents([.day], from: currentBounds.start,
                                                to: currentDay).day ?? 0"""
assert text.count(fixed) == 1, "the expected corrected month-offset block changed"
source.write_text(text.replace(fixed, historical))
result = subprocess.run(["bash", "build.sh", "--check"], cwd=probe,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
print(result.stdout, end="")
summary = re.search(r"^(\d+)/(\d+) passed$", result.stdout, re.MULTILINE)
assert result.returncode == 1, f"expected a self-test refusal, got exit {result.returncode}"
assert summary and int(summary[1]) == int(summary[2]) - 1, "expected exactly one failed self-check"
assert result.stdout.count("[FAIL]") == 1, "an unrelated check failed"
assert ("the second day of a month starting at 01:00 compares with the previous month's second day"
        in result.stdout), "the intended Havana month-comparison regression did not fail"
print("Insight regression proof: only the historical month-offset assertion failed.")
