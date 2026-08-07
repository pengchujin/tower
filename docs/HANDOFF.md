# 塔台开发交接（2026-08-07）

## 1. 当前结论

塔台已完成可运行的原生 SwiftUI 主流程：导入订阅/自有节点、节点解析和地区识别、自绘点阵世界地图、ICMP/端口测速、本地 Self-Configuration 规则、八种客户端配置生成、配置预览及导入/分享。

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

| | 内置 Self-Configuration | 导入的 `RuleScheme` |
| --- | --- | --- |
| 策略组 | 固定枚举，写死在 Swift | 按 ini 声明还原（精简 5／默认 11／全分组 29 组）|
| 地区分组 | 离线 IP 国家库 | 配置里的节点名正则 |
| 联网 | 从不 | 仅导入和刷新时 |

两套机制互不干扰，不要合并。

### 关键实现

- `RuleSchemeParser` 解析 `ruleset=` 和 `custom_proxy_group=`。`ruleset` 只按第一个逗号切分，因为内联规则 `[]GEOIP,CN` 自带逗号；组成员以 `[]` 开头是引用，否则是节点名正则；末尾 `300,,50` 是时序字段，靠“含逗号且只有数字和逗号”与节点正则区分。
- `ConfigurationGenerator.generate(nodes:scheme:target:schemes:)` 是动态组输出路径，复用原有的节点输出和 `confName` 转义。正则匹配同时试节点原名和塔台改名后的显示名，因为塔台可能加国旗前缀或去重后缀。匹配不到节点的组会回落到 DIRECT，避免输出空组被客户端拒绝。
- QuanX 的 `url-latency-benchmark` 仍走 `server-tag-regex`（第 13 条约束）。
- 导入只接受 HTTPS；规则列表按 6 个一批下载，存到 Application Support 并用完整文件保护；删除方案会一并清掉它下载的列表。
- `AppSnapshot.importedSchemes` 是 Optional——Swift 合成的解码器不会对缺失键套用默认值，改成非可选会让旧存档解不出来。

### 资源命名（不要改）

`Tower/Resources/ACL4SSR/` 下所有文件带 `ACL4SSR_` 前缀。Xcode 把资源拍平到 bundle 根目录，而两套规则都含 `Apple.list`、`Microsoft.list`、`Telegram.list` 和 `manifest.json`，去掉前缀会互相覆盖。`RuleRepository` 也靠这个前缀跳过它们。

### 验证状态

- 模拟器（iPhone 17）：105 个测试通过，1 个按平台跳过（数据保护只能在真机验证）。
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
| Self-Configuration 规则 | **上游未声明** | 默认保留所有权利 |
| IP 国家库 | CC0 1.0 | 无 |

相关文件：根目录 `LICENSE`、`THIRD-PARTY-NOTICES.md`，以及三个资源目录各自的 NOTICE。

`LICENSE` 末尾写明了「本许可仅覆盖源码」。这会让 GitHub 把许可证识别成 `Other` 而不是 `MIT`，**这是有意为之**：混合许可的项目把边界写进 LICENSE 正文，比让人看到 MIT 徽章后误以为整个仓库可随意取用更稳妥。不要为了拿徽章去掉这段说明。

### 待处理的法律风险

**Self-Configuration 上游没有任何许可证**，按著作权默认规则即「保留所有权利」，严格说本项目没有再分发授权。当前缓解措施是完整署名，并在 README 和 NOTICE 里声明：上游作者提 issue 即立即移除。

若需要移除，改动不大——规则导入功能（`RuleSchemeImportService`）已经具备运行时按需下载的能力，把这套快照从仓库删掉、改成首次使用时下载即可，代价是内置预设不再离线可用。

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

导出页也量过：`configuration()` 有缓存，命中时 500 节点仅 0.5ms，不是瓶颈，没动。

### 新增 Hiddify 导出

Hiddify 是 Flutter 外壳 + `hiddify-core`（sing-box 内核），吃 sing-box JSON。sing-box 自身在 App Store 没有独立客户端，所以格式以实际运行它的 App 命名。

JSON 用 `JSONSerialization` 构建而非拼字符串——节点名是机场可控的不可信输入，交给编码器转义。几个格式决定：拒绝从 1.11 起是路由动作（`action: reject`），选择器没有可指的出站，所以拦截类策略不生成组、规则直接带动作；Clash 的四个隐藏别名组在 sing-box 里没有 hidden 概念但仍需存在，否则悬空引用导致起不来；sing-box 的 Snell 只支持 v4 以上，与 Clash 的 v3 上限正好相反。

Egern 也已支持：三段都是单键映射的列表（`- shadowsocks:` / `- select:` / `- domain_suffix:`），策略组用 `select` 和 `auto_test`，规则每条一个 `match`，兜底是 `- default:`。字段是 snake_case（`user_id`、`udp_relay`、`skip_tls_verify`、`obfs_host`），Shadowsocks 的 cipher 要去掉 `-ietf` 中缀。

### 其他

- 首页机场开关改用规则页那个圆形对勾（`CheckmarkToggleStyle`），并补上选择震动。
- Snell 的图标之前写的是 `shell.fill`，SF Symbols 里没有这个符号——`Image(systemName:)` 遇到未知名字既不崩溃也不报错，只画空白。改为 `s.square.fill`，并加测试断言所有符号确实存在。
- 地图右上角的整体测速按钮已移除；逐节点测速仍在展开后的节点详情里。
- 订阅套餐流量：按 `subscription-userinfo` 响应头 → 内容里的 `STATUS=` 行 → 节点列表公告行取值。节点始终以订阅原地址返回体为准，`flag=clash` 只在缺结构化配额时补发一次且只读响应头——机场的 Clash 转换器会丢掉它表达不了的协议（实测少 12 个 AnyTLS 节点）。

## 2. 产品目标与确定的交互

### 首页

- “+”统一添加机场订阅和自有节点，提示同时覆盖订阅 URL 和节点协议链接。弹出时自动请求一次剪贴板并在识别成功后填充，同时保留手动粘贴按钮。
- 顶部统计项“订阅、节点、覆盖地区、自有节点”可滚动到对应内容。
- 订阅可展开节点，但不显示“更多节点”，展开使用透明度/布局变化，不从顶部滑入。
- 节点行显示 IP 国家/地区 Logo、名称、协议/传输/UDP 信息和真实延迟。
- 订阅和单节点都可以分享；单节点导出协议链接和二维码。
- 页面直接嵌入自绘的点阵世界地图（`WorldDotMapView`，不用 MapKit），显示带 Emoji 的节点标注，不单独设置“地球”标签页。

### 规则页

- 默认规则只有 ClashConnectRules/Self-Configuration。
- 策略组只保留一个前置图标，不在名称内重复 Emoji。
- “手动切换”“自动选择”“全球直连”等使用中文可见名称并匹配图标。
- 香港、日本、美国、新加坡等国家/地区策略位于业务策略之后。
- 地区组本身默认延迟优选；业务策略仍可手动选择地区组。
- 生成器必须避免地区组、节点选择和业务策略之间的循环引用。

### 导出页

- 目标客户端使用对应 App Store 图标，横向滚动选择。
- 主按钮固定在标签栏上方，一次点击就通过客户端 Scheme 导入。
- Surge、Stash/Clash、Shadowrocket、Loon 使用本地临时 URL；Quantumult X 使用文件分享。
- 支持配置摘要和完整预览，但不要在客户端切换动画中同步重复生成大文本。

## 3. 已完成的关键实现

### 本地规则

- 上游：`ClashConnectRules/Self-Configuration`。
- 固定修订：`fb658cc85802`。
- 本地资源：`Tower/Resources/SelfConfiguration/`。
- 版本、来源、数量和 SHA-256：`manifest.json`。
- 更新脚本：`Scripts/update_self_configuration_rules.py`。

运行时不拉取规则，保证离线可用并避免上游改动导致同一版本生成结果漂移。

### IP 国家库

- 上游：`sapics/ip-location-db` 的 `geo-whois-asn-country`。
- 当前版本：`2.3.2026061719`。
- 二进制索引：`Tower/Resources/IPCountry/`。
- 更新脚本：`Scripts/update_ip_country_db.py`。

节点是域名时先用系统 DNS 获取地址，再查询内置库。只有失败时才参考节点名称，因此 Amsterdam、Spain、Israel 等英文名称不再决定最终国旗。

### 一键导入

目标客户端不能读取塔台沙盒文件路径，所以 `DirectImportService` 会启动仅绑定 `127.0.0.1` 的 token 化 HTTP 服务，45 秒后关闭，再把临时 URL 放进各客户端 Scheme。该服务不监听局域网地址，不上传配置。

Quantumult X 的公开 Scheme 只覆盖远程资源操作，无法可靠导入完整本地节点、策略组和规则，因此保留文件分享。

### 策略组

当前生成器按 IP 识别结果创建地区组，为地区组建立延迟优选，同时让节点选择/业务策略引用这些地区入口。历史上出现过以下回归，修改时必须保留测试：

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

### 代码里的版本与已上传的版本不一致

工程当前是 **`1.0 (2)`**：`CURRENT_PROJECT_VERSION` 已递增，`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` 已加入。

但**没有任何机器用这份代码归档过**。两台 Mac 都查过，只有 2026-08-03 那份 build 1 的归档。也就是说：

- TestFlight 里能看到的包仍然是 build 1，不含 2026-08-04 的审查修复，也不含规则导入和 ACL4SSR 功能。
- build 1 的 Info.plist 没有 `ITSAppUsesNonExemptEncryption`，出口合规处于未回答状态。

### 内部测试可见、外部测试不可见的原因

外部测试要求出口合规已回答，内部测试不要求。build 1 因此只出现在内部测试的构建列表里，在外部群组的构建选择器中被隐藏，且界面不会说明原因。

两条路：

1. 在 App Store Connect 的构建版本旁手动回答一次出口合规，build 1 立刻可用于外部测试（但功能停留在 8-03）。
2. 打一个真正的 build 2（推荐）。代码已就绪，`ITSAppUsesNonExemptEncryption` 会自动带上，不会再被问。

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

每次重新上传前必须增加 `CURRENT_PROJECT_VERSION`，不要重复上传 build 1。

## 6. 优先任务

### P0：发布闭环

1. 确认 build 1 的 Processing/合规状态并加入内部 TestFlight 测试组。
2. 在至少一台 iOS 17+ 真机完成启动、订阅导入、地图、测速、规则和导出主流程。
3. 为下个构建补 `ITSAppUsesNonExemptEncryption = NO`，构建号增至 2。

### P1：性能和崩溃回归

1. 反复展开/关闭“配置预览”，使用包含数百节点的大订阅观察是否仍闪退。
2. 快速横向切换五个目标客户端，确认图标和配置不重复加载、动画不掉帧。
3. 第一次打开节点/订阅分享 Sheet，确认二维码生成和 Activity View 不阻塞主线程。
4. 如仍卡顿，先用 Instruments 的 Time Profiler / Allocations 复现，重点排查：
   - SwiftUI body 中重复生成完整配置。
   - 大字符串在 `Text`、剪贴板、分享 payload 之间产生多份副本。
   - 客户端图标在滚动时重复解码。
   - 二维码在主线程同步生成。

### P1：五客户端真机兼容

准备安装相应客户端的测试机，分别验证：

- Surge：代理、策略组、图标、规则和一键导入。
- Stash/Clash：YAML 语法、proxy-groups、URL-test 和图标 URL。
- Shadowrocket：节点协议链接、策略环路、规则和 Scheme 接收。
- Loon：VMess/VLESS/Trojan/Hysteria 2 参数及策略组。
- Quantumult X：分享文件能否出现在目标列表；若不能，验证“存储到文件”后手动导入。

### P2：解析兼容

- 收集不能识别的真实机场样本时，先脱敏密码、UUID、token 和域名。
- 每修复一种格式都加入最小自动测试。
- 对 HTTP 错误页、登录页和空订阅保持明确错误，不把它们解析成节点。

## 7. 真机回归清单

### 首页

- [ ] 首次点击“+”时剪贴板权限文案正常，订阅和节点都能自动识别。
- [ ] 四个统计项跳到正确位置。
- [ ] 订阅展开没有从顶部滑入或列表勾选漂移。
- [ ] 节点国旗与服务器 IP 匹配，失败时回退合理。
- [ ] 点阵地图铺满卡片，国家/地区标注不重叠，节点 Emoji 正常。
- [ ] ICMP 与“端口”回退标识准确。
- [ ] 节点和订阅分享、二维码、协议链接可用。

### 规则

- [ ] 只显示 Self-Configuration 默认规则。
- [ ] 策略列表仅一个前置 Logo，不重复 Emoji。
- [ ] 地区策略位于业务策略之后。
- [ ] 地区默认延迟优选，业务策略可手动选择地区。
- [ ] 展开/收起时选择标记不漂移。

### 导出

- [ ] 五个 App Store 图标立即出现，横向滚动与切换流畅。
- [ ] 摘要中的节点数、跳过数、规则数正确。
- [ ] 完整预览多次展开不闪退。
- [ ] 固定主按钮不被底部标签栏遮挡。
- [ ] 安装客户端时一键打开；未安装时回退分享。
- [ ] 本地临时 URL 只能从本机访问，并在约 45 秒后失效。

### 恢复与隐私

- [ ] 杀掉 App 后订阅和自有节点恢复。
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

配置生成器修改需要额外人工打开八种输出，检查：

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
