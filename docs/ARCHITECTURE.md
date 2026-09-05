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

CloudSnapshotSyncing 为可注入依赖，CloudSyncStore 实现下载/上传/删除，CloudSyncResolution 保留整份配置按更新时间决胜的产品策略。

- 下载返回后读取当前本地快照，不能使用 await 前的版本。
- 核对同步开关代次和取消状态；关闭后旧下载不写入。
- 显式同步占有比较/上传过程，抑制旧的延迟上传；等待期间的新编辑由本轮或后续合并上传处理。
- 不更改用户账号、证书或授权，不以测试模式触碰真实数据。

## 解析、地图与运行信息

- SourceInputDetector 区分输入；SubscriptionParser 处理 Base64、URI、Clash YAML 和受支持 Surge 行。拒绝的条目显式计数。
- 配额取响应头、STATUS 行、公告节点；兼容请求只补配额，不能以转换后的正文替换原始节点。
- NodeRegionResolver 使用**名称优先**，无法判断才查离线 IP 国家库。国家表与数据库由脚本生成。
- NodeMapOverview 按完整节点 revision 更新 NodeMapPresentation；不能只依赖 UUID/数量。分享再按 ID 读取最新节点，避免发送旧密码。
- WorldDotMapView 使用 Canvas / 预计算国家点阵，不使用联网地图。presentation 不在每次 View 初始化时重复计算；聚类在后台准备，仅回主线程发布仍有效的结果。
- NodeLatencyService 优先 ICMP，失败时明确标注端口握手；运行信息批量发布，国家解析按 host 复用缓存。

## 规则

- RuleSchemeRepository 管理 ACL4SSR 和用户方案；RuleDownloadStore 管理下载内容。
- RuleScheme 保留策略组、节点正则、规则顺序；定制层和自定义规则流独立保存，刷新上游不覆盖。
- 最终兜底和被引用基础组自动保留；地区组不互引或引用包含自己的父组。
- RuleSetEmissionPlanner 仅引用内容、源哈希、覆盖条数、产物提交均验证通过的规则集，无法无损表示的部分交给生成器内联。
- ACL4SSR_ 前缀防止资源拍平覆盖；Self-Configuration 只允许手动下载。
- MRS/SRS 编译、反向校验和双提交发布见 [RELEASING](RELEASING.md)。

## 完整配置与节点订阅生成

ConfigurationGenerator 按 ClientTarget 与能力矩阵输出 INI / YAML / JSON / Base64。

- Stash、Clash、Clash Mi、Karing 共用部分 YAML，远端规则能力仍分开。
- Hiddify、sing-box MT 各有协议矩阵和导入身份；Egern 使用独立 YAML 结构。
- V2Box 仅节点订阅；QuanX 分享完整文件，不假装远程资源 API 能导入策略组。
- 名称必须转义，不能让不可信 remark 注入规则。
- 代理集合仅为明确支持的完整配置传入 RemoteSubscriptionLink，自有节点内联。
- supported/skipped 统计本地输出，remoteSourceCount 单列远端来源；hasExportableProxies 决定能否导出。远端节点不受本地筛选控制。

### 有界生成缓存

ConfigurationCache 独立于 AppModel，完整配置和仅节点各有缓存族。全局签名只含共享的节点、规则、地区等；远端链接、目标能力放在目标键里。同一目标的新键替换旧键，不清空其他目标，也不无限累积。切换代理集合能力不同的客户端应复用缓存。

## 导出交互与服务

- ClientPicker 的 Button 负责轻点，原生 ScrollView 负责横滑；ClientPickerReorderGestureBridge 在最近 UIScrollView 安装独立长按识别器，成功后接管拖动，不手动禁用 pan。
- ClientFilterView 复用原生手势桥接，仅右侧 44pt 手柄接管拖动；纵向显式转换安全区坐标。添加整行可点，删除与拖动按钮始终保留布局。
- 拖动浮层是纯展示，不复用真实按钮；原行只隐藏内部图像，不能把整个 Button 透明化后再期待它在落位中接收点击。
- ReorderPlanner 用冻结几何计算插入槽及实际尺寸落点；ReorderAutoScroller 处理边缘滚动。
- 活跃拖动与视觉落位分开，松手即释放输入；旧 completion 核对 token，不能清掉新手势。浮层以 presentation offset 衔接被打断的运动。
- 行高和卡片适配 Dynamic Type；Reduce Motion 取消选择缩放，按钮表达选中语义，装饰勾号不重复朗读。
- DirectImportService 只开放 127.0.0.1 的 45 秒服务；LANSubscriptionServer 是独立、随机密钥保护的前台共享入口。
- ExportFileService / ProxyShareService 写完整保护的临时文件并清理。代理集合开启时，分享/LAN 响应可能含原始订阅凭据。

## 验证边界

TowerTests 覆盖解析/生成、缓存、地图 revision、可暂停网络竞态、排序几何与持久化；TowerUITests 覆盖实际点选、横滑、拖动、筛选和重启。Debug UI 测试使用独立临时沙盒，Release 不提供该入口。

真机触摸手感、VoiceOver、客户端接收、权限和文件保护需另验。文件行数不是性能证据；先测量，再渐进拆分职责，不一次性重写 AppModel 或生成器。
