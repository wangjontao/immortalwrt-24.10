"""Static guard for the 2.6.4-compatible control-center traffic panel."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "root/usr/lib/lua/luci/view/juliang_center/home.htm").read_text(encoding="utf-8")
console = (ROOT / "root/usr/lib/lua/luci/view/fastacl252/console.htm").read_text(encoding="utf-8")
center = (ROOT / "root/usr/lib/lua/luci/controller/juliang_center.lua").read_text(encoding="utf-8")
fastacl_init = (ROOT / "root/etc/init.d/fastacl252").read_text(encoding="utf-8")

assert "<h3>流量统计</h3>" in view
assert 'id="jc-chart"' in view
assert "luci.dispatcher.build_url('admin','juliang','status')" in view
assert view.count("luci.dispatcher.build_url('admin','juliang','status')") == 1
assert "t.tx_bytes" in view and "t.rx_bytes" in view
assert 'id="jc-total-up"' in view and 'id="jc-total-down"' in view
assert "setInterval(update,3000)" in view and "history.filter(p=>t-p.t<=120)" in view
assert "r.traffic_totals" in view and "totalStatus.textContent='持久统计" in view
assert "setInterval(update,30000)" not in view
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
assert "admin','juliang','port_traffic" in view
assert "updatePortTraffic" in view and "jc-port-rates" in view
assert "grid-template-columns:repeat(5,minmax(0,1fr))" in view
assert "function linkSpeed(v)" in view and "' Gbps'" in view
assert "port-top" in view and "port-state" in view and "port-speed" in view
assert "port_traffic_status" in center
assert "rx_bytes=tonumber" in center and "tx_bytes=tonumber" in center
assert "script_timeout='180'" in fastacl_init
assert "network_timeout='120'" in fastacl_init
assert ".f252 .subscription-create{border-color:var(--jl-line)!important;background:linear-gradient(100deg,#0a1d2c,#0d2638)!important" in console
assert ".f252 .subscription-columns{border-color:var(--jl-line)!important;background:#102738!important;color:#8fa9b8!important" in console
assert ".f252 .subscription-empty{border-color:#2a4b5e!important;background:#091b28!important" in console
assert 'id="f25-capacity"' in console and 'value="extreme"' in console
assert "capacity_profile:$('capacity').value" in console
assert 'id="f25-connection-state"' in console and "setInterval(pollConnections,3000)" in console
assert "fastacl252_connections" in (ROOT / "root/usr/lib/lua/luci/controller/fastacl252.lua").read_text(encoding="utf-8")
assert "流量统计" not in console
print("PASS control-center traffic panel samples WAN counters every 3 seconds and keeps a two-minute chart")
