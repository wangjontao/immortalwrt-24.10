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

管理地址：http://192.168.9.1；用户名 root；密码 password。首次通过有线连接配置无线与订阅。

预装 luci-app-nps 与 npc。每次开机读取 WAN 接口 MAC，去冒号并转换为大写后写入 vkey；服务器 47.83.9.208:8024/TCP，压缩和加密均启用。服务端需配置对应 vkey。

编译前在 QEMU ARM64 下检查三个核心版本、Sing-box 与 Mihomo 的 AnyTLS 配置，并检查 SSR Plus+ 实际生成的 AnyTLS 配置能通过 Xray 校验。构建后检查固件清单与 FIT 格式。
这些是软件校验，并不替代实机刷机、射频或真实节点联通测试。

下载包包含 sysupgrade.itb、插件清单、编译配置、版本锁定文件和 SHA256SUMS。
