# FastACL V2.6.8

## 2.6.8-r1

FastACL 2.6.8 backports today's management, DNS, stability and monitoring
improvements from the 2.8.2 sing-box line while retaining the dae/eBPF
dataplane used by the 2.6.x firmware family.

所有机型的系统显示名统一为 `JuLiang OS`，硬件型号继续保留在构建标识和主机名中。

## DNS

- Global direct DNS supports DoH, UDP and TCP.
- Global proxy DNS supports DoH and TCP carried through the selected node and
  optional front proxy.
- Primary WiFi / wired LAN and every managed WiFi can use their own custom DNS.
- Inherited WiFi DNS shows the effective global provider instead of an
  ambiguous blank value.
- Invalid proxy-side UDP is rejected to prevent DNS from falling back to WAN.

## Multi-WiFi

- Each WiFi card keeps an independent node, front proxy, split policy and DNS.
- One action applies all pending WiFi card changes in a single transaction and
  one hot dataplane update.
- Selected WiFi cards can be applied independently.
- One action can set or clear a front proxy for all WiFi cards or only selected
  cards; incompatible direct or unassigned cards are skipped.
- Newly created WiFi uses `wifi reconf`, so its AP, bridge, DHCP and firewall
  state becomes active immediately instead of requiring a reboot.

## Management and stability

- The FastACL status and workspace menu stays fixed while only the content pane
  scrolls, so it cannot cover WiFi controls.
- NPS is available as `System -> JuLiang管理`; legacy routes remain aliases.
- Managed WiFi runtime network and bridge mappings are reconciled when stale.
- fw4 DHCP/DNS chain coverage is checked and reloaded after WiFi hot changes.
- dnsmasq is checked during health recovery and restarted if it is unavailable.
- The custom Argon login migration works with the current template layout,
  retries at boot/package installation, and leaves the username field blank.
- The Argon sidebar brand is always migrated to the two-line
  `JuLiang / 网络服务` card; the build no longer writes the misleading
  `JuLiang 控制面板` intermediate label.

## Monitoring

- Adds CPU usage, memory usage and CPU temperature gauges.
- Draws a smooth two-minute upload/download area chart with a pointer guide and
  tooltip.
- Places wired ports and health gauges on the left, with traffic history on the
  right.
- Keeps the persistent `vnstat2` daily, monthly and total traffic statistics.

## Scope

- This release is the dae/eBPF 2.6.x line and is independent from Live 1.3 and
  FastACL 2.8.x.
- The Redmi AX6000 NMBM 110MiB layout keeps its dedicated build profile.
