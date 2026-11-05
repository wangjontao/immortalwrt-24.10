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
  monitoring, and online upgrade.
- Excludes iStore, QuickStart, DDNS, UPnP, WOL, NAS and unrelated proxy
  applications from the build profile.

## Validation target

The first compile is for `clx_s20l`. Device-side visual verification is
required before promoting this build to additional MT7981/MT7986 models.
