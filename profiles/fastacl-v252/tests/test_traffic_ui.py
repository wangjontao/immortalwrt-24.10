"""Static guard for the 2.6.4-compatible control-center traffic panel."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "root/usr/lib/lua/luci/view/juliang_center/home.htm").read_text(encoding="utf-8")
console = (ROOT / "root/usr/lib/lua/luci/view/fastacl252/console.htm").read_text(encoding="utf-8")
center = (ROOT / "root/usr/lib/lua/luci/controller/juliang_center.lua").read_text(encoding="utf-8")

assert "<h3>流量统计</h3>" in view
assert 'id="jc-chart"' in view
assert "luci.dispatcher.build_url('admin','juliang','status')" in view
assert "t.tx_bytes" in view and "t.rx_bytes" in view
assert 'id="jc-total-up"' in view and 'id="jc-total-down"' in view
assert "setInterval(update,3000)" in view and "history.filter(p=>t-p.t<=120)" in view
assert "bytes(t.tx_bytes)" in view and "bytes(t.rx_bytes)" in view
assert "Math.max(0,Number(t.tx_bytes)-Number(previous.tx_bytes))" in view
assert ".jc-speed-grid .jc-value{font-size:18px;color:#24476e}" in view
assert "linearGradient" in view and "jc-down-fill" in view and "jc-up-fill" in view
assert "pointermove" in view and "toLocaleString('zh-CN'" in view
assert "jc-tip-shadow" in view and "stroke-dasharray':'5 5'" in view
for gauge in ("cpu", "mem", "temp"):
    assert f'id="jc-{gauge}-gauge"' in view
    assert f'id="jc-{gauge}"' in view
assert "conic-gradient" in view and "jc-gauge.high" in view
assert "cpu_percent" in center and "memory_percent" in center and "temperature_c" in center
assert "/proc/stat" in center and "/proc/meminfo" in center and "thermal_zone0" in center
assert "function plot(t,up,down)" in view
assert "}plot=function(" not in view
assert "流量统计" not in console
print("PASS control-center traffic panel samples WAN counters every 3 seconds and keeps a two-minute chart")
