# JuLiangTK S20L FastACL 2.5.1-dev.1 Mihomo edition

Development firmware for ImmortalWrt 24.10 / CLX S20L. Hardware compatible strings and flash partitions are preserved. This is a distinct edition from FastACL 2.5.0 (sing-box), with its own `fastacl251` UCI configuration and console.

One LAN/WiFi, MAC plus DHCP-reserved IPv4 device assignment; direct or selected SOCKS5 / HTTP / VLESS / VMess / Trojan / Shadowsocks / Hysteria2 / TUIC exit. SOCKS5 and HTTP landing nodes support a selected front proxy. No WiFi assignment or batch WiFi creation. No PassWall, HomeProxy or OpenClash. Existing iStore, QuickStart, Argon, NPS and other source-profile software is preserved.

Mihomo 1.19.32 is pinned to the official ARM64 release SHA256. FastACL owns routing and builds only source-IP rules, with no geodata downloads or external dashboard. Native subscriptions are parsed locally into the controlled node database; airport-supplied routing/DNS/controller settings are never applied. HTTPS manual/periodic updates preserve stable node identities and retain disappeared nodes that still have device bindings.

Default DNS is direct verified Ali DoH. Advanced privacy uses verified Quad9 DoH through the device's assigned exit. A single shared `fastacl251-dns` process handles both UDP/TCP DNS, with loopback SOCKS listeners in Mihomo for each distinct exit. Cache keys include exit identity; 256 bounded entries (at most 8 KiB each), record TTL ageing, 64 upstream requests maximum. Failure returns SERVFAIL and never falls back to plaintext DNS or direct for a private device. Mihomo endpoint bootstrap uses the loopback relay and the relay dials pinned DoH IPs with certificate verification against the configured hostname.

IPv4 TCP/UDP uses nftables TPROXY. DNS port 53 redirects to the relay; bound proxy MAC/IP mismatch is blocked; forwarded traffic from proxy devices stays blocked when either service fails. Proxy-device external IPv6 is blocked in this first development version. Client-controlled DoH remains ordinary application traffic through the device route. Flow offload is disabled to avoid policy bypass.

Validation gate: actual Lua compiler/parser/subscription regressions, pinned core config checks, Go race tests for DNS exit/cache/failure/SOCKS transport, isolated Linux packet tests using actual Mihomo with two exits on one LAN, and browser interactions. Hardware verification remains required before calling this stable.

Build: `scripts/integrate-fastacl251-s20l.sh` with Go 1.24, then the standard OpenWrt build. The integration cross-compiles the standard-library-only DNS relay to static ARM64. Workflow `.github/workflows/JuLiangTK-S20L-FastACL251.yml` publishes development prereleases only after validation and firmware manifest checks.

Default LAN 192.168.7.1/24, SSH 20022; hostname JuLiangTK-S20L; primary WiFi SSID JuLiangTK, password a1111111, 2.4 GHz channel 9 / 5 GHz channel 48. Device/private-MAC changes require a new binding. Firmware upgrades should not mix old proxy service configurations without migration.
