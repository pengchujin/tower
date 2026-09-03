# 塔台开发交接（2026-08-07）

## 1. 当前结论

塔台已完成可运行的原生 SwiftUI 主流程：导入订阅/自有节点、节点解析和地区识别、自绘点阵世界地图、ICMP/端口测速、内置与手动下载规则、多客户端配置生成、配置预览及导入/分享。

### 2026-09-04：`1.0.6 (40)` 已上传 TestFlight

- 本次构建包含首页及批量管理页来源固定排序，以及 Quantumult X `no-resolve` 兼容修复；订阅和自有节点启用状态变化不再触发重排。
- 正式版 Xcode 26.6 的 iPhone 17（iOS 26.5）模拟器完整测试为 884 通过、0 失败、2 个平台条件跳过；发布前已远程回读并核验 77 个 ACL4SSR 二进制产物。
- 已在 MacBook Air M2 上完成 Release 自动签名、归档和上传，归档内版本核对为 `1.0.6 (40)`，App Store Connect 返回 `Uploaded package is processing` 与 `Upload succeeded`。后续处理完成和测试群组状态仍需在 App Store Connect 核对。

### 2026-09-03：修正 Quantumult X 规则中的 `no-resolve`

- Quantumult X 不支持 Surge / Clash 风格的尾随 `no-resolve`。内置方案与导入方案的 QX 输出都会删除该参数；标准/严格保护在 `final` 前生成与其相同策略的 `host-keyword, .`，按官方示例避免为未命中的主机名继续做 DNS 查询，而纯 IP 请求仍落到 `final`。
- “跟随方案”不会凭空增加这条保护规则；但上游 IP/GEOIP 规则明确带了 `no-resolve` 时，会转换成上述 QX 等价写法，保留来源方案的意图。
- QX 原生远程 filter 的第三列是策略名，并由 `[filter_remote]` 的 `force-policy` 覆盖。Planner 现在接受合法策略列并拒绝含 `no-resolve` 的 Clash/Surge 规则集；后者自动回落本地转换，不再把无效语法直接交给 QX。
- 根因是 2026-08-11 的 DNS 防护改动把多个客户端共用的 `no-resolve` 机制错误推广到了 QX，且生成器、远程规则校验、测试和本文件旧结论一起固化了这个假设。现在以 QX 官方 `sample.conf` / `filter.snippet` 为准，并为内置、导入、远程回落和“跟随方案”分别加了回归测试。
- 正式版 Xcode 26.6 的 iPhone 17（iOS 26.5）模拟器完整测试为 884 通过、0 失败、2 个平台条件跳过。

### 2026-09-03：首页来源保持固定顺序

- 首页的订阅和自有节点现在始终按模型中的持久化顺序展示；启用或取消勾选只改变是否参与导出，不再把停用项移动到列表末尾。
- 批量管理页保持相同行为，搜索结果只做过滤并保留原始相对顺序。勾选状态本身仍有轻量反馈，但不会再触发卡片重排动画。

### 2026-09-02：调整导出目的地默认顺序

- 新的默认顺序为 Shadowrocket、Stash、局域网共享、Surge、Loon、QuanX、Clash、V2Box、sing-box MT、Hiddify、Egern。
- 塔台生成的旧默认顺序会整体迁移到新顺序；用户已经手动拖动过的自定义顺序继续保留。局域网共享仍与客户端分开持久化位置，但迁移时会与旧官方客户端顺序一并识别。

### 2026-09-02：Stash / Clash 优先使用经验证的 MRS

- ACL4SSR 的 classical `.list` 是混合语法，MRS 只接受 `domain` 或 `ipcidr` behavior。快照更新器现在把 `DOMAIN` 保留为精确域名、把 `DOMAIN-SUFFIX` 转为 Mihomo `+.` 后缀键，并把 CIDR 规范化后使用固定版本 Mihomo 编译。每个二进制都会反向解包，核对条数和内容后才写入 manifest。
- 没有无损 MRS 表达的 `DOMAIN-KEYWORD` / `DOMAIN-WILDCARD` / `PROCESS-NAME` / `URL-REGEX` 等仍保留为内联规则，不会为了压缩配置而丢掉。IP MRS 只在该资源中的全部 IP 规则都原本声明 `no-resolve` 时生成，避免改写 DNS 匹配语义。
- App 只接受 Tower 生成的结构化 metadata，并会从随包 `.list` 独立重算源 SHA-256、总条数、MRS 类型/输入条数、CIDR `no-resolve` 完整性以及 SRS 覆盖/残余条数。还必须同时满足 `revision` / `artifactCommit` 是严格的 40 位小写 Git SHA，且每个二进制 URL 精确指向该提交下的预期文件。无 `artifactCommit`、仍指向 `main` 或任一元数据不一致时就回落原有文本/内联生成，不会删除原规则。
- 运行时还会把本次生成实际读取到的规范化规则内容与编译源做完整指纹绑定，不能只因 URL 相同就复用二进制。若下载缓存中的同 URL 规则新增、删除、改值或调序，旧 MRS/SRS 会被拒绝：Clash/Stash 回到兼容文本/本地映射，sing-box MT 的 classical 列表回到本地 JSON 规则。用户在塔台新增的 `CustomRuleFlow` 始终作为独立本地规则与二进制并存；iPhone 不内置 Mihomo/sing-box 编译器，内置快照更新仍由发布脚本重新编译、验证和发布。
- 上游 `ACL4SSR/Clash/mrs` 的当前 domain 文件不能直接复用：用 Mihomo 解包可见它保留了 `domain-suffix,example.com` 这类 classical 前缀，但 `behavior: domain` 会把整串当成域名键，已知后缀的实际请求会落到 `MATCH`。因此使用带固定 ACL 提交路径、源/产物哈希的 Tower 衍生二进制，不盲目改上游 URL 后缀。
- MRS 的首要范围仍是手机 Stash 和 Clash/Mihomo，Stash 需要 3.1.0 或更新版本。独立的 sing-box MT 现已接入同一套可验证发布链：32 个 source-format v2 SRS 覆盖 10,820 条域名、关键词和 CIDR 规则，27 条无法无损转换的 `PROCESS-NAME` / `URL-REGEX` 等继续走原有兼容过滤或内联生成。
- SRS 使用可长期访问的 HTTPS 地址，并在配置中声明 `type: remote` / `format: binary`；不能使用用户示例里的 `type: local` / `path`，因为 Tower 与 sing-box MT 位于不同 App 沙盒。正式清单必须指向产物提交的不可变 Raw commit URL；客户端直接下载二进制，App 本身无法在下载后强制核对 artifact SHA，所以全量远程 SHA 回读是发布硬门禁。
- 当前只对独立的 sing-box MT 开启 SRS。远程规则集配置明确声明 sing-box 1.14+ 的 Go HTTP client 及 `route.default_http_client`，不使用 iOS 上内存开销更高的 Apple engine，也不依赖 1.16 将移除的隐式下载器。Hiddify 虽然使用相近的 sing-box JSON 方言，但其内置核心版本与远程二进制规则集兼容性尚未单独验收，因此保持原有 source JSON 或内联路径。
- 当前快照生成 45 个 MRS 与 32 个 SRS，manifest、源文件和 77 个二进制产物已逐项核对 SHA-256、条数及孤儿文件；正式版 Xcode 26.6 的 iPhone 17 Pro 模拟器全量测试为 882 通过、0 失败、2 个平台条件跳过，Python 生成器测试为 20/20。MRS/SRS 不进入 App bundle：产物已先推送到不可变提交 `a908d7052ce932b449a7f6d8058d25e9814e605b`，正式 manifest 的 77 个 Raw commit URL 已全部远程回读并通过 SHA-256 核验。以后更新快照仍必须保持“先发布产物、再绑定 manifest、最后全量回读”的顺序；无 `artifactCommit` 的预备清单会在 App 内安全回退到文本规则。
- 同一源码已在 MacBook Air M2 上用正式版 Xcode 26.6 完成 Debug 自动签名，并覆盖安装、启动到连接的 iPhone 17 Pro；安装包版本仍为 `1.0.5 (38)`，未为这次本地验证递增发布 build。

### 2026-08-31：新增 sing-box MT 导出

- `ClientTarget.singBox` 作为独立 App Store 客户端加入导出目标，显示名为 `sing-box MT`，使用当前 App Store 图标资源 `ClientSingBox`。引入时的旧快照会只迁移一次 sing-box 的位置并保留其他客户端相对顺序，写入迁移版本后，用户后续主动拖动的位置继续保留；当前新安装默认位置以上方 2026-09-02 的顺序为准。
- 完整配置复用经过测试的 sing-box JSON 生成器；它与 Hiddify 共用文档方言，但协议矩阵独立：不写 ShadowsocksR，Snell 只接受 v4 及以上。
- 一键导入遵循上游客户端的 `sing-box://import-remote-profile?url=…#名称` 远程配置入口。塔台仍只提供 45 秒的 `127.0.0.1` 临时地址，不上传配置。
- LAN 显式 `target=sing-box` 现在直接映射到 `.singBox`，不再借用 `.hiddify` 身份。

### 2026-08-31：Clash / Stash 保留导入方案的 GEOSITE

- subconverter ini 中的 `ruleset=组名,[]GEOSITE,CN` 原本能被 `RuleSchemeParser` 正确解析，但生成阶段复用了不含 `GEOSITE` 的通用规则白名单，导致 Clash YAML 静默漏掉该规则。
- Mihomo 与 Stash 都有原生 `GEOSITE` 规则类型；现在两个 Clash 目标会原样保留，远程 classical rule-set 的兼容检查也同步放行。Surge、QuanX 等没有对应语法的目标仍会跳过，避免整份配置被拒绝。

### 2026-09-01：修复 sing-box MT 解析成功但无法联网

- 真机服务日志没有 Shadowsocks 认证、握手或超时错误；TUN 正常启动且 DNS 持续返回结果。实际问题是导出的 `dns.final` 固定为 `local`，`remote` DoH 从未使用，运营商解析可返回污染地址，随后代理会正常连接到错误目标。
- `remote` typed DoH 现在通过配置中真实存在的默认代理 selector `detour`，并成为有代理节点时的默认解析器；`local` 仅保留给 `route.default_domain_resolver` 解析代理服务器域名，避免远程 DNS 依赖一个尚未解析的代理形成递归。没有代理节点的空配置仍回退本地解析。
- DNS 开启 `reverse_mapping` 保存回答中的 IP→域名关系；两条 sing-box 生成路径还会在业务规则前加入非终止 `sniff`，并用协议或 53 端口匹配 DNS 后执行 `hijack-dns`。因此 TUN 中只有 IP 的连接可优先还原 DNS 域名，未命中映射时再从 HTTP Host、TLS SNI 或 QUIC SNI 恢复域名，最后按方案里的域名规则分流。
- App Store iOS 版不支持 `process_name`。旧配置把 `PROCESS-NAME` 与同一策略的域名/IP 聚合到一条规则，既产生大量 `Not implemented`，又因跨字段 AND 语义使整条规则无法命中；Hiddify / sing-box MT 的本地规则映射现在忽略该类型，其他域名规则继续保留。
- `SingBoxGenerationTests` 覆盖内置与导入方案的 DNS detour、resolver 分工、路由前置动作、进程规则过滤和同组域名规则保留。远程 sing-box source JSON 规则集由客户端原样下载，若上游自身含 `process_name`，塔台无法在不改写远程资源的前提下过滤，这是当前边界。

### 2026-09-01：修复部分 VLESS WebSocket TLS 节点缺少 CDN Host

- 部分订阅不会把 WebSocket Host 放在标准 `host` 字段，而是使用 Shadowrocket 风格的 `obfsParam`，或只提供可用于 TLS 的 SNI。旧实现因此会把空 Host 写进 Loon、Shadowrocket 等目标，节点导入成功但无法完成 CDN 握手。
- 订阅解析器先把可解析的 `obfsParam` 还原到标准 Host；`ProxyNode.exportableTransportHost` 再按显式 Host → 符合窄条件的非 IP SNI 回退，并拒绝把普通参数或 IP 字面量误当成 HTTP Host。完整配置生成和节点分享共用这一结果。
- `VLESSWebSocketHostTests` 覆盖 URI、Clash YAML、Loon、Shadowrocket、Surge、QuanX、Clash、sing-box、Egern 与分享链接，避免不同导出路径再次产生不一致。

当前代码版本为 `1.0.6 (40)`，Bundle ID 为 `com.jzb.tower`；已于 2026-09-04 在出门使用的 MacBook Air M2 上用正式版 Xcode 完成 Release 自动签名、本机归档和上传，App Store Connect 返回 `Uploaded package is processing` 与 `Upload succeeded`。`1.0.5 (39)` 因 1.0.5 已获批、对应预发布通道关闭而被拒绝，因此 build 39 改用 1.0.6。首次上传 build 38 时的 `Failed to Use Accounts` 则是这份正式版 Xcode 当时没有登录 Apple Account；登录后复用同一归档即成功，不是证书、描述文件或用户角色问题。家中 Mac mini M4 的 Xcode Beta 只负责开发调试，家中另一台使用正式版 Xcode 的 Mac mini M2 仍是固定发布机；Air 出门时也可以发布。

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
- QuanX 的全节点 `url-latency-benchmark` 直接列出解析后的代理节点（与 subconverter 一致），不用会匹配 `direct` 的 `server-tag-regex=.*`；地区过滤组仍用精确 `server-tag-regex`。
- 导入只接受 HTTPS；规则列表按 6 个一批下载，存到 Application Support 并用完整文件保护；删除方案会一并清掉它下载的列表。
- `AppSnapshot.importedSchemes` 是 Optional——Swift 合成的解码器不会对缺失键套用默认值，改成非可选会让旧存档解不出来。
- `AppSnapshot.selectedRuleGroups` 和 `customRuleFlows` 同样保持 Optional，旧存档解码后分别回到“完整沿用上游”和“没有自定义规则”。
- 服务分组选择只过滤拥有非 `FINAL` 规则的组；生成前从剩余规则与自定义流向递归保留引用到的基础组，并始终保留末尾兜底。
- `CustomRuleFlow` 不写入 `RuleScheme`。刷新远程方案时只更新下载缓存和时间戳，因此用户的 Tailscale 等规则不会丢失。

### 规则集优先生成（2026-08-09）

设置页提供“优先使用规则集”，默认关闭。`preferRuleSetsWasExplicitlySet` 用于迁移此前短暂存在的隐式开启值：升级后先恢复关闭，只有用户手动开启才会持续保存。`RuleSetEmissionPlanner` 会检查每个下载资源的已缓存原文与解析结果，再决定是远程引用还是本地内联：

| 客户端 | 兼容时的生成方式 | 不兼容时 |
| --- | --- | --- |
| Clash / Stash | ACL4SSR 精确域名/后缀和 CIDR 使用 Tower 生成的 `format: mrs`；残余类型内联；其他 Clash Provider YAML 使用 `format: yaml` | 清单校验失败或无兼容二进制时回落本地映射 |
| Surge / Shadowrocket | URL `RULE-SET` | 本地映射 |
| Loon | `[Remote Rule]` | 本地映射 |
| Quantumult X | 原生 `[filter_remote]` 资源 | 本地转换为 QX filter |
| Hiddify | 原生 sing-box source JSON `route.rule_set` | 本地 JSON 路由规则 |
| sing-box MT | 内置 ACL4SSR 优先引用经校验的 source-format v2 SRS；原生 sing-box source JSON 仍按 source 引用 | 本地 JSON 路由规则 |
| Egern | 原生 rule-set YAML | 本地 YAML 规则 |

不要改成“只看 URL 后缀”：`.list` 可能是 Clash、Surge 或 QuanX 的不同方言；`.yaml` 也可能是带 `payload:` 包装的 Clash Provider。后者只允许 Clash/Stash 远程引用，Surge、Shadowrocket、Loon 和 QuanX 必须内联解析后的规则。盲目引用会使整份配置被客户端拒绝。`RuleSetGenerationTests` 用七种合成资源、Clash Provider YAML 和随 App 打包的 ACL4SSR 快照同时回归这个边界。

### 资源命名（不要改）

`Tower/Resources/ACL4SSR/` 下所有文件带 `ACL4SSR_` 前缀。Xcode 会把资源拍平到 bundle 根目录；保留前缀可稳定识别来源，`RuleRepository` 也靠这个前缀跳过它们。

### 验证状态

- 模拟器（iPhone 17 Pro，iOS 26.5）：418 个测试通过，1 个按平台跳过（数据保护只能在真机验证）；结果包为 `~/Library/Developer/Xcode/DerivedData/Tower-*/Logs/Test/Test-Tower-2026.08.09_23-15-02-+0800.xcresult`。
- 真机 iPhone 17 Pro：已签名安装并启动成功。

### 真机安装

当前出门使用的 MacBook Air M2，其开发、签名、安装和启动统一使用正式版 Xcode。不要依赖或切换 `xcode-select`；先显式固定工具链，再运行后续命令：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

如果命令行提示没有账号或团队，先确认 `xcodebuild -version` 来自 MacBook Air 的正式版 Xcode，再检查这份 Xcode 的账号状态。下面的 `xcodebuild` 和 `xcrun devicectl` 必须在同一个 `DEVELOPER_DIR` 环境中执行。

MacBook Air 的正式版 Xcode 已登录开发账号，无需重复登录；优先使用自动签名。新版 Xcode 管理的开发描述文件位于
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`；旧版才可能使用 `~/Library/MobileDevice/Provisioning Profiles/`。本机已有一份仍然有效的开发描述文件：

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

Hiddify 是 Flutter 外壳 + `hiddify-core`（sing-box 内核），吃 sing-box JSON。2026-08-31 起，App Store 上的 sing-box MT 也作为独立目标使用同一文档方言；两者仍保留不同的客户端身份、导入 Scheme 和协议能力矩阵。

JSON 用 `JSONSerialization` 构建而非拼字符串——节点名是机场可控的不可信输入，交给编码器转义。几个格式决定：拒绝从 1.11 起是路由动作（`action: reject`），选择器没有可指的出站，所以拦截类策略不生成组、规则直接带动作；Clash 的四个隐藏别名组在 sing-box 里没有 hidden 概念但仍需存在，否则悬空引用导致起不来。Snell 在 Hiddify 上不可用——sing-box 这个项目实现了它，但 Hiddify 打包的内核没有，所以那些节点跳过并计数（真机验证得出，不是从 sing-box 文档推断的）。

Egern 也已支持（含 `egern:/profiles/new` 一键导入，注意是**单**斜杠、没有 authority 段；Hiddify 的 `hiddify://install-config` 反过来必须有 authority，其解析器遇到 `!uri.hasAuthority` 直接返回 nil。两种形式都有测试钉住，别互相“修正”）：三段都是单键映射的列表（`- shadowsocks:` / `- select:` / `- domain_suffix:`），策略组用 `select` 和 `auto_test`，规则每条一个 `match`，兜底是 `- default:`。字段是 snake_case（`user_id`、`udp_relay`、`skip_tls_verify`、`obfs_host`），Shadowsocks 的 cipher 要去掉 `-ietf` 中缀。

### 其他

- 首页机场开关改用规则页那个圆形对勾（`CheckmarkToggleStyle`），并补上选择震动。
- Snell 的图标之前写的是 `shell.fill`，SF Symbols 里没有这个符号——`Image(systemName:)` 遇到未知名字既不崩溃也不报错，只画空白。改为 `s.square.fill`，并加测试断言所有符号确实存在。
- 地图上方有 54pt 的“测试全部节点”主按钮和测速方式菜单；逐节点重测仍在展开后的节点详情里。
- 订阅套餐流量：按 `subscription-userinfo` 响应头 → 内容里的 `STATUS=` 行 → 节点列表公告行取值。节点始终以订阅原地址返回体为准，`flag=clash` 只在缺结构化配额时补发一次且只读响应头——机场的 Clash 转换器会丢掉它表达不了的协议（实测少 12 个 AnyTLS 节点）。

## 1.5 2026-08-10 协议补齐与首启引导

### 2026-08-12 P0 / P1 修复（build 17）

- **iCloud 冲突**：从磁盘恢复快照时同步恢复 `updatedAt`，旧云端副本不会再因为本机时间戳退回 `.distantPast` 而覆盖新数据。
- **首启联网与隐私文案**：欢迎页出现期间不会启动自动更新或 iCloud 前台同步；欢迎页与隐私政策明确区分本机默认处理和用户主动开启的 iCloud 同步。
- **去重与 TUIC**：节点身份键纳入 TUIC/Hysteria 调优字段；TUIC v5 必须同时具备合法 UUID 和密码，旧式或不完整节点统一跳过。
- **WireGuard**：新增 URI、Mihomo 单 Peer YAML、手动添加、分享和六个目标生成器。支持 Surge、Shadowrocket 完整配置、Clash/Stash、Loon、Hiddify、Egern；QuanX 与 Shadowrocket 仅节点订阅跳过。多 Peer YAML 会拒绝并计数，不做有损压平。
- 新增回归测试覆盖云端时间戳、后台触发守卫、隐私政策、协议身份、TUIC 严格校验和 WireGuard 全链路。

### 对照 Clash Meta 协议表的结论

拿 [mihomo 的 proxies 文档](https://wiki.metacubex.one/config/proxies/) 逐项对过塔台已有的十种协议，缺的是：
tuic、hysteria（v1）、wireguard、ssh、mieru、shadowquic、masque、trusttunnel、openvpn、sudoku、tailscale。

判断标准只有一条：**目标客户端能不能忠实写出来**。写不出来就不能导入，否则等于生产一批看着正常、连不上的节点（约束 12）。

| 协议 | 能表达的目标 | 处置 |
| --- | --- | --- |
| TUIC | Surge、Shadowrocket、Clash/Stash、Egern、Hiddify（5/7） | 已补 |
| Hysteria v1 | Shadowrocket、Clash/Stash、Hiddify（3/7） | 已补 |
| WireGuard | Surge、Shadowrocket、Clash/Stash、Loon、Egern、Hiddify（缺 QuanX） | 已补；只接受完整单 Peer |
| ssh / mieru / shadowquic / masque / trusttunnel / openvpn / sudoku / tailscale | 0～1 个 | 不做 |

WireGuard 使用独立字段保存本机私钥、对端公钥、本地 IP/IPv6、预共享密钥、`reserved`、MTU、DNS、Allowed IPs 和保活间隔。URI 采用 Sub-Store 常见参数；Mihomo YAML 同时兼容旧式扁平写法与官方单 Peer `peers` 写法。`ProxyNode` 无法忠实表达多 Peer，因此这类条目明确拒绝并计数。

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

### Stash 每次导入都新建一条配置：塔台这边没有可改的地方（2026-08-10）

现象是 Stash 的配置列表里堆了一串 `08-10-214146 塔台`、`08-10-214149 塔台`，相差几秒。

先排除掉的：**名字是对的**，「塔台」就是设置里那个导出名。前面的 `MM-DD-HHMMSS` 是 Stash 自己拼的。

Stash 的 [URL Schema 文档](https://stash.wiki/en/faq/url-schema) 里 `install-config` 只有一个参数：

```
stash://install-config?url=${url-encoded}
clash://install-config?url=${url-encoded}
```

没有 `name`，也没有任何「替换已有配置」的语义。而两次导入的下载地址其实完全一样（一键导入的服务是固定端口 65172 + 持久化 token + 稳定文件名），仍然生成两条。

真机进一步确认了去重规则：**第一次导入名字是对的（`塔台`），第二次才变成 `08-10-220528 塔台`**，换一种导入方式重来也是同样的节奏。所以 Stash 是**按名字建、重名加时间戳前缀**，既不认 URL 也从不更新已有配置——只要再导一次就一定多一条，塔台无论怎么写都改变不了。

用户的用法是：Stash 里只留一条，需要新配置时删掉旧的再导，或者接受多出来的那几条。

试过一版「给本机客户端一个常驻的稳定订阅地址（127.0.0.1 固定端口），导入一次之后靠 Stash 自己的更新按钮刷新」，代码能跑、测试也过，但按用户要求整个撤掉了——导出页保持只有一键导入。要是以后再有人提这个想法，先去看这段：可行，但会在导出页多两个入口、并且让局域网订阅多一个常驻监听，用户不要这个复杂度。

### 首页「地区」数字来回跳的原因不是动画（2026-08-10）

现象是 50 → 64 →回落到 60。第一反应会去查 `MetricPill` 的弹簧，但那里 `dampingFraction` 是 1，临界阻尼不会过冲——**数字真的到过 64**。

`coveredCountryCount` 原来是这么算的：

```swift
nodeIPCountryCodes[node.id] ?? NodeRegionResolver.countryCode(for: node)
```

IP 在前、名字在后，正好和约束 19 反着。IP 查询是异步的，所以每落地一个结果就**顶掉**名字已经定好的国家，集合里的元素在解析过程中反复增删，数字自然先冲高再回落。地图（`NodeMapOverview`）用的是名字优先，筛选器（`NodeFilterView`）跟统计一样是 IP 优先——三处两种顺序，也正是约束 19 说的「不要让两边给出不同的国家」。

改成 `AppModel.countryCode(for:)` 一个入口，名字优先、IP 兜底，三处全部走它。数字现在只会随着「名字看不出来的节点」拿到 IP 结果而单调增长，不会冲高回落。

以后再看到界面数字抖动，先确认数据本身抖不抖，再去怀疑动画。

### 手动添加：协议列表要和客户端支持对齐

手动添加原来漏了 TUIC 和 Hysteria 1。补的时候顺带把几件事定下来：

- `secret` 的含义统一为「协议的身份」——有 UUID 的填 UUID，没有的填密码/PSK。TUIC 是唯一两者都要的，多出来的密码放在新的 `password` 字段。
- Hysteria 1 的上下行带宽在表单里是必填，默认 50/100。它按带宽控速，填 0 或留空不是「不限速」而是不能用。
- TUIC 的拥塞控制和 UDP 中继给了独立字段（`congestionControl` / `udpRelayMode`），没有挪用 `protocolParam` / `flow`——那两个字段有各自的协议含义，借用会在编辑已有节点时把值写串。
- 「添加」按钮以前只看服务器和端口填没填，协议自己的必填项要等点下去才抛错。改成 `isMissingRequiredCredential` 提前判断，错误在点之前就体现为按钮不可用。

`ManualNodeDraftTests.testEveryProtocolAtLeastOneClientCanWriteIsOffered` 断言手动添加的协议集合恒等于「至少一个目标客户端能写出来的协议」集合，以后再加协议时忘了这里会直接挂测试。

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

### Clash YAML：双引号标量里的转义没有解码（2026-08-10）

有机场的 YAML 是序列化器生成的，非 ASCII 一律写成转义：

```yaml
- name: "\U0001F1ED\U0001F1F0 香港 01"
```

`parseYAMLPair` 只把引号 trim 掉，从不解码，于是节点名字就是那串转义文本本身——列表里显示成 `\U0001F1ED\U0...`，生成的每一份配置里也是这个。

修法是新增 `yamlScalar(_:)`：双引号标量走 `decodeYAMLEscapes`（`\xXX` / `\uXXXX` / `\UXXXXXXXX` 以及 `\n` `\t` 这些，并把 `\uD83C\uDDED` 这种代理对合并成一个码点）；单引号标量**不能**走同一条路，YAML 里单引号内的反斜杠就是反斜杠、`''` 是唯一的转义，解码它只会把名字改坏。上一条修的嵌套序列元素也共用这个函数。

顺带一提这个 bug 的连带影响：地区识别是「名字优先」的，名字里的国旗没解码出来就只能回退查离线 IP 库，所以地区可能对、也可能不对，但一定绕了远路。

### 设置页的「安全与开源」

引导页只出现一次，之后想核对它的说法就没地方看了，所以设置页底部放一条可点的小行进去，点开是同样四条。做成一行而不是第五张整宽卡片：这是需要时才查的说明，不是每次进设置都要看的开关。两处共用 `WelcomeView.promises` 和 `PromiseRow`——隐私声明在两个地方说得不一样，比只说一次更糟。

### 设置页的「重置所有配置」

设置页最底部提供破坏性的“重置所有配置”。执行前必须用居中的 alert 明确确认；确认后清空本机订阅、自建节点、规则导入与自定义、导出偏好、测速和地区缓存，停止局域网共享并更换访问密钥，关闭续费提醒和本机 iCloud 同步，最后持久化为首次安装的默认状态。设置页里正在编辑的配置名称也要同时恢复为“塔台”，避免点“完成”时把旧草稿重新写回。

重置只处理这台设备，不删除 iCloud 上的远端副本，也不撤销通知或本地网络等系统权限。前者可能仍被另一台设备使用，后两者只能由系统设置管理；确认文案必须把这些边界说清楚。删除 iCloud 副本仍由 iCloud 设置卡片里的独立操作负责。

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


## 1.6 上架前审核（2026-08-10）

### 隐私清单 `Tower/PrivacyInfo.xcprivacy`

之前完全没有这个文件。Apple 从 2024-05 起强制要求，缺了会在上传后收到 ITMS-91053 并被退回。

清单本身不被 App 读取，所以**它过期不会有任何症状**——不会崩、不会报错，只会在几周后变成一封审核邮件。`PrivacyManifestTests` 因此不只是校验字段，还会扫 `Tower/` 下所有 Swift 源码里的必需理由 API 符号，发现有用到但没声明的直接挂测试。

塔台实际用到三类，逐条对应真实调用点：

| 类别 | 理由码 | 调用点 |
| --- | --- | --- |
| `UserDefaults` | `CA92.1` | `DirectImportAccessTokenStore`、`LANSubscriptionAccessTokenStore`、`@AppStorage("hasSeenWelcome")` |
| `FileTimestamp` | `C617.1` | `ExportFileService.purge(in:olderThan:now:)` 读导出目录里文件的修改时间，清理过期临时文件 |
| `SystemBootTime` | `35F9.1` | `NodeLatencyService` 用 `ProcessInfo.processInfo.systemUptime` 差值算延迟 |

只声明 `UserDefaults` 是不够的——后两个是审的时候翻源码才发现的，漏掉照样退回。

`NSPrivacyTracking = false`、`NSPrivacyTrackingDomains` 和 `NSPrivacyCollectedDataTypes` 都是空的：塔台一条数据都不收集，这和引导页那四条承诺是同一件事，只是换成 Apple 的格式再声明一遍。

### ATS：`NSAllowsArbitraryLoads` 必须保留，不要「整理」掉

`Tower/Info.plist` 里的全局 ATS 例外看着很粗，但在保留 HTTP 订阅支持的前提下**没有更窄的写法**：

- 用户填的订阅地址是任意主机，无法预先列进 `NSExceptionDomains`。
- `NSAllowsArbitraryLoadsInWebContent` 只作用于 WebView，塔台不用 WebView。
- **`NSAllowsLocalNetworking` 不能加**。iOS 10 以上只要同时出现这两个键，系统就会**忽略** `NSAllowsArbitraryLoads` 只认 `NSAllowsLocalNetworking`。塔台最低 iOS 17，加上去等于当场关掉 HTTP 订阅支持。这是最容易被当成「顺手收紧一下」而写坏的地方。

塔台自己的三个本地监听（127.0.0.1 的一键导入 65172、局域网订阅 65171）也是明文 HTTP，同样依赖这个例外。

#### App Review 备注可以直接用这段

> 塔台是本地的订阅转换工具，不含任何服务端。需要明文 HTTP 有两个原因：
> 一、用户输入的机场订阅地址由用户自己提供，其中一部分机场只提供 HTTP，主机名无法预先枚举成 ATS 例外域名；添加界面会明确提示 HTTP 订阅以明文传输。
> 二、把转换结果交给同机的代理客户端（Surge、Stash、Shadowrocket 等）时，配置通过仅绑定 127.0.0.1、45 秒后自动失效的本地 HTTP 服务传递，不经过任何网络。
> App 不收集、不上传任何用户数据，订阅内容与生成的配置只在设备本机处理。

如果哪天决定只收 HTTPS，那时才可以把 `NSAllowsArbitraryLoads` 换成 `NSAllowsLocalNetworking`，两件事必须一起做。

### 1.0 只发 iPhone

工程原本是 `TARGETED_DEVICE_FAMILY = "1,2"`，也就是**声称支持 iPad**——但代码里一处 iPad 适配都没有：没有 `horizontalSizeClass`、没有 `NavigationSplitView`、没有任何 idiom 判断。

在 iPad Pro 13" 上实际跑过：内容挤在屏幕上方 40%，下面一大片空白，而且引导页顶部有一处「开始使用」文字错位（iPhone 上不出现，是 regular size class 才有的问题）。

这个状态下声称支持 iPad 有两个代价：iPad 截图变成必填，以及 Guideline 2.4.1 / 4.0 的拒审风险——审核员是会在 iPad 上测的。

已改为 `"1"`，并删掉了随之失效的 `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`。

方向上这也是可逆的那一边：以后加 iPad 支持是新增功能，撤掉已发布的 iPad 支持是砍功能。真要做的话不是改一行——至少要把三个 Tab 换成 `NavigationSplitView` 侧栏、地图和节点列表分栏、固定的 26pt 边距改成随宽度自适应，顺带修掉上面那处错位。

### 这次没能覆盖的

代码层面审完了，下面这些只有真机能确认，发版前建议逐项过一遍：七种客户端的实际导入（这一轮动了 QuanX 模块顺序、Hysteria 2 obfs、YAML 转义解码）、TUIC 与 Hysteria 1 能否真正连通、ICMP 测速与点阵地图、以及引导页在小屏和大字号下的排版。

## 1.7 DNS 默认值（2026-08-11）

TestFlight 反馈提到「配置没有防 DNS 泄漏功能」。核对下来比反馈说得更糟：**Surge / Shadowrocket / Loon 三家写的是 `dns-server = system, …`**——`system` 不是「没配」，是明确要求优先使用运营商解析器，比留空还差。Clash/Stash 和 Egern 则完全没有 DNS 段。只有 Hiddify（sing-box 的 schema 逼着你声明 servers 和 detour）是对的。

### 为什么客户端必须自己做 DNS

规则按域名匹配，但连接到达时往往只剩 IP——域名早被系统解析掉了，那次解析既泄漏了查询、又可能拿回污染结果。所以 `dns:` 块不是可选优化，是分流能否成立的前提。

`fake-ip` 是「防泄漏」的实际机制：客户端立刻返回保留段里的假地址并记下映射，流量到达时反查回域名再匹配规则，**真实解析交给节点那一侧完成**——本地从来没发出过那个查询。代价是假地址对需要真 IP 的场景无效，所以 `fake-ip-filter` 要放行局域网和探测类域名。

### 三条互相独立、缺一漏一段

1. **`nameserver` 列表内不能混明文。** mihomo 对列表里所有解析器**并发查询**取最快，所以一条明文会把整列表的加密配置作废——查询照样以明文发出去了。`fallback` 同理：`fallback-filter` 只决定采用哪个结果，不阻止发出。因此通用列表全部用 DoH，明文只允许出现在 `default-nameserver`（它只解析 DoH 服务商自己的域名，泄漏的信息仅是「在用 DoH」）。
2. **`proxy-server-nameserver` 必须写。** 解析节点域名不能走节点本身。开了 fake-ip 又漏了这条，节点域名会被答成假地址，结果是全盘连不上——这是唯一一个把 DNS 改进变成彻底断网的错误。
3. **IP 类规则要避免触发额外解析。** 支持 `no-resolve` 的客户端应在 IP/GEOIP 规则上带该参数，否则引擎可能为了判断规则而先在本地解析域名。Quantumult X 不支持这个参数；其官方方案是在 `final` 前放置同策略的 `host-keyword, .`，让未被前面域名规则命中的主机名直接进入兜底策略，纯 IP 请求则继续匹配 `final`。Clash、Surge、Loon 使用 `no-resolve`，Egern 使用 `no_resolve: true`，QX 使用上述 host 兜底。

### 这次改了什么

| 目标 | 改动 |
| --- | --- |
| Clash / Stash | 新增完整 `dns:` 块：fake-ip + 全加密 `nameserver`/`fallback` + `proxy-server-nameserver` + `fallback-filter` 按 GeoIP 分流 |
| Surge | 去掉 `system`，补 `encrypted-dns-server`（字段名有官方文档佐证） |
| Shadowrocket / Loon | **只**去掉 `system`。两家的加密 DNS 字段名没有可靠出处，不猜——这个项目在客户端字段名上猜错过不止一次 |
| Quantumult X | 保留 `no-system`；删除无效的 `no-resolve`，在 `final` 前增加同策略的 `host-keyword, .` |
| Egern | 补 `no_resolve: true` |
| Hiddify | 不动，原本就对 |

用 `fallback-filter` 的 GeoIP 判断而不是 `geosite:cn`，是因为后者要客户端运行时去拉 geosite 数据——和塔台自包含、不依赖运行时下载的立场冲突。

### 还没做的

机场订阅自带的 `dns:` 块目前仍被丢弃。[PR #5](https://github.com/pengchujin/tower/pull/5) 做的是这件事，和本节是正交的两件事：本节管「机场没给时塔台自己给」，PR 管「机场给了就转过去」。该 PR 基于旧 main，已冲突，且会与本次改动重叠（它有两条断言 `dns-server = system` 存在的测试，rebase 时要一并删除）。

真机未验证：各客户端对新 DNS 段的接受情况，尤其 Surge 的 `encrypted-dns-server` 和 Clash 的 fake-ip 是否影响节点连通。

### DNS 保护档位（2026-08-28）

规则方案的“DNS 与网络”页新增三档保护，保存在当前 `RuleScheme` 的本地定制中，不修改订阅、上游规则文件或其他规则方案。旧存档没有该字段时迁移为“标准保护”，所以升级不会改变既有输出。

| 档位 | 生成行为 |
| --- | --- |
| 跟随方案 | 保留用户填写的普通／加密 DNS，不额外启用 Clash Fake-IP、fallback 或 DNS 接管 |
| 标准保护 | 保持此前的默认输出：加密 DNS、Fake-IP、节点域名专用解析，以及各客户端支持的 DNS 短路写法；QX 使用 `host-keyword, .` 而不是 `no-resolve` |
| 严格保护 | 在标准保护上，仅为已确认支持的 Clash 增加 TUN `dns-hijack` / `strict-route`，并为 Surge 增加 `hijack-dns = *:53` / `encrypted-dns-follow-outbound-mode = true` |

严格保护没有推广到 Stash、Shadowrocket 或其他客户端，因为这些客户端的等价字段和副作用尚未逐项验证。它可能影响局域网、公共网络认证，以及服务器地址本身是域名的代理节点；界面会在选择时显示风险提示。

## 1.8 Mac 上的局域网共享（2026-08-12，未验证）

塔台当时以 "Designed for iPhone" 出现在 Apple 芯片 Mac 上。工程现已恢复 iPhone + iPad 通用支持（`TARGETED_DEVICE_FAMILY = "1,2"`），Mac 可用性仍是 App Store Connect 里的单独开关。用户曾报告：Mac 上装得上，但局域网共享给出的链接打不开。

### 两个已定位的原因

1. **沙盒缺入站权限。** iOS App 在 Mac 上跑在 macOS 沙盒里，接受入站连接需要 `com.apple.security.network.server`。`Tower/Tower.entitlements` 原来只有 iCloud 三个键。这个键在 iOS 上完全没有作用（iOS 由系统自动沙盒化），所以 iPhone 上再怎么测都不会暴露它缺失——`RepositoryConsistencyTests` 里加了一条针对 checkout 的断言看着它。
2. **监听接口写死成 Wi-Fi。** `requiredInterfaceType = .wifi` 在 iPhone 上是防止监听落到蜂窝的安全栏，在走网线的 Mac 上则匹配不到任何接口。已改为 `LANSubscriptionListenerEnvironment.networkListening(pinnedToWiFi:)`，由 `ProcessInfo.processInfo.isiOSAppOnMac` 在运行时决定。

注意 "Designed for iPhone" **不是 Mac Catalyst**，是同一个 iOS 二进制跑在 macOS 沙盒下，编译期分不出平台，只能运行时判断。

顺带把地址查找改名为 `LANIPv4Address.currentLANAddress`（Mac 上它返回的通常是以太网地址），失败文案也从「请先连接 Wi-Fi」改成「请先接入 Wi-Fi 或有线网络」，否则走网线的 Mac 用户会照着错误提示去找一个不存在的故障。

### 2026-08-12 真机验证：通了

在 Mac 上实测局域网共享**可用**。这回答了改动时那个没有把握的问题：**"Designed for iPhone" 的 App 允许监听入站连接**，前提是带上 `com.apple.security.network.server`。Apple 文档两边都没写，只能靠实测——现在有答案了，不要再当作未知重新讨论。

签名也接受这个 entitlement，尽管 iOS 描述文件里没有这个键。

### 还没单独确认的

- Mac 走网线和走 Wi-Fi 是否都可用（改动本身就是为网线场景做的，但两种情况没有分别记录过结果）。
- macOS 系统设置 → 隐私与安全性 → 本地网络 里塔台的授权状态。功能既然通了，说明授权要么自动给了、要么这条路径不需要它。

### Mac 可用性开关

功能已验证，可以在 App Store Connect 打开「在 Apple 芯片 Mac 上提供」。打开之后 Mac 就是要长期维护的第二个平台：它的网络环境比 iPhone 复杂（多网卡、雷雳网桥、VPN 虚拟网卡），`LANIPv4Address` 里 en0 优先的排序在 Mac 上不保证挑对接口，这是后续最可能出问题的地方。

## 1.9 2026-08-21 代码审查修复

第二次完整代码审查后的修复，全部带回归测试（`ReviewFixTests` 新增 12 条，另有若干既有测试按新形状更新）。审查范围是数据逻辑、操作逻辑和流畅度；AppModel 拆分与信息架构调整属于产品决策，本轮明确不做。

### 数据逻辑

| 问题 | 影响 | 修复 |
| --- | --- | --- |
| `apply()` 不恢复 `lastLocalEditAt` | 启动后 `lastLocalEditAt` 为 nil，前台同步用 `.distantPast` 比对，**任何**远端快照都会赢——包括更旧的那份，随后覆盖本地文件。离线时改的订阅在下次启动被静默丢弃 | `apply()` 恢复 `snapshot.updatedAt`；同时清掉属于已替换节点 id 的测速与地区缓存 |
| 批量添加订阅时一条失败即整批作废 | 粘 5 条第 3 条 404，一条都加不进去 | 逐条判定；成功的入库，失败的走既有 `SubscriptionRefreshReport` 列出。全失败仍抛错以留住添加面板；显式取消则整批放弃 |
| 刷新后排除状态按 `kind\|server\|port\|name\|rawURI` 匹配 | 机场把剩余流量/倍率写进 remark，塔台自己也会给纯国旗节点重编号——名字一变即失配，被排除的节点**静默回到每一份导出配置** | `carriedOverExclusions`：先精确匹配，失配再用去掉 remark 的宽松键，且**只有该键在刷新前后都唯一时才认**，避免反向误排除 |
| 配额探测与主请求并发打同一 host | 抵消了 `subscriptionIDsGroupedByHost` 按 host 排队的防限流设计，单个订阅即产生 2 个并发请求 | 改为「确实缺配额时才发、且在主请求之后」 |
| iCloud 副本无法删除 | `CloudSyncStore.removeRemoteSnapshot()` 从无调用方，设置页却明说「关闭同步不会删除已有副本」，上传成了单向门 | 关闭同步时提供「关闭并删除 iCloud 副本 / 只关闭同步」；关闭后设置页保留独立删除入口 |
| IP 地区解析结果不落盘 | 每次冷启动都要为所有「名字看不出地区」的节点重跑 `getaddrinfo` | 按 **host** 持久化（不是节点 id——id 每次解析都重新生成）；随快照按当前节点剪枝 |

### 流畅度

| 问题 | 影响 | 修复 |
| --- | --- | --- |
| `RuleDownloadStore` 每次调用都重读并重切文件 | 规则页对每个方案的每个规则集、每帧都走一遍。ACL4SSR 一套约 430 KB，单文件最大 191 KB。**内置快照有缓存，下载的方案完全没有** | 加按 mtime + size 失效的解析缓存；`isClashProviderYAML` 复用同一份，不再为判类型二次读盘 |
| 仅节点模式先生成完整配置再丢弃 | 四个支持该模式的客户端，每帧付两笔；且节点订阅自身从不缓存 | `contentMode` 进缓存键，仅节点走独立轻量路径 |
| `persist()` 主线程全量编码 + 落盘，每个开关调一次 | 实测 500 节点约 5 ms/次（模拟器，真机更慢），正好落在响应点击的那一帧里 | 新增 `PersistencePolicy`：App 用 250 ms 合并写，退到后台强制 flush。**默认仍是 `.immediate`**，测试语义不变 |
| 地图卡片每帧做 5 遍全量聚类 | 地区解析按 8 个一批 merge，每批触发 5 遍全表聚类 | body 内算一次传下去 |
| 节点筛选页每帧过滤 5 遍 | 每次求值都解析显示名并做 4 次不区分大小写搜索，搜索框输入可感延迟 | 同上 |
| 折叠的订阅卡片仍复制整个节点数组 | 每帧为每个卡片复制其全部节点（含各 String 字段） | 折叠时只用 `nodeCount(for:)` 计数 |
| 每个 HTTP 请求新建 `URLSession` | 连接与 TLS 会话不复用，刷新 10 个订阅即 10 次完整握手 | 共享一个 ephemeral session；顺带彻底关闭 cookie 处理 |
| 逐行 DNS 请求各自成「一批」 | 并发 `getaddrinfo` 数等于可见行数；靠上层页面预先整体解析才没炸 | 逐行请求汇入统一队列（50 ms 合并窗口） |

### 操作逻辑

- **删除不可达的 `.rulesOnly`**。`supportedContentModes` 只返回 `[.fullConfiguration, .nodesOnly]`，`decodeExportContentModes` 还会把它过滤掉，用户永远选不到、旧存档也恢复不出来，但生产代码里留着 9 处分支和一个生成器方法。`ExportView.modeExplanation` 给它和 `.fullConfiguration` 返回同一句话，是当初就没想清楚的证据。枚举 case、生成器、分支、两个测试一并移除。
- **添加/编辑订阅的「取消」现在真的取消**。此前是脱离结构的 `Task`，面板关掉后请求继续跑完（最长 30 秒 × 多次 UA 尝试），仍会把订阅加进去并弹「已添加」。改为持有 task，取消与 `onDisappear` 都会 cancel。
- **搜索框文案**：按产品要求使用 `在线搜索规则：如 YouTube OpenAI`，并由回归测试固定，避免后续整理文案时再次误改。
- **Toast 出现有动画了**。`showToast` 直接赋值、不在任何 transaction 内，插入过渡从不运行——每条提示都是「啪」地出现再优雅滑走。改由 toast id 驱动整段动画。

### 本地化

Xcode 提取器（`xcodebuild -exportLocalizations`）比对发现 **42 条**源码能显示但目录里没有的文案，全部会在其余 14 种语言下直接显示中文。已按 15 种语言补齐（630 条译文），格式符逐条校验。

此前用 grep 手写的扫描只找到 7 条——`Text("…")`、`Label`、`.navigationTitle`、`.accessibilityHint`、`Section`、`TextField` 占位符、弹窗标题等位置全部漏掉，插值也无法还原成 `%@` / `%lld`。因此新增 `Scripts/check_localization.sh` 调用 Xcode 自己的提取器比对，**不要改回 grep 实现**。

**两个脚本的分工**：`check_localization.sh` 负责**发现**缺口（只读，跑完不改动任何文件），既有的 `generate_localizations.py` 负责**填补**（从 Xcode 导出的源目录机器翻译并生成两份目录）。README 一直记着后者的用法，缺口积到 42 条说明那一步被跳过了，而当时没有任何东西会因此报错——现在有了。

**这 42 条是手写翻译，没走生成器**，因为其中大量是 `已选` / `未选` / `好` / `候选策略` 这类短标签和无障碍文案，机器翻译在缺上下文时容易失准。后续批量补文案仍建议先跑生成器再人工过一遍短标签。

两个必须知道的坑：

- **提取器会误报「无用条目」**。它给 72 条打了 `extractionState: stale`，其中包括 `ACL4SSR 默认` / `精简` / `全分组` 及其简介——这些来自 `ACL4SSR_manifest.json`，运行时经 `String(localized: String.LocalizationValue(name))` 本地化，静态提取看不见。照着 stale 清理会把内置方案名的翻译全删掉。
- **提取会改写源文件**。`-exportLocalizations` 直接往目录里写新键、打 stale 标记，并按自己的 JSON 风格重排整个文件（`InfoPlist.xcstrings` 也会被动）。脚本已做备份/还原，跑完不留任何改动。

`LocalizationTests` 只守了 4 个 InfoPlist 键里的 3 个，`CFBundleName` 翻译齐全却无人看管——已纳入。

### 本轮明确未做

- **DoH 仍是进程级设置。** 加密解析器只能配在 `NWParameters.PrivacyContext` 上，URLSession 没有任何途径挂载；真要隔离须用 NWConnection 手写 HTTP 客户端（TLS、重定向、分块编码自理）。`SubscriptionRequestGate` 只能排开订阅请求，同时刻的规则下载、测速、地区查询仍受影响。约束已写进 `applyDNSOverHTTPS` 的注释。
- **导出页仍是同步生成、无加载态。** 改异步要给 `.task(id:)` 编一个含目标客户端、内容模式、协议过滤、节点、规则方案、配置名、`preferRuleSets` 的复合 id，漏掉任一项都会**静默导出陈旧配置**。用这个风险换开标签页时的一次卡顿不划算；仅节点缓存已让来回切换变廉价。
- **局域网共享仍在主线程生成配置。** 有缓存兜底，且该功能本就要求 App 在前台，收益不抵改动面。
- **`effectiveScheme` 未做记忆化。** 磁盘缓存修好后剩下的 `customized()` 开销与策略组数量（几十个）成正比，不再与规则行数相关；记忆化需要一个覆盖全部定制输入的失效键，算错就会用陈旧方案生成配置。
- **Toast 仍是单槽位。** 批量刷新路径已自行抑制中间提示，实际重叠场景罕见。

### 一个自我撤销

配额探测原本还加了「记住这个 host 不返回配额头」的缓存，写完发现有缺陷：一旦标记就永不再探测，`recordQuota` 再也走不到，机场之后开始发送配额头也不会恢复；且为进程级可变状态，会让测试相互污染。收益仅为每次刷新省一个请求，已移除。

## 2. 产品目标与确定的交互

### 首页

- “+”统一添加机场订阅和自有节点，提示同时覆盖订阅 URL 和节点协议链接。弹出时自动请求一次剪贴板并在识别成功后填充，同时保留手动粘贴按钮。
- 顶部统计项“订阅、节点、覆盖地区、自有节点”可滚动到对应内容。
- 订阅可展开节点，但不显示“更多节点”，展开使用透明度/布局变化，不从顶部滑入。
- 节点行显示 IP 国家/地区 Logo、名称、协议/传输/UDP 信息和真实延迟。
- 订阅和单节点都可以分享；单节点导出协议链接和二维码。
- 页面直接嵌入自绘的点阵世界地图（`WorldDotMapView`，不用 MapKit），有节点覆盖的国家直接把其地图点显示为鲜明绿色，当前选中国家用更深、更密的绿色；未覆盖国家保持灰色，不再叠加独立绿色定位点。
- 世界点阵保留完整 `-180...180` 经度；斐济、新西兰和格陵兰不会再因裁剪被压到地图边缘。地图支持缩放、拖动和分层标签，密集地区按节点数稳定取舍文字。覆盖国家的整个点阵轮廓都可直接点击，选中标签使用中性文字和材质底色，不用绿字压在绿色地图上。

### 规则页

- 默认使用内置 ACL4SSR；Self-Configuration 位于页面底部并由用户手动下载。
- 当前方案提供可搜索的服务分组勾选页；取消勾选后规则数量和全部完整配置导出立即更新。
- 自定义规则流可新增、编辑、启停和删除，带 Tailscale 示例；规则与方案分开保存，重启 App 或刷新方案后仍保留。
- 生成配置不引用远程策略组图标，只保留名称内有语义的 Emoji。
- “手动切换”“自动选择”“全球直连”等使用中文可见名称。
- 香港、日本、美国、新加坡等国家/地区策略位于业务策略之后。
- 地区组本身默认延迟优选；业务策略仍可手动选择地区组。
- 生成器必须避免地区组、节点选择和业务策略之间的循环引用。

### 导出页

- 十个目标客户端使用各自的官方 App Store 图标；横向滚动选择并支持长按拖动排序。
- 主按钮固定在标签栏上方，一次点击就通过客户端 Scheme 导入。
- Surge、Stash、Clash、Shadowrocket、Loon、Hiddify、sing-box MT 和 Egern 使用本地临时 URL；Quantumult X 使用文件分享。
- 支持配置摘要和完整预览，但不要在客户端切换动画中同步重复生成大文本。
- 摘要和完整预览按配置语义着色：注释使用次要文字，INI 分区及键、YAML 顶层分类、URL、字符串、数字分色显示，并随深浅色模式调整对比度。着色层不得改写源文或破坏选择复制。

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

`LANSubscriptionServer` 是单独的用户可控服务，不要和 `DirectImportService` 合并：前者绑定 Wi-Fi、持续到用户关闭或 App 被系统挂起，后者只绑定 `127.0.0.1` 且 45 秒自动关闭。导出页把“局域网订阅”作为客户端式目的地展示；用户选择该目的地时立即启动服务，并集中提供启停、自动/显式目标格式、带 32 位随机访问密钥的地址、二维码和使用说明，设置页不再重复提供入口。局域网目的地与所有客户端使用同一套长按拖动排序并单独持久化位置；旧快照缺少该位置字段时使用当前默认的第 3 位。它不能加入 `ClientTarget`，因为它不是一种配置格式，而是按请求方 User-Agent 或 `target=` 参数选择实际格式的传输入口。密钥可手动轮换，旧链接立即失效。

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
- QuanX 全节点自动组误用 `server-tag-regex=.*` 会把 `direct` 也加入候选；必须像 subconverter 一样直接列出代理节点。地区自动组仍使用转义后的精确 `server-tag-regex`。

## 4. 当前 TestFlight / App Store Connect 状态

### 已确认

- App 名称：塔台。
- App Store Connect App ID：`<App Store Connect App ID>`。
- Bundle ID：`com.jzb.tower`。
- SKU：`com.jzb.tower`。
- 签名 Team ID：`<TEAM_ID>`。
- 仓库与 `origin/main` 当前版本为 `1.0.6 (40)`；Air 上已有对应的有效签名归档。
- build 40 已由 Air 上传成功，Xcode 返回 `Uploaded package is processing` 与 `Upload succeeded`；后续处理完成和测试群组状态仍需在 App Store Connect 核对。

### Air 本机归档与 App Store Connect 上传是两项能力

Air 当前处于 Aqua 会话，正式版 Xcode 已登录开发账号，匹配的证书与描述文件可用。工程故意不保存 `DEVELOPMENT_TEAM`；命令行归档必须从本机忽略配置或匹配描述文件得到唯一团队，并只在进程内传入。没有显式传参时报 `Signing for Tower requires a development team`，不能据此判断账号未登录。

`1.0.5 (38)` 的自动签名、Store 校验与 `.xcarchive` 已成功，归档保存在 Air 的 `~/Builds/Tower-TestFlight-1.0.5-38-时间/`。第一次上传在 `IDEDistributionUploadAccountStep` 返回 `Failed to Use Accounts`；用户随后确认正式版 Xcode 当时没有登录 Apple Account。在 **Settings ▸ Accounts** 登录后，复用原归档上传成功。因此：

- 证书、描述文件、Bundle ID 与归档从始至终都正常。
- 账号退出后本地签名材料仍可能继续构建和归档，所以“归档成功”不能证明 Xcode 已登录。
- 相同错误先检查当前正式版 Xcode 的 **Settings ▸ Accounts**；登录后直接重试现有归档，不要重新构建。
- 账号已登录仍失败时，再检查 App Store Connect 角色、协议状态或使用家中 Mac mini M2。

### 远程 Mac 归档必须进入图形会话

SSH 登录落在 launchd 的 `Background` 域，`codesign` 取不到钥匙串私钥，必然报 `errSecInternalComponent`。解锁钥匙串要密码、切到 Aqua 会话要 sudo，都不能由自动化代劳。

这个限制只针对远程 SSH / Background 会话，不适用于当前 Air 自己的 Aqua 终端。备用 Mac mini M2 发布时，使用 `Scripts/release_testflight.sh` 让脚本切换到那台机器的 Aqua 会话；手工操作则必须在那台机器自己的终端或 Xcode Organizer 中完成。`DEVELOPER_DIR`、团队 ID 和钥匙串密码都按 `docs/RELEASING.md` 处理，不把私密值写进命令示例或仓库。

### 代码与已上传版本

工程当前为 **`1.0.6 (40)`**，`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` 已加入。`1.0.5 (39)` 因 1.0.5 预发布通道已关闭而未被接收；改为 1.0.6 后，build 39 已成功发布到预发布通道，build 40 也已由 Air 上传成功并进入 App Store Connect 处理。

### 外部测试还需要补的材料

- **App 隐私**问卷必须完成，否则构建在外部群组里不可选。塔台不收集任何数据，如实勾选即可。
- TestFlight **测试信息**：Beta App 描述、需要测试的内容、反馈邮箱、联系人。
- 外部测试需要经过 **Beta App Review**，内部测试不需要。
- 审核时容易被问用途。建议在「需要测试的内容」里写明：本 App 只在本机把订阅转换成各客户端配置文件，不含 VPN 或代理功能，不接管流量，不上传用户数据。

## 5. 备用远程 Mac mini M2 发布说明

家中另一台 Mac mini M2 是远程 TestFlight 发布机，位于同一局域网，主机为 `<用户名>@<构建机地址>`，其正式版 Xcode 已登录 Apple 开发者账号。家中的 Mac mini M4 使用 Xcode Beta 做开发调试，不承担归档上传。凭据和登录密码不写入仓库，也不应发给接手模型保存。

该机器的默认 `xcode-select` 曾指向 Command Line Tools，构建命令需要显式指定：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

运行归档前先执行 `xcodebuild -version`，确认命令来自 Mac mini M2 的正式版 Xcode。不要在 Mac mini M4 的 Xcode Beta 上执行正式归档上传。

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
发布脚本的预检会从 `security find-identity -v -p codesigning` 中接受同团队的有效 Development 或 Distribution 身份；仅有证书而没有可用私钥时会在归档前直接失败。

归档命令基线：

```sh
xcodebuild -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Tower-1.0.2-23.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  CODE_SIGN_STYLE=Automatic \
  archive
```

导出使用 `app-store-connect`、`destination=upload`、Automatic signing、Team ID `<TEAM_ID>`。本地 `.artifacts/` 中可能有归档和 IPA 备份，但已被 `.gitignore` 排除；它们不是源码交接的一部分。

每次重新上传前必须增加 `CURRENT_PROJECT_VERSION`，并以 `Tower.xcodeproj/project.pbxproj` 中的当前值为准。**设备支持编译在构建里**，改了工程不重新上传，App Store Connect 仍然会按旧构建处理；build 号复用会被 App Store Connect 直接拒收。

## 6. 优先任务

### 已修：Shadowrocket 完整配置用错了传输层键名（issue #10，2026-08-17）

**现象**：同一份订阅，Shadowrocket「仅节点」能连，「完整配置」连不上。报告人对比 Shadowrocket 自己导出的节点，差异是 `"obfs": "xhttp"`（能用）对 `"obfs": "none"`（不能用），服务端是 VLESS + XHTTP + REALITY。

**根因**：`ConfigurationGenerator.appendSurgeTransport` 里，Shadowrocket 分支写的是 `transport=<名字>`。那是 Surge / Loon 的词汇；**Shadowrocket 的 `.conf` 用 `obfs=` 表示传输层**，于是这个键被忽略，obfs 保持默认 `none`，节点被当成非 XHTTP 处理。

两路独立证据一致：手册「编写本地节点」一节把 VLESS 写成 `名称=vless,地址,端口,password=…,tls=true,obfs=websocket,peer=…`（VMess 同样是 `obfs=websocket`）；报告人贴的 Shadowrocket 导出 JSON 里字段就叫 `obfs`。后者是更硬的依据——见下面 §303 记的判据：看它自己写出来的配置，别只看手册。

**修复范围**：同一分支负责 xhttp、grpc、h2、httpupgrade，现已统一按 Shadowrocket 的完整配置语法输出 `obfs=<传输名>`，不再写会被忽略的 `transport=`。WebSocket 仍保留原有兼容写法。`TransportGenerationTests` 覆盖了四种传输，防止重新退回 `transport=`。

**两处保持不动**：

- **ws 保持现状。** 它走的是前一个分支，写 `ws=true` / `ws-path=`（Surge 词汇），从没有人报过坏。Shadowrocket 一向能吃 Surge 配置，很可能是兼容的；没有证据就改，风险是把能用的搞坏。
- **`method` 那条差异大概率是症状不是病因。** 能用的节点是 `"method": "auto"`、坏的是 `""`，但手册的 VLESS 示例里没有 `method=`，`auto` 更像 Shadowrocket 解析成功后自己填的默认值。

**验收状态**：生成语法及回归测试已通过；XHTTP 已按报告人的可用导出值修正。真机导入后的实际连通性仍以节点服务端和 Shadowrocket 当前版本为准，发布后继续观察 issue 反馈。

### 已实现：订阅展开后展示机场公告（2026-08-25）

订阅卡保持原来的紧凑收起高度；展开后，节点列表前会出现一块中性的「机场公告」区域，
完整显示机场写入订阅的重置日、官网、客服、续费提醒等自由文本。公告和节点共用原有的
展开事务，没有额外的弹出动画或材质层；长文支持自动换行与选择复制。

展示仍由 `SubscriptionUsage.distinctNotices` 驱动：已有结构化流量、到期数据时，重复的
配额/到期句子不会再显示；带「重置」「续费」「客服」等含义的可操作公告即使也出现
「流量」或「到期」字样仍会保留。相同公告只展示第一次，空白行忽略。

回归覆盖在 `SubscriptionUsageTests.testActionableAnnouncementsSurviveStructuredFactsAndAreDeduplicated`
和 `SubscriptionInteractionTests.testExpandedSubscriptionShowsDistinctAnnouncementsBeforeNodes`。

同日的订阅展开列表与地图选中地区列表统一复用 `CompactNodeRow`：保留旗帜、节点名、
协议副标题和测速结果，去掉每行的圆角底色与卡片间距，换成约 54pt 高的平铺行和
细分隔线。未测试时不再显示「待测试」；测速进行中显示进度，完成后才直接显示延迟或
不可达。节点不再提供第二层详情展开，右侧固定为 44pt 分享按钮，避免同一种节点行在
地图和订阅里表现不同。自有节点仍使用原来的可展开详情样式。
对应回归为 `SubscriptionInteractionTests.testMapAndSubscriptionReuseAStaticCompactNodeList`。

### 待修：UA 兜底重试会让机场少给节点（2026-08-12 记录）

订阅返回 403 / 406 / 421 / 426 时，`SubscriptionParser` 会依次改用伪装 UA 重试：先 `Shadowrocket/...`，再 `clash.meta`。

`clash.meta` 那一跳正对着本文档第 18 条描述的坑：机场按 Clash 转换的返回体会丢掉它表达不了的协议，实测有机场因此少 12 个 AnyTLS 节点。顺序是对的（Shadowrocket 在前，通常返回原始格式），而且只在默认 UA 被拒时才走——否则一个节点都拿不到，所以不能简单删掉。

**要解决的是「用户不知道」**：走到 `clash.meta` 那一跳时节点可能悄悄变少，界面上看不出来，用户只会觉得机场删了节点。至少要在订阅那一行标出「本次用兼容模式获取，节点可能不完整」。

顺带：`shadowrocketCompatibilityUserAgent` 里硬编码了 `CFNetwork/3892.100.1 Darwin/27.0.0`，会随系统版本过期，需要有人定期核对。

### 待样本确认、暂不修：VMess 节点名称退化为服务器域名（2026-09-01 记录）

**现象**：用户反馈某机场在旧版塔台中能显示 VMess 的节点备注，更新后同一批 VMess 只显示
`mcm-a-test.mcn-app.org`、`t.cnmjcn.cyou`、`p4.cna.linuxlh.xin` 这类服务器域名；同一订阅中的
AnyTLS、Hysteria 2 节点仍保留正常名称。这里丢失的是**节点名称**，不是国家/地区识别结果。

**已确认的代码路径**：标准 `vmess://base64(JSON)` 只从 JSON 的 `ps` 取名，空缺时以
`server` 兜底；Shadowrocket endpoint-only VMess 只读取 `remarks` 或 URI fragment，空缺时以
`address.host` 兜底。截图显示的恰好是纯 host，因此名称在进入 UI 前就已经走了订阅解析器的
兜底，不是列表 UI 或 `NodeRegionResolver` 把正常名称替换掉。后者已有统一的
`proxyNameQueryValue`，可识别 `remarks`、`remark`、`name`、`ps`、`tag` 及 URL-safe Base64，
但 legacy VMess 尚未复用它。

**高概率回归触发点**：build 23 把默认订阅 User-Agent 从 `Tower/1.0 (iOS; local subscription converter)`
改成了 Shadowrocket UA。机场可能据 UA 将原来带 JSON `ps` 的响应切换成 endpoint-only 方言；只要
连接字段仍可解析，`SubscriptionService` 就会接受该响应，不会因为名称已退化成域名而继续尝试其他 UA。
目前只有截图，尚不能判定机场是完全没发送名称，还是把名称放进了塔台未识别的 `remark/name/ps/tag`
或外层 fragment，所以不要在拿到样本前改实现。

**用户决定**：先不修，待确认反馈所用订阅。拿到来源后只在本地做脱敏验证，订阅 URL、UUID、密码、
token 不得进入文档、日志或测试夹具：

1. 对同一订阅分别使用旧 Tower UA 和当前 Shadowrocket UA，比较节点数、VMess 方言及名称字段；
2. 临时把该订阅的自定义 UA 设为旧 Tower UA 后刷新，若备注恢复即可坐实 UA 分流；
3. 从一条脱敏 VMess URI 确认名称实际位于 `ps`、`remarks/remark/name/tag` 还是外层 fragment；
4. 确认后再决定是否恢复 Tower UA 为首选、保留 Shadowrocket / `clash.meta` 兜底，并让两条 VMess
   解析路径统一复用名称解码逻辑。不要把 `clash.meta` 提到首选，以免机场转换时丢掉 AnyTLS。

### 待修：并发刷新缺上限，且索引跨 await 失效（2026-08-12 记录）

`AppModel.performRefreshAllSubscriptions` 把下拉刷新从串行改成了 `withTaskGroup` 并发。改动本身有价值——旧实现第一条失败就 `break`，后面的订阅根本不会被尝试；新实现每条都跑一次并收进 `SubscriptionRefreshReport`。三个问题：

1. **注释承诺的并发上限没有实现。** 注释写着「keeping the request burst small enough for airport panels that rate-limit a single client」，代码却是把所有 `sourceIDs` 一次性 `addTask`。它替换掉的旧注释恰好说明串行是故意的，正是为了避开机场的 burst 限流。需要一个真正的并发窗口（例如一次最多 3 条）。注释里提到的 URLSession per-host 限制是连接复用限制，不是节流，且不同机场不同 host。
2. **下拉刷新取消不掉。** `Task.detached` + `await refreshTask.value` 是为了躲开 SwiftUI 对 `.refreshable` 手势任务的取消。副作用是用户松手、切走、关页面，队列都会跑完。注意 `AppModel` 是 `@MainActor`，detached 进去马上跳回主 actor——它买到的只是「不被取消」，不是后台执行。
3. **`updateSubscription` 里的 `index` 跨 `await` 使用。** `firstIndex` 在 fetch 之前算出，`subscriptions[index].lastUpdatedAt` 在之后才写；刷新期间删掉一条订阅就会指错甚至越界。这个写法原来就有，但串行时只有一条订阅持有过期索引，现在是 N 条在整个刷新期间都持有。改成 await 之后按 `id` 重新查一次即可。

状态修改本身是安全的：`@MainActor` 把它们串行化了，并行的只有网络请求。

### 已解决：规则集为什么在 Stash 上没生效（2026-09-02）

**现象**：开了「优先使用规则集」，Surge 输出 `RULE-SET`，Stash 仍然逐条内联。

**原因**：`RuleSetEmissionPlanner.nativeFormat(for:url:lines:isClashProviderYAML:)` 给每个目标一份类型白名单，规则是**整份列表里只要有一条白名单外的类型，整份退回内联**。`clashRuleTypes` 不含 `URL-REGEX`（那是 Surge / QuanX 的概念，Clash 内核没有等价物），而内置的三份列表各夹了几条：

| 列表 | 总条数 | URL-REGEX |
| --- | --- | --- |
| `ACL4SSR_ProxyMedia.list` | 372 | **1** |
| `ACL4SSR_ChinaMedia.list` | 38 | **1** |
| `ACL4SSR_Download.list` | 22 | 7 |

判断标准没错，粒度太粗——372 条里 1 条不兼容就全部内联。

**subconverter 怎么做的**（`src/generator/config/ruleconvert.cpp`，同一套白名单，`ClashRuleTypes` 同样不含 `URL-REGEX`）：逐行循环里 `continue` 跳过那一行，**不是** `return` 掉整份。所以它的 Clash 输出是 371 条 + 丢 1 条。

**最终方案**：不引用混合原文，也不让客户端静默丢行。更新脚本将同一份固定 ACL4SSR 文本分成可无损表达的 domain MRS、ipcidr MRS 与内联残余规则。App 通过源文本 SHA-256 锁定二进制对应关系，并在任何不确定时 fail closed 回落旧生成路径。这样避免了「一条不支持就整份内联」，也不会为了内存优化牺牲规则。下方 A/B 是当时的备选分析，现已全部不采用。

- **A. 接受客户端静默忽略。** 照常引用原 URL，那条 `URL-REGEX` 由 Clash 自己跳过。依据：ACL4SSR 官方放在 `Clash/config/` 下的 `ACL4SSR_Mini_Fallback.ini` 就引用了含 `URL-REGEX` 的 ProxyMedia——上游根本没为 Clash 清洗过，说明「Clash 忽略一条不认识的规则」在这个生态里是常态，不会导致配置被拒。改动只是把这类「已知会被静默忽略」的类型放进容忍列表，并在导出摘要里提示「N 条规则会被 X 忽略」。
- **B. 维持内联但按行筛。** 放弃规则集，逐条写入并丢掉不认的类型。完全自洽，但文件仍然几千行——用户开这个开关就是为了避免这个。

**倾向 A**，但有个前提必须逐客户端确认：只对「客户端确认会**静默忽略**」的类型放宽。若某类型会让客户端**拒绝整份配置**（QuanX 就是这种脾气，见 §1.4 的模块顺序和 `tls-verification` 两次教训），那仍然必须退回内联。这个区别不能一概而论。

**已确认的事实**（不用重查）：肥羊的 `sub-web-modify` 前端没有任何规则集逻辑，只是选远程配置 URL 的 Vue 界面，逻辑全在 subconverter 后端。

### 待修：Surge 节点证书校验失败与“跳过证书”（2026-08-25 反馈）

TestFlight build 31 的反馈截图来自 Surge iOS 策略组测速。部分节点对
`iosapps.itunes.apple.com`、`*.apple.com` 等 SNI 建立 TLS 连接时返回
`NSOSStatusErrorDomain: -67901`，同时报告证书有效期过长、根不受信任、证书用途不匹配和
主机名不匹配。这不是普通的延迟超时；当前仅凭截图也不能断定是塔台导出错误，因为同一份
配置里仍有其他节点测试成功。

处理前先拿一条失败节点，对比原订阅字段与塔台生成的 Surge 节点行，确认
`skip-cert-verify` / `allowInsecure` 是否在解析和生成之间丢失。修复边界如下：

- 原订阅明确要求跳过验证时，Surge 输出必须保留 `skip-cert-verify=true`；未声明时不能擅自补上。
- 如增加手动覆盖，只允许按单个节点或单个订阅开启，默认关闭，并明确提示会失去服务器身份校验；禁止做成全局静默开关。
- “跳过证书”只影响节点到代理服务器的 TLS 验证，不能改写策略组测速地址，也不能用于绕过目标网站的 HTTPS 校验。
- VLESS + REALITY 等目标客户端无法忠实表达的节点继续按支持矩阵跳过并计数，不能靠关闭证书验证伪装成普通 TLS 节点。
- 为 Surge 支持的每种 TLS 协议补生成器回归：原值为 `true` 时字段存在，原值为 `false` 时字段不存在；再用失败样本在真机 Surge 完成策略组测速和实际连通验收。

### P0：发布闭环

1. 在至少一台 iOS 17+ 真机完成启动、订阅导入、平面点阵地图、测速、规则和导出主流程。
2. 每次上传前递增 `CURRENT_PROJECT_VERSION`，并重新核对 App 隐私、Beta 测试信息和外部测试审核状态。

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

### P2：兼容 iOS 16（暂不启动）

> 2026-08-18 完成只读评估。当前最低系统为 iOS 17.0；实际按 iOS 16.0 编译时，首先被 Observation 状态管理和新版 Environment 注入阻塞，不能只修改 Deployment Target。

- 推荐最低支持版本为 **iOS 16.0**；iOS 15 需要同时维护旧导航、分享和扫码实现，暂不纳入计划；不考虑 iOS 14 及以下。
- 将 `AppModel` 从 iOS 17 的 `@Observable` / `@Environment(AppModel.self)` 迁移为可回溯到 iOS 16 的状态注入方式，并回归持久化、订阅刷新、规则选择和导出状态。
- 为 `sensoryFeedback`、`ContentUnavailableView`、新版 `onChange`、滚动定位与内容过渡等 iOS 17 API 增加兼容实现；iOS 16.4 API 应移除或增加 iOS 16.0 回退。
- 不支持 VisionKit 扫码的旧设备保留粘贴识别和手动添加入口，并显示明确提示，不阻塞订阅和节点导入。
- 预计改造与回归共 **3–5 个工作日**。完成门槛包括 iOS 16 模拟器、当前系统 iPhone、iPad，以及至少一台真实 iOS 16 设备上的主流程验证。

### P2：WireGuard / Tailscale 客户端兼容研究

> 2026-08-13 仅完成公开资料调研，尚未开始实现或真机验收。后续不能仅凭生成器能输出字段就宣称支持，必须在对应客户端完成导入、连接、DNS、UDP、出口 IP 和重启恢复测试。

- WireGuard：继续核对并真机验收 Surge、Shadowrocket、Clash/Mihomo、Stash、Loon、Hiddify、Egern；Quantumult X 暂按不支持处理并明确计入跳过。
- Tailscale 可作为出站策略或节点的已确认目标：Surge、Clash/Mihomo、Stash。分别实现目标原生语法，不能把 Mihomo YAML 直接复用于 Surge。
- Shadowrocket：新版提供全局 Tailscale 隧道模块，但尚未确认存在可由塔台直接导入的普通节点/订阅格式。先研究客户端设置与导入行为，不生成未经验证的节点。
- Hiddify：上游 sing-box 已有 Tailscale Endpoint，但尚未确认 Hiddify 当前正式版是否完整接受、保存和运行该配置。需要实际版本测试后再决定是否开放。
- Loon、Quantumult X、Egern：暂未发现公开的 Tailscale 节点语法，保持跳过，后续随客户端更新复查。
- Tailscale 配置里的 `auth-key`、机器身份和自定义控制服务器属于敏感数据：全程仅本地处理；日志、预览、二维码与普通分享默认脱敏，不得进入测试夹具或 Git。
- 设计 Tailscale 数据模型前先明确访问 Tailnet 服务、接受子网路由、使用 Exit Node 三种用途，避免把“加入 Tailnet”和“公网出口节点”混成一个开关。
- 为每个开放的目标添加最小生成器测试、缺字段/无效 Auth Key 测试和实际客户端验收记录；测试样本只使用可撤销、短期、受限的测试 Key。

#### TODO：Tailscale 一次配置、持续更新

> 2026-09-03 复核 Tailscale、Surge、Stash、Mihomo 与 sing-box 官方文档后的实现草案。目标是用户在塔台配置一次、在目标客户端认证一次，后续更新塔台配置时复用原有 Tailscale 机器/节点身份，不重复产生 Tailnet 设备。

- [ ] 将 Tailscale 建模为独立的“自有连接”，不能继续用 `DOMAIN-SUFFIX,tailscale.com` 等自定义规则冒充 Tailscale 接入；自定义规则只负责流量匹配，不能在 iOS 的单 VPN 限制下建立 Tailnet 隧道。
- [ ] 每条连接生成并永久保存内部 UUID。显示名称允许修改，但导出使用的身份键不得随名称变化：Surge 固定 `section-name`，Mihomo 固定 `state-dir`，sing-box 固定 `state_directory`；删除后重新添加才生成新 UUID。
- [ ] 数据模型至少区分：访问 Tailnet Peer/MagicDNS、接受子网路由、使用指定 Exit Node；另保存稳定 hostname、可选 control URL、是否允许 Exit Node 时访问 LAN，以及目标客户端启用状态。
- [ ] 默认使用交互认证。`auth-key` 只作为首次部署方式，存入 Keychain，默认选择一次性、短期、预授权且非 ephemeral 的 Key；不得进入日志、普通预览、二维码、测试夹具或长期更新地址。完成首次认证后提供“移除部署密钥”。不要在塔台保存 OAuth Client Secret。
- [ ] Stash 第一阶段：输出固定名称的 `type: tailscale` 节点，默认不写 `auth-key`，引导用户从节点菜单的 Tailscale 页面登录；保持自动 Tailnet 路由开启。重点真机核对远程 Proxy Provider 更新后是否继续复用已认证身份，不能只依据“通常不需要重新认证”的文档表述。
- [ ] Surge 第一阶段：同时生成 `[Proxy]` 策略和 `[Tailscale <固定 section-name>]`，默认使用 `interactive-login = true`；显示名称变化不得重命名 section。核对自动 MagicDNS/Peer 地址路由、显式子网路由和 Exit Node。
- [ ] Clash/Mihomo 第二阶段：输出固定 `state-dir: ./tailscale/tower-ts-<UUID>`、`ephemeral: false`，根据用途生成 `accept-routes`、`exit-node` 与 LAN 访问字段；无交互界面的部署只在首次文件中使用 Auth Key。
- [ ] sing-box MT 第二阶段：按 sing-box 1.12+ Endpoint 语法输出固定 `state_directory: tailscale/tower-ts-<UUID>`，优先在客户端 `Tools > Endpoints` 完成交互认证；结合 Tailscale DNS/`preferred_by` 路由，而不是把整个 `100.64.0.0/10` 粗暴导向普通策略。正式开放前核对 sing-box MT 实际内核版本和导入保留行为。
- [ ] Shadowrocket、Hiddify、Loon、Quantumult X、Egern 在没有官方可导入语法和真机证据前继续标为不支持，不生成猜测配置。
- [ ] 把导入流程拆成“首次安装”和“后续更新”。首次安装完整配置并完成一次认证；后续配置必须保持所有内部身份键不变。Stash 等把 URL Scheme 重复安装视为新配置的客户端，优先使用固定远程配置/Proxy Provider 更新，不反复执行安装 Scheme。
- [ ] 评估固定更新地址：当前塔台 `/sub/<token>?target=...` 的路径和端口可复用，但 iOS 后台会挂起服务且局域网 IP 可能变化；不能宣称同一 iPhone 可全天候自动刷新。需要常驻更新时，只考虑用户自行控制的 Mac/NAS/路由器端点，不把配置或 Tailscale 密钥上传到塔台服务器。
- [ ] 真机验收至少覆盖：首次交互登录、更新配置后设备数量不增加、客户端重启、配置重载、MagicDNS、IPv4/IPv6 Peer、UDP、子网路由、Exit Node 出口 IP、移除 Auth Key 后再次启动、修改显示名称后身份仍复用，以及删除重建后确实得到新身份。

官方依据：[Surge Tailscale](https://manual.nssurge.com/policies/tailscale.html)、[Stash Tailscale](https://stash.wiki/en/proxy-protocols/proxy-types#tailscale)、[Stash Proxy Provider](https://stash.wiki/en/proxy-protocols/proxy-providers)、[Mihomo Tailscale](https://wiki.metacubex.one/en/config/proxies/tailscale/)、[sing-box Tailscale Endpoint](https://sing-box.sagernet.org/configuration/endpoint/tailscale/)、[Tailscale 身份](https://tailscale.com/docs/concepts/tailscale-identity)、[Auth Key 安全](https://tailscale.com/docs/features/access-control/auth-keys/how-to/secure-auth-keys)、[与其他 VPN 共存限制](https://tailscale.com/docs/reference/faq/other-vpns)。

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

- [ ] 十个客户端的官方 App Store 图标立即出现；横向滚动、拖动排序与切换流畅。
- [ ] 摘要中的节点数、跳过数、规则数正确。
- [ ] 完整预览多次展开不闪退。
- [ ] 固定主按钮不被底部标签栏遮挡。
- [ ] 安装客户端时一键打开；未安装时回退分享。
- [ ] 本地临时 URL 只能从本机访问，并在约 45 秒后失效。

### 2026-08-21 审查修复的真机项

- [ ] 大订阅下首页地图滚动与地区展开不发涩（聚类由每帧 5 次降为 1 次）。
- [ ] 节点筛选页边打字边搜索没有输入延迟（过滤由每帧 5 次降为 1 次）。
- [ ] 下载过 Self-Configuration 后进出规则页不卡顿（下载规则列表现在有磁盘缓存）。
- [ ] **刷新订阅后，此前取消勾选的节点仍是取消状态。** 机场改写 remark 时最容易复现；失效是静默的，节点会直接回到导出配置里。
- [ ] 连续勾选多个节点时无掉帧；退到后台再回来，勾选状态已落盘（写入合并为 250 ms 一次，退后台强制 flush）。
- [ ] iCloud 同步开关：开启、立即同步、关闭时的「关闭并删除 iCloud 副本 / 只关闭同步」两个分支都正确。
- [ ] 离线改动后重启 App，本地修改不被 iCloud 上更旧的快照覆盖。
- [ ] 添加订阅时点「取消」：面板关闭后不再出现「已添加」提示，订阅也没有被加入。
- [ ] 批量粘贴多条订阅、其中一条不可达：可达的正常入库，失败的出现在失败报告里。
- [ ] Toast 出现和消失都有动画（此前只有消失有）。
- [ ] 仅节点模式（Shadowrocket / Loon / Quantumult X / Hiddify）导出内容与完整配置切换正常，互不串味。

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

配置生成器修改需要额外人工打开全部完整配置目标，检查：

- 所有组引用存在且无环。
- 地区组只含对应节点，空地区不产生死组。
- 节点名称转义、去重和协议跳过正确。
- 规则顺序与末尾兜底未改变。
- 图标字段符合目标客户端语法，显示名称不重复 Emoji。

界面文案有增删时另外运行：

```sh
bash Scripts/check_localization.sh
```

`LocalizationTests` 只校验「目录里已有的条目是否 15 种语言齐全」，看不到「源码有、目录没有」这一类缺口——它不会报错，只会让那句话在其余 14 种语言下显示中文。该脚本用 Xcode 自己的提取器比对，不要改回 grep 实现（见 §1.9）。

发布脚本或标识符相关改动运行：

```sh
bash Scripts/tests/release_testflight_test.sh
```

它同时扫描「`git add -A` 会提交的一切」——已追踪文件和未被忽略的新文件——确认没有团队 ID、构建机地址或本机私密配置里的值混进去。只扫已追踪文件正是这类泄漏能进仓库的原因：新文件在 `git add` 之前对检查不可见。

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
