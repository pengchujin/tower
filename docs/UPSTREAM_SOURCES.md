# 上游客户端、内核与协议的发布渠道

塔台的导出依赖各客户端和内核的能力，它们更新后要及时复核。来源清单是 [`Scripts/upstream_sources.json`](../Scripts/upstream_sources.json)，`watch` 由脚本自动检查，`links` 供人工查阅。本文是清单的阅读版，最后核对于 2026-11-09。

## 怎么用

```bash
python3 Scripts/check_upstream_updates.py
```

- 第一次运行只记录基线（`.artifacts/upstream-state.json`，不提交），之后每次只列出变化：App Store 新版本和更新说明、GitHub 新 Release / 预发布、Telegram 新消息、TestFlight 名额变化、Sparkle 新版本、文档页内容变化。
- `--all` 列出全部当前值；`--only <id 或 client/core/protocol/converter>`、`--type <appstore/github/appcast/telegram/testflight/page>` 缩小范围；`--report <文件>` 另存报告；`--dry-run` 不更新基线。
- GitHub 匿名每小时 60 次，脚本会自动用 `gh auth token` 或 `GITHUB_TOKEN`。
- 只读公开页面，不发送任何订阅、节点或配置。
- 测试：`python3 Scripts/tests/check_upstream_updates_test.py`（含「每个 `ClientTarget` 都有来源」的校验，新增客户端时会提醒补清单）。

## 维护流程

每周跑一次，发版前必跑。

1. **先只看不记**：`python3 Scripts/check_upstream_updates.py --dry-run`。处理完再不带 `--dry-run` 跑一次，把基线推进到当前版本；没处理完的变化不要推进，下次还会列出来。
2. **分拣**：每条变化归到下面一类。
   - 只修 bug、界面、性能、和导出无关的新功能 → 忽略。
   - 新协议、新参数、新规则类型、新策略组选项、DNS 写法、导入 Scheme 变化 → 对照代码确认塔台是否已处理（`grep` 协议名 / 字段名，看 `ClientTarget.supports`、`RoutingRuleCapabilities`、各 `ConfigurationGenerator` 分支）。
   - 只在 TestFlight / beta / alpha → 记到 [TODO](TODO.md)「上游更新：等正式版」，正式版发布后再做。
   - 文档页哈希变化 → 打开页面对照 [CLIENT-COMPATIBILITY](CLIENT-COMPATIBILITY.md)、[RULE_EXPORT_AUDIT](RULE_EXPORT_AUDIT.md) 里引用的条目。
3. **改代码**：依据写进注释（客户端版本号 + 官方文档地址）。官方文档没写、只有 Sub-Store 等第三方实现时，要在兼容文档里注明并真机验收。无法忠实表达的仍按 CLAUDE.md 第 12 条拒绝并计数。内核更新用本地 `mihomo -t` / `sing-box check` 复验导出（只校验文件，不启动内核、不动网络）。
4. **记录**：改动写进 HANDOFF；还没做的写进 TODO「上游更新」一节；做完的从 TODO 勾掉。

### 更新来源清单

- 新增 `ClientTarget` 时同步在 `Scripts/upstream_sources.json` 加一条（`targets` 写 rawValue），否则脚本测试失败。
- 加渠道前先确认是官方的：官网或官方仓库链接到它才写 `official: true`；只能间接确认的写 `false` 并在 `notes` 说明。只收公告频道，不收讨论群。
- 渠道失效（仓库改名、App 下架、频道停更）时，`检查失败` 一节会报出来：改清单、更新本文表格，在 `notes` 写明原来的地址和变更日期。
- 改完清单跑 `python3 Scripts/tests/check_upstream_updates_test.py`，再 `--all --dry-run --only <id>` 实跑一次新条目。
- 页面哈希类（`type: page`）只放导出所依据的文档页，内容常变的页面（首页、带时间戳的页面）会一直误报，不要加。

### 渠道可信度

- **App Store lookup**（`itunes.apple.com/lookup?id=…&country=us`）是所有 iOS 客户端最可靠的正式版信号。Surge KB 的 iOS 发布说明停在 5.14.6，Stash 的 iOS 发布说明页落后于商店，都不能当版本来源。
- **Telegram 频道**是测试版最快的信号（QuanX、Surge、Stash、Clash 的 TestFlight 更新都先发在这里）。清单里 `official: false` 的频道内容准确但官网没有链接，不要当作官方声明引用。只收频道，不收讨论群（群没有公开预览）。
- **GitHub Release**：Karing 和 Clash Mi 的 GitHub 版本通常领先 App Store。mihomo、ClashMac 的 `Prerelease-Alpha` 是滚动 tag，发布日期不变，脚本按附件更新时间判断。

## 客户端

| 塔台目标 | 客户端 | 正式版 | 测试版 / TestFlight | 公告频道 | 文档与 URL Scheme |
| --- | --- | --- | --- | --- | --- |
| `surge` | Surge | App Store [1442620678](https://apps.apple.com/us/app/surge-5/id1442620678) | 仅购买者申请（[说明](https://kb.nssurge.com/surge-knowledge-base/faq/ios-testflight)） | [@SurgeTestFlightFeed](https://t.me/s/SurgeTestFlightFeed)、[@SurgeChangelog](https://t.me/s/SurgeChangelog)（均未经官网链接）；X [@nssurge](https://x.com/nssurge)、[@surgebeta](https://x.com/surgebeta) | [手册](https://manual.nssurge.com)、[Scheme](https://manual.nssurge.com/tools/url-scheme.html)、[KB](https://kb.nssurge.com) |
| `surge-mac` | Surge Mac | Sparkle [正式版](https://nssurge.com/mac/latest/appcast-signed.xml) | Sparkle [Beta](https://nssurge.com/mac/latest/appcast-signed-beta.xml) | 同上 | [发布说明](https://nssurge.com/support/mac/release-notes)、Homebrew `surge` |
| `shadowrocket` | Shadowrocket | App Store [932747118](https://apps.apple.com/us/app/shadowrocket/id932747118) | 无公开链接 | [@ShadowrocketNews](https://t.me/s/ShadowrocketNews)（群 [@ShadowrocketApp](https://t.me/ShadowrocketApp)） | 官网 [shadowlaunch.com](https://shadowlaunch.com)；[LOWERTOP/Shadowrocket](https://github.com/LOWERTOP/Shadowrocket) 是社区手册 |
| `loon` | Loon | App Store [1373567447](https://apps.apple.com/us/app/loon/id1373567447) | 无公开链接 | [@LoonNews](https://t.me/s/LoonNews)（群 [@Loon0x00](https://t.me/Loon0x00)） | [文档](https://nsloon.app/docs/intro)、[节点](https://nsloon.app/docs/Node/)、[Scheme](https://nsloon.app/docs/category/scheme) |
| `quanx` | Quantumult X | App Store [1443988620](https://apps.apple.com/us/app/quantumult-x/id1443988620) | 频道发布 TestFlight 版本 | [@QuanXNews](https://t.me/s/QuanXNews)（未经官网链接；[@QuanX_API](https://t.me/s/QuanX_API) 是第三方） | [sample.conf](https://github.com/crossutility/Quantumult-X/blob/master/sample.conf)、[url-scheme.md](https://github.com/crossutility/Quantumult-X/blob/master/url-scheme.md)（两份都在自动监控） |
| `clash` | Stash | App Store [1596063349](https://apps.apple.com/us/app/stash-rule-based-proxy/id1596063349)（中国区未上架） | 仅购买者，App 内申请（[说明](https://stash.wiki/en/faq/testflight)） | [@StashFeed](https://t.me/s/StashFeed)（群 [@StashFans](https://t.me/StashFans)） | [stash.wiki](https://stash.wiki)、[协议](https://stash.wiki/en/proxy-protocols/proxy-types)、[Scheme](https://stash.wiki/en/faq/url-schema)、[iOS 发布说明](https://stash.wiki/en/release-notes/ios) |
| `egern` | Egern | App Store [1616105820](https://apps.apple.com/us/app/egern/id1616105820) | 无公开链接 | [@egern_news](https://t.me/s/egern_news)（未经官网链接） | [文档](https://egernapp.com/docs/intro)、[Scheme](https://egernapp.com/docs/url-scheme) |
| `v2box` | V2Box | App Store [6446814690](https://apps.apple.com/us/app/v2box-v2ray-client/id6446814690) | — | 未找到官方频道 | — |
| `anywhere` | Anywhere | App Store [6758235178](https://apps.apple.com/us/app/anywhere-proxy/id6758235178) | — | 无；X [@argsment](https://x.com/argsment) | [README（含 Scheme）](https://github.com/NodePassProject/Anywhere#readme)，GPLv3，无 Release |
| `clash-apple` | Clash | App Store [6794257189](https://apps.apple.com/us/app/clash-rule-based-proxy/id6794257189) | 频道发布 TestFlight 版本 | [@clashbyclash](https://t.me/s/clashbyclash) | [clash.md](https://clash.md/guide/)、[Apple 平台差异](https://clash.md/guide/config/apple-platforms)；内核 [ProjectClash/Clash](https://github.com/ProjectClash/Clash/releases) |
| `karing` | Karing | App Store [6472431552](https://apps.apple.com/us/app/karing/id6472431552)；[GitHub](https://github.com/KaringX/karing/releases) 更早 | [TestFlight](https://testflight.apple.com/join/RLU59OsJ)（已满） | 群 [@KaringApp](https://t.me/KaringApp) | [karing.app](https://karing.app/en/)、[Clash 兼容](https://karing.app/clash) |
| `clash-mi` | Clash Mi | App Store [6744321968](https://apps.apple.com/us/app/clash-mi/id6744321968)；[GitHub](https://github.com/KaringX/clashmi/releases) 更早 | [TestFlight](https://testflight.apple.com/join/bjHXktB3)（已满） | 群 [@ClashMiApp](https://t.me/ClashMiApp) | [clashmi.app](https://clashmi.app/guide/) |
| `hiddify` | Hiddify | App Store [6596777532](https://apps.apple.com/us/app/hiddify-proxy-vpn/id6596777532)；[GitHub](https://github.com/hiddify/hiddify-app/releases) | [TestFlight](https://testflight.apple.com/join/dsNjHxjb)（开放，链接来自第三方汇总） | [@hiddify](https://t.me/s/hiddify)（波斯语为主） | [文档](https://hiddify.com/app/)、[Scheme](https://hiddify.com/app/URL-Scheme/) |
| `sing-box` | sing-box MT | App Store [6785326793](https://apps.apple.com/us/app/sing-box-mt/id6785326793) | 仅赞助者（[@yet_another_sponsor_bot](https://t.me/yet_another_sponsor_bot)） | 见下方 sing-box 内核 | [Apple 客户端](https://sing-box.sagernet.org/clients/apple/)、[Scheme](https://sing-box.sagernet.org/clients/general/) |
| `clash-verge` | Clash Verge Rev | [GitHub](https://github.com/clash-verge-rev/clash-verge-rev/releases) | `-rc.N`；滚动 `alpha` / `autobuild` | [@clash_verge_re](https://t.me/s/clash_verge_re) | [clashverge.dev](https://www.clashverge.dev)、[Scheme](https://www.clashverge.dev/guide/url_schemes.html) |
| `clashmac` | ClashMac | [GitHub](https://github.com/666OS/ClashMac/releases)（只发二进制） | 滚动 `Prerelease-Alpha` | [@Pinched666](https://t.me/s/Pinched666)（作者个人频道，杂谈多） | [clashmac.app](https://clashmac.app/guide/) |
| `flclash` | FlClash | [GitHub](https://github.com/chen08209/FlClash/releases) | 频道发 `-pre.N` | [@FlClash](https://t.me/s/FlClash) | [CHANGELOG](https://github.com/chen08209/FlClash/blob/main/CHANGELOG.md) |
| `mihomo-party` | Clash Party（原 Mihomo Party） | [GitHub](https://github.com/mihomo-party-org/clash-party/releases) | — | 群 [@mihomo_party_group](https://t.me/mihomo_party_group) | [clashparty.org](https://clashparty.org/docs/handson)、Homebrew `clash-party` |

## 内核与参考转换器

| 名称 | 发布 | 频道 | 文档 | 说明 |
| --- | --- | --- | --- | --- |
| mihomo | [GitHub](https://github.com/MetaCubeX/mihomo/releases)，滚动 `Prerelease-Alpha` | 无公开官方频道 | [wiki.metacubex.one](https://wiki.metacubex.one/config/) | mihomo 系客户端的内核；`mihomo -t` 校验 |
| sing-box | [GitHub](https://github.com/SagerNet/sing-box/releases)，`-alpha/beta/rc.N` | [@yapnc](https://t.me/s/yapnc) | [配置](https://sing-box.sagernet.org/configuration/)、[changelog](https://sing-box.sagernet.org/changelog/) | sing-box MT 与 Hiddify 的内核；`sing-box check` 校验 |
| hiddify-core | [GitHub](https://github.com/hiddify/hiddify-core/releases) | 同 Hiddify | [文档](https://i.hiddify.com/core) | 版本变化频繁 |
| KaringX/sing-box | 无 Release，跟 `karing_v<上游版本>` 分支 | — | — | 看 Karing Release 即可 |
| subconverter | [GitHub](https://github.com/tindy2013/subconverter/releases) | [@subconverter](https://t.me/s/subconverter)（2024 后无更新） | [README](https://github.com/tindy2013/subconverter/blob/master/README-cn.md) | 对照用 |
| Sub-Store | [GitHub](https://github.com/sub-store-org/Sub-Store/releases)（tag 不带 v） | — | [Wiki](https://github.com/sub-store-org/Sub-Store/wiki) | 对照用 |

## 协议

| 协议 | 规范 / 官网 | 分享链接 | 参考实现（自动跟踪） | 备注 |
| --- | --- | --- | --- | --- |
| Shadowsocks | [AEAD](https://shadowsocks.org/doc/aead.html)、[SIP022](https://shadowsocks.org/doc/sip022.html)、[SIP003 插件](https://shadowsocks.org/doc/sip003.html) | [SIP002](https://shadowsocks.org/doc/sip002.html) | [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust/releases) | simple-obfs 已弃用 |
| v2ray-plugin | [仓库](https://github.com/shadowsocks/v2ray-plugin) | SIP002 `plugin=` | 同左 | |
| ShadowTLS | [v3 协议](https://github.com/ihciah/shadow-tls/blob/master/docs/protocol-v3-en.md) | 无官方格式 | [ihciah/shadow-tls](https://github.com/ihciah/shadow-tls/releases) | 各客户端写法不同 |
| ShadowsocksR | [仓库](https://github.com/shadowsocksrr/shadowsocksr) | [SSR 链接](https://github.com/shadowsocksrr/shadowsocks-rss/wiki/SSR-QRcode-scheme) | 停更 | sing-box / Surge / Egern 不支持 |
| VMess | [v2fly](https://www.v2fly.org/developer/protocols/vmess.html) | [v2rayN 旧格式](https://github.com/2dust/v2rayN/wiki/Description-of-VMess-share-link)、[Xray #716](https://github.com/XTLS/Xray-core/discussions/716) | [v2fly/v2ray-core](https://github.com/v2fly/v2ray-core/releases) | |
| VLESS / REALITY / Vision | [Xray 文档](https://xtls.github.io/development/protocols/vless.html)、[REALITY](https://github.com/XTLS/REALITY) | [Xray #716](https://github.com/XTLS/Xray-core/discussions/716) | [XTLS/Xray-core](https://github.com/XTLS/Xray-core/releases)，频道 [@projectXtls](https://t.me/s/projectXtls) | Surge 不支持 |
| Trojan | [协议](https://trojan-gfw.github.io/trojan/protocol) | [trojan-go 草案](https://p4gefau1t.github.io/trojan-go/developer/url/) | 停更 | |
| Hysteria / Hysteria 2 | [v2 协议](https://v2.hysteria.network/docs/developers/Protocol/)、[v1](https://v1.hysteria.network/docs/protocol/) | [v2 URI](https://v2.hysteria.network/docs/developers/URI-Scheme/) | [HyNetworks/hysteria](https://github.com/HyNetworks/hysteria/releases)（原 apernet，tag `app/v2.x.y`） | |
| TUIC v5 | [SPEC](https://github.com/tuic-protocol/tuic/blob/master/SPEC.md) | 无官方格式 | [Itsusinn/tuic](https://github.com/Itsusinn/tuic/releases)（官方仓库 2023 停更） | |
| MASQUE | [RFC 9298](https://www.rfc-editor.org/rfc/rfc9298.html)、[RFC 9484](https://www.rfc-editor.org/rfc/rfc9484.html)、[RFC 9297](https://www.rfc-editor.org/rfc/rfc9297.html) | — | — | [Surge](https://manual.nssurge.com/policies/masque.html) 用 CONNECT-UDP；mihomo / Stash 用 CONNECT-IP |
| WireGuard | [协议](https://www.wireguard.com/protocol/) | — | — | sing-box 用 [endpoint](https://sing-box.sagernet.org/configuration/endpoint/wireguard/)，outbound 已弃用 |
| AnyTLS | [协议](https://github.com/anytls/anytls-go/blob/main/docs/protocol.md) | [URI](https://github.com/anytls/anytls-go/blob/main/docs/uri_scheme.md) | [anytls/anytls-go](https://github.com/anytls/anytls-go/releases) | |
| Snell | [KB 发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)（自动监控） | — | 闭源 | 当前 v6；sing-box 1.14 起支持 |
| TrustTunnel | [PROTOCOL.md](https://github.com/TrustTunnel/TrustTunnel/blob/master/PROTOCOL.md)、[trusttunnel.org](https://trusttunnel.org/) | [DEEP_LINK.md](https://github.com/TrustTunnel/TrustTunnel/blob/master/DEEP_LINK.md) | [TrustTunnel/TrustTunnel](https://github.com/TrustTunnel/TrustTunnel/releases) | 不在 AdguardTeam 组织下 |
| Tailscale | [Auth Keys](https://tailscale.com/kb/1085/auth-keys) | — | [tailscale/tailscale](https://github.com/tailscale/tailscale/releases) | 见 [TAILSCALE](TAILSCALE.md) |
| SOCKS5 / HTTP / SSH | [RFC 1928](https://www.rfc-editor.org/rfc/rfc1928.html)、[RFC 9110 CONNECT](https://www.rfc-editor.org/rfc/rfc9110.html#name-connect)、[RFC 4254](https://www.rfc-editor.org/rfc/rfc4254.html) | 惯例写法 | — | |

各客户端的协议文档页（mihomo、sing-box、Surge、Stash、Egern 等）记录在清单每个协议条目的 `links` 里。

## 首次调研发现的变化（2026-11-09）

以下已在 `a29201b` 处理（「Clash」App 改用 mihomo DNS、Clash Party 改名），或只是渠道变化，已写进清单：

- 「Clash」App 有独立文档 [clash.md](https://clash.md/guide/)，基于 mihomo，当前仓库在 ProjectClash 组织（不再是 TokenPLS/Hako）。
- Mihomo Party 改名 Clash Party，仓库 `mihomo-party-org/clash-party`，Homebrew cask `clash-party`。
- sing-box 官方 Apple 客户端旧上架 SFI（6451272673）和 sing-box VT（6673731168）已下架，当前是 sing-box MT（6785326793）；商店版本号与内核 tag 不同步。
- Surge Mac 的 Sparkle 源在 `/mac/latest/`。
- Hysteria 仓库改名 HyNetworks/hysteria；TUIC 官方仓库停更，活跃分支 Itsusinn/tuic。

还没处理的上游变化见 [TODO](TODO.md#上游更新待处理2026-11-09)。
