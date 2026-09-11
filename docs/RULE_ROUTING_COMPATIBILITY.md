# Surge / Clash 分流规则修复与对比验证

更新：2026-09-11，1.0.14（52）发布候选。这里的“支持”指塔台的规则导入、持久化和生成能力；各客户端的版本、平台和运行条件仍然适用。

## 最新实现

Mihomo YAML 的锚点、别名、合并、跨行 flow 容器和尾随逗号已重新实现，并加入输入大小、递归深度与展开预算限制。仅解析配置模板；未恢复把 MRS / GEOSITE 转成海量文本规则的试验。公开模板的规则下载、保存重开和 Mihomo 输出已验证，完整 YAML 规范的全部语法不在支持范围内。

规则方案支持链接、文本和文件导入；Clash 的 proxy-provider 与策略组分开处理。规则集编辑按用户反馈保留文本输入和下方客户端兼容性提示，已移除逐条条件预览与表单。导入名称不含 Emoji 时，预览、定制和候选列表保持纯文本。

## 历史回退：Smart YAML / MRS 文本展开

用户实测反馈严重卡顿和目标客户端崩溃，已按要求回退该轮改动。此前将 MetaCubeX MRS 改为文本资源后，展开约 170,756 条规则，部分输出达到数 MB；哈希一致、策略引用有效及核心语法检查不能代替客户端加载的内存和交互稳定性验证。这轮未完成必要的容量与性能验收，不应视为可用兼容方案。

撤回范围包括 YAML 锚点/别名/合并、具名 direct/reject 别名、MRS 同源文本替换、缓存读取防护及该轮新增测试/文案。保留下文之前完成的分流规则修复。回退当时恢复为拒绝该 Smart YAML；后续仅重新实现了上文的有限 YAML 模板语法支持。

电脑端已切回 ACL4SSR 默认方案，并移除本次试验导入的方案和不再被引用的缓存。旧试验记录在本机 `.artifacts/smart-yaml-fix/`，回退记录在 `.artifacts/smart-yaml-rollback/`；旧导出产物不应继续导入客户端。回退后 20 项 XCTest、15 项 Swift Testing 定向回归通过。手机和电脑已覆盖安装并启动回退开发版 1.0.13（51）；手机仍保存两份该方案，当前未选中，已告知用户需另行移除已导入数据。

## 本轮改动

| 原问题 | 当前处理 |
| --- | --- |
| B01 / B02 普通 REJECT、DIRECT 被筛掉或编辑器拒绝 | 修复规则组筛选与策略校验；内置策略保留，不依赖是否勾选同名业务组 |
| B03 Mihomo 网络、来源、端口、进程等规则丢失 | 补充能力映射；AND / OR / NOT 使用递归条件树，保留次序和子条件 |
| B04 Surge 与 Mihomo 规则名称不匹配 | 转换 DEST-PORT / DST-PORT、PROTOCOL TCP/UDP / NETWORK、SRC-IP / SRC-IP-CIDR、进程名称与路径；端口比较和多个范围进行等价转换 |
| B05 domain / ipcidr provider 丢失 | 保存 behavior / format / interval；处理内联 payload、已下载的裸域名与 CIDR；支持 YAML flow payload 和 payload 行尾注释 |
| B06 远程与展开结果不同 | 补齐上述 provider、普通规则参数与网络/端口条件的展开路径。Egern 和 sing-box 原生资源的通用展开仍未完成 |
| B07 Loon Remote Rule 未导入 | 读取远程地址与 policy，尊重 enabled=false |
| B08 / B09 规则参数被当成策略或丢失 | 固定顶层策略字段，分别保存普通规则、FINAL 和资源引用参数；规则文本编辑往返保留资源元数据。目标不能表达时提示；不能表达 FINAL 条件时阻止导出 |
| B10 Surge 含逗号的引号正则输出损坏 | 保留引号、括号、转义和行尾注释边界。Mihomo 不能表达的叶子逗号值不直接输出 |
| B12 Stash URL-REGEX 被误删 | Stash 与 Mihomo 分开判断；局域网自动识别也分开，不再将 Clash Mi 交给 Stash 生成器 |
| B13 远程 QuanX 域名别名丢失 | HOST / HOST-SUFFIX / HOST-KEYWORD / HOST-WILDCARD 先转为公共域名规则，引用策略覆盖资源的策略 |
| B15 丢失无提示、计数不准确 | 被跳过的规则给出规则与目标提示，并从计数扣除；REJECT 条件或内置策略不能表达时阻止生成可用配置 |
| D01 自动添加 no-resolve | **保留用户要求的既有设计，不作为 Bug，也未撤回** |

保留原来的 ACL4SSR 仓库路径解析、任意数字检测间隔和局域网按钮动画修复。

## UDP 443 的结果

Mihomo：

```yaml
- AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT
- DOMAIN-SUFFIX,openai.com,OpenAI
```

Surge：

```ini
AND,((PROTOCOL,UDP),(DEST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT
DOMAIN-SUFFIX,openai.com,OpenAI
```

sing-box 使用包含 network、port、domain_suffix 三个子条件的 logical/and 规则，action 为 reject。chatgpt.com 可以使用同样的结构。不会把不能表达的协议条件直接去掉，变成整个域名的 REJECT。

Mihomo 与 sing-box 的本机运行测试各检查四种请求：openai.com UDP 443 拒绝；同域名 TCP 443、UDP 8443、其他域名 UDP 443 均选择 OpenAI。测试保留生成的业务规则，替换入站与上游传输为 loopback；sing-box DNS 使用本地合成回答。非拒绝请求有实际选择 OpenAI/Test 出站的日志。没有启用系统代理或 TUN；这不等于真实机场出口连通、App 网络扩展或 OpenAI 可用性验证。Surge 只做了 CLI 配置校验，没有切换用户现有配置。

## 与参考转换器对比

使用本地 SubConverter 0.9.0 和 SubStore 2.38.4 的规则模块。8 类合成规则分别比较 Surge / Clash：SubConverter 同时检查 INI 的内联规则与列表资源两条路径；SubStore 调用上游解析器和生成器，替换日志与 YAML 序列化适配层，不改匹配逻辑。SubStore 是规则资源转换器，不能用它证明完整策略组配置往返无损。

| 输入 | SubConverter 0.9.0 实测 | SubStore 2.38.4 实测 | 塔台处理 |
| --- | --- | --- | --- |
| DOMAIN-SUFFIX | 保留规则和绑定的 REJECT | 保留域名匹配器 | 保留，筛选后也保留 |
| AND | 部分路径丢弃；Surge 输出出现丢失策略字段 | 解析结果为空 | 保留条件树并转换方言 |
| DEST-PORT | 列表导出 Clash 丢弃；内联路径保留错误方言 | Surge 输出 DST-PORT | 输出目标客户端所需类型 |
| SRC-PORT | Surge 列表路径丢弃 | 归并为 IN-PORT，改变语义 | 区分来源端口与监听端口 |
| SRC-IP 单地址 | Clash 列表路径丢弃；内联不转换 | Clash 改名但没有补 CIDR 前缀 | 按 IPv4 / IPv6 补 /32 或 /128 |
| IP-CIDR,no-resolve | 保留 | 保留 | 保留，并维持既有自动补标志设计 |
| 带逗号的 URL 正则 | 被拆分或截断 | 未解析 | Surge 保留；Mihomo 提示不可表达 |

参考工具存在自己的边界，不能以“与它一样”作为正确性标准。最终依据官方方言、实际生成文件和核心校验。

## 样本与验证边界

- 复用原调研的 113 份输入及 17 份资源，保留修改前后模型、文本编辑、规则组筛选、远程/展开和各目标输出。
- 复用本机授权的 17 份订阅缓存，共解析 1,205 个节点，生成 546 份产物；9 份仅节点输出为空，原因是该目标没有支持的节点，与本轮分流规则丢失不同。私人地址、节点和配置不入仓库，也未发给外部转换服务。
- 256 份非空输出的核心检查：Surge 92/92、Mihomo 82/84、sing-box 80/80；两项 Mihomo 限制见下一条。Mac 全量 1,056 项 XCTest（33 跳过）与 81 项 Swift Testing 零失败，最终资源参数补修另有 15 项定向回归通过。iOS 全量 1054 项 XCTest（3 跳过）与 82 项 Swift Testing，零失败；不把“不支持某个目标而阻止导出”的空文件记作核心通过。
- 已验证的版本限制：本机 Mihomo 1.19.27 不认识新版文档中的 REMATCH-NAME；UID 在该 macOS 核心不可用。保留原规则不代表旧版/所有平台支持。

两端开发版已覆盖安装并启动，版本仍为 1.0.13（51），未发布；Mac 主窗口与两端签名已核对。已有方案需重新导入或重新保存原配置文本，再重新导出；刷新远程规则不能恢复此前解析时丢失的字段。

## 本地规则编辑界面初版验证记录（2026-09-10，表单现已移除）

“我的规则集”已使用共同解析器；条件摘要、AND / OR / NOT 嵌套表单、原文切换、动作与兼容性提示已接通到保存、持久化和生成。明确的内置拒绝/直连动作保持，普通策略名仍按规则集的绑定方式处理，界面会说明。无效输入指出原始行号并拒绝覆盖；表单仅重写当前行，其他行及换行格式保持。远程列表继续作为引用，不在编辑器内展开下载内容。

Mac 实际操作及模拟器 UI 往返测试通过；从该本地规则保存链路产生的三份小配置通过 Mihomo / Surge / sing-box 核心语法检查。Mihomo / sing-box 本地回环各四种路由情况通过，Surge 仅作语法检查。实体手机覆盖安装启动成功，但真机 UI runner 在测试连接建立前退出（code 74），手机触摸行为尚未验收。预览每页最多 20 条，不创建全列表条件表单。Loon / Shadowrocket 未实现递归方言转换的旧透传路径已关闭，涉及拒绝时阻止对应导出。该改动不恢复 Smart YAML / MRS 文本展开试验。

## 仍未完成的边界

- Mihomo SUB-RULE、SCRIPT、依赖命名规则集的复杂组合与完整脚本定义，没有通用迁移实现。
- Surge 本地文件或自定义命名 RULE-SET 依赖没有随配置搬运；不直接生成悬空引用。SYSTEM / LAN 可保留给 Surge，其他目标没有通用等价表达。
- 需要认证请求头或 exclude-filter 的 provider 显式拒绝导入，避免保存为失去认证/过滤的 URL；通用文件型与 MRS 解码仍未支持；YAML anchor/merge 当前已支持，见上文。
- Egern 原生 IPv6 字段（B11）、Egern/sing-box 原生资源的通用展开、QuanX 的接口/设备专属参数，以及 Loon/Shadowrocket 全量逻辑规则转换仍需独立补齐。
- 不可等价转换的普通分流规则会警告并跳过，用户应检查提示；涉及拒绝条件或兜底条件时阻止生成。没有宣称所有输入均无损转换。
- 远程规则以后可能更新，CLI 校验与当前缓存不能保证未来规则内容；Surge 远程资源是否触发提前解析警告仍需实际客户端验收，不能据此撤回 no-resolve 设计。

## 官方依据

[Mihomo 路由规则](https://wiki.metacubex.one/config/rules/)、[Mihomo 规则集合](https://wiki.metacubex.one/config/rule-providers/)、[Surge 逻辑规则](https://manual.nssurge.com/rules/logical.html)、[Surge 规则概览](https://manual.nssurge.com/rules/overview.html)、[Surge 来源和端口规则](https://manual.nssurge.com/rules/source-and-port.html)、[Stash 规则类型](https://stash.wiki/en/rules/rule-types)、[sing-box 路由规则](https://sing-box.sagernet.org/configuration/route/rule/)、[SubConverter](https://github.com/tindy2013/subconverter)、[SubStore](https://github.com/sub-store-org/Sub-Store)。
