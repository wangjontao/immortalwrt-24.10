# 红米 AX6000 / NMBM 110MiB / FastACL 2.7.1

FastACL 2.7.1 keeps the safety and wireless fixes from 2.6.4 and adds the
optional sing-box TUN dataplane described in `README-2.7.1.md`.

The default remains dae eBPF/TPROXY. The NMBM 110MiB target is built with the
same package set so TUN can be selected on devices with sufficient storage and
memory, while online firmware upgrade remains intentionally disabled.
