# FastACL 2.5.3 — S20L 测试版

以实机修复后的 Lite 版本为基线。内部包名、UCI、服务与 API 继续使用 fastacl252，以兼容既有配置。

已包括 DNS Relay MagicNetwork 修复、附加 WiFi DNS 12553 防火墙放行、IP 拨号、原 CF 跟随选项、列表和折叠、柔和标题、节点及设备绑定出口检测。增加按 SSID 的连接设备、IP、MAC、信号、链路速率、每 3 秒采样的收发流量速率；折叠后暂停采样。

实际速率来自 AP station 字节计数差值，包含局域网流量。Tx/Rx 链路速率为无线协商速率，不是实际吞吐。无法发现设备 IP 时明确显示未知。

root 保留完整管理和 SSH；admin 保留独立 crypt 密码与受限 LuCI ACL，不增加全局管理权限。无线视图复用 FastACL ACL 的只读 LuCI 入口，不暴露 WiFi 密钥。

状态：功能基线已形成，仍需完整硬件、长稳、IPv6、故障防直连及升级场景测试。GitHub 发布使用 prerelease 标识，禁止视作全量验收通过。

控制中心显示名为“JuLtiang 控制中心”，展示 WAN 实时收发速率及柔和渐变标题；界面不展示 S20L 品牌后缀，但构建目标仍为 CLX S20L。移除 NAS、统计菜单，不选择 luci-app-samba4 / luci-app-statistics；WAN 实时速率不依赖 collectd。
