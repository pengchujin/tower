# 技术架构

产品约束见 [CLAUDE](../CLAUDE.md)，命令和回归清单见 [DEVELOPMENT](DEVELOPMENT.md)。本文只维护模块边界，不记录历史版本或测试次数。

## 状态与数据流

`TowerApp → AppModel → Services → AppSnapshot`

- TowerApp 持有唯一 MainActor / Observation AppModel；前台按设置同步/刷新，离开前台提交待保存快照。
- PersistenceStore 原子写入完整文件保护的快照。App 使用 250ms 合并保存，测试默认立即保存；背景切换必须 flush。
- apply 恢复 snapshot.updatedAt 到 lastLocalEditAt，并使旧来源请求失效；加载快照不能当成新编辑。
- AppSnapshot 新字段提供旧文件默认值/迁移。完整客户端顺序与可见集合分开；LAN 是 ExportDestination，不是 ClientTarget。

## 异步一致性

### 订阅提交

SubscriptionService / SubscriptionParser 负责请求和解析；SourceUpdateCoordinator 为来源 ID 发放提交票据。

1. 编辑/刷新开始时记录请求参数和票据。
2. 网络等待后重新按 ID 查找来源、核对票据与 URL/请求选项。
3. 只有有效结果才能替换节点、写元数据、保存；删除、快照替换或后续编辑让旧结果失效。
4. 替换节点统一经过 carriedOverExclusions：先精确身份，后去 remark 的唯一宽松键，不能因 ID 更新而恢复排除项。

普通行刷新与批量刷新复用进行中的来源任务。不同 host 并行，同 host 排队；批量结束合并保存和提醒。取消任务不能代替提交校验，因为网络依赖可能忽略取消。

### iCloud

CloudSnapshotSyncing 为可注入依赖。CloudSnapshotMerge 按上次共同快照做三路合并；首次同步缺少的项目不代表删除，同字段并发修改或删除与编辑冲突时暂停，要求用户选择备份。

CloudSyncStore 使用只追加的 `state-versions-v2` 版本图保存快照和父版本，防止不同设备并发写入互相覆盖。原 `state.json` 仅作迁移输入和恢复副本；所有设备需升级后才能继续互相同步。云端文件未下载完整时请求下载并等待后续重试，不当成空配置。应用远端结果前保留本地备份，设置提供恢复入口；明确重置清除本地恢复数据，删除云端副本同时清除云端历史。

- 下载返回后读取当前本地快照，不能使用 await 前的版本。
- 核对同步开关代次和取消状态；关闭后旧下载不写入。
- 显式同步占有比较/上传过程，抑制旧的延迟上传；等待期间的新编辑由本轮或后续合并上传处理。
- 不更改用户账号、证书或授权，不以测试模式触碰真实数据。

## 解析、地图与运行信息

- SourceInputDetector 区分输入；SubscriptionParser 处理 Base64、URI、Clash YAML 和受支持 Surge 行。拒绝的条目显式计数。
- 配额取响应头、STATUS 行、公告节点；兼容请求只补配额，不能以转换后的正文替换原始节点。
- NodeRegionResolver 在无手动指定时保持名称优先，完整顺序为**手动指定 → 名称 → 离线 IP 国家库**，不使用域名后缀/关键词推断地区。手动值存于 ProxyNode.countryOverride，刷新按唯一节点身份保留。国家表与数据库由脚本生成；国家和 ASN 数据固定版本、SHA-256 与许可证。
- IPCountryLookupService 合并同 host DNS 请求，成功缓存一小时、失败/冲突30秒；多个地址国家冲突不取第一个。持久国家缓存按数据库版本失效。IPASNDatabase 按需映射固定记录及名称池，仅详情查询并显示网络组织；不建立代理隧道，不调用在线 IP 查询接口。
- NodeMapOverview 按完整节点 revision 更新 NodeMapPresentation；不能只依赖 UUID/数量。分享再按 ID 读取最新节点，避免发送旧密码。
- WorldDotMapView 使用 Canvas / 预计算国家点阵，不使用联网地图。国家点位索引一次建立，色阶数据后台准备；点阵按颜色合并绘制，手势期间复用底图并在结束后追上测速结果。二、三级选中保持倍率，平移缓存的清晰点阵，不在回中时切换概览与细节渲染器。presentation 不在每次 View 初始化时重复计算；聚类在后台准备，仅回主线程发布仍有效的结果。
- NodeLatencyService 默认自动，仅提供自动、ICMP、TCP；自动优先 ICMP，失败时仅对支持 TCP 的协议回退并标注端口握手，UDP-only 协议不做 TCP 探测；运行信息批量发布，国家解析按 host 复用缓存。

## 规则

- RuleSchemeRepository 管理 ACL4SSR 和用户方案；RuleDownloadStore 管理下载内容。
- RuleScheme 保留策略组、节点正则、规则顺序；定制层和自定义规则流独立保存，刷新上游不覆盖。
- 最终兜底和被引用基础组自动保留；地区组不互引或引用包含自己的父组。
- RuleSetEmissionPlanner 仅引用内容、源哈希、覆盖条数、产物提交均验证通过的规则集，无法无损表示的部分交给生成器内联。
  - 内置 ACL4SSR：Surge 引用原列表；mihomo 系和 Stash 用 MRS；sing-box MT 和 Hiddify 用 SRS（sing-box MT 的 DNS 规则另引用同一列表的纯域名 SRS）；Loon / QuanX / Egern 用塔台发布的同内容列表，覆盖类型由 App 按随包文本独立复算。
  - 「我的规则集」里没有链接的连续规则，在 Surge 写成 `[Ruleset]`，mihomo 系和 Stash 写成 `type: inline` provider；分组补充规则仍逐条写在最前。
  - 规则集下载：mihomo 系不写 `proxy:`，按配置自己的规则走（实测命中 github 关键词经节点选择）；Hiddify 用 `download_detour`，sing-box MT 用 `http_client`。
- ACL4SSR_ 前缀防止资源拍平覆盖；Self-Configuration 只允许手动下载。
- MRS/SRS 与 Loon / QuanX / Egern 列表的生成、反向校验和双提交发布见 [RELEASING](RELEASING.md)。

## 完整配置与节点订阅生成

ConfigurationGenerator 按 ClientTarget 与能力矩阵输出 INI / YAML / JSON / Base64。

- Stash、Clash、Clash Mi、Karing 共用部分 YAML，远端规则能力仍分开。
- Hiddify、sing-box MT 各有协议矩阵和导入身份；Egern 使用独立 YAML 结构。
- SingBoxDNSPolicy 仅处理官方 sing-box MT 的「规则判定 / 全局代理 / 直接连接」与 DNS 联动。全局 selector 默认自动选择全部节点，也可手选，DNS 通过独立 detour 跟随。递归检查代理组是否可能到达 DIRECT，必要时创建无直连候选的自动组；DNS 域名规则从同一份本机缓存投影，保持优先级，不依赖远端 SRS 是否启用。普通目标先经 DNS 规则解析，节点启动解析继续独立；严格保护不回退直连。Hiddify 不套用该适配层。
- Surge / Surge Mac 的仅节点模式输出 `policy-path` 纯策略列表，主操作复制聚合订阅链接；WireGuard 需要独立配置节，继续使用完整配置。节点模式能力与 URL Scheme 导入能力分开建模。
- Anywhere / V2Box 仅节点订阅；AnywhereExport 负责独立 URI 参数映射和无法保真节点过滤，规则由目标客户端管理。有跳过证书校验的 VLESS（TLS，raw / HTTPUpgrade）/ Trojan / AnyTLS 节点时，另生成 AJSON（`GeneratedConfiguration.anywhereAJSON`），本机临时服务只对带 `X-Anywhere-Format: ajson/1` 的请求返回它，其余节点在文档里仍是原链接。此时兼容数按一键导入计算，另加一条兼容性提示说明复制文本或存文件不含这些节点。QuanX 分享完整文件，不假装远程资源 API 能导入策略组。
- 分流规则按条件树转换方言（`RoutingRuleCapabilities`）：Surge、mihomo 系、Stash、Loon、Shadowrocket 共用这一套，每个目标只输出自己文档列出的规则类型和选项，选项写在策略名后面；sing-box 和 Egern 有各自基于同一条件树的写法；QuanX 仍走 `mappedRule` 的逐字段路径。不能表达的规则跳过并提示；拦截规则被跳过时，在提示最前面汇总条数，不阻止导出。MRS 规则集不下载、不解码，只给 mihomo 系远程引用。
- Loon 和 QuanX 先匹配本地规则、再匹配远程列表，规划器会把排在本地规则前面的远程列表改为内联。
- 名称必须转义，不能让不可信 remark 注入规则。
- 策略组图标：`PolicyGroupEmoji` 是唯一的 Emoji 识别器（名字自带 → 服务 / 类别 → 地区 → 组的作用 → 组里的规则列表 → 成员 → 类型兜底；导出和自动补全用带方案的 `recognized(for:in:)`）；`RuleScheme.withPolicyGroupIcons` 在生成时把它换成 Fluent Emoji 3D 或圆形国旗的地址，写在 `tower-icon` 参数里，由各格式输出为 `icon-url` / `icon` / `img-url`；能画图标的客户端同时去掉名字里的 Emoji，所有引用一起改名。地区组名字保留国旗 Emoji，同时写圆形国旗图标（Surge 除外，`regionIconsFromName`）；QuanX 用塔台发布的 144px 圆底图（`PolicyGroupIconCatalog.circleURL`，raw.githubusercontent.com），覆盖全部 Fluent Emoji 和国旗；未发布前写 SF Symbols（`<名称>.system`），只覆盖 `PolicyGroupIconSupport.symbols` 的键，其余保留名字里的 Emoji。导入方案的「自动补全 Emoji」（`ruleGroupEmojiAutofill`）只对新导入的默认开启。
- 代理集合仅为明确支持的完整配置传入 RemoteSubscriptionLink，自有节点内联。
- Tailscale 内网（`TailnetConnection`）不是节点：
  - `TailnetConfigurationWriter` 在生成之后，把它写进完整配置：一个不被任何组引用的策略，加上置顶规则。内置方案和导入方案共用这一处。
  - 客户端按 `Flavor` 分四类：surge、stash、mihomo、singBox。不支持的目标会跳过并写一条兼容性提示。
  - Auth Key 由 AppModel 从本机钥匙串（`TailnetAuthKeyStore`）读出，计入缓存键。快照只保存连接本身。
  - Surge 永远只写 `interactive-login`，不写 Key。
  - 各客户端的写法和取舍见 [TAILSCALE](TAILSCALE.md)。
- 目标枚举的名字和显示名不一致：`ClientTarget.clash` 是 Stash，`.clashApple` 才是名为 Clash 的客户端。按显示名找代码时要注意。
- supported/skipped 统计本地输出，remoteSourceCount 单列远端来源；hasExportableProxies 决定能否导出。远端节点不受本地筛选控制。

### 有界生成缓存

AppModel 对配置请求输入、节点筛选/来源计数和地区统计保留值类型快照。命中时仍读取全部 Observation 输入，内容、设置或规则下载 revision 变化就失效；请求按目标/内容模式分开缓存，能力覆盖只保留当前变体。不能用 UUID 或节点数量替代完整输入一致性检查。

ConfigurationCache 独立于 AppModel，完整配置和仅节点各有缓存族。全局签名只含共享的节点、规则、地区等；远端链接、目标能力放在目标键里。同一目标的新键替换旧键，不清空其他目标，也不无限累积。切换代理集合能力不同的客户端应复用缓存。

## 导出交互与服务

- ClientPicker 的 Button 负责轻点，原生 ScrollView 负责横滑；ClientPickerReorderGestureBridge 在最近 UIScrollView 安装独立长按识别器，成功后接管拖动，不手动禁用 pan。
- ClientFilterView 复用原生手势桥接，仅右侧 44pt 手柄接管拖动；纵向显式转换安全区坐标。添加整行可点，删除与拖动按钮始终保留布局。
- 拖动浮层是纯展示，不复用真实按钮；原行只隐藏内部图像，不能把整个 Button 透明化后再期待它在落位中接收点击。
- ReorderPlanner 用冻结几何计算插入槽及实际尺寸落点；ReorderAutoScroller 处理边缘滚动。
- 活跃拖动与视觉落位分开，松手即释放输入；旧 completion 核对 token，不能清掉新手势。浮层以 presentation offset 衔接被打断的运动。
- 行高和卡片适配 Dynamic Type；Reduce Motion 取消选择缩放，按钮表达选中语义，装饰勾号不重复朗读。
- Mac 的 Surge 聚合节点链接复用前台局域网服务，URL 显式携带目标和 `content=nodesOnly`；切换页面或完整配置不改变旧链接的节点语义，响应按当前已启用节点和该目标的协议筛选重新生成。Mac 需局域网连接并保持塔台运行。iPhone 复制节点链接复用 DirectImportService 的 127.0.0.1 / 3 分钟后台交接，与 LAN 共享的系统后台续时独立；更新时重新复制。
- DirectImportService 只开放 127.0.0.1 的 3 分钟服务；LANSubscriptionServer 是独立、随机密钥保护的共享入口。iPhone 离开前台时通过 LANSharingBackgroundLease 申请有限后台时间；回到前台仅释放执行断言，保留监听和 URL；系统到期或用户停止时才关闭，不另设倒计时。Mac 不使用 iOS 后台断言。
- ExportFileService / ProxyShareService 写完整保护的临时文件并清理。代理集合开启时，分享/LAN 响应可能含原始订阅凭据。

## 验证边界

TowerTests 覆盖解析/生成、缓存、地图 revision、可暂停网络竞态、排序几何与持久化；TowerUITests 覆盖实际点选、横滑、拖动、筛选和重启。Debug UI 测试使用独立临时沙盒，Release 不提供该入口。

真机触摸手感、VoiceOver、客户端接收、权限和文件保护需另验。文件行数不是性能证据；先测量，再渐进拆分职责，不一次性重写 AppModel 或生成器。
