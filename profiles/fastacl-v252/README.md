# FastACL 2.8.1

FastACL 2.8.1 is the native sing-box branch. It does not use dae as a dataplane,
configuration compiler, node validator, probe, or runtime dependency.

- `sing-box TPROXY` is the default mode and uses an isolated IPv4 nft table,
  fwmark policy routing, and TCP/UDP TPROXY inbounds.
- `sing-box TUN` is an optional production mode using the same sing-box policy,
  DNS helper, nodes, chains, and device/WiFi rules.
- The two modes can be switched without falling back to another core.
- Device and WiFi assignment, smart/custom routing, platform priority, DNS
  splitting and blocking, subscriptions, UDP, chains, health recovery, NPS,
  and online upgrade remain available.

The DNS helper uses `fastacl252_relay.lua` for resolver and slot policy.
Imported nodes are validated directly by `sing-box check`.

See `README-2.8.1.md` for the release summary. The `2.8.0` branch remains the
rollback branch.
