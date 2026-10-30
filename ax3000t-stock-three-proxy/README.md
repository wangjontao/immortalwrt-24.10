# JuLiang OS / Xiaomi AX3000T traditional U-Boot

适用于小米 AX3000T 的 **112 MiB 大分区传统 U-Boot 布局**。构建输出
`xiaomi_mi-router-ax3000t` 的 `squashfs-sysupgrade.bin` 和
`initramfs-factory.ubi`。factory UBI 用于传统 U-Boot 首次引导安装，完成后再
使用 sysupgrade 固件升级。该产物不能用于 OpenWrt U-Boot 布局或小分区原厂布局。
构建保留 AX3000T 的 DTS、分区和刷机兼容标识，仅替换系统显示名称。

基线为 ImmortalWrt `openwrt-24.10` 提交
`817ba5c0958c64fad5d067c330678892b90e716c`。所有外部源码均由
`sources.lock.json` 与 `cores.lock.json` 固定。

| 组件 | 固定版本 |
|---|---|
| 系统显示名 | JuLiang OS |
| PassWall 2 | 26.10.20-1 |
| GeoView | 0.1.10 |
| Sing-box | 1.14.4 |
| SSR Plus+ | 198-2 / v198.2 |
| Xray | 26.10.21 |
| Mihomo / Meta | 1.19.33 |
| OpenClash | 0.48.002 |
| LuCI 主题 | Argon |

PassWall 2、GeoView、V2Ray GeoIP/GeoSite 数据均已编入固件；旧的 PassWall 1
不再安装。SSR Plus+ 的 AnyTLS 继续由 Sing-box 承载。三个代理插件第一次启动时
均不接管流量，添加节点后只启用其中一个。

## 默认设置

- 管理地址：`http://192.168.9.1`
- 根账户：`root` / `password`
- 超级管理员：`jontao` / `jontao`（LuCI 完整 ACL）
- 2.4G：`JuLiang-2.4G`
- 5G：`JuLiang-5G`
- 无线密码：`66668888`
- 加密方式：WPA2-PSK / CCMP
- 默认主题：Argon
- 首页：`JuLiang Live`

登录页使用 JuLiang 网络服务卡片布局和本地风景背景，不加载外部资源。

`JuLiang Live` 是登录后的第一个 LuCI 页面，显示 WAN、系统负载、内存、无线数量、
物理网口和最近两分钟实时流量，并提供无线、PassWall 2 和重启入口。实时数据由本机
LuCI 接口读取，不加载外部资源。

预装 `luci-app-nps` 与 `npc`。每次开机读取 WAN MAC，去掉冒号并转成大写后写入
vkey；服务器为 `47.83.9.208:8024/TCP`。服务端需要配置对应 vkey。

构建前会在 QEMU ARM64 下校验 Sing-box、Xray 和 Mihomo，并验证 SSR Plus+
实际使用的 AnyTLS 生成器。构建后检查固件清单、JuLiang Live 文件、默认配置和
FIT 格式。软件校验不能替代实机刷机、射频与真实节点联通测试。

下载包包含 AX3000T 传统 U-Boot factory/sysupgrade 固件、插件清单、编译配置、
锁定文件和 `SHA256SUMS`。

登录背景照片：Sebastian Unrau / Unsplash。
