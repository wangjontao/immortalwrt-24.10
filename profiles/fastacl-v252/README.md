# FastACL 2.5.2-dev.1 dae development

Independent S20L / ImmortalWrt 24.10 edition pinned to dae v2.1.1. DNS relay and console use the separate fastacl252 configuration. Direct encrypted DNS is the default. Advanced privacy DNS follows the same native proxy chain as the assigned device and fails with SERVFAIL instead of falling back to direct DNS. Native links list the landing before the front; actual traversal is front then landing.

Validation gates include Lua parsing, importer and subscription tests, Go race and real two-endpoint chain tests, browser interactions, and actual dae eBPF network-namespace traffic. Tests verify distinct device exits, direct devices, IP/MAC mismatch blocking, IPv6 protection and core-failure blocking. Firmware builds depend on all validation jobs succeeding. These cloud tests do not replace an S20L cold-boot and WiFi hardware test. Do not run multiple transparent proxy engines simultaneously.

Official upstream source: https://github.com/daeuniverse/dae/tree/v2.1.1 (AGPL-3.0).
