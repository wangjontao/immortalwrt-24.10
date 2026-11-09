from pathlib import Path
import json
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
m=lua.execute((ROOT/'root/usr/lib/lua/fastacl252_wireless.lua').read_text(encoding='utf-8'))
rows=m.parse("""Station 02:00:00:00:00:01 (on phy1-ap0)
        rx bytes: 100000
        tx bytes: 200000
        signal: -51 [-51, -53] dBm
        tx bitrate: 866.7 MBit/s VHT-MCS 9
        rx bitrate: 780.0 MBit/s VHT-MCS 8
        connected time: 312 seconds
Station 02:00:00:00:00:02 (on phy1-ap0)
        signal: -72 dBm
""")
assert len(rows)==2
assert rows[1]['rx_bytes']==100000 and rows[1]['tx_bytes']==200000
assert rows[1]['signal']==-51 and rows[1]['tx_link_mbps']==866.7 and rows[1]['connected_seconds']==312
assert rows[2]['rx_bytes'] is None and rows[2]['signal']==-72
assert len(m.parse(''))==0
account=(ROOT/'root/etc/uci-defaults/96-juliang-center').read_text(encoding='utf-8')
assert "username='admin'" in account and "ADMIN_HASH='$1$" in account
assert "juliang_operator.write='*'" not in account and "juliang_operator.read='*'" not in account
assert "juliang_operator.read='juliang-bbr'" in account
assert "juliang_operator.write='juliang-bbr'" in account
acl=json.loads((ROOT/'root/usr/share/rpcd/acl.d/juliang-fastacl252.json').read_text(encoding='utf-8'))
assert 'system' not in acl['juliang-fastacl252']['write'].get('uci',[])
bbr_acl=json.loads((ROOT/'root/usr/share/rpcd/acl.d/juliang-bbr.json').read_text(encoding='utf-8'))
assert 'juliang_bbr' in bbr_acl['juliang-bbr']['write']['uci']
print('PASS wireless counters, missing fields, signal/link rates and restricted admin invariants')

center=(ROOT/'root/usr/lib/lua/luci/controller/juliang_center.lua').read_text(encoding='utf-8')
assert 'statistics/rx_bytes' in center and 'statistics/tx_bytes' in center
assert 'traffic=counters' in center
assert "_('无线设备管理')" in center
wireless_view=(ROOT/'root/usr/lib/lua/luci/view/juliang_center/wireless.htm').read_text(encoding='utf-8')
assert '无线设备管理' in wireless_view
assert 'profile_update' in wireless_view and 'action:\'profile_update\'' in wireless_view
assert '实时上传' in wireless_view and '本次上传' in wireless_view
assert 'grid-template-columns:repeat(4,minmax(0,1fr))' in wireless_view
assert '@container(max-width:520px)' in wireless_view
assert '编辑设置' not in wireless_view or '编辑' in wireless_view
wireless_module=(ROOT/'root/usr/lib/lua/fastacl252_wireless.lua').read_text(encoding='utf-8')
wifi_module=(ROOT/'root/usr/lib/lua/fastacl252_wifi.lua').read_text(encoding='utf-8')
assert 'section=section' in wireless_module and 'hidden=w.hidden' in wireless_module
assert 'function M.update_profile' in wifi_module and "encryption','psk2+ccmp'" in wifi_module
sysctl=(ROOT/'root/etc/sysctl.d/99-juliang-wifi-high-density.conf').read_text(encoding='utf-8')
assert 'net.core.rmem_default=1048576' in sysctl
assert 'net.core.rmem_max=16777216' in sysctl
assert 'net.core.wmem_max=16777216' in sysctl
assert 'net.core.optmem_max=262144' in sysctl
assert 'net.core.netdev_max_backlog=4096' in sysctl
