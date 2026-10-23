# 红米 AX6000 / D大 U-Boot / NMBM 110MiB / FastACL 2.5.8 r2

本构建基于已成功编译的 FastACL 2.5.8 r2 源码 `efbf360e92ae7925cdaa37fbdc067fed38052f40`，保留固定入口切换、DNS/分流数据随包安装、附加 WiFi DHCP/DNS 放行等 r2 内容。仅增加红米 NMBM 110MiB 目标接入和对应升级分区修正。

适配提供的 U-Boot 文件：`dhcp-meshkey-mt7986_redmi_ax6000-fip-fixed-parts.bin`，SHA256 `a86672dea750bdd5daa643d386478b82e41de873ac0faedea7b83ae720ca4e3c`。

## 启动布局

- U-Boot 选择 `immortalwrt-110m`，不是 `default` 的内核/根文件系统分区分离布局，也不是 490MiB 扩容布局。
- 启用 NMBM；UBI 分区为 `0x600000 + 0x6e00000`，大小 110MiB。
- UBI 中分别存放 `kernel` 和 `rootfs`，不采用 ubootmod 的 `fit` 卷方案。
- 内核设备树目标 `xiaomi,redmi-router-ax6000`，保留原有网口、MAC 和无线 EEPROM 配置。

## 选择文件

1. `*-squashfs-factory.bin`：首次通过这份 D大 U-Boot 的“固件升级”刷入，内部是 UBI 镜像。
2. `*-squashfs-sysupgrade.bin`：进入相同 NMBM 110MiB 系统后升级，内部是包含内核和根文件系统的 sysupgrade tar；不是将 ITB 改后缀。

这两份固件不适用于此前编译的 raw-NAND SP1 ubootmod 引导，也不适用于 U-Boot 的 default/490MiB 布局。构建任务不刷写设备，不包含 Factory/EEPROM 或引导分区写入操作。

CI 检查源码分区、实际内核设备树、factory UBI 格式、sysupgrade 内容，以及 r2 国内 IP/DNS 数据是否实际装入根文件系统。成功编译不等于已在你的路由器实机启动验证。
