# 分流规则与配置导出审计（2026-09-28）

对象：main 分支 `c72ab81` 的 `ConfigurationGenerator`、`RoutingRuleSyntax`、`RuleSetEmissionPlanner`。问题是：各客户端的完整配置里，会不会丢规则、写出语法错误，或者改变分流语义。

参考了 Sub-Store 的规则生成器（`e08f1b1`，2026-09-27）、subconverter 的 `ruleconvert.cpp`，以及各客户端的官方文档。Shadowrocket 没有官方文档，用的是社区手册 [LOWERTOP/Shadowrocket](https://github.com/LOWERTOP/Shadowrocket)。

## 修复状态（2026-09-28 当天）

下面列出的问题都已在代码里修复，只有「没有验证的」一节和 P4 的真机确认还需要手动完成。修复细节和回归测试见 [HANDOFF](HANDOFF.md#未发布分流规则导出审计修复2026-09-28)。修复后用同一套方法复验，结果如下：

- mihomo 系、sing-box、Surge 仍然全部通过核心校验。
- Loon、QuanX、Egern、Shadowrocket 的引用检查全部清零。
- Stash 和 Shadowrocket 只剩 mihomo 不认识、但这两个客户端支持的写法。

## 方法

用一个临时 XCTest（审计后已删除）调用 `ConfigurationGenerator`，生成了三批配置：

- **真实场景**，共 128 份：
  - 节点：协议审计用的 26 个节点（SS / SS2022 / ShadowTLS / VMess / VLESS / Reality / Trojan / Hysteria2 / Naive）。
  - 方案：内置 Self-Configuration、ACL4SSR 默认 / 全分组 / 精简三套。
  - 规则集：内联和远程引用两种。
  - 客户端：16 个完整配置目标，另加 16 份仅节点导出。
- **规则样本**，共 2655 份：9 月 11 日规则修复时整理的 113 份单项语法样本（Surge / mihomo / Loon / QuanX / Egern / sing-box），逐一导出到所有目标。
- **代理集合开启**，共 53 份：一个远程订阅加一个本地节点，覆盖支持代理集合的目标。
- **常见写法定向测试**：
  - 屏蔽 QUIC 的 `AND,((PROTOCOL,UDP),(DEST-PORT,443)),REJECT(-NO-DROP)`
  - `pre-matching` / `extended-matching`
  - `REJECT-TINYGIF`
  - `GEOSITE`
  - `IP-CIDR6` / `IP-ASN` / `DOMAIN-WILDCARD` / `USER-AGENT`

校验方式：

- 核心校验器：
  - mihomo 1.19.31 `-t`：mihomo 系六个目标和 Karing；Stash、Shadowrocket 作参考。
  - sing-box 1.14.2 `check`：sing-box MT、Hiddify。
  - Surge Mac 6.4.4 `surge-cli --check`：Surge、Surge Mac。
- Loon、QuanX、Egern、Shadowrocket 没有命令行校验器，另写了引用检查：规则的策略名、选项位置、策略组成员和规则集引用是否都存在，规则类型是否在官方文档里。
- 规则数量按类型统计，和 Surge 输出逐项对比。

## 总体结论

- 用内置方案和三套 ACL4SSR 生成的配置，mihomo 系、sing-box、Surge 全部通过核心校验，没有告警。Stash 和 Shadowrocket 只在 mihomo 不认识的 `URL-REGEX` 上报错，这两个客户端本身支持该规则；去掉 `URL-REGEX` 后，其余内容全部通过。
- 规则数量上，除了下面列出的问题，各目标都没有静默丢失：sing-box 少的 474 条是跨列表重复项，去重后首个命中的策略不变；其余差异都有「无法转换规则」提示。
- 真正会写出错误配置的，集中在 **Loon / Shadowrocket 的旧逐字段拼接路径**（`mappedRule` 非 compiled 分支）和 **Loon 的策略组过滤器**。另有几处过于保守的阻止导出，会让导入的 Surge 配置无法转到其他客户端。

## P1：写出无效配置

### 1. Loon + ACL4SSR 全分组：8 个策略组引用了不存在的过滤器

`🇭🇰 香港节点 = select,DIRECT,塔台筛选 23 · 🇭🇰 香港节点`

- 触发条件：
  - 默认设置（不开代理集合）。
  - 方案里任何用节点名正则分组的组。全分组里有 8 个：香港、日本、美国、台湾、狮城、韩国、奈飞节点、网易音乐。
  - 和节点能不能匹配无关。
- 原因：
  - `remoteGroupSelection`（`ConfigurationGenerator.swift:1123`）只要组有 `nodePatterns` 就返回 `includesRemoteNodes = true`，不看有没有远程订阅。
  - `loonScheme`（:1693）因此把过滤器名加进组成员。
  - 但 `loonRemoteProxySections`（:3039）在没有订阅时直接返回空，`[Remote Filter]` 根本没写。
  - 另外，有订阅但 `aliases` 为空时，过滤器行同样不写，组里的引用照样悬空。
- 引入：`373bc9f`（2026-09-05），1.0.10 起的版本都包含。
- 开启代理集合时 `[Remote Filter]` 会写出，引用完整，所以只在默认路径出错。
- Loon 遇到不存在的成员时是整份配置拒绝，还是忽略这个成员，需要真机确认。无论哪种，写出的都是无效引用。
- 修复方向：只在确实写出过滤器行时，才把过滤器名加进成员。补一条测试：没有远程订阅时，Loon 全分组不含 `塔台筛选`。

### 2. Loon / Shadowrocket：规则选项被写在策略名前面

| 来源 | 塔台输出（Loon / Shadowrocket） | 正确写法 |
| --- | --- | --- |
| `DOMAIN-SUFFIX,ads.example,REJECT,pre-matching` | `DOMAIN-SUFFIX,ads.example,pre-matching,REJECT` | Shadowrocket：`…,REJECT,pre-matching`；Loon：去掉 |
| `DOMAIN,x,Proxy,extended-matching` | `DOMAIN,x,extended-matching,Proxy` | Shadowrocket：放到策略名后面；Loon：去掉 |
| mihomo `IP-CIDR,192.168.0.0/16,Proxy,src` | `IP-CIDR,192.168.0.0/16,src,Proxy` | 转成来源 IP 规则，或者跳过并提示 |
| Surge `notification-text=` / `always-capture=`、QuanX `force-cellular` / `via-interface=` | 同样写在策略名前面 | 跳过这些选项 |

- 原因：`mappedRule`（:3527）的旧路径只识别**结尾的** `no-resolve`（:3591），其余选项都留在 `parts` 里，再把策略名追加到最后。
- 后果：
  - 两个客户端都会把第三个字段当成策略名，没有任何提示。Loon 文档和 Shadowrocket 手册都规定选项写在策略名之后。
  - 带 `pre-matching` 的 `DOMAIN-SET` 会把选项展开到每一行（`RuleResourceContent.applying`），一个广告域名集就会产生成千上万行错误规则。
- 触发条件：导入的 Surge 配置里有这些选项。广告拦截规则里常见 `pre-matching` 和 `extended-matching`。
- 修复方向：
  - 解析时把 matcher 和选项分开，按目标的白名单把选项放到策略名后面：Shadowrocket 保留 `no-resolve`、`extended-matching`、`pre-matching`；Loon 只保留 `no-resolve`。
  - 其他选项丢掉并提示。
  - `src` 在不支持的目标上跳过。

## P2：分流语义改变

### 3. QuanX：`src` 被丢掉，来源规则变成了目的地规则

- mihomo `IP-CIDR,192.168.0.0/16,Proxy,src` 导出成 `ip-cidr, 192.168.0.0/16, Proxy`。
- 原因：QuanX 分支（:3571）重建 `parts` 时丢掉了所有选项。
- 后果：本来按设备来源分流，变成了按目的地分流，而且没有提示。
- 修复：遇到 `src` 就跳过并提示。

### 4. Loon 远程规则模式：留在本地的规则会跑到所有远程列表前面

- Loon 的匹配顺序是：本地 `[Rule]` > 插件规则 > `[Remote Rule]`（见[社区说明](https://wiki.repcz.link/loon/filter/)）。塔台（:1755）把远程规则集写进 `[Remote Rule]`，留在本地的规则写进 `[Rule]`，原有的相对顺序就被打乱了。
- 以 ACL4SSR 为例：`GEOIP,CN,🎯 全球直连,no-resolve` 本来排在最后，现在排到了 BanProgramAD 前面（19 条国内广告 IP，应该 REJECT）和网易云音乐列表前面（国内 IP，应该走「🎶 网易音乐」组）。
- 实际影响：只影响直接按 IP 连接的请求，因为 GEOIP 带 `no-resolve`，而且 Loon 本身先匹配域名规则。
- 触发条件：用户打开「规则集远程引用」（默认关闭）。
- 修复方向：规划 Loon 的输出时，一旦某条本地规则排在远程规则集后面，就把它之后的远程规则集都改成内联；或者整份方案退回内联。

### 5. sing-box MT / Hiddify：ACL4SSR 方案的 `GEOIP,CN` 被跳过

- 有「无法转换规则：GEOIP,CN」提示，但这是 ACL4SSR 里国内 IP 直连的兜底规则。丢掉之后，没被列表覆盖的国内 IP 会落到「🐟 漏网之鱼」，走代理。
- sing-box 1.12 起取消了 geoip，官方做法是引用 `geoip-cn` 规则集。塔台已经在自己的仓库里发布了 ACL4SSR 的 SRS 文件，可以同样固定一份 geoip-cn SRS，远程引用。更新流程和 NOTICE 要一并补上。
- 内置 Self-Configuration 方案没有 GEOIP 规则，不受影响。

### 6. 规则列表没下载时，`RULE-SET` 会静默变空

- 生成器只在 `DOMAIN-SET` 缺缓存时提示「部分规则还没下载完成」并阻止导出（:247）。`RULE-SET` 缺缓存时，内联和远程两种模式下都直接产出零条规则，没有任何提示。
- 规则下载缓存（`ImportedRules`）只存在本机，而导入的方案会通过 iCloud 同步。`apply()` 套用快照之后也不会自动下载。所以在第二台设备上，导出配置会缺少这些规则集。
- 这一条来自代码阅读和生成测试（缓存为空时导出，Surge 的 `[Rule]` 里只剩 `FINAL`），第二台设备上的界面表现还没有实测。
- 修复方向：
  - 检查条件扩展到所有缺缓存的远程资源。
  - 或者在套用快照后补下载缺失的列表，但要遵守约束 16：只有用户主动触发时才联网。

## P3：过于保守，可以表达却阻止了导出或丢了规则

| 输入 | 现状 | 各客户端的实际能力 |
| --- | --- | --- |
| `REJECT-NO-DROP`、`REJECT-TINYGIF` | 除 Surge 以外的所有客户端都**阻止导出** | Shadowrocket 原生支持两者；Loon 有 `REJECT-IMG`（QuanX 的 `reject-img` 只能用在重写里，分流里只能写 `reject`）；mihomo 可以降级为 `REJECT`。Surge 常见的屏蔽 QUIC 规则就用 `REJECT-NO-DROP`，导入这类配置后，其他客户端全部无法导出 |
| `REJECT` 规则带 `pre-matching`、`extended-matching` | mihomo 系、Stash、sing-box、Hiddify **阻止导出** | 两者去掉后不影响拒绝语义（塔台的 provider 路径注释也写了 mihomo 会忽略 `extended-matching`），可以去掉后提示 |
| AND / OR / NOT | Loon、Shadowrocket、Egern、QuanX 一律跳过；涉及 REJECT 时阻止导出 | Loon 3.1.7+ 文档支持；Shadowrocket 手册支持（`PROTOCOL` 只能写在逻辑规则里）；Egern 有 `and` / `or` / `not`。QuanX 确实不支持 |
| mihomo `DST-PORT` / `NETWORK` / `SRC-IP-CIDR` | Loon、Shadowrocket 跳过 | Shadowrocket 原生是 `DST-PORT`；Loon 是 `DEST-PORT` / `PROTOCOL`；旧路径没做方言转换 |
| Egern 的 `IP-ASN`、`DOMAIN-WILDCARD`、`DOMAIN-REGEX`、`USER-AGENT`、`IP-CIDR6` | 前四种跳过；IPv6 写进 `ip_cidr` | Egern 文档里分别有 `asn`、`domain_wildcard`、`domain_regex`、`user_agent`、`ip_cidr6`。映射表在 `egernRuleMatchers`（:4920）；IPv6 这条即已知的 B11 |
| mihomo `UID` | 原样写给全部 mihomo 目标 | mihomo 只在 Linux / Android 支持。本机核心报 `uid rule not support this platform`，**整份配置加载失败**。塔台的目标都跑在 macOS / iOS / Windows 上（FlClash 的 Android 版除外），应该跳过 |

## P4：写出了文档没有的规则类型，需要真机确认

- **Shadowrocket**：
  - `DEST-PORT`（手册写的是 `DST-PORT`）
  - 单独使用的 `PROTOCOL`（手册说只能写在逻辑规则里）
  - `SUBNET`、`SRC-IP`
  - `PROCESS-NAME`：ACL4SSR 有 18 条，每份 Shadowrocket 导出都带着
  - `RULE-SET,SYSTEM` / `LAN` / 本地文件：Shadowrocket YAML 里没有对应的 provider
  - 远程模式用 Clash `rule-providers` 语法，没有验收过（HANDOFF 已记录）
- **Loon**：
  - `PROCESS-NAME`（ACL4SSR）
  - `DOMAIN-WILDCARD`
  - `SRC-IP`（Sub-Store 对 Loon 也会丢掉 SRC-IP）
  - `SUBNET`
  - 写在 `[Rule]` 里的 `RULE-SET`
- **Stash**：生成器允许 `SRC-PORT`、`IN-PORT`，文档里都没有。
- **Karing**：拿到的是完整的 mihomo 规则词汇，它的内核是 sing-box，实际能接受哪些类型没有核对过。

这些类型大多来自导入的 Surge 配置，内置方案只涉及 `PROCESS-NAME`。Loon 和 Shadowrocket 对未知类型是整份拒绝还是跳过这一行，要先在真机上确认，再决定跳过还是保留。

## 和参考转换器的对照

- Sub-Store 的规则生成器是逐行转换：
  - Loon：丢掉 `SRC-IP` / `GEOSITE` / `GEOIP`，IP 规则只保留 `no-resolve`。
  - QuanX：丢掉 `URL-REGEX` / `DEST-PORT` / `SRC-IP` / `IN-PORT` / `PROTOCOL` / `GEOSITE` / `GEOIP`，再做 HOST 系改名。
  - Clash：`DEST-PORT → DST-PORT`、`SRC-IP → SRC-IP-CIDR`、`IN-PORT → SRC-PORT`。
  - 它不处理选项的位置，也不处理逻辑规则。
- subconverter 给 Loon 用的是 `Surge2RuleTypes`，不含 AND / OR / NOT；给 QuanX 做 `IP-CIDR6 → IP6-CIDR`。
- 塔台在逻辑规则树、端口区间和来源 IP 补前缀上比两者都完整，而且会提示不能表达的规则。上面的问题都在两者没覆盖到的地方，所以不能用「和它们一样」来判断对错。

## 没有验证的

- 所有结论都来自生成文件、核心校验器和文档，没有在 Loon、Shadowrocket、QuanX、Egern、Stash 真机上导入。
- 本机的 Surge Mac 是 6.4.4，比 iOS 5.21 旧。
- sing-box 用的是官方 1.14.2，Hiddify 的内核版本可能不同。

## 导入这一侧：真实配置测试（2026-09-28 晚）

前面几节审计的是「方案已经在塔台里之后，怎么写给各个客户端」。这一节测的是导入：用 App 真实的导入流程（`AppModel.importScheme`，会实际下载规则列表），导入 10 份公开的真实配置，再导出到全部客户端，用核心校验器和引用检查验证。

| 配置 | 来源 | 结果 |
| --- | --- | --- |
| ACL4SSR `ACL4SSR_Online_Full.ini` | subconverter | ✅ 29 个策略组、33 条规则全部保留，导出通过校验。以前测过 ACL4SSR 仓库全部 30 多份 `.ini`，数量同样一致 |
| qichiyuhub `full.ini`、cutethotw `GeneralClashRule.ini` | subconverter | ❌ 导入失败：「配置包含无法安全转换的语法」 |
| Loyalsoldier 示例 | Clash，domain / ipcidr / classical 规则集 | ✅ |
| Repcz `mihomo/Client/config.yaml` | mihomo，text 规则集 | ✅ |
| 666OS `Pro_cn.yaml` | mihomo，全部是 MRS 规则集 | ❌ 规则变成乱码；Clash Mi 的内联配置被 mihomo 拒绝加载 |
| qichiyuhub `config.yaml` | mihomo，MRS 规则集 + 自定义直连代理 | ❌ 所有客户端都被阻止导出 |
| Stash 官方示例 | Stash | ❌ 一条 SCRIPT 拒绝规则导致全部被阻止 |
| Repcz `Surge.conf` | Surge | ⚠️ 连导回 Surge 的内联配置都被 Surge 拒绝；mihomo 系、Loon、QuanX、sing-box 被阻止 |
| TributePaulWalker `Surge Pro.conf` | Surge | ⚠️ Surge 正常；其他客户端全部被阻止 |

### 问题

1. **MRS 规则集被当成文本解码**（P1）。
   - 现代 mihomo 配置（666OS、qichiyuhub 等）的 `rule-providers` 大多是 `format: mrs`。导入时塔台把二进制文件按文本解码，得到上万条乱码规则，比如 666OS 有 9670 行 `DOMAIN,<乱码>`。
   - 后果：Clash Mi 等 mihomo 系的内联配置里带着乱码，mihomo 直接拒绝加载；其他客户端丢掉这些规则集里的全部规则，还附带几千条「无法转换」提示。
   - 只有 mihomo 系在「优先使用规则集」模式下能用：`format: mrs` 被原样引用，校验通过。
   - 修复方向：识别 MRS（`format: mrs`、`.mrs` 后缀，或二进制内容），不要按文本存储。mihomo 系无论哪种模式都改为远程引用 MRS；其他客户端每个规则集只给一条提示。塔台没有 MRS 解码器（MRS 是 zstd 压缩加专有结构，iOS 系统库不支持 zstd），以前尝试过把 MRS 展开成文本，因为规则量太大（约 17 万条）已经回退。
2. **subconverter `.ini` 的类型前缀不认识**（P1）。
   - `ruleset=组名,clash-classic:https://…`（还有 `clash-domain:`、`clash-ipcidr:`、`quanx:`、`surge:` 等）是 subconverter 的常见写法，引用 blackmatrix7 规则集基本都用它。塔台不认识这些前缀，整份导入失败。
   - 修复方向：按前缀解析；`clash-domain` / `clash-ipcidr` 对应 provider 的 behavior。
3. **mihomo 里自定义的直连 / 拒绝代理被丢掉**（P1）。
   - 例如 `proxies: - {name: 直连, type: direct}`。导入时会剥掉所有代理定义以免存下节点凭据，这个「直连」也一起没了。于是 `MATCH,直连` 等规则指向不存在的策略组，所有客户端都被阻止导出。
   - 修复方向：`type: direct` / `reject`（以及 `reject-drop`）的代理不含凭据，映射成内置 `DIRECT` / `REJECT` 的别名即可。
4. **规则集的选项被套到不支持它的规则类型上**（P1，Surge 导出也会坏）。
   - `RULE-SET,…,REJECT,pre-matching` 内联展开时，`RuleResourceContent.applying` 把 `pre-matching` 加到了每一行，包括 `URL-REGEX`。Surge 报「marked for pre-matching, but the rule type doesn't support this」并拒绝整份配置。
   - 修复方向：按规则类型挑选能接收的选项：`pre-matching` 只给域名、IP 类和逻辑规则，`extended-matching` 只给域名类和 URL-REGEX。
5. **`FINAL,…,dns-failed` 阻止所有非 Surge 客户端**（P2）。只有 Surge 有 `dns-failed`，其他客户端去掉它不影响分流。
6. **`REJECT-DROP` 阻止 QuanX、Egern、sing-box**（P2）。可以按 `REJECT-NO-DROP` 的做法替换成 `REJECT`；sing-box 还可以写成 `action: reject, method: drop`。
7. **「拒绝规则转不了就阻止整份导出」的策略，让大多数 Surge 配置转不到别的客户端**（需要决定）。
   - 真实的 Surge 广告规则里常有 `URL-REGEX`（mihomo 不支持）和 `DOMAIN-WILDCARD`（Loon 文档里没有）。按现在的 B15 设计，只要有一条这样的 REJECT 规则，整份就被阻止。
   - 可选方案：改为「跳过并在兼容性提示里醒目标出」，或者让用户在导出页确认后继续。
   - Stash 示例的 `SCRIPT` 规则是同一个问题。

### 修复状态（同日）

1–6 已修复。第 7 项按用户决定：拦截规则转不过去时跳过，并在兼容性提示最前面写「N 条拦截规则无法在 X 中表达，已跳过：这些请求不会被拦截」，不再阻止整份导出。修复后，这 10 份配置全部能导入，也都不再被整份阻止。回归测试见 `RuleImportFidelityTests`。

- **MRS**：不下载、不按文本解码。mihomo 系（不含 Karing）无论是否打开「优先使用规则集」，都远程引用 `format: mrs`；其他客户端每个 MRS 规则集给一条「无法读取 MRS 规则集，已跳过」。下载内容带 NUL 字节时，按「不是可读文本」处理。
- **subconverter**：认识 `clash-domain:` / `clash-ipcidr:` / `clash-classic:` / `quanx:` / `surge:` 前缀，以及末尾的更新间隔。
- **mihomo 的 `type: direct` / `reject` / `reject-drop` 代理**：映射成内置策略。
- **列表选项**：按 Surge 手册，`pre-matching` 只给域名、IP、端口、逻辑等支持它的规则类型，`extended-matching` 只给域名类和 URL-REGEX。
- **`FINAL` 的 `dns-failed`**：非 Surge 客户端去掉并提示。
- **`REJECT-DROP`**：在 QuanX、Egern、sing-box 上换成 `REJECT`。
- **DNS**：顺带发现并修了一个问题。Surge 的 `h3://`（DNS over HTTP/3）以前会让 mihomo 拒绝整份配置（`unsupport scheme: h3`），sing-box 则悄悄丢掉这个解析器。现在 mihomo 系写成 `https://…#h3=true`，Stash / Shadowrocket / Karing 写成普通 `https://`，sing-box 用 `h3` 类型。编辑器和网络设置里也放行了 `h3://`。

### 哪些规则能换写法

原则：改写后必须等价，或只多匹配极少、可预期的范围；不能扩大拦截面，也不能靠猜测。

| 规则 | 目标 | 处理 |
| --- | --- | --- |
| `DOMAIN-WILDCARD,*.example.com` | Loon | 改写成 `AND,((DOMAIN-SUFFIX,example.com),(NOT,((DOMAIN,example.com))))`（Loon 3.1.7+ 逻辑规则，范围与原规则一致；最初写成单纯的后缀规则，会多匹配 example.com 本身，2026-09-29 按 Codex 审查修正）；不含通配符的改写成 `DOMAIN`。其他形状（`ads-*.x.com`）没有等价写法，跳过 |
| `GEOIP,<国家>` / `GEOIP,LAN` | sing-box、Hiddify | 用内置 IP 国家库展开成 `ip_cidr`；LAN 转成 `ip_is_private` |
| `IP-ASN` | sing-box、Hiddify | 用内置 ASN 库展开成 `ip_cidr` |
| `REJECT-TINYGIF` / `REJECT-NO-DROP` / `REJECT-DROP` | 没有这些策略的客户端 | 换成最接近的拒绝策略（Loon 的 `REJECT-IMG`，其他用 `REJECT`） |
| mihomo `DST-PORT` / `NETWORK` / `SRC-IP-CIDR` | Surge、Loon、Shadowrocket | 换成各自的 `DEST-PORT` / `DST-PORT`、`PROTOCOL`、`SRC-IP` |
| `URL-REGEX` | mihomo、sing-box、QuanX | 跳过。它要看完整 URL，而 HTTPS 的路径只有在中间人解密时才看得到；改写成域名规则会把整个域名拦掉 |
| `USER-AGENT` | mihomo、sing-box | 跳过。这两者只看连接，不读 HTTP 头 |
| `PROCESS-NAME` | iOS 客户端 | 跳过。iOS 上拿不到进程名 |
| `DOMAIN-REGEX`、`GEOSITE` | Surge、Loon、Shadowrocket、QuanX | 跳过。前者没有正则规则；后者塔台没有 geosite 数据，展开后规则量太大（MRS 展开的尝试已回退） |
| MRS 规则集 | 非 mihomo 客户端 | 跳过。MRS 是 zstd 压缩的专有结构，iOS 系统库不支持 zstd |
| `SCRIPT` | 所有目标 | 跳过。脚本定义带不过去 |
| 逻辑规则里嵌套 `RULE-SET` | 所有目标 | 跳过。无法把规则集展开进逻辑规则 |

### 验证方式

临时 XCTest 已删除。输入和输出只放在本机临时目录。

## 与参考转换器逐项对比（2026-09-28 深夜）

同一份输入分别交给三家转换，再用 mihomo 1.19.31、sing-box 1.14.2、Surge Mac `surge-cli` 校验。所有输出只放在本机临时目录，因为里面有测试服务器的地址和凭据。

- **节点**：协议审计的测试节点，加上 3 种 AnyTLS 写法（普通、跳过证书校验加随机指纹、Reality）和 TUIC，共 30 行。
- **规则**：ACL4SSR 全分组。
- **三家**：塔台（本地修改后的版本）、subconverter 0.9.0（tindy2013 原版的最后一个发行版，本机运行）、Sub-Store 后端 `e08f1b1`（2026-09-27，本机运行，`/api/proxy/parse`，只转换节点）。

### 能不能加载

| 输出 | 结果 |
| --- | --- |
| subconverter → Surge | ❌ Surge 拒绝整份配置：写了 Surge 不支持的 `2022-blake3-chacha20-poly1305` |
| subconverter → sing-box | ❌ 加载失败：用的是 sing-box 1.14 已移除的旧 DNS 格式 |
| subconverter → Clash（mihomo） | ✅ |
| Sub-Store → mihomo / sing-box / Surge 的节点 | ✅ |
| 塔台 → 全部目标 | ✅（见上文各节） |

### 节点层面

| 情况 | 塔台 | subconverter | Sub-Store |
| --- | --- | --- | --- |
| Surge 的 trojan gRPC / trojan Reality | 跳过（Surge 不支持） | ❌ 写成普通 trojan，参数静默丢失，连不上 | 跳过 |
| Surge / Loon / QuanX 的 SS2022 chacha20 | 跳过 | ❌ 照写，Surge 整份拒绝 | 跳过 |
| Stash 的 VLESS 加密（`encryption: mlkem768…`） | 跳过（只有 mihomo 支持） | — | ❌ 照写，Stash 不认识，会按普通 VLESS 连接，连不上 |
| Stash 的 trojan Reality | 跳过（Stash 3.4 暂缓，见 TODO） | — | 写出（Stash 3.6+ 支持） |
| Loon 的 Hysteria2 端口跳跃 | `server-ports="a:b"`（符合 Loon 文档） | — | ❌ `a-b` |
| mihomo 的 AnyTLS 指纹 | `client-fingerprint` | — | 多写一个无效的 `fp: random` 字段（无害） |
| sing-box 的 uTLS 指纹（非 Reality） | ❌→✅ 以前丢失，本轮已修 | — | ✅ |
| QuanX 的 `vless … obfs=http` | ❌→✅ 以前跳过，本轮已修（sample.conf 有这种写法） | — | ✅ |
| Egern 的 VLESS Reality over gRPC | ❌→✅ 以前跳过，本轮已修（Egern 文档支持） | — | ✅ |
| Loon 的 Reality 指纹 `tls-profile` | ❌→✅ 以前丢失，本轮已修 | — | ✅ |
| Loon 的 Hysteria2 `fast-open` | 固定写 `true`（真机测试通过，保留） | — | 写 `false` |

其余差异都是默认值写与不写（`tls: true`、`packet-encoding: xudp`、`skip-cert-verify: false`、`tfo: false`），或者 WebSocket early data 的两种等价写法，不影响连接。

### 规则层面（ACL4SSR 全分组）

- **规则数**：两家基本一致。subconverter 取的是 ACL4SSR 最新版，塔台用固定版本的快照，因此差几十条；两家都跳过了 mihomo 不支持的 URL-REGEX。
- **规则集依赖 subconverter 服务**：在 Surge、Loon、QuanX 上，subconverter 只写规则集链接；QuanX 的链接指向 subconverter 服务自己（`/getruleset?...`）。服务停掉，规则就全部失效；用公共转换服务时，规则请求还会经过别人的服务器。塔台把规则写进配置，或者直接引用 GitHub 上固定版本的原文件。
- **Loon 的规则顺序**：subconverter 把 `GEOIP,CN` 放在本地 `[Rule]`、列表放在 `[Remote Rule]`，GEOIP 因此排到所有列表前面。塔台上一轮刚修掉这个问题。
- **sing-box**：subconverter 仍然写 `geoip`（1.12 起已移除）和 `process_name`（iOS 上不可用）；塔台展开成地址段，并跳过 `process_name`。

### AnyTLS 支持情况

| 客户端 | 支持 | 依据 | 塔台 |
| --- | --- | --- | --- |
| Surge | ✅ | 手册 policies/anytls | 导出（Reality 跳过：Surge 的 AnyTLS 没有 Reality） |
| Stash | ✅ | stash.wiki 代理类型（只列了基本字段） | 导出 |
| Loon | ✅ 3.4.0+ | nsloon.app 节点文档，支持 Reality | 导出 |
| Quantumult X | ✅ | 官方 sample.conf，含 Reality | 导出 |
| Shadowrocket | ✅ | LOWERTOP 手册 | 导出 |
| Egern | ✅ | 官方文档，含 Reality 和证书固定 | 导出 |
| mihomo 系、sing-box、Karing、Hiddify | ✅ | 内核支持 | 导出（mihomo 没有 AnyTLS Reality，跳过） |
| Anywhere | ✅ | README 和源码（`anytls://`） | 导出。它的链接没有「跳过证书校验」和证书固定，这两类节点在链接里仍然跳过（按约束 12）；一键导入时对支持 AJSON 的版本改发 AJSON，VLESS（TLS，raw / HTTPUpgrade）/ Trojan / AnyTLS 的跳过证书校验可以保留（issue #51）；Hysteria 与 Reality 没有对应字段，VLESS WS / gRPC / XHTTP 在 Anywhere 里重建 TLS 时丢掉 `insecure`（真机实测失败），都仍跳过，现在会显示具体原因；指纹映射已和 Anywhere 自己的 Clash 导入一致（`chrome`→chrome_133、`ios`→chrome_120、`random`→默认） |
| V2Box | ❌ 没有证据 | 协议列表里没有 AnyTLS | 跳过 |

### 空策略组的回退

以前：没有可用节点的策略组改为 DIRECT，这和 subconverter 的做法一致；mihomo 遇到空组也会自动填入 COMPATIBLE（等同直连）。但父组如果把它排在第一位，父组的默认选择就会变成直连。例如 ACL4SSR 的「🎥 奈飞视频」第一项是「🎥 奈飞节点」，订阅里没有标注奈飞的节点时，Netflix 会悄悄走直连。

现在：空组本身仍然保留为直连，规则直接指向它时行为不变；但父组不再引用它，默认选项会顺延到下一个成员（如「🚀 节点选择」）。父组如果因此变空，也按同样规则逐层处理。

规则转不过去时，统一跳过、继续往下匹配，最后落到 FINAL。这是唯一可行的回退方式；拦截规则被跳过时，会在提示最前面说明。

## sing-box 的 DNS（2026-09-29）

起因：用户转来一段 Gemini 对塔台 sing-box 配置的点评，说「DNS 没有分流规则，所有域名都经代理用 1.1.1.1 解析，国内网站会被调度到海外 CDN」，以及「上千行内联规则浪费内存」。

### 原来的做法

- **sing-box MT**（`SingBoxDNSPolicy`）：把规则列表里的域名投影成 DNS 规则。直连组的域名用国内 DoH（223.5.5.5），其余用远程 DoH（1.1.1.1，经代理）；列表外的域名走 `final: remote`。按设计不使用「按解析结果的 IP 判断」，因为那样会先把域名发给国内 DNS，造成泄露。
- **Hiddify**：没有任何 DNS 规则，`final: remote`，和 Gemini 描述的完全一致。本轮没有改。
- **mihomo 系**：`fake-ip`，国内 DoH 作 `nameserver`，国外 DoH 作 `fallback`，再用 `fallback-filter geoip CN` 判断。开了 fake-ip 并且规则都带 `no-resolve` 时，走代理的域名不会在本机解析，所以没有泄露；只有直连的域名会被解析。
- **Surge、Loon、QuanX、Stash、Shadowrocket**：由客户端自己决定，走代理的域名在代理端解析。

### 实测（sing-box 1.14.2，本机，出口绑定 en0，远程 DNS 走测试节点）

| 域名类型 | 原来 | 改后 |
| --- | --- | --- |
| 列表内国内（百度、淘宝、B 站图片、美团） | 国内 | 国内 |
| 列表外国内（火山引擎、网宿、海康、大疆） | 美国 / 日本 / 新加坡的 CDN | 全部国内 |
| 国外（Google、GitHub、Netflix、Cloudflare） | 美国 | 不变 |
| 列表外国外域名，首次解析 | 约 80 ms | 约 150 ms（多查一次，之后走缓存） |

另外做了一个反证：把国内 DNS 指向一个根本不存在的地址，列表外的国内和国外域名仍然能解析。这说明它们没有经过国内 DNS，没有泄露。

内存：内联规则的配置运行时约 25 MB；打开「优先使用规则集」（远程 SRS）后约 65 MB。Gemini 说的「内联规则浪费内存」不成立。

### 改动

按 sing-box 官方文档「Traffic bypass usage for Chinese users → Without DNS leaks」的做法，在投影规则之后加一条 DNS 规则：列表外的域名先经代理问 Google DoH（`remote-cn`，因为 1.1.1.1 不支持 ECS），并带 `client_subnet: 114.114.114.0/24`；只有返回国内 IP 时才采用（规则集只含 IP 段时，sing-box 会把它当作对解析结果的过滤条件），否则落到原来的 `final: remote`。

- 生效条件：只在 sing-box MT、使用塔台默认 DNS 设置、DNS 保护模式不是「跟随方案」、存在代理节点、`final` 为 remote 时添加。
- 国内 IP 段来自内置 IP 库，做成内联规则集 `tower-geoip-cn`，路由的 `GEOIP,CN` 和这条 DNS 规则共用一份（`IP-ASN` 同理，用 `tower-asn-<n>`）。Hiddify 仍然内联地址段。
- 已知局限：ECS 用的是通用的国内网段，拿到的是国内 CDN 节点，但不一定是离用户所在运营商最近的那个。要做到运营商级别，就得先知道用户的 IP，而这本身就会泄露。

## DNS 保护模式评估（2026-09-29）

### 三种模式实际写了什么

| 模式 | sing-box MT | mihomo 系 | Surge | QuanX |
| --- | --- | --- | --- | --- |
| 跟随方案 | 只用方案里的 DNS，不强制接管 53 端口，不开 `strict_route` | 只写 `nameserver`，不开 fake-ip（默认 redir-host） | 原样写 | 不加兜底规则 |
| 标准保护 | 按规则列表投影 + ECS 提示（本日新增） | fake-ip + 国内 `nameserver` + 国外 `fallback` + `fallback-filter geoip CN`（已改，见下） | 原样写 | 在 final 前加 `host-keyword, .` 兜底 |
| 严格保护 | 规则模式下全部经远程 DNS | 在标准保护基础上加 TUN、`dns-hijack`、`strict-route` | 额外接管 DNS | 同标准保护 |

### 实测 mihomo 1.19.31（标准保护，塔台导出的 Clash Mi 配置）

- **走代理的域名**（Google、Le Monde，以及火山引擎、大疆这类列表外的国内网站）：本机完全不做解析，没有泄露。
- **列表外的国内网站命中 MATCH，走代理**：火山引擎要 1.29 秒。原因是 GEOIP 按用户要求自动带 `no-resolve`（D01），所以这些域名没有机会被判定为国内。
- **直连的域名（百度）**：同时发给 223.5.5.5、doh.pub、1.1.1.1、dns.google 四家（A 和 AAAA 各一次，共 8 次查询），全部直连发出，最终采用国内结果。发给国外那两家的查询是 `fallback` 机制带来的多余请求，在国内直连也常被干扰。

### 问题

1. **设置页不区分国内 DNS 和远程 DNS**（最重要）。页面只有「普通 DNS」和「加密 DNS」两个列表。用户一旦保存过（方案里有了 `networkSettings`）：
   - sing-box 的远程 DNS 会变成「加密 DNS 列表经代理」，默认就是 223.5.5.5 / doh.pub 经代理，国外域名因此交给了国内 DNS。
   - mihomo 的 `fallback` 也变成同一组国内 DoH，`fallback-filter` 失效。
   - 本日新增的 ECS 提示只在默认设置下生效。
   结果是：**点一次「保存」，保护反而变弱**。
2. **mihomo 仍在用 `fallback` + `fallback-filter`**：它让直连域名同时去问国外 DNS。mihomo 文档里 `fallback-filter.geosite` 已经弃用，推荐改用 `nameserver-policy`。
3. **「跟随方案」在 mihomo 上会关掉 fake-ip**：所有域名都会先在本机解析。模式名字看不出这个副作用。

### 参考实现

- **subconverter 0.9.0**：
  - Clash 只有请求里带 `clash.dns=1` 时才写 `dns: enable/listen`，不给任何解析服务器。
  - Surge、Loon 只写国内的普通 DNS 或 DoH。
  - sing-box 模板是「国内优先」：国外列表走 fake-ip 或代理 DNS，其余域名全部交给国内 DNS。国内 CDN 准，但未知域名会泄露给国内 DNS。而且模板用的是 1.12 已移除的 `geosite` / `address` 字段，`block` 标签和规则里的 `dns_block` 对不上，当前 sing-box 加载不了。
  - 没有任何「保护模式」概念。
- **Sub-Store**：只转换节点，不生成 DNS。DNS 交给用户自己的模板或覆写脚本。
- **sing-box 官方**：给中国用户两套做法，「允许泄露」（国内 DNS 先查，国内 IP 才采用）和「不泄露但稍慢」（远程 DNS 带 ECS，国内 IP 才采用）。塔台标准保护现在采用后者。
- **mihomo 官方**：推荐 fake-ip，用 `nameserver-policy` 让国内列表走国内 DoH，`proxy-server-nameserver` 负责解析节点域名，需要时开 `respect-rules`，远程 DNS 可以用 `#ecs=` 参数。

### 已实施（2026-09-29，用户确认「其他的都改」）

1. **国内 / 远程 DNS 分开**：`RuleSchemeNetworkSettings.remoteDNSServers`。
   - 设置页分成「国内 DNS（直连）」（原来的加密 DNS 列表）和「远程 DNS（经代理）」两组。
   - 远程默认 `https://8.8.8.8/dns-query`、`https://1.1.1.1/dns-query`。默认值故意写 IP：`dns.google` 本身被封，国内 DNS 可能给出伪造地址。
   - 升级前保存的设置里这一项为空，`effectiveRemoteDNSServers` 会回退到默认值，不会再拿国内列表经代理去查。
   - 导入时 Clash 的 `fallback`、以及带 `#<代理组>` 的 `nameserver` 归到远程；`#h3=true` 还原成 `h3://`；Tower 自己的文本格式用 `tower-remote-dns-server`。
2. **sing-box**：
   - `remote` 系列服务器改由远程列表生成，不再复制国内列表。
   - ECS 提示改为跟着「标准 / 严格」模式走，不再看是否保存过设置。优先用远程列表里第一个支持 ECS 的服务器（`supportsClientSubnet`：Google、Quad9 ECS 版），没有就用 Google。
   - 严格保护下，直连列表的域名改为经代理向 `remote-cn` 查询，并带中国子网。这样不会发到国内 DNS，但仍然能拿到国内 CDN。
3. **mihomo 系（含 Stash、Karing、Shadowrocket 的 Clash 格式）**：
   - 标准保护去掉 `fallback` / `fallback-filter`，`nameserver` 和 `proxy-server-nameserver` 只用国内 DoH。内置预设同步。
   - 严格保护（Clash / Clash Mi / Verge / Mac / FlClash / Clash Party）：`nameserver` 改成远程列表里支持 ECS 的服务器，写法是 `…#<纯节点组>&ecs=114.114.114.0/24&ecs-override=true`，没有就用 Google。
   - 严格保护下 `proxy-server-nameserver` 仍用国内 DoH，负责解析节点域名，避免先有鸡还是先有蛋。
   - Karing 没有文档说明支持 `#` 后缀，严格保护下仍按标准写。
4. **「跟随方案」说明**补充了「Clash 系客户端会先在本机解析每个域名」。标准、严格模式的说明也按新行为重写。

实测（mihomo 1.19.31、sing-box 1.14.2，塔台实际导出的 ACL4SSR 默认方案，真实节点，出口 en0）：

- 默认、标准、严格、跟随四种设置 × Clash Mi / Verge / Karing / sing-box，共 16 份配置，`mihomo -t` 和 `sing-box check` 全部通过。
- **mihomo 严格保护**：日志显示 `DNS [https://8.8.8.8:443/dns-query] config with ecs: 114.114.114.0/24`，查询经「♻️ 自动选择」节点发出。
  - 列表外的国内网站（火山引擎、网宿、华为云、大疆、海康等）全部拿到国内地址。
  - Google 拿到真实地址。对照组「标准保护」让国内 DoH 直查 `www.google.com`，得到的是被污染的 69.171.235.22。fake-ip 下走代理的域名本来就不在本机解析，所以标准保护实际不受影响。
- **sing-box 严格保护**：直连列表的域名命中投影规则后，经代理发往 `remote-cn`，响应里带 `SUBNET: 114.114.114.0/24`。
- **已知局限**：少数国内权威 DNS 不理会 ECS。`www.baidu.com` 在 sing-box 严格保护下拿到百度香港的 45.113.192.x，响应的 scope 是 `/0`。标准保护下直连列表仍然查国内 DNS，不受影响，这也是默认用标准保护的原因。

### D01 调整：mihomo 最后一条 GEOIP 去掉 `no-resolve`（2026-09-29，用户决定）

- **依据**：查证 Surge 手册，`no-resolve` 是**建议**而不是要求。
  - 手册的说法：域名请求遇到第一条不带 `no-resolve` 的 IP 规则时会停下来，先在本地做一次 DNS 查询；带 `no-resolve` 就直接跳过这条规则。
  - 塔台当初全客户端统一加它，是因为 1.0.12 时 Surge 提示「IP 规则排在域名规则前面」，而且不加的话，列表外的域名会被拿去问本地 DNS。
  - 代价是列表外的国内网站会走代理。
- **现在的做法**：只对「MATCH 前最后一条、由塔台自动加上 `no-resolve` 的 `GEOIP`」去掉 `no-resolve`，范围如下：
  - 只限 mihomo 核心且支持 `#代理组` 的客户端：Clash / Clash Mi / Verge / Mac / FlClash / Clash Party。「Clash」App 原先被当作与 Stash 同文档而排除；2026-11-09 核对 clash.md 后确认它是 mihomo 1.19.33 衍生内核、配置按原样运行，已并入。
  - 列表中间的 GEOIP、来源文件自己写了 `no-resolve` 的规则、Karing / Stash / Shadowrocket / Surge / Loon 都不变。
- **配套 DNS 改动**：否则每个列表外的域名（包括国外的）都会被拿去问国内 DNS，等于泄露。
  - 标准保护的 `nameserver` 也改为经纯节点组、带中国子网的远程 DNS（和严格保护相同）。
  - 另加 `direct-nameserver: 国内 DoH`：列表里本来就直连的域名（例如百度）由它解析，拿到准确的 CDN 节点，也避开了不认 ECS 的网站。
  - 列表外的国内网站，直连时沿用判定时经代理 + ECS 拿到的国内地址，不会再查一次国内 DNS（实测确认）。
  - 找不到纯节点组（例如没有节点）时 DNS 无法经代理，仍保留 `no-resolve` 和国内 `nameserver`。
  - 「跟随方案」本来就用方案里的 DNS 解析所有域名，去掉 `no-resolve` 不会多发任何查询，所以也去掉。
- **代价**：列表外的国外网站要先经代理查一次 DNS 才能判定，首次连接会多一次经代理的 DNS 往返（约 100–300 ms，之后有缓存）。列表内的域名不受影响。
- 实测（mihomo 1.19.31，Clash Mi 导出的 ACL4SSR 默认方案，真实节点，fake-ip，经 mixed 端口发真实请求）：
  - 火山引擎、网宿、大疆、海康都命中 `GeoIP(cn)` 走直连。火山引擎从原来经代理的 1.29 秒降到 0.76 秒。
  - 百度命中国内列表直连，由 `direct-nameserver`（223.5.5.5 / doh.pub）解析。
  - Google 命中列表走代理，本机不解析。
  - Le Monde、Cloudflare 这类列表外的国外网站，只经代理向 8.8.8.8 查询，然后命中 MATCH 走代理，**没有发给国内 DNS**。
  - 国内 DoH 只收到节点域名和 doh.pub 自身的引导查询。
  - 24 份配置（默认 / 严格 / 跟随 × 8 个 Clash 格式目标）中，mihomo 系全部通过 `mihomo -t`。Stash 格式本来就含 mihomo 不支持的 `URL-REGEX`，和本次改动无关。
- `direct-nameserver` 需要 mihomo 1.19.0 以上。旧核心会忽略这个字段，直连时改用 `nameserver`（经代理 + ECS），仍然可用。

### 未改
- **sing-box 的 DNS 地址过滤写法（已迁移）**：1.14 已把 DNS 规则里不带 `match_response` 的 `rule_set` / `ip_cidr` 标为弃用，1.16 删除。
  - 原计划等官方客户端普及到 1.15 再迁移。实测发现 iOS 官方 App 每次启动都会弹「弃用警告 … 您的配置文件已过时，请联系您的配置提供者」，所以 2026-09-29 提前迁移。
  - 现在写成两条规则：`{"query_type":["A","AAAA"],"action":"evaluate","server":"remote-cn","client_subnet":…}`，后面跟 `{"match_response":true,"rule_set":["tower-geoip-cn"],"action":"respond"}`。
  - 行为和旧写法一致。只对 A / AAAA 查询做，其他类型不会重复查询两次。
  - 代价：官方 sing-box 目标要求 1.14 及以上，更旧的 App 会报配置错误。
  - 验证：sing-box 1.14.2 `check` 不再有弃用警告。标准和严格保护实跑，列表外的 8 个国内网站都拿到国内地址，国外网站结果不变。
