"""Turn `flutter analyze` output into GitHub annotations; exit 1 on errors."""
import re
import sys

pattern = re.compile(r"^\s*(info|warning|error) [•-] (.+?) [•-] (\S+?):(\d+):(\d+) [•-] (\S+)\s*$")
errors = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = pattern.match(line)
    if not m:
        continue
    level, msg, path, row, col, rule = m.groups()
    kind = "error" if level == "error" else "warning"
    errors += level == "error"
    print(f"::{kind} file={path},line={row},col={col}::[{rule}] {msg}")
sys.exit(1 if errors else 0)
