#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
theme = ROOT / "package/luci-theme-juliang/ucode/template/themes/juliang"
for name in ("header.ut", "footer.ut"):
    text = (theme / name).read_text(encoding="utf-8")
    assert "S20L" not in text, name

print("JuLiang theme uses model-neutral branding: OK")
