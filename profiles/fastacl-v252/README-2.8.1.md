# FastACL 2.8.1

FastACL 2.8.1 is the JuLiang OS maintenance release built from the 2.8.0
sing-box firmware baseline. It keeps the native sing-box TPROXY/TUN dataplane
and collects the interface, assignment, branding, upgrade, and permission
fixes validated on the router.

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

The `2.8.0` branch remains available for rollback. Build profiles and workflows
for this release use the `FastACL281` names.
