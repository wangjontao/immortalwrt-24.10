# AX3000T / ImmortalWrt 24.10 / ubootmod 三插件版

仅适用于小米 AX3000T 的 OpenWrt ubootmod 启动布局。主刷机文件为 sysupgrade.itb；不能用于原厂或其他不兼容 U-Boot 布局。保留现有 U-Boot，不刷写 preloader/FIP。

基线：ImmortalWrt openwrt-24.10 分支 817ba5c0958c64fad5d067c330678892b90e716c（2026-10-23）。所有软件源提交固定在 sources.lock.json。

| 组件 | 固定版本 |
|---|---|
| Passwall | 26.10.22-2 |
| Sing-box | 1.14.4 |
| SSR Plus+ | 198-2 / v198.2 |
| Xray（SSR Plus+ AnyTLS） | 26.10.21 |
| OpenClash | 0.48.002 |
| Mihomo / Meta | 1.19.33 |

内核程序使用官方 ARM64 静态发行文件及 SHA256 校验。OpenClash 的 Meta 核心已内置到 /etc/openclash/core/clash_meta，无需首次另行下载核心。

三个插件默认均不启用，自行添加节点或订阅后，选择其中一个透明代理插件运行。不要同时开启三个插件接管流量。这里不含 FastACL／dae。

默认采用 ImmortalWrt 标准 LAN 和登录设置；首次通过有线连接配置管理密码、无线与订阅。没有预置代理节点或共享管理密码。

编译前在 QEMU ARM64 下检查三个核心版本、Sing-box 与 Mihomo 的 AnyTLS 配置，并检查 SSR Plus+ 实际生成的 AnyTLS 配置能通过 Xray 校验。构建后检查固件清单与 FIT 格式。
这些是软件校验，并不替代实机刷机、射频或真实节点联通测试。

下载包包含 sysupgrade.itb、插件清单、编译配置、版本锁定文件和 SHA256SUMS。
