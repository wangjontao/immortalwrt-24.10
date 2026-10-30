# FastACL 3.0

FastACL 3.0 is the JuLiang OS X86 VLAN gateway release.

## Network layout

- `eth0`: WAN, DHCP by default.
- `eth1`: untagged management LAN plus tagged VLAN trunk to the AP.
- Management address: `192.168.7.1/24`.
- SSH: port `20022`.
- Web login: user `admin`, password `@password@`.

The AP must use bridge/AP mode with DHCP and NAT disabled. Keep the AP
management address on the untagged management VLAN, then map each SSID to a
tagged VLAN created by the FastACL VLAN page.

## One-click VLAN provisioning

Open `VLAN 分流` in LuCI. The batch form creates:

- the 802.1Q device and static interface;
- the gateway subnet and DHCP scope;
- the firewall zone and forwarding rules;
- the FastACL VLAN exit policy;
- the VLAN/SSID mapping shown for AP configuration.

By default VLAN 10 uses `192.168.10.0/24`, VLAN 11 uses
`192.168.11.0/24`, and so on. Up to 32 VLANs can be created in one operation.

## Per-device binding

The main FastACL console exposes a fixed IP, VLAN, node, DNS and split-policy
selector for each client. A bound proxy client is enforced by the MAC + IPv4
pair on every managed VLAN interface.

## Image outputs

The build produces both BIOS and UEFI combined images plus an EFI ISO. Prefer
the EFI image on J1900 boards configured for UEFI boot.
