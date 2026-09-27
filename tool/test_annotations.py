"""Turn `flutter test --machine` output into GitHub annotations; exit 1 on failures.

Flutter prints the real exception (e.g. layout overflow) as test output before
the generic "Test failed" error, so the output of failing tests is included.
"""
import json
import sys


def esc(s):
    return s.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


names, prints, failed = {}, {}, 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        e = json.loads(line)
    except ValueError:
        continue
    t = e.get("type")
    if t == "testStart":
        names[e["test"]["id"]] = e["test"]["name"]
    elif t == "print":
        prints.setdefault(e.get("testID"), []).append(e.get("message", ""))
    elif t == "error":
        failed += 1
        tid = e.get("testID")
        out = "\n".join(prints.pop(tid, []))
        msg = (out + "\n---\n" + e.get("error", "") + "\n" + e.get("stackTrace", ""))[:6000]
        print(f"::error title={names.get(tid, 'test')}::{esc(msg)}")
    elif t == "done":
        print("done: success" if e.get("success") else "done: FAILED")
sys.exit(1 if failed else 0)
