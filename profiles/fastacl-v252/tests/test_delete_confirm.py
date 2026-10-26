"""Guard destructive node and WiFi actions behind two confirmations."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "root/usr/lib/lua/luci/view/fastacl252/console.htm").read_text(encoding="utf-8")
single = (ROOT / "root/usr/lib/lua/luci/controller/fastacl252.lua").read_text(encoding="utf-8")
batch = (ROOT / "root/usr/lib/lua/luci/controller/fastacl252_batch.lua").read_text(encoding="utf-8")

assert "function confirmTwice(first,second)" in view
for handler in ("delete-selected", "wifi-delete-selected", "wifi-clear-all"):
    line = next(line for line in view.splitlines() if f"$('{handler}').onclick" in line)
    assert "confirmTwice(" in line, line
assert "confirmTwice('删除 '+w.ssid" in view
assert "confirmTwice('删除 '+n.name" in view
assert "force:1" in view and "force:true" in view
assert "h.formvalue('force')" in single
assert "if force then" in single
assert "req.force==true" in batch and "bound[id] and not force" in batch
assert "关联设备和 WiFi 已切换为国内直连" in batch
print("PASS forced node deletion and double confirmation for node and WiFi deletion")
