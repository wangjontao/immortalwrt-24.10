# FastACL 2.5.2-dev.1 dae dependency foundation

Target: JuLiangTK S20L / ImmortalWrt 24.10, Linux 6.6, ARM64. Independent from the existing sing-box and Mihomo editions.

Pinned official dae v2.1.1 ARM64 binary package, with SHA256 verification. Runtime dependencies: ip-full, tc-full, sched-core, sched-bpf, veth and certificate bundle; curl and bpftool are included for subscription support and diagnostics. Kernel configuration enables eBPF/JIT, cgroups, BPF stream parser, kprobes/events, ingress/egress and full debug/BTF metadata. OpenWrt's BTF option manages the host build tooling; inspect generated Linux configuration, not just the user-level .config.

Merge `dependencies.config` into the dedicated S20L configuration and call `scripts/integrate-fastacl252-dependencies.sh`. After kernel preparation, run `profiles/fastacl-v252/check-kernel.sh` against its actual .config. Confirm /sys/kernel/btf/vmlinux exists on hardware, then load dae's real eBPF programs and verify LAN bridge/WiFi paths.

This commit adds prerequisites only. It does not install an enabled dae service, replace the current proxy, or claim that the FastACL 2.5.2 console/routing/DNS backend is finished. Source-IP/MAC device assignments, subscription lifecycle, per-device encrypted DNS, fail-closed protection and hardware tests remain the next development stage. Do not run two transparent proxy backends simultaneously.

Upstream source and license: https://github.com/daeuniverse/dae/tree/v2.1.1 (AGPL-3.0). Official kernel requirements: https://github.com/daeuniverse/dae/blob/v2.1.1/docs/en/README.md
