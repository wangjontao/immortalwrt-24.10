#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
env = (
    ROOT / "profiles/fastacl-v252/root/usr/lib/lua/fastacl252_env.lua"
).read_text(encoding="utf-8")
controller = (
    ROOT / "profiles/fastacl-v252/root/usr/lib/lua/luci/controller/fastacl252.lua"
).read_text(encoding="utf-8")
console = (
    ROOT / "profiles/fastacl-v252/root/usr/lib/lua/luci/view/fastacl252/console.htm"
).read_text(encoding="utf-8")

for mode in ("auto", "compact", "balanced", "quad", "high", "extreme"):
    assert mode in controller
    assert f'value="{mode}"' in console

for profile, connections, per_session in (
    ("compact", "12288", "64"),
    ("balanced", "16384", "96"),
    ("quad", "28672", "112"),
    ("high", "40960", "128"),
    ("extreme", "65536", "512"),
):
    assert f"{profile}={{{connections},{per_session}}}" in env

print("FastACL six capacity profiles are present: OK")
