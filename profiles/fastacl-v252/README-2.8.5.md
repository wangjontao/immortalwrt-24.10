# JuLiang OS v2.8.5

This is the first JuLiang OS release with the independent
`luci-theme-juliang` package.

## Theme

- Removes the Argon theme and Argon configuration application from the image.
- Uses the LuCI 24.10 Bootstrap template contract without depending on the
  Bootstrap theme package at runtime.
- Provides desktop and mobile navigation, a secure login page, LuCI form,
  table, modal, dropdown, alert, and status styling.
- Uses the JuLiang OS v2.8.5 name throughout the visible interface.
- Keeps Bahnschrift-style data typography and the V1.3 dark network-console
  visual language.

## Control center

- Preserves the S20L multi-WiFi workflow: main WiFi/LAN default route, batch
  WiFi creation, SSID route assignment, and single-WiFi per-device routing.
- Keeps the native sing-box dataplane, DNS policy, NPS client, traffic
  monitoring, and timezone synchronization.
- Removes the online-upgrade controls and routes from the Lite edition.
- Excludes iStore, QuickStart, DDNS, UPnP, WOL, NAS and unrelated proxy
  applications from the build profile.
- Uses `nps.jontao.top` as the packaged and runtime NPS endpoint.

## Build targets

- MT7986: S20L, S20P, JDCloud RE-CP-03, and Redmi AX6000 NMBM110M.
- MT7981: all 34 device profiles present in the LEDE Filogic target.

## Factory defaults

- LAN address: `192.168.7.1`
- SSH: port `20022`, user `root`, password `@password@`
- WiFi 2.4G: `JuLiang-OS-2.4G`
- WiFi 5G: `JuLiang-OS-5G`
- WiFi password: `66668888`

The JuLiang theme migrates preserved LuCI settings when their configured
theme path no longer exists, preventing the Bootstrap fallback after upgrade.
