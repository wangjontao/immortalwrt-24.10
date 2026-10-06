# JuLiangTK S20L · FastACL 2.5.0-dev.1

基于 `wangjontao/immortalwrt-24.10` 的 `openwrt-24.10` 分支开发。只针对 **S20L / MT7986A / fw4 nftables**，不做旧机型和 iptables 适配。当前是开发测试版，真实 S20L 冷启动、手机/电脑连续运行验证通过后再定正式版。

## 固件

| 项目 | 设置 |
|---|---|
| 展示机型 | JuLiangTK S20L |
| 硬件 compatible / 分区 | 原 `clx,s20l` 保持不变 |
| 管理地址 | 192.168.7.1 |
| SSH | 20022，root 密码沿用原构建默认值 |
| 主 WiFi | JuLiangTK，2.4G / 5G 共用同一名称和 LAN |
| 无线密码 | a1111111 |
| 固定信道 | 2.4G 9 / 5G 48 |
| FastACL | 2.5.0-dev.1，纯设备分流 |
| 核心 | 官方 sing-box 1.12.25 ARM64，校验固定 SHA256 |
| 保留软件 | iStore、QuickStart、Argon、TTyD、DDNS、UPnP、WOL、Samba4、SQM、定时重启、Statistics、NPS/npc 等原配置工具 |
| 移除软件 | PassWall、PassWall2、HomeProxy、OpenClash，以及旧多无线生成脚本 |

该大版本建议全新配置刷入，旧的无线代理分配不迁移为设备分配。镜像文件仍采用原 S20L 硬件标识，避免破坏 sysupgrade 校验。

## 按设备分配

- 一个 WiFi 接入多部手机/电脑；读取 DHCP 租约和 IPv4 邻居表。租约存在不等于在线。
- MAC → DHCP 固定 IPv4 → 独立代理出口或国内直连，支持批量设置和解除绑定。
- 检查重复 MAC、IP、其他静态租约和已有设备地址；改地址后需重新获取 DHCP。
- 未绑定默认国内直连；已绑定代理设备不回落直连。
- 所有节点使用一个原生 sing-box 核心；同节点和前置组合共享 outbound，健康状态不重启核心或重写防火墙。
- SOCKS5/HTTP 落地节点可按设备单独选择前置节点，不修改其他设备的绑定。
- 没有无线分配界面和批量建立 WiFi 功能。

## 节点和机场订阅

- 内置手动批量导入：SOCKS5 / SK5 / HTTP(S) / VLESS / VMess / Trojan / SS / Hysteria2 / TUIC。
- 多个 HTTPS 机场订阅，手动或按 1–168 小时定时更新。
- 本机解析链接列表、Base64、Clash YAML `proxies` 与 sing-box JSON `outbounds`，不上传订阅到第三方转换器。
- 订阅下载采用 DoH 并校验证书；下载/解析/核心检查失败保留旧节点。
- 订阅节点 ID 按来源、协议、名称和同名出现顺序稳定生成；同名节点改服务器/密码时保持绑定。
- 订阅删除的已绑定节点标记“下架，保留绑定”；未绑定旧节点清理。删除正在使用的节点/订阅会被拒绝。
- 订阅地址和节点密码不出现在状态接口中；配置文件使用 root-only 权限。
- 首版不支持 SSR、SS 插件和所有机场自定义扩展；遇到不支持的 Clash 协议整次更新报错，防止悄悄丢失节点。

## DNS 与故障保护

- 默认阿里 DoH 直连；高级隐私按设备出口使用 Quad9 DoH。无明文 DNS 故障回退。
- 对受管 LAN 的 TCP/UDP 53 请求接管；节点域名由核心加密 DNS 解析。
- 代理设备 IPv4 的 MAC/源 IP 组合校验，改 IP/冒用固定 IP 不自动直连。
- 首版只做 IPv4 分配；默认关闭 LAN RA/DHCPv6 通告，另阻断代理设备 IPv6 转发和 LAN IPv6 53 请求。
- 无线/有线二层互访和 MAC 冒用攻击不属于身份认证；下级 NAT 后共享同一 MAC/IP 的多个设备无法分开。
- 应用自带 DoH/DoT 不会被解密改写，代理设备的连接仍经该设备出口。
- HTTP 节点不支持任意 UDP，失败时不会直连回退。
- 为防止硬件/软件流量卸载绕过规则，固件关闭 flow offloading。

## 开发与安装

云构建：`.github/workflows/JuLiangTK-S20L-FastACL25.yml`，先测试再编译，产物发布为 prerelease。

软件开发包需要 24.10 fw4、LuCI Lua、lyaml、curl TLS/DoH、sing-box **1.12.x**。在完整包目录可执行：

```sh
sh install.sh --check
sh install.sh --preview   # 安装未启用的页面；保存设备会写 DHCP 租约
sh install.sh --activate  # 启用独立设备分流，要求没有其他透明代理接管
```

页面：`/cgi-bin/luci/admin/services/fastacl25`。安装器不替换核心；提供备份及 `rollback.sh`。

`fastacl25 stop` 保留保护规则；显式 `fastacl25 cleanup` 或完整回退才释放规则。应用失败请检查 `/tmp/fastacl25/apply.log` 和 `/tmp/fastacl25/check.log`。

## 验证

- `tests/test_policy.py`：设备出口、共享核心、前置、DNS、地址冲突、规则顺序、错误节点保护和配置语法。
- `tests/test_import.py`：链接和四种订阅格式；生成八类协议配置交给官方核心检查。
- `tests/test_subscription.py`：更新保持 ID、多个来源同名隔离、下架节点保留/删除。
- `tests/test_firewall.py`：Linux 隔离网络中同 LAN 两设备经 SOCKS/HTTP 出口、直连、IPv6 防绕过、源身份错误和核心故障保护。
- `tests/test_browser.py`：模拟后端下真实页面的设备分配、DNS、搜索及订阅操作。截图仅表示演示 UI，不代替实机接口测试。

设备数仍受 AP、CPU、内存、地址池和带宽限制；不同公网 IP 需要节点实际提供不同出口。测试中生成 256 条规则不代表实机已验证可同时接入 256 台。
