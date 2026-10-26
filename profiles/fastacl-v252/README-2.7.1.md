# FastACL V2.7.1

V2.7.1 keeps dae eBPF/TPROXY as the default dataplane and adds an optional
sing-box TUN backend.

## Dataplane selection

- `fastacl252.main.dataplane=ebpf` is the default and preserves the 2.6.4 path.
- `fastacl252.main.dataplane=tun` starts sing-box with a TUN inbound and stops dae.
- Only one dataplane may own TCP/UDP forwarding at a time.
- DNS interception, DNS leak protection, device/WiFi bindings and WAN watchdog remain FastACL-owned.
- Switching dataplane uses the normal guarded apply path and preserves configuration.
- Six consecutive TUN runtime failures automatically restore the last FastACL config with `dataplane=ebpf`.

## TUN backend

- Full tunnel flow is handled by pinned sing-box 1.12.25.
- Supports SOCKS, HTTP, VLESS, VMess, Trojan, Shadowsocks, Hysteria2 and TUIC outbounds.
- Supports SOCKS/HTTP preproxy chains through sing-box `detour`.
- Direct devices remain direct; proxy devices and WiFi networks are routed by source IPv4.
- Smart IP split routes domestic CIDRs directly and other traffic through the selected node.
- Custom direct/proxy/block rules preserve their order.
- Platform priority uses the authenticated FastACL local relay and the existing fake-IP map.
- Node-domain resolution uses FastACL DNS at `127.0.0.1:12553`.
- FastACL owns a dedicated policy route table. Only forwarded LAN/WiFi traffic
  enters TUN; router-generated traffic keeps using the main routing table, so
  SSH, LuCI and NPS management paths are not pulled into the tunnel.
- LAN and managed WiFi connected routes are cloned into the dedicated table
  before the TUN default route is installed.
- `fastacl-tun0` is registered as a main LAN zone device so fw4 preserves
  bidirectional forwarding without masquerading source addresses.
- sing-box interface auto-detection is disabled so direct outbounds cannot
  select the TUN interface and create a routing loop.
- Defaults: interface `fastacl-tun0`, address `172.19.0.1/30`, MTU `9000`, stack `mixed`.

## Safety boundaries

- TUN does not provide hardware/software flow offload.
- TUN and dae must never run as competing default-route owners.
- IPv4 policy is the first release scope; IPv6 general forwarding is not enabled.
- External node and WAN failures remain external faults.
- TUN forwarding is validated on the main LAN bridge; independently managed
  per-WiFi firewall zones still require device-level validation before rollout.
- Redmi AX6000 NMBM 110MiB remains excluded from online firmware updates.
- TUN should be piloted on physical devices before wide deployment, especially 512 MiB MT7981 models.
