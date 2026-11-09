#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
controller = (
    ROOT / "profiles/fastacl-v252/root/usr/lib/lua/luci/controller/fastacl252.lua"
).read_text(encoding="utf-8")
start = controller.index("function wifi_action()")
end = controller.index("\nfunction ", start + 1)
action = controller[start:end]

assert "wifi reconf >/dev/null 2>&1" in action
assert "wifi reload >/dev/null 2>&1" not in action

print("FastACL WiFi edit applies without reloading all radios: OK")
