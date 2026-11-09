# 客户端兼容与使用边界

## 客户端与导出

| 配置类型 | 客户端 |
| --- | --- |
| 完整配置 | Shadowrocket、Stash、Surge、Loon、QuanX、Clash、sing-box MT、Hiddify、Egern、Clash Mi、Karing |
| 仅节点订阅 | V2Box |
| 前台局域网共享 | 按客户端 User-Agent 自动识别，或手动指定支持格式 |

QuanX 使用系统文件分享；其他目标通过客户端 URL Scheme 导入，无法打开时回退分享。Hiddify 和 sing-box MT 虽然同为 sing-box JSON，身份与协议能力分别处理。无法无损表达的节点会跳过并计数，不会伪装成另一种协议。

**代理集合**默认关闭。开启后，Stash、Clash、Clash Mi、Karing、Surge、Loon、QuanX、Egern 的完整配置可包含原始订阅 URL，由客户端自行更新远端节点。Shadowrocket、Hiddify、V2Box、sing-box MT 保持本地展开。

远端来源必须返回目标兼容的格式；远端节点不受塔台的逐节点勾选、协议筛选、名称追加和自定义 DoH 控制。协议筛选与节点计数只作用于本地输出；摘要另外列出远端来源数。塔台规则或自有节点变化后仍需重新导出。

## Mac 版

**[免费下载 Mac 版](https://github.com/pengchujin/tower/releases/latest)**：打开 DMG，将 Tower 拖入 Applications（应用程序）。支持 macOS 14 及以上，兼容 Apple 芯片与 Intel Mac；应用使用 Developer ID 签名并通过 Apple 公证，无需 TestFlight。暂不提供应用内自动更新，下载新版覆盖安装即可。

工程支持 Mac Catalyst，沿用原来的图标卡片、横向滚动、筛选和排序。`Surge` 保留手机版身份，`Surge Mac` 使用桌面版专用导入入口；新增 `Clash Verge`、`ClashMac`、`FlClash` 和 `Clash Party`（原 Mihomo Party），生成完整 Clash / Mihomo YAML。

Mac 默认顺序为 Shadowrocket、局域网共享、Surge Mac、Clash Verge、ClashMac、FlClash、Clash Party、sing-box MT、Clash，再接其余客户端。手机默认隐藏五个 Mac 专用客户端，可从筛选中手动添加；两端的排序、显示范围和当前客户端分别保存。

Surge Mac 6.7+ 和 Clash Verge 支持一键导入；旧版 Surge Mac 找不到导入入口时复制订阅，ClashMac 同样复制订阅并显示具体导入步骤。FlClash、Clash Party 使用各自的专用导入入口。Mac 局域网共享支持 Wi-Fi 与有线网络，切到其他 App 后继续提供服务，退出塔台或停止共享后失效。本机一键导入仍为 3 分钟的独立临时服务。

构建与验证见 [开发文档](DEVELOPMENT.md)。1.0.9（47）已通过直接分发签名、公证、Gatekeeper 和启动检查；iCloud 签名授权已核对，跨设备同步尚未进行直接分发包专项实测。Mac App Store 尚未正式发布。

## 隐私与网络边界

转换、规则匹配、地区查询在本机完成，没有第三方在线转换或 IP 查询服务。订阅凭据默认留在设备；主动开启 iCloud 后存入自己的 iCloud，主动开启代理集合后原始 URL 随配置交给目标客户端。分享文件也会分享其中的凭据，请只交给可信接收方。

- 本机一键导入使用仅绑定 `127.0.0.1`、3 分钟失效的临时 HTTP 服务，不是长期订阅托管。
- 局域网共享是独立的前台服务，主动开启后允许同一网络的设备凭随机密钥获取配置；关闭或轮换密钥可撤销访问。代理集合开启时，这份配置也可能含原始订阅链接。
- 凭据类快照、配置文件和二维码使用完整文件保护；临时导出文件会清理。
- 内置规则不会在运行时联网更新；只有用户导入或刷新规则时才获取 HTTPS 地址。
- 添加面板请求一次剪贴板读取，仅识别受支持链接；相机与本地网络按使用场景请求权限。

详见[隐私政策](privacy.md)及[使用与支持](support.md)。

## 规则与已知边界

### QuanX 的手动策略组会记住上次的选择

QuanX 的 `static` 策略组按名字记住用户上次选中的项，重新导入配置不会回到第一项。用户反馈「🚀 节点选择」默认是 DIRECT 时，先核对导出文件：塔台写的第一项是「♻️ 自动选择」。确认无误后，让用户在 QuanX 里手动选一次，之后重新导入会保持住（2026-09-29 真机确认）。

### mihomo 系的 DNS

- 标准保护：fake-ip；`proxy-server-nameserver` 用国内 DoH，不写 `fallback` / `fallback-filter`。走代理的域名不在本机解析。
  - 支持 `#代理组` 的 mihomo 客户端：`nameserver` 经纯节点组、带中国子网查询远程 DNS，`direct-nameserver` 用国内 DoH。MATCH 前最后一条 `GEOIP` 不带 `no-resolve`，列表外的国内网站因此能直连。
  - 其他 Clash 格式客户端：`nameserver` 用国内 DoH，GEOIP 保留 `no-resolve`。
- 严格保护（Clash / Clash Mi / Verge / Mac / FlClash / Clash Party）：`nameserver` 改为远程列表中支持 ECS 的服务器，写成 `…#<纯节点组>&ecs=114.114.114.0/24&ecs-override=true`。`proxy-server-nameserver` 仍用国内 DoH，另加 TUN、`dns-hijack` 和 `strict-route`。Karing、Stash 和 Shadowrocket 的 Clash 格式没有文档说明支持该后缀，所以按标准保护写。「Clash」App 有自己的文档 [clash.md](https://clash.md/guide/config/dns)，内核是 mihomo 1.19.33 衍生版，配置按原样运行（只替换 system/dhcp 来源），2026-11-09 起与其他 mihomo 客户端相同；它的 `tun.stack` 从 iOS 1.0.14 起不生效。
- 跟随方案：不开 fake-ip，客户端会先在本机解析每个域名。
- 依据：[mihomo DNS](https://wiki.metacubex.one/config/dns/)（`#代理组`、`&ecs=`、`ecs-override`、`proxy-server-nameserver`）。

### sing-box MT 的模式与 DNS

重新导出的完整配置提供「规则判定 / 全局代理 / 直接连接」，默认「规则判定」，客户端可记住之后的选择。一份配置内切换，文件名保持塔台或用户自定义名称。规则判定沿用原方案；全局代理指向独立同名 selector，默认自动选择全部可用节点，也可手动选具体节点；此模式的 DNS 复制原解析器设置并跟随该 selector。直接连接的流量和 DNS 直连。不增加含 DIRECT 的全局候选；没有节点时全局代理拒绝连接。组名冲突使用数字后缀，保留用户原策略组。Hiddify 保持独立适配。

- 标准保护：按本机缓存的域名规则顺序选择 DNS。仅 DIRECT 或成员全部直连的策略组使用直连加密 DNS，混合策略组和其他域名使用代理 DNS；IP 规则不用于推测 DNS 分流。DNS 接管先于模式规则。
- 代理 DNS 使用「远程 DNS（经代理）」列表，不再复用国内列表。ECS 提示用 1.14 的 `evaluate` + `match_response` + `respond` 写法，所以官方 sing-box 目标需要 1.14 及以上。标准和严格保护下，未列出的域名会先经代理向支持 ECS 的远程 DNS 带中国子网查询，结果是国内地址才采用（`remote-cn`）。
- 严格保护：规则判定模式的普通 DNS 统一经代理，直连列表的域名也经 `remote-cn` 带中国子网查询；代理失败不回退直连。主动切换直接连接后使用直连 DNS。
- 跟随方案：保留方案解析器，仍处理隧道自身 DNS，不额外强制接管所有 53 端口流量或启用严格路由。
- 节点地址和解析器地址的启动解析独立于代理，防止循环依赖。自定义加密解析器使用域名时，允许配置的 bootstrap DNS 解析该解析器域名；规则文件下载也有独立的域名解析。

使用当前 typed DNS 格式。这里的标准保护使用真实 DNS 与 reverse mapping，不强制 Fake-IP。`strict_route` 在 Apple NetworkExtension 客户端中并未实现，不能视为系统级防泄露保证；应用内自带 DoH、系统绕过隧道等情况仍取决于客户端和系统设置。官方依据：[模式规则](https://sing-box.sagernet.org/configuration/experimental/clash-api/)、[DNS 规则](https://sing-box.sagernet.org/configuration/dns/rule/)、[Apple 平台限制](https://sing-box.sagernet.org/clients/apple/features/)。

自定义规则在本机生成，不即时编译 MRS/SRS。内置 ACL4SSR 的已验证二进制可供兼容客户端引用：Stash / Clash / Clash Mi 使用 MRS，sing-box MT 使用 SRS；其他目标沿用兼容文本或内联。内容与编译源不一致时回退，不复用旧二进制覆盖新规则。发布流程固定源版本、哈希和不可变产物 URL。

SS 插件支持 simple-obfs、WebSocket 模式 v2ray-plugin，以及下述 ShadowTLS 组合；WireGuard 多 Peer 不做有损压缩；Snell 等协议按各目标能力判断。Surge 输入目前仅解析 `[Proxy]` 中的 SS 行，其他行计入跳过。客户端是否接收分享、重复导入是否覆盖，由客户端决定，不能由生成成功推断连通。


### Shadowsocks + ShadowTLS

导入支持 SIP003 `ss://…?plugin=shadow-tls;…`、Clash YAML 的 `plugin-opts`（行内及缩进格式），以及 Surge SS 行中的 `shadow-tls-*` 字段。ShadowTLS 的版本、SNI、密码独立保存；不会覆盖 SS 密码。支持保存重载、iCloud 数据序列化、节点分享及刷新身份匹配。当前要求显式版本与 SNI；未知参数或缺失必要字段的节点拒绝导入并计入跳过。

| 导出目标 | 当前实现 |
| --- | --- |
| Stash | ShadowTLS v2/v3，保留 `plugin: shadow-tls` 与独立参数 |
| Clash、Clash Verge、ClashMac、FlClash、Clash Party、Clash Mi | Mihomo 格式，ShadowTLS v1/v2/v3 |
| Karing | 暂不支持：用户真机反馈无法连接，已撤回实验性导出；完整配置及仅节点均跳过 ShadowTLS |
| Surge / Surge Mac | ShadowTLS v2/v3；SS2022 限 AES-128/256，独立 `shadow-tls-*` 参数 |
| sing-box MT / Hiddify 完整配置 | SS outbound 经内部 ShadowTLS outbound 的 detour；辅助通道不进入策略组 |
| Loon | ShadowTLS v2/v3，完整配置和仅节点均保留独立密码、SNI、版本 |
| Shadowrocket | ShadowTLS v3；完整配置和包含 ShadowTLS 的仅节点订阅均使用 YAML plugin/plugin-opts |
| Egern | ShadowTLS v3，完整配置使用独立 shadow_tls 对象；不将 v1/v2 冒充 v3 |
| Hiddify 仅节点 | 包含 ShadowTLS 时使用仅含 outbounds 的 JSON，以 §hide§ 隐藏辅助通道；普通列表沿用 URI |
| 其他目标 | 未验证表达方式，明确跳过，不降级为普通 SS |

ShadowTLS 包装 TCP，不意味着支持 UDP。Mihomo、Stash、Surge 保留来源声明的普通 SS UDP 参数；sing-box detour 当前仅输出 TCP，源明确要求 UDP 的此类节点跳过。本轮不新增 UDP-over-TCP，来源显式启用该模式时拒绝导入。自定义 TLS 指纹与跳过证书校验仅在对应导出能保真时保留，否则跳过。已有证书 pin、复合传输等无法完整表达的组合仍跳过。

依据：[Mihomo SS 插件](https://wiki.metacubex.one/en/config/proxies/ss/)、[Stash 协议说明](https://stash.wiki/en/proxy-protocols/proxy-types)、[Surge ShadowTLS](https://manual.nssurge.com/policies/tls.html)、[Surge SS2022](https://manual.nssurge.com/policies/shadowsocks.html)、[sing-box ShadowTLS](https://sing-box.sagernet.org/configuration/outbound/shadowtls/)。客户端实际接收和连通仍需按版本验收，不能将内核检查等同于每个客户端真机验证。


ShadowTLS 补充适配依据（2026-09-17）：[Loon 官方节点格式](https://nsloon.app/en/docs/Node/)、[Egern 官方代理格式](https://egernapp.com/docs/configuration/proxies/)，并对照 [Sub-Store Loon producer](https://github.com/sub-store-org/Sub-Store/blob/07d94ef9e1970e98787dd0ab40dc3d454b06a5ba/backend/src/core/proxy-utils/producers/loon.js) 和 [Egern producer](https://github.com/sub-store-org/Sub-Store/blob/07d94ef9e1970e98787dd0ab40dc3d454b06a5ba/backend/src/core/proxy-utils/producers/egern.js)。独立实现字段映射，不引入转换器代码或联网转换服务。Loon 的 ShadowTLS 密码使用裸字段，不能套用 Surge 的百分号编码；无法安全表达的分隔符、空白和控制字符组合跳过。两种新目标暂不支持显式 TLS 指纹或跳过 ShadowTLS 证书校验，避免静默丢参数。普通 SS UDP 开关保留，未宣称 UDP 连通已验收。

Sub-Store 该版本还提供 Surge、ClashMeta/Mihomo、sing-box、Shadowrocket 的 ShadowTLS 处理；是否生成并不代表每种客户端均已连通。原版 [tindy2013/subconverter](https://github.com/tindy2013/subconverter/tree/a0d4eab28cb8b6c782d4ce5c3a918de4829b4a72) 的 src 全文未找到 shadow-tls/shadowtls 处理，不能用其旧版通用 SS 支持推断 ShadowTLS 支持。该结论不涵盖社区 fork。


Shadowrocket 补充（2026-09-17）：[官方 2.2.38 更新记录](https://t.me/s/ShadowrocketNews?before=484)明确包含 v3 解析与读取修复；[Sub-Store Shadowrocket producer](https://github.com/sub-store-org/Sub-Store/blob/07d94ef9e1970e98787dd0ab40dc3d454b06a5ba/backend/src/core/proxy-utils/producers/shadowrocket.js) 对 SS 保留 shadow-tls 插件结构。塔台据此开放完整 YAML 的 v3 基础组合，保留两层密码、SNI、版本及普通 UDP 开关；显式 TLS 指纹、跳过证书校验、v1/v2 等组合仍不扩大放行。仅节点 URI 是另一条导入路径，继续跳过并提示使用完整配置。用户已确认 Loon/Egern 手机连接可用；Shadowrocket 新输出需重新真机验收。

ShadowTLS 仅节点补充（2026-09-18）：不直接开放未经证实的 SIP003 插件 URI。Shadowrocket 采用 [Sub-Store 的节点列表输出](https://github.com/sub-store-org/Sub-Store/blob/07d94ef9e1970e98787dd0ab40dc3d454b06a5ba/backend/src/core/proxy-utils/producers/shadowrocket.js) 对应的 proxies-only YAML。Hiddify 根据 [JSON 订阅解析入口](https://github.com/hiddify/hiddify-core/blob/db74dfc/v2/config/parser.go) 接收 outbounds-only JSON，使用 [selector 构建逻辑](https://github.com/hiddify/hiddify-core/blob/db74dfc/v2/config/builder.go) 的 §hide§ 标记隐藏 ShadowTLS 辅助通道。两者都不附带塔台的规则或策略组；混合订阅中的普通节点保留，无 ShadowTLS 的列表保持原格式。沿用版本、TLS 参数和 TCP/UDP 能力限制。手机上的实际订阅导入及连接仍待用户验收。

Karing 验收结论（2026-09-18）：官方示例虽有 ShadowTLS 字段，但用户真机测试无法连接，因此撤回实验性导出。文档示例及生成测试不等于客户端连通验证。根因未定位，暂不重新开放；其他客户端能力不受影响。

### 上游更新对照修正（2026-11-09，未发布）

依据 `Scripts/check_upstream_updates.py` 抓到的各客户端 2026-09 以来的更新说明，逐条对照代码：

- 「Clash」App 严格 / 标准保护、Egern SSR、Loon 通配与 `tls-profile` 已于 2026-11-09 真机验收通过。
- **sing-box MT 暂停 MASQUE**：`masque-client` endpoint 要 sing-box 1.15，App Store 的 sing-box MT 仍是 1.14，遇到未知 endpoint 会整份配置加载失败。现在跳过并计数，等 MT 用上 1.15 稳定版再打开（`ClientTarget.singBoxSupportsMASQUE`）。
- **Loon `tls-profile`**：只写官方列出的值，`chrome` 原样，`safari` / `ios` 写成 `safari-ios18`，Firefox、Edge 等不写（用 Loon 默认）。
- **Loon `DOMAIN-WILDCARD`**（3.5.3，build 1008+）：`*.x` 仍改写成「后缀 x 且不是 x」的逻辑规则，旧版 Loon 也能读；其他 `*` / `?` 通配原样写 `DOMAIN-WILDCARD`，不再丢弃。
- **Snell v6 `mode`**：Surge 手册要求和服务端一致。塔台不保存 mode，`default`（或不写）照常导入；`unshaped`、`unsafe-raw` 拒绝导入并计入跳过数。
- **VLESS XHTTP 的额外设置**：分享链接里非空的 `extra`、Clash YAML `xhttp-opts` 里 path / host / mode / Host 头以外的字段（`download-settings`、`xmux`、填充等）表达不了，拒绝导入并计数。
- **Egern SSR**（2.21.0）：按 Sub-Store Egern producer 写 `type: shadowsocksr`、`method` / `protocol` / `protocol_param` / `obfs` / `obfs_param`。只放行流加密和它列出的协议 / 混淆插件，其余跳过。Egern 官方文档还没写 SSR。

### SSH 与 TrustTunnel（未发布）

这两种协议没有分享链接格式，只能从 Clash YAML 导入（`type: ssh` / `trusttunnel`），或者手动添加。无法表达的组合会跳过并计数。详见 [HANDOFF](HANDOFF.md#未发布新增-ssh-与-trusttunnel2026-09-28)。

| 导出目标 | SSH | TrustTunnel |
| --- | --- | --- |
| Surge / Surge Mac | 只导出密码登录，可固定服务器公钥；带私钥的跳过 | HTTP/2、HTTP/3 |
| Stash | 导出；带服务器公钥的跳过 | 只导出 HTTP/3，HTTP/2 实测超时 |
| Clash 系、Clash Mi | 导出 | 导出 |
| Shadowrocket | 只导出密码登录；带私钥的跳过，实测会在认证前断开 | 导出 |
| Egern | 导出；带私钥口令的跳过 | 跳过 |
| sing-box MT、Hiddify、Karing | 导出 | 跳过 |
| Loon、QuanX | 跳过 | 跳过 |

### Tailscale 内网（未发布）

只写进完整配置，不是节点，不进任何策略组。支持 Surge、Stash、Clash 系（mihomo）和 sing-box MT；Shadowrocket、Loon、QuanX、Egern、Hiddify、Karing 跳过并提示。Auth Key 只存本机钥匙串，会写给 Stash、mihomo 和 sing-box，永远不写给 Surge（Surge 在自己的策略编辑页里登录）。各客户端写法见 [TAILSCALE](TAILSCALE.md)。
