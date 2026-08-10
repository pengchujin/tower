# 塔台开发交接（2026-08-07）

## 1. 当前结论

塔台已完成可运行的原生 SwiftUI 主流程：导入订阅/自有节点、节点解析和地区识别、自绘点阵世界地图、ICMP/端口测速、内置与手动下载规则、七种客户端配置生成、配置预览及导入/分享。

当前代码版本为 `1.0 (3)`，Bundle ID 为 `com.jzb.tower`，已归档并上传到 TestFlight。归档在开发者本机完成；分发签名和上传走 Xcode Organizer，因为 SSH 会话拿不到钥匙串私钥（见 §4）。

这个仓库快照的重点不是继续堆功能，而是做一次真机回归、补齐 TestFlight 元数据和修正仍可复现的性能/兼容问题。

## 1.1 2026-08-04 代码审查修复

一次完整代码审查后修掉了下列问题，全部带回归测试（`ConfigurationCredentialTests`、`ImportHardeningTests`）。

### 配置生成

| 问题 | 影响 | 修复 |
| --- | --- | --- |
| Loon SOCKS5 无凭据时输出 `Socks5,host,port,,` | 无认证 SOCKS5 节点在 Loon 中不可用 | 用户名/密码成对输出或整体省略 |
| Surge/Shadowrocket 位置参数把密码写进用户名位 | 有密码无用户名的 SOCKS5/HTTP 认证失败 | 缺用户名时补空位，保持字段对齐 |
| QuanX 丢弃 Trojan/Hysteria 2 的 `skip-cert-verify` | 自签证书节点只在 QuanX 握手失败 | 两种协议补 `tls-verification=false` |
| QuanX 写死 VMess `method=chacha20-poly1305` | 忽略节点实际加密方式 | 按节点 cipher 输出，`auto` 回退到受支持值 |
| QuanX 丢弃 SSR `protocol-param` / `obfs-param` | SSR 节点参数不全 | 补 `ssr-protocol-param` 和 `obfs-host` |
| 节点名中的换行、`#`、`;` 直接进入配置 | 机场 remark 可截断或注释掉后续配置 | `confName` 统一折行并转义；Clash 的 `yaml()` 同步折行；QuanX 的 tag 和策略成员改用 `confName` |
| 非 QuanX 目标不校验规则类型 | 未来快照引入新类型会静默产出坏行 | 按 Surge/Loon/Shadowrocket 支持的类型白名单过滤 |

### 解析

- IPv6 字面量节点不再带方括号入库。此前 `URLComponents.host` 返回 `[2001:db8::1]`，导致 `inet_pton` 失败（无国家识别）、`getaddrinfo` 失败（ICMP 静默退回端口）、Clash `server` 字段非法。
- URI 和 Clash YAML 中带 SIP003 `plugin` / `plugin-opts` 的 SS 节点改为拒绝并计数，不再伪装成可用的裸 SS 节点。**当前仍不支持 plugin，这是已知边界，不是回归。**
- 重复的 query key（如 `?sni=a&sni=b`）不再触发 `Dictionary(uniqueKeysWithValues:)` 崩溃；内联 YAML 映射同理。
- 导入结果的跳过条数会显示在 Toast 中。

### 隐私与落盘

- 导出配置和二维码 PNG 改为 `.completeFileProtection` 写入，并在各自目录中清理超过 5 分钟的旧文件。此前它们以默认保护级别无限堆积在 `tmp`，内容包含全部节点明文密码。
- 按既定产品要求恢复 `AddSourceSheet` 展示时的一次性剪贴板请求；只在内容可识别时填充，并用视图状态防止同一次展示重复读取。
- 删除从未被读取的 `ImportResult.responseHeaders`，它把订阅响应头（含 `subscription-userinfo`、cookie）带进了 App 状态。

### 地区识别与性能

- 与常用英文词冲突的两字母国家码（`us`、`in`、`my`、`de`、`ca` 等）在节点名称中仅大写时匹配，服务器主机名的标签仍按域名规则忽略大小写。此前 “My fast node” 判成马来西亚、“Rio de Janeiro” 判成德国，而 `us.example.com` 又无法识别美国。误判或漏判都会影响地区策略组。
- 移除法国的错误 token `frr`；`fra` 明确保留给法兰克福。
- IP 国家解析与延迟测试统一按 8 个一批，展开大地区不再同时发起 N 个 `getaddrinfo`。
- `RuleRepository` 的 bundle 扫描（69 个文件、约 2.1 万行）从 `init` 移到首次取用时，不再阻塞启动主线程；同一 bundle 只加载一次。
- `ConfigurationPreviewFormatter.summary` 改为只遍历它保留的行。此前它把整份约 700 KB 配置切成上万个子串，只为取前 18 行，而导出页每次 body 求值都会调用一次。

### 仓库

- `.codex_work/` 和 `outputs/` 加入 `.gitignore`。它们此前未被追踪却留在工作区，内含与本项目无关的私人材料，一次 `git add -A` 就会提交。

## 1.2 规则导入与 ACL4SSR

规则页新增两项能力：内置 ACL4SSR 的默认／精简／全分组三套规则，以及输入链接导入 subconverter 远程配置。

### 与内置预设的区别

ACL4SSR 的 `.ini` 自带策略组定义，和塔台固定的 `RulePolicy` 枚举是两套东西，因此新增了 `RuleScheme` 这条并行路径：

| | 内置 ACL4SSR | 导入的 `RuleScheme` |
| --- | --- | --- |
| 策略组 | 按随包 ini 声明还原 | 按 Clash YAML、ini 或 Surge 配置声明还原 |
| 地区分组 | 配置里的节点名正则 | 配置声明的成员或节点名正则 |
| 联网 | 从不 | 仅用户下载和刷新时 |

两套机制互不干扰，不要合并。

### 关键实现

- `RuleSchemeParser` 解析 `ruleset=` 和 `custom_proxy_group=`。`ruleset` 只按第一个逗号切分，因为内联规则 `[]GEOIP,CN` 自带逗号；组成员以 `[]` 开头是引用，否则是节点名正则；末尾 `300,,50` 是时序字段，靠“含逗号且只有数字和逗号”与节点正则区分。
- `ConfigurationGenerator.generate(nodes:scheme:target:schemes:)` 是动态组输出路径，复用原有的节点输出和 `confName` 转义。正则匹配同时试节点原名和塔台改名后的显示名，因为塔台可能加国旗前缀或去重后缀。匹配不到节点的组会回落到 DIRECT，避免输出空组被客户端拒绝。
- QuanX 的 `url-latency-benchmark` 仍走 `server-tag-regex`（第 13 条约束）。
- 导入只接受 HTTPS；规则列表按 6 个一批下载，存到 Application Support 并用完整文件保护；删除方案会一并清掉它下载的列表。
- `AppSnapshot.importedSchemes` 是 Optional——Swift 合成的解码器不会对缺失键套用默认值，改成非可选会让旧存档解不出来。
- `AppSnapshot.selectedRuleGroups` 和 `customRuleFlows` 同样保持 Optional，旧存档解码后分别回到“完整沿用上游”和“没有自定义规则”。
- 服务分组选择只过滤拥有非 `FINAL` 规则的组；生成前从剩余规则与自定义流向递归保留引用到的基础组，并始终保留末尾兜底。
- `CustomRuleFlow` 不写入 `RuleScheme`。刷新远程方案时只更新下载缓存和时间戳，因此用户的 Tailscale 等规则不会丢失。

### 规则集优先生成（2026-08-09）

设置页提供“优先使用规则集”，默认关闭。`preferRuleSetsWasExplicitlySet` 用于迁移此前短暂存在的隐式开启值：升级后先恢复关闭，只有用户手动开启才会持续保存。`RuleSetEmissionPlanner` 会检查每个下载资源的已缓存原文与解析结果，再决定是远程引用还是本地内联：

| 客户端 | 兼容时的生成方式 | 不兼容时 |
| --- | --- | --- |
| Clash / Stash | `rule-providers` + `RULE-SET`；Clash Provider YAML 使用 `format: yaml` | 本地映射 |
| Surge / Shadowrocket | URL `RULE-SET` | 本地映射 |
| Loon | `[Remote Rule]` | 本地映射 |
| Quantumult X | 原生 `[filter_remote]` 资源 | 本地转换为 QX filter |
| Hiddify / sing-box | sing-box source JSON `route.rule_set` | 本地 JSON 路由规则 |
| Egern | 原生 rule-set YAML | 本地 YAML 规则 |

不要改成“只看 URL 后缀”：`.list` 可能是 Clash、Surge 或 QuanX 的不同方言；`.yaml` 也可能是带 `payload:` 包装的 Clash Provider。后者只允许 Clash/Stash 远程引用，Surge、Shadowrocket、Loon 和 QuanX 必须内联解析后的规则。盲目引用会使整份配置被客户端拒绝。`RuleSetGenerationTests` 用七种合成资源、Clash Provider YAML 和随 App 打包的 ACL4SSR 快照同时回归这个边界。

### 资源命名（不要改）

`Tower/Resources/ACL4SSR/` 下所有文件带 `ACL4SSR_` 前缀。Xcode 会把资源拍平到 bundle 根目录；保留前缀可稳定识别来源，`RuleRepository` 也靠这个前缀跳过它们。

### 验证状态

- 模拟器（iPhone 17 Pro，iOS 26.5）：418 个测试通过，1 个按平台跳过（数据保护只能在真机验证）；结果包为 `~/Library/Developer/Xcode/DerivedData/Tower-*/Logs/Test/Test-Tower-2026.08.09_23-15-02-+0800.xcresult`。
- 真机 iPhone 17 Pro：已签名安装并启动成功。

### 真机安装

不需要登录 Apple ID。`.derived-data-device` 里留有一份仍然有效的开发描述文件，已装到
`~/Library/MobileDevice/Provisioning Profiles/<描述文件 UUID>.mobileprovision`：

- `iOS Team Provisioning Profile: *`，团队 `<TEAM_ID>`，通配 App ID，有效期到 2027-07-29
- 授权设备 UDID `<设备 UDID>`，即这台 iPhone 17 Pro
- 钥匙串里 `Apple Development: chujin peng` 证书的 `OU` 正是 `<TEAM_ID>`，私钥齐全

```sh
xcodebuild -project Tower.xcodeproj -scheme Tower -configuration Debug \
  -destination 'id=<devicectl 设备标识>' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<TEAM_ID> build

xcrun devicectl device install app --device <devicectl 设备标识> \
  <DerivedData>/Build/Products/Debug-iphoneos/Tower.app
```

这是正式开发团队签名，不是免费个人团队：不会 7 天过期，也不需要在设备上手动信任证书。
手动签名（`CODE_SIGN_STYLE=Manual` + `PROVISIONING_PROFILE_SPECIFIER`）会被拒绝，因为这份描述文件是 Xcode 托管的，必须用自动签名。

## 1.3 开源发布（2026-08-05）

仓库已公开：**https://github.com/pengchujin/tower**，默认分支 `main`，MIT 许可。

### 发布前做过的脱敏

以下标识信息已从全部文档中替换为占位符。**新增文档时不要再把它们写回去**，需要时用占位符加口头说明：

| 占位符 | 原本是什么 |
| --- | --- |
| `<设备 UDID>` | 测试 iPhone 的硬件 UDID，永久标识 |
| `<devicectl 设备标识>` | `xcrun devicectl` 用的设备 identifier |
| `<TEAM_ID>` | Apple 开发者团队 ID |
| `<描述文件 UUID>` | 开发描述文件 UUID |
| `<Delivery UUID>` | Apple 上传回执 UUID |
| `<App Store Connect App ID>` | App Store Connect 的 App ID |
| `<构建机地址>` | 局域网构建机 IP |

git 历史检查过，**不需要重写**：证书、密钥、描述文件、IPA 从未入库；`.codex_work/` 和 `outputs/` 里的私人材料也从未被提交（它们只是留在工作区，现已在 `.gitignore` 中）。

### 许可结构

源码 MIT，但 `Tower/Resources/` 下的第三方数据**不适用 MIT**，各自保留原条款：

| 资源 | 上游许可证 | 义务 |
| --- | --- | --- |
| ACL4SSR 规则 | CC BY-SA 4.0 | 署名 + 衍生作品相同方式共享 |
| IP 国家库 | CC0 1.0 | 无 |

相关文件：根目录 `LICENSE`、`THIRD-PARTY-NOTICES.md`，以及随包资源目录各自的 NOTICE。

`LICENSE` 末尾写明了「本许可仅覆盖源码」。这会让 GitHub 把许可证识别成 `Other` 而不是 `MIT`，**这是有意为之**：混合许可的项目把边界写进 LICENSE 正文，比让人看到 MIT 徽章后误以为整个仓库可随意取用更稳妥。不要为了拿徽章去掉这段说明。

### Self-Configuration 分发边界

仓库和 App 包不含 Self-Configuration 配置或规则列表。规则页底部只提供用户明确触发的上游下载入口，下载内容保存在当前设备并可删除。这是必须保持的 P0 约束，不能重新把快照加入 `Tower/Resources/`。

## 1.4 2026-08-07 导出兼容性与地区识别

### 各客户端拒绝配置的四个原因

真机逐个导入时发现的，共同点是机场只按自己服务端的宽松标准发字段，各客户端严格程度不同。**一行不合法整份配置就拒绝加载**，所以每个都会连累其余几百个节点。

- **Stash：`invalid UUID length: 8`**。Xray 允许 VMess/VLESS 的 id 是任意短于 32 字节的字符串，并用 SHA-1 对「全零命名空间 + 文本」导出 v5 UUID；Clash 系没有这套映射。生成时做同样的推导（`ProxyNode.exportableUUID`），写进去的正是服务端比对的值，所以节点是真能连的。32 字节以上又不是 UUID 的没有忠实表达，跳过并计入已跳过。
- **Surge：`ws-path` 的值无效**。WebSocket 路径就是 HTTP 请求路径，必须绝对。Xray 的 `GetNormalizedPath` 自己也会补斜杠，所以补上等于还原本来就该发的路径。五处写路径的地方统一走 `ProxyNode.exportablePath`。
- **QuanX：语法错误（无 TLS 却有 `tls-verification`）**。该键只在声明了 TLS 层时合法。机场会发「没开 TLS 但带 allowInsecure」的节点，改成只在 `node.tls` 为真时写。Trojan/Hysteria 2 在 QuanX 里恒为 TLS，那三个调用点保持无条件。
- **QuanX：语法错误（`hysteria2=`）**。QuanX 根本没有这个服务器类型——其 `sample.conf` 记录了 ss2022、REALITY、vless-flow、AnyTLS 却没有任何 Hysteria。已从支持矩阵移除，改为跳过并计数。AnyTLS 保留，`sample.conf` 里确有 `anytls=`。

### 地区识别改为名称优先

顺序：国旗 Emoji → 中英文国名/别名/城市 → 大写国家代码 → 域名 → 内置离线 IP 库。策略分组和界面用同一个顺序。

国家表从手写的 20 个扩到 187 个，由 `Scripts/update_country_table.py` 从 Natural Earth 生成到 `Tower/Services/CountryTable.swift`（含名称、别名、标注坐标），香港/新加坡/澳门等 110m 精度略掉的小地区在脚本里补齐。之前只有那 20 个有坐标，别的连地图都上不去。

三字母代码只在名字里大写时才认——`AND` 是安道尔、`ARE` 是阿联酋、`CAN` 是加拿大，不加限制会把「Hong Kong and Tokyo」判成安道尔。`SS`/`WS` 和 `GB/MB/TB` 直接拉黑：在节点名里它们是 Shadowsocks、WebSocket 和流量单位。

### 性能：一次列表渲染 3754ms → 5.5ms

上一版的匹配每次都线性扫约 2100 条拼写，且每次比较新建一个字符串；视图每行要问 5 次（国旗、标题、3 个无障碍标签）。500 个节点即一次重绘数百万次字符串操作。

改为索引：单词和国家代码走字典，多词国名按首词分桶，中文名按首字分桶（纯英文名根本不会碰到中文表），再加一层按名字/主机名的记忆化。另外订阅展开和地图选中地区两个列表原本是普通 `VStack`，为显示十行会把几百行全建出来，改成 `LazyVStack`。

2026-08-07 又补了一层运行时修复：IP 地区查询和测速虽然已经限制为每批 8 个，但旧实现每完成一个节点就分别修改一次 `@Observable` 字典/集合，后台结果回来时会反复使整个首页失效。现在由 `NodeCountryResolutionBatch` / `NodeLatencyResultBatch` 先收齐一批，再各发布一次；强制重测前清理旧延迟也从逐节点写入改为一次字典替换。地图父视图已经统一解析全部节点，地图区域内的行不再随滚动重复启动同一 IP 查询，其他入口的节点行仍保留按需解析。

用 iOS 26.5 模拟器写入 1000 个节点后安装运行，借助无障碍滚动从第 1 个推进到第 70 个节点，未崩溃；12 秒采样中主线程 10207 个样本有 9429 个停在事件循环等待（约 92%），物理内存 70.0 MB、峰值 70.2 MB。采样本身包含无障碍树读取开销，所以它证明这一规模下没有持续占满主线程，不能替代最终真机 FPS 验收。

同一份 1000 节点快照还做了规则/导出运行验收：在服务分组表搜索“国外媒体”只保留目标行，勾选状态稳定，返回后规则数从 3,160 立即更新到 3,532；导出页同步显示 3,532 条且 1,000 个节点全部兼容。客户端顺序用无障碍“向后移动/向前移动”完成一次往返并恢复；Surge 超长配置全屏预览成功打开、滚动文本可见并正常关闭，没有复现旧闪退。

导出页也量过：`configuration()` 有缓存，命中时 500 节点仅 0.5ms，不是瓶颈，没动。

### 新增 Hiddify 导出

Hiddify 是 Flutter 外壳 + `hiddify-core`（sing-box 内核），吃 sing-box JSON。sing-box 自身在 App Store 没有独立客户端，所以格式以实际运行它的 App 命名。

JSON 用 `JSONSerialization` 构建而非拼字符串——节点名是机场可控的不可信输入，交给编码器转义。几个格式决定：拒绝从 1.11 起是路由动作（`action: reject`），选择器没有可指的出站，所以拦截类策略不生成组、规则直接带动作；Clash 的四个隐藏别名组在 sing-box 里没有 hidden 概念但仍需存在，否则悬空引用导致起不来。Snell 在 Hiddify 上不可用——sing-box 这个项目实现了它，但 Hiddify 打包的内核没有，所以那些节点跳过并计数（真机验证得出，不是从 sing-box 文档推断的）。

Egern 也已支持（含 `egern:/profiles/new` 一键导入，注意是**单**斜杠、没有 authority 段；Hiddify 的 `hiddify://install-config` 反过来必须有 authority，其解析器遇到 `!uri.hasAuthority` 直接返回 nil。两种形式都有测试钉住，别互相“修正”）：三段都是单键映射的列表（`- shadowsocks:` / `- select:` / `- domain_suffix:`），策略组用 `select` 和 `auto_test`，规则每条一个 `match`，兜底是 `- default:`。字段是 snake_case（`user_id`、`udp_relay`、`skip_tls_verify`、`obfs_host`），Shadowsocks 的 cipher 要去掉 `-ietf` 中缀。

### 其他

- 首页机场开关改用规则页那个圆形对勾（`CheckmarkToggleStyle`），并补上选择震动。
- Snell 的图标之前写的是 `shell.fill`，SF Symbols 里没有这个符号——`Image(systemName:)` 遇到未知名字既不崩溃也不报错，只画空白。改为 `s.square.fill`，并加测试断言所有符号确实存在。
- 地图上方有 54pt 的“测试全部节点”主按钮和测速方式菜单；逐节点重测仍在展开后的节点详情里。
- 订阅套餐流量：按 `subscription-userinfo` 响应头 → 内容里的 `STATUS=` 行 → 节点列表公告行取值。节点始终以订阅原地址返回体为准，`flag=clash` 只在缺结构化配额时补发一次且只读响应头——机场的 Clash 转换器会丢掉它表达不了的协议（实测少 12 个 AnyTLS 节点）。

## 1.5 2026-08-10 协议补齐与首启引导

### 对照 Clash Meta 协议表的结论

拿 [mihomo 的 proxies 文档](https://wiki.metacubex.one/config/proxies/) 逐项对过塔台已有的十种协议，缺的是：
tuic、hysteria（v1）、wireguard、ssh、mieru、shadowquic、masque、trusttunnel、openvpn、sudoku、tailscale。

判断标准只有一条：**目标客户端能不能忠实写出来**。写不出来就不能导入，否则等于生产一批看着正常、连不上的节点（约束 12）。

| 协议 | 能表达的目标 | 处置 |
| --- | --- | --- |
| TUIC | Surge、Shadowrocket、Clash/Stash、Egern、Hiddify（5/7） | 已补 |
| Hysteria v1 | Shadowrocket、Clash/Stash、Hiddify（3/7） | 已补 |
| WireGuard | Surge、Shadowrocket、Clash/Stash、Egern、Hiddify（缺 QuanX） | 未做，见下 |
| ssh / mieru / shadowquic / masque / trusttunnel / openvpn / sudoku / tailscale | 0～1 个 | 不做 |

WireGuard 暂缓的原因不是客户端支持不够，而是它和其余十二种协议的形状不一样：没有「服务器 + 一个密钥」，需要本机私钥、对端公钥、本地 IP/IPv6、预共享密钥、`reserved`、MTU、DNS，`wireguard://` 也没有统一写法。这要给 `ProxyNode` 加一整组字段并给六个生成器各写一套，不适合和这次的改动混在一起。机场订阅里出现 WireGuard 的比例也远低于 TUIC。

### 每个客户端的写法来源

不是猜的，各自有出处：

- **Surge**：`tuic-v5, 服务器, 端口, uuid=, password=, sni=`。Sub-Store 的 `surge.js` 里 `token` 为空就写 `tuic-v5`；Surge 没有 Hysteria v1 的服务器类型。
- **Shadowrocket**：`tuic, 服务器, 端口, password=, user=<uuid>, peer=<sni>, udp=1`，Hysteria v1 是 `hysteria, …, auth=, obfsParam=, protocol=, upmbps=, downmbps=, udp=1`。来自其使用手册的「编写本地节点」一节，和 REALITY 那次一样，它的字段名是自己的一套。
- **Clash / Stash**：`type: tuic` 用 `uuid`/`password`/`congestion-controller`/`udp-relay-mode`；`type: hysteria` 用 `auth-str`/`up`/`down`。
- **Egern**：`- tuic:` 用 `uuid`/`password`/`sni`/`alpn`（列表）/`skip_tls_verify`；其 producer 的类型白名单里有 tuic 没有 hysteria。
- **Hiddify（sing-box）**：`type: tuic` 用 `congestion_control`/`udp_relay_mode`；`type: hysteria` 用 `auth_str`/`up_mbps`/`down_mbps`。
- **Loon、Quantumult X**：两种都没有，按约束 12 跳过并计数。

### 解析上的几个坑

- `tuic://` 是唯一一个 userinfo 两半都有意义的 scheme：`tuic://<uuid>:<password>@host:port`。
- Hysteria v1 的密钥在 query 里（`auth=`），不在 userinfo。
- Hysteria v1 的 `up`/`down` 不是可选提示。它的拥塞控制是速率型的，没有带宽预算的节点要么加载失败要么极慢，所以缺省补 50/100。
- Hysteria v1 的 obfs 是一个共享字符串（`obfs=xplus` 时真正的密钥在 `obfsParam`），和 Hysteria 2 的「方法 + 密码」两件事不一样。
- `alpn` 从 URI 里拿到的是逗号拼接的一个字符串，写进 Clash/Egern 必须还原成 YAML 列表，否则 `h3,h2` 会被当成一个协议名。
- 顺手补齐了 Clash YAML 解析：`clashKind` 之前没有 anytls 和 snell，机场发的 Clash 订阅里这两种一直被算成无法识别。`auth-str`/`auth_str`/`psk` 现在都能落到 `password`。

### Shadowrocket 的 Hysteria 2 用 `password=`，不要改成 `auth=`（2026-08-10 真机确认）

Shadowrocket 手册的「编写本地节点」一节把 Hysteria 2 写成 `auth=密码`，和塔台实际写的 `password=` 不一致，一度怀疑是又一次「字段名猜错」。**真机验过了：不是。** 导入塔台生成的配置后，节点详情页的密码栏正常填好，节点也能连上——Shadowrocket 收 `password=`，这条不用动。

留这段是为了别再翻一次案：它的手册只列了一种写法，不代表另一种不被接受。要判断 Shadowrocket 认哪个字段，看它自己写出来的配置或详情页回填的值，不要只看手册。

（对比 REALITY 那次：手册和 producer 都没提，但节点详情页能证明它支持，判断依据是同一个。）

外部资料也和真机结论一致，可以一并留档：公开仓库里能找到的 Hysteria 2 `.conf` 行，凡是写 `password=` 的都在 Surge 配置里，写 `auth=` 的都在 Shadowrocket 模板里——两边各写各的，没有哪一份能证明另一种被拒。Sub-Store 的 `shadowrocket.js` 帮不上忙，它产出的是 URI 节点列表，根本不写 `[Proxy]` 本地节点行。

代码里 `case .hysteria2` 和 `writes(_:to:excluding:)` 都留了注释指回这一节，别再翻案。

#### 但 Salamander 混淆之前是真的丢了（2026-08-10）

同一行还有个没被发现的洞：`hysteria2Obfs(node)` 拿到的混淆密码只写进了 Clash 和 sing-box，Surge / Shadowrocket 那条线一个字都没写。服务端开了 Salamander 就会把没混淆的包全丢掉，所以这类节点导进去看着完全正常、永远连不上，正好是约束 12 说的那种。

两边的写法都有出处，且混淆器的名字是**写在键名里**的，不作为值传：

- **Surge**：`salamander-password=`（官方手册 Hysteria 2 页；同页还有它自己的 `gecko-password=`）。
- **Shadowrocket**：`obfsParam=`（手册「编写本地节点」一节，Hysteria 2 那行没有 obfs 类型字段，因为协议只有 Salamander 一种）。

因此混淆器名字不是 `salamander` 的节点，在这两个目标下按约束 12 跳过并计数——写出去等于宣称它是 Salamander。塔台的解析器目前也产不出别的名字。

Shadowrocket 的 `obfsParam=` 只有手册出处，还没真机验过：**下次真机回归时，用一个开了 Salamander 的 Hysteria 2 节点确认它能连上**，别默认它对。

### 两个「一个节点毁掉整份配置」的真机报错（2026-08-10）

- **QuanX：`配置文件语法错误, duplicated section, [server_remote]`**。这是调整模块顺序时自己引入的：`quanXScheme` 先写了一遍 `[server_remote]/[filter_remote]/[rewrite_remote]`，结尾又调 `quanXTrailingSections` 写了第二遍。QuanX 对重复模块和缺失模块一样零容忍。已把该辅助函数删掉，改成在 `quanXScheme` 里按固定顺序各写一次；`ProfileRejectionTests` 断言两条 QuanX 生成路径的模块序列都恰好等于那 12 个、顺序一致。
- **Stash：`proxy 301: hysteria2 obfs: salamander requires obfs-password`**。根因在解析：Clash YAML 的 obfs 密码之前只读 `obfs-param`，那是 SSR 的键名，Hysteria 2 叫 `obfs-password`。于是节点带着 obfs 类型、没有密码进来，生成器把 `obfs:` 单独写出去，Mihomo 直接拒掉整份配置——不是拒那一个节点。两头都修了：解析补 `obfs-password` / `obfs_password`，生成侧新增 `hysteria2Obfs(_:)`，类型和密码要么都写要么都不写。没有密码的 obfs 层本来也连不上，丢掉它至少不牵连同文件里其余几百个节点。

### Clash YAML：嵌套序列会把节点截断（2026-08-10）

`parseClashYAML` 判断「新节点开始」只看 `trimmed.hasPrefix("-")`，不看缩进。机场写的

```yaml
    http-opts:
      path:
        - /
```

里那个 `- /` 因此被当成新节点，后果有两个，第二个更严重：

1. 凭空多出一条没有 `type`/`server` 的条目，被计入「跳过/无法识别」；
2. **真节点在那一行被截断**，后面的 `reality-opts`、`skip-cert-verify`、`udp` 全部落进那条垃圾条目。这些 VLESS 节点会以「纯 TLS 借用 SNI」的形式导入——看着正常，永远连不上，正是约束 12 要避免的那种。

实测某公开列表 475 个条目里有 28 处这种嵌套，即 28 条 REALITY 节点丢了 `public-key`。修完后 447 个节点、0 跳过、117 条带 `reality-opts` 的全部拿到了 public-key。

修法：记住 `proxies:` 下第一个 `-` 的缩进作为条目缩进，只有缩进不深于它的 `-` 才开新条目；更深的 `-` 当成上一个空值键的序列元素，用逗号拼接——`alpn:` 下的多个元素因此也能完整保留，而且拼出来正好是 `ProxyNode.alpn` 和各生成器已经在用的那种形式。顺带把之前一直丢掉的 `http-opts`/`ws-opts` 里的 `path` 也接上了。

### 首启引导页

`Tower/Features/Onboarding/WelcomeView.swift`，`@AppStorage("hasSeenWelcome")` 控制只出现一次。

放在这里的原因：塔台要用户交出订阅地址，那是机场给的最敏感的东西——一条带账号的链接。先要东西再解释去向是错的顺序。

四条各自点名机制而不是形容词：本机转换、代码公开、地区识别不联网、只在用户按下时联网。仓库那条排在第二位、紧跟它能验证的第一条，地址写全而不是藏在一个词后面——不能核对的开源声明没有意义。文案一律从简，四条都压到一行以内。

动效按 `apple-design` 的默认：临界阻尼、无回弹（这里没有任何手势动量可继承），逐条 0.06s 错峰；`accessibilityReduceMotion` 打开时退化为纯交叉淡入。底部按钮条是 `.regularMaterial`，内容从下面滚过去。十五种语言的文案已进 `Localizable.xcstrings`。


## 2. 产品目标与确定的交互

### 首页

- “+”统一添加机场订阅和自有节点，提示同时覆盖订阅 URL 和节点协议链接。弹出时自动请求一次剪贴板并在识别成功后填充，同时保留手动粘贴按钮。
- 顶部统计项“订阅、节点、覆盖地区、自有节点”可滚动到对应内容。
- 订阅可展开节点，但不显示“更多节点”，展开使用透明度/布局变化，不从顶部滑入。
- 节点行显示 IP 国家/地区 Logo、名称、协议/传输/UDP 信息和真实延迟。
- 订阅和单节点都可以分享；单节点导出协议链接和二维码。
- 页面直接嵌入自绘的点阵世界地图（`WorldDotMapView`，不用 MapKit），显示带 Emoji 的节点标注，不单独设置“地球”标签页。
- 世界点阵保留完整 `-180...180` 经度；斐济、新西兰和格陵兰不会再因裁剪被压到地图边缘。密集地区会按选中状态/节点数优先，再尝试 16 个近邻位置，无法避让的低权重文字才隐藏，节点本身始终显示。

### 规则页

- 默认使用内置 ACL4SSR；Self-Configuration 位于页面底部并由用户手动下载。
- 当前方案提供可搜索的服务分组勾选页；取消勾选后规则数量和七种导出立即更新。
- 自定义规则流可新增、编辑、启停和删除，带 Tailscale 示例；规则与方案分开保存，重启 App 或刷新方案后仍保留。
- 生成配置不引用远程策略组图标，只保留名称内有语义的 Emoji。
- “手动切换”“自动选择”“全球直连”等使用中文可见名称。
- 香港、日本、美国、新加坡等国家/地区策略位于业务策略之后。
- 地区组本身默认延迟优选；业务策略仍可手动选择地区组。
- 生成器必须避免地区组、节点选择和业务策略之间的循环引用。

### 导出页

- 七个目标客户端使用塔台自绘的品牌色矢量标识，不打包或仿制第三方 App Store 图标；横向滚动选择并支持长按拖动排序。
- 主按钮固定在标签栏上方，一次点击就通过客户端 Scheme 导入。
- Surge、Stash/Clash、Shadowrocket、Loon 使用本地临时 URL；Quantumult X 使用文件分享。
- 支持配置摘要和完整预览，但不要在客户端切换动画中同步重复生成大文本。

## 3. 已完成的关键实现

### 规则存储

- ACL4SSR 固定快照位于 `Tower/Resources/ACL4SSR/`，随 App 离线提供。
- Self-Configuration 不在仓库或 App 包内；用户点击规则页底部按钮后从上游下载。
- 远程方案与规则提供者保存到 Application Support，删除方案会一并清理。
- 分组勾选与 `CustomRuleFlow` 保存在 `state.json` 的独立字段中；删除方案时同步清理该方案的本地定制。

### IP 国家库

- 上游：`sapics/ip-location-db` 的 `geo-whois-asn-country`。
- 当前版本：`2.3.2026061719`。
- 二进制索引：`Tower/Resources/IPCountry/`。
- 更新脚本：`Scripts/update_ip_country_db.py`。

地区识别以节点名称为第一信号，再检查服务器主机名；两者都无结果时，域名才通过系统 DNS 解析并查询内置 IP 国家库。这个顺序与 `NodeRegionResolver.resolvedRegion` 一致。

### 一键导入

目标客户端不能读取塔台沙盒文件路径，所以 `DirectImportService` 会启动仅绑定 `127.0.0.1` 的 token 化 HTTP 服务，45 秒后关闭，再把临时 URL 放进各客户端 Scheme。该服务不监听局域网地址，不上传配置。

Quantumult X 的公开 Scheme 只覆盖远程资源操作，无法可靠导入完整本地节点、策略组和规则，因此保留文件分享。

### 局域网订阅与“透传”

`LANSubscriptionServer` 是单独的用户可控服务，不要和 `DirectImportService` 合并：前者绑定 Wi-Fi、持续到用户关闭或 App 被系统挂起，后者只绑定 `127.0.0.1` 且 45 秒自动关闭。设置页会展示带 32 位随机访问密钥的地址，密钥可手动轮换，旧链接立即失效。

- 路由：`/sub/<token>?target=auto`，另兼容 `/download/<token>`；支持 GET/HEAD。
- 自动识别：OpenClash 的 `clash.meta`、Clash Verge/Mihomo/Stash、Surge、Shadowrocket、Loon、Quantumult X、Hiddify/sing-box、Egern。
- 未知 User-Agent 返回带可用 `target=` 值的 400，不默认输出 Clash，避免客户端悄悄接收错误格式。
- 显式 `target` 优先，可用于不发送品牌 User-Agent 的 Windows/Mac 客户端。
- 安全边界：LAN URL 和响应不含机场 URL；每次请求用本地节点、规则和协议筛选实时生成。上游需要自定义 UA/DoH 时仍由 `SubscriptionService` 获取，路由器或电脑不会拿到上游 token。
- iOS 后台不能作为常驻服务器，客户端刷新时必须让塔台保持前台；界面已明确提示。

2026-08-07 用目标清单提供的 4 个实时订阅做过一次性兼容验收：四个 HTTPS 端点均返回 200，随后由 iOS 模拟器内的 `SubscriptionService` 携带自定义 UA，并通过 Cloudflare DoH 请求，四个来源都成功解析出节点。URL 只通过模拟器临时环境传入，测试结束后立即清除，未写入源码、结果包或文档。

自动测试不只调用路由函数：`testLoopbackListenerServesGeneratedConfigurationEndToEnd` 会真实启动 `NWListener`，通过 `URLSession` 携带 OpenClash User-Agent 请求随机端口，并核对 200、`X-Tower-Target: clash` 与生成内容。测试环境只把监听依赖切到 `127.0.0.1`，App 默认仍固定为 Wi-Fi 环境。

首次开启会触发 `NSLocalNetworkUsageDescription` 权限。真机验收要把手机和另一台设备放到同一 Wi-Fi，分别用 `curl -A clash.meta '<自动链接>'` 和显式 `?target=surge` 验证，随后轮换密钥确认旧 URL 返回 404。

### 策略组

当前生成器按名称优先、离线 IP 回退的统一结果创建地区组，为地区组建立延迟优选，同时让节点选择/业务策略引用这些地区入口。历史上出现过以下回归，修改时必须保留测试：

- 地区组互相引用导致 Surge/Shadowrocket 报循环。
- 节点选择间接包含自身。
- 策略名称自带 Emoji，同时 UI/客户端图标字段再显示一次，造成重复。
- 地区组只有手动选项或只有自动组，不能兼顾默认延迟优选和人工覆盖。
- QuanX 的 `url-latency-benchmark` 直接列节点标签会报语法错误；必须输出 `server-tag-regex`，并对节点标签中的正则字符逐个转义。

## 4. 当前 TestFlight / App Store Connect 状态

### 已确认

- App 名称：塔台。
- App Store Connect App ID：`<App Store Connect App ID>`。
- Bundle ID：`com.jzb.tower`。
- SKU：`com.jzb.tower`。
- 签名 Team ID：`<TEAM_ID>`。
- 已上传的构建：`1.0 (3)`（2026-08-07），含本文 §1.4 的全部修复。此前为 `1.0 (1)`（2026-08-03）。

### 归档只能在图形会话里做

SSH 登录落在 launchd 的 `Background` 域，`codesign` 取不到钥匙串私钥，必然报 `errSecInternalComponent`。解锁钥匙串要密码、切到 Aqua 会话要 sudo，都不能由自动化代劳。

所以归档必须在那台机器**自己的终端窗口**里跑，且三条命令要在同一个会话里连续执行：

```sh
security unlock-keychain ~/Library/Keychains/login.keychain-db

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && cd ~/tower-release && xcodebuild -project Tower.xcodeproj -scheme Tower -configuration Release -destination 'generic/platform=iOS' -archivePath ~/tower-release/build/Tower-1.0-N.xcarchive -allowProvisioningUpdates DEVELOPMENT_TEAM=<TEAM_ID> CODE_SIGN_STYLE=Automatic archive

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && cd ~/tower-release && xcodebuild -exportArchive -archivePath ~/tower-release/build/Tower-1.0-N.xcarchive -exportOptionsPlist .artifacts/UploadOptions-TestFlight.plist -allowProvisioningUpdates
```

`DEVELOPER_DIR` 不能省：那台机器的 `xcode-select` 指向 CommandLineTools，改它要 sudo，用环境变量绕过。`UploadOptions-TestFlight.plist` 是 `destination: upload`，第三条直接传到 App Store Connect，不用开 Organizer。归档前务必 `git pull` 并确认 `CURRENT_PROJECT_VERSION` 是新值。

### 代码与已上传版本

工程和已上传构建均为 **`1.0 (3)`**，`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` 已加入。下次归档前必须先递增 `CURRENT_PROJECT_VERSION`，不要重复上传 build 3。

### 外部测试还需要补的材料

- **App 隐私**问卷必须完成，否则构建在外部群组里不可选。塔台不收集任何数据，如实勾选即可。
- TestFlight **测试信息**：Beta App 描述、需要测试的内容、反馈邮箱、联系人。
- 外部测试需要经过 **Beta App Review**，内部测试不需要。
- 审核时容易被问用途。建议在「需要测试的内容」里写明：本 App 只在本机把订阅转换成各客户端配置文件，不含 VPN 或代理功能，不接管流量，不上传用户数据。

## 5. 远程 Mac 归档说明

远程构建机位于同一局域网，主机为 `jzb@<构建机地址>`，已经登录 Apple 开发者账号。凭据和登录密码不写入仓库，也不应发给接手模型保存。

该机器的默认 `xcode-select` 曾指向 Command Line Tools，构建命令需要显式指定：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### 非交互 SSH 归档为什么一定失败

2026-08-05 重新验证过，根因已定位，**不要再从远程 SSH 尝试归档**：

```
$ launchctl managername
Background          ← SSH 会话在 Background 域，不在 GUI 的 Aqua 会话
$ security show-keychain-info ~/Library/Keychains/login.keychain-db
User interaction is not allowed.
```

即使该用户有 GUI 登录、钥匙串已解锁，SSH 会话仍属于不同的 launchd 域，codesign 拿不到钥匙串上下文，归档必然以 `errSecInternalComponent` 失败。

两个绕过办法都需要凭据，因而只能由人操作：`security unlock-keychain` 要钥匙串密码，`launchctl asuser` 要 root（该机未配置免密 sudo）。

**可行做法**：在那台机器自己的终端窗口里先 `security unlock-keychain ~/Library/Keychains/login.keychain-db`，再在**同一会话**执行归档；或者直接用 Xcode 图形界面 Product ▸ Archive ▸ Distribute App，GUI 本身就在 Aqua 会话里，最省事。

不要把钥匙串密码放进脚本、Shell 历史或 Git。

### 归档用开发证书签名是正常的

曾误判「机器上没有 Apple Distribution 证书 ⇒ 无法上传 App Store」。**这是错的。**

2026-08-03 那份成功上传的归档，实际签名就是 `Apple Development: …`。归档阶段用开发证书签名属正常流程，**分发签名发生在 Distribute / `-exportArchive` 这一步**，Xcode 会重新签名，分发证书可以由 Apple 云端托管、本地钥匙串不留私钥。

所以排查上传问题时，不要以 `security find-identity` 里没有 Distribution 证书作为判据。

归档命令基线：

```sh
xcodebuild -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Tower-1.0-1.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  CODE_SIGN_STYLE=Automatic \
  archive
```

导出使用 `app-store-connect`、`destination=upload`、Automatic signing、Team ID `<TEAM_ID>`。本地 `.artifacts/` 中可能有归档和 IPA 备份，但已被 `.gitignore` 排除；它们不是源码交接的一部分。

每次重新上传前必须增加 `CURRENT_PROJECT_VERSION`，当前已使用 build 3。

## 6. 优先任务

### P0：发布闭环

1. 在至少一台 iOS 17+ 真机完成启动、订阅导入、平面点阵地图、测速、规则和导出主流程。
2. 下次上传前把构建号从 build 3 继续递增，并重新核对 App 隐私、Beta 测试信息和外部测试审核状态。

### P1：性能和崩溃回归

1. 反复展开/关闭“配置预览”，使用包含数百节点的大订阅观察是否仍闪退。
2. 快速横向切换七个目标客户端，确认矢量标识和配置不重复生成、动画不掉帧；长按拖动后重启 App，确认顺序保留。
3. 第一次打开节点/订阅分享 Sheet，确认二维码生成和 Activity View 不阻塞主线程。
4. 如仍卡顿，先用 Instruments 的 Time Profiler / Allocations 复现，重点排查：
   - SwiftUI body 中重复生成完整配置。
   - 大字符串在 `Text`、剪贴板、分享 payload 之间产生多份副本。
   - 客户端切换时重复生成配置或重建大文本预览。
   - 二维码在主线程同步生成。

### P1：七客户端真机兼容

准备安装相应客户端的测试机，分别验证：

- Surge：代理、策略组、图标、规则和一键导入。
- Stash/Clash：YAML 语法、proxy-groups、URL-test 和图标 URL。
- Shadowrocket：节点协议链接、策略环路、规则和 Scheme 接收。
- Loon：VMess/VLESS/Trojan/Hysteria 2 参数及策略组。
- Quantumult X：分享文件能否出现在目标列表；若不能，验证“存储到文件”后手动导入。
- Hiddify：sing-box JSON 的一键导入和内核兼容跳过。
- Egern：YAML 结构、`egern:/profiles/new` Scheme 和规则兜底。

### P2：解析兼容

- 收集不能识别的真实机场样本时，先脱敏密码、UUID、token 和域名。
- 每修复一种格式都加入最小自动测试。
- 对 HTTP 错误页、登录页和空订阅保持明确错误，不把它们解析成节点。

## 7. 真机回归清单

### 首页

- [ ] 首次点击“+”时剪贴板权限文案正常，订阅和节点都能自动识别。
- [ ] 四个统计项跳到正确位置。
- [ ] 订阅展开没有从顶部滑入或列表勾选漂移。
- [ ] 节点国旗优先遵循明确名称，名称无结果时使用离线 IP 回退。
- [ ] 点阵地图铺满卡片，国家/地区标注不重叠，节点 Emoji 正常。
- [ ] ICMP 与“端口”回退标识准确。
- [ ] 节点和订阅分享、二维码、协议链接可用。

### 规则

- [ ] 默认显示内置 ACL4SSR，Self-Configuration 位于底部且只能手动下载。
- [ ] 生成配置没有 `icon`、`icon-url` 或 `img-url` 远程策略图标字段。
- [ ] 地区策略位于业务策略之后。
- [ ] 地区默认延迟优选，业务策略可手动选择地区。
- [ ] 展开/收起时选择标记不漂移。

### 导出

- [ ] 七个自绘矢量客户端标识立即出现，不含第三方 App 图；横向滚动、拖动排序与切换流畅。
- [ ] 摘要中的节点数、跳过数、规则数正确。
- [ ] 完整预览多次展开不闪退。
- [ ] 固定主按钮不被底部标签栏遮挡。
- [ ] 安装客户端时一键打开；未安装时回退分享。
- [ ] 本地临时 URL 只能从本机访问，并在约 45 秒后失效。

### 恢复与隐私

- [ ] 杀掉 App 后订阅和自有节点恢复。
- [ ] 用户开启续费提醒后才请求通知权限；机场到期前 24 小时触发，关闭后清除待发送提醒。
- [ ] 日志中没有订阅 URL、节点密码、UUID 或完整配置。
- [ ] 飞行模式下仍可查看已保存内容并生成配置。
- [ ] 打开“+”面板时只出现一次系统粘贴请求；支持的订阅或节点链接自动填入，不支持的文本不覆盖输入框，手动粘贴仍可用。
- [ ] `ImportHardeningTests.testExportedConfigurationIsWrittenWithCompleteFileProtection` 在真机上不再 skip 且通过。模拟器不实现数据保护，这条只能在真机验证。
- [ ] 分享配置或二维码后，`tmp/TowerExports` 与 `tmp/TowerQRCodes` 中的旧文件会在下次生成时清掉。

## 8. 自动测试与提交门槛

至少运行：

```sh
xcodebuild -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derived-data-sim \
  test
```

配置生成器修改需要额外人工打开七种输出，检查：

- 所有组引用存在且无环。
- 地区组只含对应节点，空地区不产生死组。
- 节点名称转义、去重和协议跳过正确。
- 规则顺序与末尾兜底未改变。
- 图标字段符合目标客户端语法，显示名称不重复 Emoji。

提交前执行 `git diff --check`，确认没有把 `.artifacts`、`.derived*`、证书、描述文件或 API Key 加入暂存区。

## 9. 文档与代码入口

- 产品说明：`README.md`
- 接手约束：`CLAUDE.md`
- 架构：`docs/ARCHITECTURE.md`
- 中央状态：`Tower/AppModel.swift`
- 领域模型：`Tower/Models/DomainModels.swift`
- 配置生成：`Tower/Services/ConfigurationGenerator.swift`
- 一键导入：`Tower/Services/DirectImportService.swift`
- 订阅解析：`Tower/Services/SubscriptionParser.swift`
- 首页：`Tower/Features/Subscriptions/SubscriptionsView.swift`
- 规则页：`Tower/Features/Rules/RulesView.swift`
- 导出页：`Tower/Features/Export/ExportView.swift`
- 自动测试：`TowerTests/`

## 10. 交接原则

- 先复现、记录输入规模和设备，再修性能或崩溃。
- 不以模拟器成功代替客户端 Scheme 和真机网络验收。
- 不为了“一键导入”引入公网中转或上传用户配置。
- 不追踪生成产物和签名材料。
- 功能、测试、文档与 build number 同步提交，避免下一位接手者从聊天记录猜状态。
