# FastACL 2.8.0

FastACL 2.8.0 是独立的 sing-box 内核版本，不包含 dae 数据面，也不依赖 dae 配置生成、探针或运行进程。

## 数据面

- `sing-box TPROXY`：默认正式模式。nft 只标记代理设备和代理 WiFi，流量进入 sing-box TCP/UDP TPROXY 入站；国内直连、UDP、DNS 防泄漏和硬件转发路径保持独立。
- `sing-box TUN`：可选正式模式。使用同一套 sing-box 策略、DNS helper 和节点配置，建立隔离的 TUN 路由表。
- 两种模式可以在 LuCI 中直接切换。切换失败只回滚当前模式，不会自动降级到另一模式。

## 保留能力

- 节点、前置链、订阅和出口检测。
- 设备与 WiFi 分流、平台优先、smart/custom IP 规则。
- 代理 DNS 与国内 DNS 分离、域名/IP 拦截、DNS 防泄漏。
- 受管 WiFi 为纯 IPv4 网络，DNS helper 对 AAAA 返回 NODATA，避免手机优先选择不可达的 IPv6 地址。
- 固定入口映射、来源身份防绕过、NPS、在线升级和健康恢复。
- TCP 与 UDP 代理。

## 2.8.0 清核

- 删除 `fastacl252_dae.lua` 和 dae 正式依赖。
- 节点导入校验直接使用 `sing-box check`。
- 运行配置由 sing-box 编译器生成，DNS helper 使用独立的 `fastacl252_relay.lua` 策略映射。
- 正式运行脚本不再包含 `dae run`、`dae validate`、`dae reload` 或 `router.next.dae`。

2.7.1 分支继续保留，用于旧版本回滚；2.8.0 与它分开构建和发布。
