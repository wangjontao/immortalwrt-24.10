#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
makefile = (
    ROOT / "package/network/services/uhttpd/Makefile"
).read_text(encoding="utf-8")

assert "PKG_SOURCE_DATE:=2025-07-06" in makefile
assert "PKG_SOURCE_VERSION:=7e64e8bad2415cec0a6d9770ec379db54273c7a7" in makefile
assert "PKG_SOURCE_DATE:=2025-10-03" not in makefile

print("uhttpd is pinned to the stable concurrent-request build: OK")
