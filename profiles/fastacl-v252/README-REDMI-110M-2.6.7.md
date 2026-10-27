# 红米 AX6000 / D大 U-Boot / NMBM 110MiB / FastACL 2.6.7

本构建在 FastACL 2.6.0 的 Factory 无线身份修复基础上，加入 2.6.7 的持久化 WAN 流量统计、2.8.1 管理界面与主 LAN 默认出口、长期稳定性、DNS 防泄漏、无线默认参数和 WAN 看门狗修正。

完整改动见 `README-2.6.7.md`。

## 启动布局

- U-Boot 选择 `immortalwrt-110m`。
- 启用 NMBM；UBI 分区为 `0x600000 + 0x6e00000`，大小 110MiB。
- UBI 中分别存放 `kernel` 和 `rootfs`，不使用 ubootmod 的 `fit` 卷方案。
- 内核设备树目标 `xiaomi,redmi-router-ax6000`，保留原有网口、MAC 和无线 EEPROM 配置。

## 选择文件

1. `*-squashfs-factory.bin`：首次通过对应 D大 U-Boot 的固件升级功能刷入。
2. `*-squashfs-sysupgrade.bin`：进入相同的 NMBM 110MiB 系统后升级。

这两份固件不适用于 raw-NAND SP1 ubootmod 引导，也不适用于 U-Boot 的 default/490MiB 布局。构建任务不刷写设备，不包含 Factory/EEPROM 或引导分区写入操作。
