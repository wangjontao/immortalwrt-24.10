"""Static checks for persistent WAN traffic totals."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
controller = (ROOT / "root/usr/lib/lua/luci/controller/juliang_center.lua").read_text(encoding="utf-8")
view = (ROOT / "root/usr/lib/lua/luci/view/juliang_center/home.htm").read_text(encoding="utf-8")
setup = (ROOT / "root/usr/libexec/juliang-traffic-setup").read_text(encoding="utf-8")
init = (ROOT / "root/etc/init.d/juliang-traffic").read_text(encoding="utf-8")
hotplug = (ROOT / "root/etc/hotplug.d/iface/99-juliang-traffic").read_text(encoding="utf-8")
makefile = (ROOT / "package-Makefile").read_text(encoding="utf-8")

assert "/usr/bin/vnstat --json" in controller
assert "traffic.day" in controller and "traffic.month" in controller
assert "traffic_totals=traffic_totals()" in controller
for item in ("today-up", "today-down", "month-up", "month-down"):
    assert f'id="jc-{item}"' in view
assert "每 30 秒更新" in view and "traffic_totals" in view
assert "jsonfilter -e '@.l3_device'" in setup
assert 'DatabaseDir "/etc/vnstat"' in setup
assert "/etc/init.d/vnstat restart" in init
assert '"$INTERFACE" = wan' in hotplug
assert "+vnstat2" in makefile
assert "/usr/libexec/juliang-traffic-setup" in makefile

print("PASS persistent WAN traffic totals use vnstat and survive WAN rebinding")
