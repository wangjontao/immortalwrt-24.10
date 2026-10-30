# Xiaomi AX3000T 112 MiB U-Boot

This U-Boot is built for the JuLiang OS single-UBI layout used by the
`xiaomi_mi-router-ax3000t-112m` image target.

- UBI start: `0x00600000`
- UBI size: `0x07000000` (112 MiB)
- Default layout: `112m(ubi)`
- Recovery address: `http://192.168.1.1/`
- Recovery entry: hold `mesh` or `reset` while powering on
- Automatic recovery: if the firmware cannot boot, U-Boot starts Web failsafe

The `stock` split layout remains available in the U-Boot web interface for
compatibility. Do not flash this single-UBI factory image while the `stock`
layout is selected.

## Installation safety

1. Back up all NAND partitions from the current U-Boot Web interface.
2. Update BL2 with `mt7981_ax3000t-bl2.bin`.
3. Update U-Boot with
   `mt7981_ax3000t-fip-fixed-parts-multi-layout.bin`.
4. Power off, hold `mesh` or `reset`, then power on and open
   `http://192.168.1.1/`.
5. Flash the matching `*-112m-initramfs-factory.ubi` as a factory image.
6. Boot JuLiang OS and use its system upgrade page for later
   `*-112m-squashfs-sysupgrade.bin` updates.

Keep a serial console and a full-flash backup available. Partition and image
format checks confirm that this U-Boot and firmware pair is compatible, but
an actual boot test on the target router is still required.

Run `verify-pair.sh UBOOT_DIR FACTORY.ubi SYSUPGRADE.bin` to repeat the
partition, FIT, DTB, recovery-string, and checksum checks.
