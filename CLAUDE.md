# Claude 接手指南

这是“塔台”iOS App 的仓库级入口说明。开始修改前，请依次阅读：

1. `README.md`：产品能力、隐私模型和已知边界。
2. `docs/HANDOFF.md`：当前实现状态、发布边界和任务索引。
3. `docs/ARCHITECTURE.md`：模块、数据流、配置生成和测试结构。

## 工程基线

- 原生 SwiftUI，最低 iOS 17，建议使用 Xcode 26 或更新版本。
- 工具链必须按 [AGENTS.md](AGENTS.md) 的机器规定设置 DEVELOPER_DIR，并用 xcodebuild -version 复核；不切换全局 xcode-select。命令见 [DEVELOPMENT](docs/DEVELOPMENT.md)，账号/上传排错见 [RELEASING](docs/RELEASING.md)。
- 工程：`Tower.xcodeproj`；Scheme：`Tower`。
- Bundle ID：`com.jzb.tower`。
- App Store Connect App ID：`<App Store Connect App ID>`。
- 规则快照和 IP 国家库都随 App 打包，运行时不依赖远程转换服务。
- `DEVELOPMENT_TEAM` 故意没有写死在工程里；本地运行时由 Xcode 或命令行覆盖。

## 不可破坏的产品约束

1. 订阅内容、节点和生成配置只在本机处理，不上传到第三方转换或 IP 查询服务。
2. 域名节点可以使用系统 DNS 解析，但国家识别必须继续查询内置离线 IP 库。
3. Surge、Stash、Shadowrocket、Loon 的一键导入继续使用仅绑定 `127.0.0.1`、3 分钟自动失效的临时服务。
4. Quantumult X 没有完整本地配置导入 Scheme，保持系统文件分享，不要伪装成完整一键导入。依据是官方 [url-scheme.md](https://github.com/crossutility/Quantumult-X/blob/master/url-scheme.md)：`update-configuration` 和 `add-resource` 的 `remote-resource` 只接受 `server_remote` / `filter_remote` / `rewrite_remote` 三种**远程资源地址**，`[policy]` 策略组不在其中。只导节点和规则会得到一份引用了不存在策略组的配置。
5. 国家/地区组默认使用延迟优选，同时保留父级策略中的手动选择入口；不要让地区组互相引用或引用包含自己的上级组。
6. 策略组名称只显示一个前置 Logo。生成配置时可附带各客户端支持的图标字段，但不要把同一个 Emoji 再拼进可见名称：能画图标的客户端（`PolicyGroupIconSupport.drawsIcons`）写图标、名字去掉 Emoji；只写字段、未确认会显示的客户端保留 Emoji。图标一律由 `PolicyGroupEmoji` 决定的 Emoji 换成 Fluent Emoji 3D 图片；QuanX 真机上 256px 的 Fluent 原图画不出来，改用塔台发布的 144px「Fluent 3D + 浅色圆底」（`Rulesets/PolicyGroupIcons/FluentCircle/`，raw.githubusercontent.com 地址，用户 2026-10-19 选定），覆盖全部 Fluent Emoji 和国旗，和其他客户端用同一个 Emoji；未发布前回退 SF Symbols（`img-url=<名称>.system`，只覆盖 `PolicyGroupIconSupport.symbols` 的键）；地区组名字始终保留国旗 Emoji（客户端展开组时候选只显示名字），同时写圆形国旗图标（只显示 Σ 默认图标太空），这是「不要重复 Emoji」的唯一例外；Surge / Surge Mac 会把名字里的国旗画在图标位，不写国旗图标（用户 2026-10-19 确认）；识别顺序：名字自带 → 名字里的服务 / 类别 → 地区 → 组的作用（自动、故转、手动、直连…）→ 组里引用的规则列表 → 成员（只有 DIRECT、只有 REJECT、节点过滤都指向同一地区）→ 按类型兜底（手动选择组为 🌐）；都认不出时不补 Emoji，只有图标兜底。词表来自 GitHub 上 8,362 份公开配置的组名，改词表后用 `Scripts/policy_group_corpus.py` 复核覆盖率并逐条看「结果变了」的组名。在线规则库的条目 Emoji（`RuleCatalogEntry.emoji`）决定了已保存的组名，取值不能改。
7. 首页订阅展开不使用从顶部滑入的过渡；节点列表不再提供“显示更多节点”。
8. 首页使用自绘的点阵世界地图（`WorldDotMapView`），不用 MapKit。地图数据是 `Tower/Resources/WorldMap/WorldDotMap.txt` 陆地点阵和 `WorldDotCountries.txt` 国家归属层，用 `Scripts/update_world_dot_map.py` 一并重新生成；有节点覆盖的国家按延迟状态显示地图点，未测试为灰蓝色，选中国家保持同色系加深、加密且名称保持中性文字；覆盖国家的整个点阵轮廓必须可直接点击，不再叠加独立绿色定位点。
9. 节点名来自机场 remark，属于不可信输入。写进配置前必须经过 `confName`（INI 系）或 `yaml()`（Clash），两者都会折掉换行；不要新增绕过它们的名称输出路径。
10. 写到磁盘的凭据类文件一律使用 `.completeFileProtection`，临时目录必须有清理逻辑。这包括导出配置和二维码 PNG，不只是 `state.json`。
11. 打开添加面板时自动发起一次系统剪贴板读取请求；只在内容是受支持的订阅或节点链接时自动填充，同一次面板展示不要重复读取。保留“从剪贴板粘贴”按钮作为手动入口。
12. 无法忠实表达的节点（例如带 SIP003 plugin 的 SS）要拒绝并计入跳过数，不要导入成“看起来正常但连不上”的节点。
13. Quantumult X 的全节点 `url-latency-benchmark` 要像 subconverter 一样直接列出解析后的代理节点，不得用 `server-tag-regex=.*`，否则会把 `direct` 也收进自动选择。地区等过滤组仍可用转义后的精确 `server-tag-regex`。
14. 导入的规则方案（`RuleScheme`）按来源文件声明的策略组原样还原，地区组用节点名正则；内置 Self-Configuration 预设继续用离线 IP 国家库分组。不要把两套机制混在一起。
15. `Tower/Resources/ACL4SSR/` 下所有资源必须保留 `ACL4SSR_` 前缀。Xcode 把资源拍平到 bundle 根目录，两套规则都含 `Apple.list`、`Microsoft.list`、`Telegram.list` 和 `manifest.json`，去掉前缀会互相覆盖；`RuleRepository` 也依赖这个前缀跳过它们。
16. 只有用户主动导入或刷新规则链接时才允许联网取规则；内置快照任何情况下都不联网。规则地址只接受 HTTPS。
17. **本仓库是公开的**（https://github.com/pengchujin/tower）。设备 UDID、团队 ID、描述文件 UUID、App Store Connect App ID、构建机地址、个人邮箱一律不写进任何文件，需要时用 `<设备 UDID>` 这类占位符。提交前先检查新增文档有没有把这些写回去。
18. 套餐流量按 `subscription-userinfo` 响应头 → 内容里的 `STATUS=` 行 → 节点列表里的公告行取值。**节点始终以订阅原地址的返回体为准**：机场的 `flag=clash` 转换器会丢掉它表达不了的协议（实测有机场因此少 12 个 AnyTLS 节点），所以 `flag=clash` 只在缺结构化配额时补发一次、且只读响应头，不用它的返回体。
19. 节点地区**用户手动指定优先，否则先按节点名判断**（国旗 Emoji → 中英文国名/别名/城市 → 大写国家代码），名字看不出来才查内置离线 IP 库；不要从服务器域名后缀或词语猜国家。网络组织按服务器 IP 查内置 ASN 库，不表示实际代理出口；策略分组和界面用同一个顺序，不要让两边给出不同的国家。国家表由 `Scripts/update_country_table.py` 生成到 `Tower/Services/CountryTable.swift`，不要手改。
20. 国旗一律用 Emoji 正常渲染，不要为个别地区自绘图形；iOS 没有字形的（例如 TW）就显示成两个字母，这是系统行为。列表里国旗外面不加圆形底。
21. `Tower/Resources/` 下的第三方数据不适用源码的 MIT 许可。新增或更新打包资源时，必须同步更新 `THIRD-PARTY-NOTICES.md` 和对应目录的 NOTICE，注明来源、固定版本和许可证。`LICENSE` 里「仅覆盖源码」那段说明不要删除，即使 GitHub 因此把许可证识别成 `Other`。
22. 刷新订阅必须保住用户「取消勾选」的节点。节点 id 每次解析都会重新生成，机场又常把剩余流量、倍率写进 remark，塔台自己也会给纯国旗节点重编号——所以不能只按含 name 的精确 identity 匹配。`AppModel.carriedOverExclusions` 是唯一的判定入口：先精确匹配，失配再用去掉 remark 的宽松键，且只有该键在刷新前后都唯一时才认。丢失排除的后果是静默的——节点直接回到每一份导出配置里。
23. `AppModel.apply()` 必须把 `snapshot.updatedAt` 恢复到 `lastLocalEditAt`。不恢复的话，启动后第一次前台同步会拿 `.distantPast` 去和 iCloud 比，任何远端快照都赢——包括更旧的那份，然后覆盖本地文件。离线时改的订阅会在下次启动被静默丢弃。
24. Tailscale 内网（`TailnetConnection`）不是节点，不能进任何策略组、测速组或地区组，只接收置顶的 Tailscale 地址段、MagicDNS 后缀和用户子网规则。Auth Key 只存本机钥匙串（`TailnetAuthKeyStore`），不进快照、不同步 iCloud，配置预览里要打码；不要写给 Surge（它按 Key 哈希存身份，会多注册一台设备），Stash 目前没有可用的客户端登录，必须写。`stableSlug` 来自连接 UUID，Surge 配置段名和 mihomo / sing-box 状态目录都依赖它，改了会让每次重新导入都多出一台设备。塔台不代用户登录 Tailscale 或自动生成 Key（OAuth apps 只限同一 tailnet、Key 一次性且 1 小时过期），评估见 `docs/TAILSCALE.md`。

25. 分流规则只按各客户端文档输出：规则类型、选项、内置策略都以 `RoutingRuleCapabilities` / `RoutingBuiltinPolicies` 的白名单为准，选项写在策略名后面。不能表达的规则跳过并提示；拦截规则跳过时，要在兼容性提示最前面说明「这些请求不会被拦截」，但不阻止整份导出。可以换成等价写法的就换（例如 Loon 的 `*.x` 通配改写成「后缀 x 且不是 x 本身」的 `AND`/`NOT` 逻辑规则、sing-box 的 GEOIP / IP-ASN 用内置库展开），不能为了「看起来能导」把 Surge 方言原样透传，也不能改写成更宽的拦截范围。MRS 规则集没有解码器，只给 mihomo 系和 Stash（3.1.0 起）远程引用。Loon 和 QuanX 先匹配本地规则、再匹配远程列表，远程规则集不能排到任何本地规则前面；内置方案结尾的 `GEOIP,CN` 和 QuanX 的 DNS 保护兜底规则因此也以塔台发布的列表引用（`Tower_GEOIP_CN_*`、`Tower_catch_all_quanx`），客户端写不出的规则不算挡在前面的本地规则。IP 规则默认自动加 `no-resolve`；唯一例外是 mihomo 系（不含 Karing；「Clash」App 有自己的 clash.md 文档、内核是 mihomo 衍生版，2026-11-09 起算在内）MATCH 前最后一条自动加的 `GEOIP`，而且只在 DNS 经代理带 ECS 解析时（或「跟随方案」）才去掉——别在 DNS 仍走国内解析时去掉，否则列表外的域名会全部泄露给国内 DNS。依据见 `docs/RULE_EXPORT_AUDIT.md`。

26. 规则定制页的「分流规则」是一个列表、所有组都能拖，按**客户端里策略组的声明顺序**（`groupOrder`）排列，和规则首页「查看策略组」、导出到 Stash 等客户端的面板顺序必须一致（「节点选择」排第一）；不要单独拆出「节点分组」。**拖动同时调整被拖组的匹配优先级**（用户 2026-10-15 确认）：`AppModel.matchingOrderAfterDragging` 看这次拖动越过了哪些组——往下拖越过了原本排在它后面匹配的组，就改为紧跟在其中最后匹配的那个之后；往上拖越过了原本排在它前面匹配的组，就改为紧挨在其中最先匹配的那个之前（拖过头、越过多组时也成立）；往上拖从不降低优先级，往下拖从不提高，放下位置与现有匹配先后一致时匹配不变；没有规则的节点组只改面板顺序。结果存 `RuleSchemeCustomization.matchingOrder`，由 `RuleScheme.reordering` 应用：只有被拖的组整组移动，其余组每条规则原地不动，行尾 `GEOIP` 兜底规则留在原处。匹配一旦改变且有域名因此改走别的组（`matchingOrderConflicts` / `RuleGroupDomainMatcher`），必须弹「匹配结果会改变」并可「撤销」（同时恢复 `groupOrder` 和 `matchingOrder`）。绝不能把 `groupOrder` 整张套到规则上（issue #40：会让「节点选择」的 GFW 大列表压过 AI、奈飞、直连和广告拦截）。匹配顺序其余部分 = 来源方案顺序 + 规则库/规则集插到第一条冲突规则前（`customRulesetInsertionIndex`）+ 策略组详情「我添加的规则」（`CustomRuleFlow.isGroupSupplement`）永远最先、按 `SupplementRule.matchingOrder` 从具体到宽泛。`rulePriorityOrder` 只为清理旧数据保留读取，不要再写入或应用。

## 开发入口

构建、测试、本地化、真机安装命令统一维护在 [DEVELOPMENT](docs/DEVELOPMENT.md)。更新资源须核对 manifest / NOTICE、哈希与测试，规则发布见 [RELEASING](docs/RELEASING.md)。客户端、内核与协议的上游更新用 `Scripts/check_upstream_updates.py` 检查，维护流程见 [UPSTREAM_SOURCES](docs/UPSTREAM_SOURCES.md#维护流程)，待处理项在 [TODO](docs/TODO.md)。

## 改动验收

- 每次提交至少通过 TowerTests；配置生成相关修改要覆盖全部目标客户端。
- 新增或修改界面文案后跑 `Scripts/check_localization.sh` 发现缺口，再用 `Scripts/generate_localizations.py --source-catalog <Xcode 导出的 Localizable.xcstrings>` 填补，短标签和无障碍文案需人工复核。`LocalizationTests` 只校验「目录里已有的条目是否 15 种语言齐全」，对「源码有、目录没有」完全无感——这类缺口不会报错，只会在其余 14 种语言下直接显示中文。该脚本用 Xcode 自己的提取器比对，不要改用 grep 手写：`Text`、`Label`、`.navigationTitle`、`.accessibilityHint`、弹窗标题等位置手写正则覆盖不全，插值也无法还原成 `%@` / `%lld`。
- 目录里被 Xcode 标成 `stale` 的条目**不要删**。内置 ACL4SSR 方案名和简介来自 manifest，运行时经 `String(localized: String.LocalizationValue(name))` 本地化，静态提取器看不见它们。
- 涉及导入、分享、剪贴板、地图、ICMP、动画或大文本预览时，模拟器结果只算基础验证，必须再用真机验收。
- 发布新包前递增 `CURRENT_PROJECT_VERSION`，归档并核对 Bundle ID、版本号和签名团队。
- 不提交 `.artifacts`、DerivedData、归档、IPA、证书、描述文件、App Store Connect API Key 或任何密码。
- 加密合规：当前实现没有自研或非标准加密，只通过 Apple 系统网络栈使用 HTTPS。App target 的 Debug/Release 都已设置 `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`，构建不会再在 App Store Connect 留下待回答的出口合规问题；新增 target 时记得一并设置。

真机清单见 `docs/DEVELOPMENT.md`，待办见 `docs/TODO.md`，当前状态见 `docs/HANDOFF.md`。
