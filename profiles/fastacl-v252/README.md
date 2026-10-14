# FastACL 2.5.2-dev.2 dae development

Independent JuLiangTK S20L / ImmortalWrt 24.10 edition pinned to dae v2.1.1. The main WiFi keeps device-level MAC + fixed-IP routing. Optional managed WiFi networks can be created on demand (up to +14 5GHz and +8 2.4GHz), each with its own 172.16.x.0/24, DHCP, AP isolation, proxy binding and DNS policy. No extra WiFi is created by default.

The LuCI UI includes a responsive JuLiang control center, device routing, multi-WiFi management, node import/subscriptions and DNS provider selection. Direct DNS choices include Baidu, AliDNS and Tencent DNSPod; proxy DNS choices include Cloudflare, Google, Cisco OpenDNS and Quad9. Devices and managed WiFi can override the global resolver with a supported provider or custom DNS. Proxy-side custom DNS must use DoH and follows the assigned proxy exit to avoid direct DNS leakage.

Manual import accepts SOCKS5/SK5/HTTP/HTTPS/VLESS/VMess/Trojan/SS/Hysteria2/TUIC and common host:port:user:pass lines. Subscription formats include HTTPS link lists, Base64, Clash YAML and sing-box JSON. Bound subscription nodes are retained when removed upstream.

The firmware excludes iStore, QuickStart, PassWall, PassWall2, HomeProxy and OpenClash. NPS points to nps.jontao.top:8024 and derives its VKey from the uppercase physical WAN MAC. Restricted LuCI operator access is included; SSH remains on port 20022.

Validation gates cover Lua syntax, import/subscription regressions, Go race tests, dae configuration validation, real eBPF routing/fail-close tests and responsive browser interactions. Firmware builds start only after validation succeeds. These cloud tests do not replace a real S20L cold boot, WiFi radio test and mobile-device routing test.

Official dae source: https://github.com/daeuniverse/dae/tree/v2.1.1 (AGPL-3.0).
