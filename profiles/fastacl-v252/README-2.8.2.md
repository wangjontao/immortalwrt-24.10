# FastACL 2.8.2

FastACL 2.8.2 is the JuLiang OS maintenance release built from the 2.8.1
sing-box firmware baseline. It keeps the native sing-box TPROXY/TUN dataplane
and collects the interface, assignment, branding, upgrade, and permission
fixes validated on the router.

## 2.8.2 changes

- Custom DNS now supports direct DoH, UDP and TCP. Proxy-side custom DNS
  supports DoH and TCP through the selected node and front proxy.
- Every managed WiFi, the primary WiFi/LAN, devices in existing assignment
  views, and newly created WiFi expose independent DNS controls.
- WiFi DNS inheritance shows the effective global DNS instead of only the
  generic `follow global` label.
- Per-WiFi node, front proxy, DNS and split settings can be applied together
  in one transaction; selected WiFi cards can be applied as a group.
- Wireless runtime bridge mapping and fw4 DHCP/DNS chains are reconciled after
  hot apply, preventing a WiFi label from temporarily serving another subnet.
- FastACL health recovery verifies `dnsmasq`; DHCP gates are restored
  automatically after an interrupted service or firewall refresh.
- NPS is relocated to `System -> JuLiang管理`, with old routes kept as aliases.
- The monitoring center adds CPU, memory and CPU-temperature gauges, a smooth
  gradient traffic chart with interactive history, and a responsive layout.
- Today/month upload and download totals use `vnstat2` through the independent
  `juliang-traffic` service. The database is stored under `/etc/vnstat` and
  preserved during firmware upgrades.

## Console

- Five fixed workspaces: overview, nodes and subscriptions, single-WiFi
  multi-device assignment, multi-WiFi assignment, and global settings.
- The status header and workspace navigation stay fixed while content scrolls.
- Nodes come before subscriptions; labels and visual hierarchy are separated
  for faster scanning.
- Gradient menu buttons, clearer page headings, and a restrained five-tab
  layout replace the earlier crowded navigation.
- Notifications dismiss automatically after three seconds.
- Nodes can be edited, copied, exported individually, or exported as a complete
  backup.
- Node exit probes reuse an unambiguous saved front-proxy chain and report the
  front node name with the detected public exit.

## Assignment

- The primary WiFi and wired LAN default exit supports the same node, front
  proxy, DNS path, DNS provider, split routing, and platform-priority behavior
  as managed WiFi and devices.
- Any supported outbound protocol can use a front proxy.
- Primary WiFi/LAN and created WiFi panels are collapsible.
- Existing single-WiFi device assignment and force-TK behavior are retained.

## System

- The Argon product mark is `JuLiang 网络服务`.
- The parent LuCI menu is `JuLiang 控制面板`; its first child is `监测中心`.
- The overview heading is `JuLiang 监测中心`.
- Online-upgrade status and action URLs are peer routes under
  `/admin/juliang/`; the worker is compatible with `set -u` and writes
  `key=value` status records.
- Build image discovery follows the generated `juliang-os` filename prefix
  instead of assuming the upstream `immortalwrt` name.
- Kernel validation checks the native nftables `NFT_TPROXY` dependency and no
  longer requires the unused legacy iptables `NETFILTER_XT_TARGET_TPROXY`.
- BBR TCP acceleration has an independent ACL and is delegated to the
  restricted `admin` account without granting general system access.

The `2.8.1` branch remains available for rollback. Build profiles and workflows
for this release use the `FastACL282` names.

## Model coverage

- MT7981 matrix: 32 devices across the standard, U-Boot, eMMC and NAND variants.
- MT7986 matrix: S20L, S20P, JDCloud RE-CP-03, GL.iNet GL-MT6000, Redmi AX6000
  NMBM 110MiB and Netcore N60 Pro.
- Redmi AX6000 remains excluded from automatic online upgrades until its runtime
  partition layout can be identified safely.
