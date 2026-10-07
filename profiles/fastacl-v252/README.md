# FastACL 2.5.2-dev.1 dae dependency foundation

Target: JuLiangTK S20L / ImmortalWrt 24.10, Linux 6.6, ARM64. Independent from the existing sing-box and Mihomo editions.

Pinned official dae v2.1.1 ARM64 binary package, with SHA256 verification. Runtime dependencies: ip-full, tc-full, sched-core, sched-bpf, veth and certificate bundle; curl and bpftool are included for subscription support and diagnostics. Kernel configuration enables eBPF/JIT, cgroups, BPF stream parser, kprobes/events, ingress/egress and full debug/BTF metadata. OpenWrt's BTF option manages the host build tooling; inspect generated Linux configuration, not just the user-level .config.

Merge `dependencies.config` into the dedicated S20L configuration and call `scripts/integrate-fastacl252-dependencies.sh`. After kernel preparation, run `profiles/fastacl-v252/check-kernel.sh` against its actual .config. Confirm /sys/kernel/btf/vmlinux exists on hardware, then load dae's real eBPF programs and verify LAN bridge/WiFi paths.

The native compiler now generates paired MAC/IPv4 device rules, shared fixed exit groups, front-to-landing chains, identity mismatch blocking and default direct routing without GeoIP downloads. It requires previously validated device configuration and checked native node URIs; raw URI protocol validation and LAN/DHCP validation remain caller responsibilities. Unit fixtures are additionally checked with the pinned ARM64 dae validator under QEMU in CI. Configuration validation does not test eBPF loading or actual packets.

This stage does not enable a dae service or replace the current proxy. Console integration, subscription URI conversion, the encrypted DNS relay, complete fail-closed guards and real eBPF/hardware tests remain unfinished. DNS port 53 is explicitly excluded from dae interception so it can be redirected to the encrypted local relay. Private DNS currently rejects compilation rather than silently using direct DNS: dae's native DNS selectors do not provide device source-IP/MAC routing. Do not run two transparent proxy backends simultaneously.

Upstream source and license: https://github.com/daeuniverse/dae/tree/v2.1.1 (AGPL-3.0). Official kernel requirements: https://github.com/daeuniverse/dae/blob/v2.1.1/docs/en/README.md
