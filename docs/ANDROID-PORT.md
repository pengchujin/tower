# 塔台 Android 版技术方案与交接（2026-08-25）

## 0. 这份文档的状态

接手前先分清三类内容，不要把待验证项当成已定项去实现：

| 标记 | 含义 |
| --- | --- |
| **【已定】** | 已经基于实测代码做出决策，除非 Phase 1 spike 推翻，否则照做 |
| **【闸门】** | Phase 1 spike 的验证目标，结果决定走 2A 还是 2B 分支 |
| **【待拍板】** | 产品决策，代码上无法推导，必须问项目所有者，不要自己选一个默认值往下做 |

> **2026-08-25 起本文档内已无【待拍板】项**，四项产品决策全部关闭，记录见 §10。新出现的待定事项追加到 §10。

本文只覆盖 Android 移植。iOS 现状见 `docs/HANDOFF.md`，模块和数据流见 `docs/ARCHITECTURE.md`，仓库级约束见根目录 `CLAUDE.md`——**那 23 条约束对 Android 同样有效**，映射见 §7。

---

## 1. 结论摘要

**【已定】** Android 版用 **Kotlin + Jetpack Compose** 写 UI 和 App 壳。

**【闸门】** 核心逻辑（解析、配置生成、规则、地区识别、状态机）**尽量共享现有 Swift 代码**，通过官方 Swift Android SDK 交叉编译成 `.so`，Kotlin 侧经 C ABI + JNI 调用。可行性由 Phase 1 决定，不可行则降级到 Kotlin 重写 + 黄金文件契约（§4.4）。

依据是一次实测：塔台的逻辑层几乎不依赖 Apple 框架。25,910 行 App 代码里共 **14,472 行落在纯 Foundation 边界内**，其中包括 2,769 行的 `AppModel`（只 `import Foundation` 和 `Observation`）和 2,974 行的 `ConfigurationGenerator`（只 `import Foundation`）。这不是巧合，是既有分层的结果，应该利用而不是推倒。

配套的 15,732 行测试是这个项目最贵的资产——它们编码了约束 9、18、19、22、23 这类**静默失败**的行为。共享核心的全部意义在于让这套测试同时守住两个平台。

---

## 2. 实测：代码可移植性地图

以下是逐文件扫描非 Foundation import 的结果（`Tower/`、`Tower/Models/`、`Tower/Services/`）。**Codex 不需要重新扫这一遍。**

### 2.1 纯 Foundation，直接可移植（7,307 行）

```
Tower/Models/CustomRuleFlow.swift              278
Tower/Models/RuleCatalog.swift                 559
Tower/Models/RuleScheme.swift                  662
Tower/Models/SelfConfigurationSource.swift      21
Tower/Services/CloudSyncPreference.swift        19
Tower/Services/CloudSyncStore.swift            171   ← 见 §5.3
Tower/Services/ConfigurationGenerator.swift   2974   ← 核心资产
Tower/Services/CountryTable.swift              213   ← 脚本生成
Tower/Services/ExportFileService.swift          42
Tower/Services/LocalNodeImport.swift           500
Tower/Services/NodeRuntimeBatch.swift           71
Tower/Services/PersistenceStore.swift           35
Tower/Services/ProxyShareService.swift         370
Tower/Services/RuleRepository.swift             87
Tower/Services/RuleSchemeImportService.swift   190
Tower/Services/RuleSchemeParser.swift          595
Tower/Services/RuleSchemeRepository.swift      195
Tower/Services/RuleSetEmissionPlanner.swift    222
Tower/Services/SourceInputDetector.swift       103
```

### 2.2 依赖极浅，替换成本低（7,165 行）

| 文件 | 行数 | 依赖 | 实际用量 | 替换方案 |
| --- | --- | --- | --- | --- |
| `AppModel.swift` | 2769 | `Observation` | `@Observable` / `@MainActor` | Observation 随 Swift 工具链走，非 Apple SDK；**Phase 1 必须验证 Android 上可用**。文件里出现的 "SwiftUI" 全是注释，无实际依赖 |
| `SubscriptionParser.swift` | 1910 | `Network` | 仅 `NWParameters.PrivacyContext.default` 两处（:398, :407），用于 DNS 隐私上下文 | 抽成 `DNSPolicy` 协议，Android 侧给等价实现 |
| `DomainModels.swift` | 1484 | `CryptoKit` | 仅 `Insecure.SHA1()`（:745） | swift-crypto，或 40 行自实现 |
| `NodeRegionResolver.swift` | 652 | `CoreLocation` | 仅 `CLLocationCoordinate2D` 值类型（:12） | 自定义 `struct Coordinate` |
| `IPCountryDatabase.swift` | 182 | `Darwin` | mmap + `inet_pton` | Android Bionic 同样提供，改 import 即可 |
| `RuleDownloadStore.swift` | 168 | `CryptoKit` | 仅 `SHA256.hash`（:92） | swift-crypto |

> `SubscriptionParser` 的 `import Network` 是本次移植中最需要留神的一处：它在注释里明确说明了为什么**不**自己实现 TLS/DNS 客户端（:386–388）。Android 侧的替代实现必须保持同一立场——走系统网络栈，不要为了对齐行为去引入自研解析。

### 2.3 平台外壳，必须重写（不进核心）

| 文件 | 行数 | 依赖 | Android 对应 |
| --- | --- | --- | --- |
| `DirectImportService.swift` | 305 | `Network`, `UIKit` | Intent + FileProvider，见 §5.2 |
| `LANSubscriptionServer.swift` | 568 | `Network`, `Darwin` | 大概率**整个删掉**，见 §5.2 |
| `NodeLatencyService.swift` | 571 | `Network`, `Darwin` | Kotlin `Socket` / `InetAddress.isReachable`，见 §5.5 |
| `SubscriptionReminderService.swift` | 149 | `UserNotifications` | WorkManager + NotificationManager |
| `TowerApp.swift` | 142 | `SwiftUI` | Activity + Compose |
| `Tower/Features/**`、`Tower/Design/**` | ~9,000 | SwiftUI | 全量重写 |

### 2.4 语言中立资源，直接复用（10.5 MB）

```
Tower/Resources/IPCountry/     10 MB    mmap 二进制 IP 国家库
Tower/Resources/ACL4SSR/      428 KB    规则快照（保留 ACL4SSR_ 前缀，见 §7 第 15 条）
Tower/Resources/WorldMap/     140 KB    WorldDotMap.txt 陆地点阵 + WorldDotCountries.txt 归属层
Tower/Resources/RuleCatalog/   32 KB    内置规则目录
```

这些是纯数据文件，两端共用同一棵树，由 `Scripts/` 下的 Python 脚本统一生成。**Android 侧不要另存一份副本。**

---

## 3. 架构决策

### 3.1 选型 **【已定】**

- **UI / App 壳**：Kotlin + Jetpack Compose（Material 3）。最低 API 26（Android 8.0）。
- **不用 Flutter / React Native**。理由：iOS 的 SwiftUI 已经写完，跨平台框架在这个项目上省不下 UI 成本；而首页 1,566 行自绘点阵地图、Intent 导入、原始 socket 测延迟、mmap 10 MB 数据库、前台服务——每一项都落在跨平台框架的痛点上。
- **不用 KMP（Kotlin Multiplatform）把核心改写成 Kotlin 再让 iOS 消费**。理由是风险方向错了：这等于把**静默失败最集中的代码**（约束 22 的 `carriedOverExclusions` 宽松匹配、约束 23 的 `lastLocalEditAt` 恢复）推倒重写，同时动一个已经在 TestFlight 上的 App。收益要等到重写完成之后才出现，代价立刻发生。

### 3.2 目标分层

```
┌─────────────────────────┬─────────────────────────┐
│   iOS: SwiftUI          │   Android: Compose      │
│   Features/ Design/     │   ui/ theme/            │
├─────────────────────────┼─────────────────────────┤
│   iOS 平台服务          │   Android 平台服务      │
│   Network/UIKit/UN      │   Intent/WorkManager    │
├─────────────────────────┴─────────────────────────┤
│              TowerCore（纯 Foundation）            │
│   AppModel · ConfigurationGenerator · Parser       │
│   RuleCatalog · RuleScheme · NodeRegionResolver    │
├───────────────────────────────────────────────────┤
│        shared/resources/（语言中立数据）           │
└───────────────────────────────────────────────────┘
```

核心与外壳之间用协议隔离。核心**不允许**出现 `import UIKit / SwiftUI / Network / UserNotifications / CoreLocation`，由 target 划分在编译期强制。

---

## 4. 阶段计划

### Phase 0：iOS 侧分层（必做，无 Android 依赖）**【已定】**

**这一步先做，且即使 Android 版最终不做也有价值。**

把 `Tower/Services` 和 `Tower/Models` 拆成两个 target：

- `TowerCore`：§2.1 + §2.2 的全部文件，**编译时链接不到任何 Apple 框架**
- `Tower`（App）：§2.3 + Features + Design

具体动作：

1. 新建 `TowerCore` framework target，把 §2.1 文件原样移入。
2. 处理 §2.2 的六处依赖：
   - `Insecure.SHA1` / `SHA256` → 引入 swift-crypto，或在 `TowerCore` 内自实现（两处调用，自实现更省依赖）
   - `CLLocationCoordinate2D` → `TowerCore` 内定义 `struct Coordinate: Hashable, Sendable { var latitude, longitude: Double }`
   - `NWParameters.PrivacyContext` → 定义 `protocol DNSPolicyProviding`，iOS 实现留在 App target
   - `Darwin` → 改成条件 import（`#if canImport(Darwin)` / `#elseif canImport(Glibc)`）
3. 把 §2.3 的服务反转成协议注入：`AppModel` 持有 `LatencyProbing`、`ReminderScheduling`、`ConfigImporting`、`CloudSyncing` 协议，而不是具体类型。
4. 测试按同样边界拆成 `TowerCoreTests` 和 `TowerTests`。

**验收标准：**

- `TowerCore` 在 `-target arm64-apple-ios17.0` 下不链接 UIKit/SwiftUI/Network/CoreLocation/UserNotifications（用 `otool -L` 或 target 的 Link Binary 列表核对）
- 全部 15,732 行测试仍然绿
- 拆分后 `TowerCore` 行数应接近 14,472（§2.1 + §2.2 的实测合计），下限 12,000。**如果显著低于这个数，说明 `AppModel` 的 UI 耦合比扫描结果重，先停下来报告，不要硬拆。**

**这一步的产出本身就是决策依据**：`AppModel` 里可移植状态机与 UI 绑定的真实比例，决定 Android 版值不值得做。

### Phase 1：Swift on Android spike **【闸门】**

只搬最小闭环：`ConfigurationGenerator` + `RuleCatalog` + `DomainModels`，交叉编译成 Android `.so`，在模拟器上跑 `ConfigurationGeneratorTests`。

**必须量出并写进本文档的三个数：**

| 指标 | 通过线 |
| --- | --- |
| APK 体积增量（Swift runtime + 核心） | < 25 MB（按 ABI 分包后单 ABI） |
| 冷启动到首次生成七种配置完成 | 不劣于 iOS 同机型量级 |
| Foundation 缺口数量 | 逐条记录，不要绕过去不说 |

**已知需要验证的具体风险点，逐条给结论：**

1. `Observation` 模块在 Android 工具链是否可用——决定 `AppModel` 能不能共享，这是最大的单点
2. `JSONEncoder` 的 `.sortedKeys` + `.iso8601` 行为是否与 Darwin 一致——`PersistenceStore` 和 `CloudSyncStore` 依赖它产出稳定字节
3. `String` 的 Unicode 行为（国旗 Emoji 是 regional indicator 对，约束 19/20 直接依赖它）
4. `Data(contentsOf:options:.mappedIfSafe)` 或等价 mmap 路径能否读 10 MB IP 库
5. 本地化：核心里散布着 `String(localized:)`（如 `CloudSyncStore` 的错误文案），Android 上无对应实现——**大概率需要把核心里的用户可见文案改成错误码，由 Kotlin 侧查表**。这一条会波及 iOS，评估工作量后再定。

**闸门判定【已定】：**

| spike 结果 | 走哪条分支 |
| --- | --- |
| 全部通过 | **Phase 2A**：核心整体共享 |
| 仅 1（`Observation`）失败，其余通过 | **Phase 2A′**：`AppModel` 单独用 Kotlin 重写，其余核心仍共享 |
| 2（`JSONEncoder` 字节稳定性）失败 | **Phase 2B**：核心整体 Kotlin 重写 |
| 仅 5（本地化文案）需要改造 | 仍走 2A，把文案改错误码列为 2A 的前置任务 |

3、4 失败不单独决定分支，但必须记录并给出替代实现。

### Phase 2A：共享 Swift 核心（spike 通过）

- `TowerCore` 抽成独立 SwiftPM package，仓库根目录 `core/`
- 暴露层用 **C ABI**（`@_cdecl`），不用 Swift 直接对 JNI——接口面收窄到「传 JSON 进、传 JSON 出」的少数几个函数：`tower_apply_snapshot`、`tower_generate_config`、`tower_parse_subscription`、`tower_resolve_regions`
- Kotlin 侧一层 `TowerCoreBridge`，负责 JNI + 序列化，**不含业务逻辑**
- 按 ABI 分包（arm64-v8a 为主，x86_64 仅供模拟器）

### Phase 2A′：混合——`AppModel` Kotlin + 其余核心共享 **【已定的降级路线】**

`Observation` 不可用时走这条。Kotlin 侧持有状态机，按需调用 Swift 核心。

**这是三条分支里最复杂的一条，接手时要清楚它的代价：**

- 桥接面从「几个粗粒度函数」变宽——`AppModel` 对核心的调用（解析订阅、生成配置、解析地区、规则定制）都要跨 JNI。好在这些调用本身是粗粒度的，单次调用开销可以摊薄，**但不要因此把桥接做成细粒度的属性读写**。
- **代价主要不在性能，在数据模型重复**：`AppSnapshot` 及其全部嵌套类型（`SubscriptionSource`、`ProxyNode`、`RuleScheme`、`RuleSchemeCustomization`、`CustomRuleFlow`、`LocalRuleSet` …）必须在 Kotlin 侧再定义一遍。这正是共享核心本想消除的漂移风险，只是范围缩小到了数据层。
- 因此走 2A′ 时，§6.4 的黄金文件**必须扩展到 `AppSnapshot` 的编解码往返**，且把约束 22（`carriedOverExclusions`）、约束 23（`lastLocalEditAt`）的用例放在最高优先级——这两条的实现会跨语言边界，是最容易静默失效的地方。
- Kotlin 侧的 `AppSnapshot` 必须逐字段对齐 `DomainModels.swift:1206` 起的可选性注释。**任何一个 optional 写成非 optional，旧存档就解码失败。**

### Phase 2B：Kotlin 重写核心（spike 失败）

- 按 §2.1 + §2.2 的边界逐文件重写，**优先级顺序**：`ConfigurationGenerator` → `SubscriptionParser` → `RuleScheme*` → `NodeRegionResolver` → `AppModel`
- 强制配套：黄金文件契约（§6.4）先建立，再写实现。**不要先写实现后补契约。**

### Phase 3：Android App

Compose UI 重写。地图（`WorldDotMapView`，1,566 行）用 Compose `Canvas`，点阵数据直接读 `WorldDotMap.txt` / `WorldDotCountries.txt`，**约束 8 的交互要求原样保留**：覆盖国家的整个点阵轮廓可点击，不叠加独立定位点。

---

## 5. Android 侧的产品差异

这几处不是移植问题，是产品问题。

### 5.1 导出目标客户端 **【已定：改展示名】**

iOS 的 `ClientTarget` 是七个：

| case | 显示名 | 产物 | Android 上是否存在 |
| --- | --- | --- | --- |
| `surge` | Surge | Surge 完整配置 | 无 Surge，但 **Surfboard 吃 Surge 格式** |
| `clash` | Stash | Clash YAML | 无 Stash，但 **Clash Meta / FlClash 吃同格式** |
| `hiddify` | Hiddify | sing-box 内核 | **有 Hiddify，另有 SFA (sing-box for Android)** |
| `shadowrocket` | Shadowrocket | 本地配置 | 无 |
| `loon` | Loon | 完整配置 | 无 |
| `quanx` | QuanX | Quantumult X | 无 |
| `egern` | Egern | Egern YAML | 无 |

**共享核心的最大红利在这里**：`ConfigurationGenerator` 已有的三条产物主线（Surge 格式 / Clash YAML / sing-box）恰好覆盖 Android 主流客户端，生成逻辑一行不用改，改的只是展示层的目标列表。

**已定：Android 侧改展示名。** `surge` → Surfboard，`clash` → Clash Meta，`hiddify` → sing-box。`rawValue` 一律不动（已进 `state.json`，见 §8 第 2 条）。

不存在的四个目标（`shadowrocket` / `loon` / `quanx` / `egern`）在 Android 侧**直接隐藏，不要留死入口**。

#### 由此产生的 Phase 0 任务：展示属性必须移出核心

`ClientTarget` 现在把展示属性和领域标识混在 `DomainModels.swift` 里：`name`、`subtitle`、`symbol`、`appIconAssetName`、`brandSymbol`、`brandColorHex` 全是 UI 关注点，其中 `symbol` / `appIconAssetName` 还是 SF Symbols 和 iOS 素材名，在 Android 上无意义。

**Phase 0 必须把这六个属性从 `TowerCore` 移到各自的平台层**，核心只保留 `rawValue` 和领域行为。

**一个必须先解决的冲突**：`target.name` 被写进了生成配置的注释头——

```
ConfigurationGenerator.swift:434   # Generated locally by 塔台 for \(target.name)
ConfigurationGenerator.swift:1968  # Generated locally by 塔台 for \(target.name)
```

改展示名会让同一份订阅在两端产出**字节不同**的配置（iOS 写 `for Stash`，Android 写 `for Clash Meta`），黄金文件（§6.4）立刻失效。

三种解法，**选第 2 种**：

1. 头部改用 `rawValue` —— 用户可见的配置头出现 `for clash`，可读性变差
2. **`generate()` 增加 `displayName: String` 参数，由平台层传入；黄金文件固定传一个规范值**（推荐：与 iOS 现值一致，即 Surge / Stash / Shadowrocket / Loon / QuanX / Hiddify / Egern）
3. 黄金文件比对时跳过注释头 —— 会同时丢掉对 `scheme.name`、来源标注等其他头部字段的保护，**不要选**

选 2 的代价是 `generate()` 多一个参数，收益是核心彻底不含展示名，且黄金文件在两端字节一致。

### 5.2 一键导入：临时服务器可以退休 **【已定】**

iOS 的 `LANSubscriptionServer`（568 行，仅绑 127.0.0.1、45 秒失效）是被 URL Scheme 逼出来的方案。Android 有更好的原语：

- `FileProvider` 生成 `content://` URI + `grantUriPermission` 单次授权 + `Intent.ACTION_VIEW`
- 部分客户端另有 scheme：Clash Meta 系 `clash://install-config?url=`、sing-box `sing-box://import-remote-profile?url=`

**FileProvider 路径严格优于开端口**：不监听任何 socket，授权粒度到单个 URI 和单次调用，进程退出自动失效。因此 Android 侧不移植 `LANSubscriptionServer`，约束 3 在 Android 上改写为「用 FileProvider 单次授权，不落 public 目录，用完即删」。

scheme 路径需要远程 URL，与约束 1（内容不出本机）冲突，**除非** URL 指向本机——那又退回到开端口。所以 scheme 只在用户导入的是「远程订阅链接本身」时可用，生成的配置一律走 FileProvider。

### 5.3 iCloud 同步没有对等物 **【已定：A，仅加密文件导出】**

`CloudSyncStore` 的设计（171 行，单文件快照 + `updatedAt` 决胜）依赖 iCloud Drive ubiquity container。Android 没有对等物，而**真正的跨端同步必须有服务器，直接违反约束 1**。

**已定：走 A —— Android 不做云同步，只做「加密文件导出 / 导入」。** 不引入 Google Drive，不自建同步服务。

由此确定的实现要求：

- **`CloudSyncStore` 保持 iOS 独有**，Phase 0 把它反转成 `CloudSyncing` 协议注入 `AppModel`；Android 侧注入一个不可用实现，而不是在核心里加 `#if os(Android)` 分支。
- **约束 23 的 `updatedAt` / `lastLocalEditAt` 逻辑留在核心，一行不许删。** Android 上它虽不可观测，但删掉会静默破坏 iOS 的离线编辑（见 §8 第 8 条）。
- **导出文件格式必须两端互通**。用户手动把文件从 iPhone 搬到 Android 是这个方案下唯一的跨端路径，所以：
  - `AppSnapshot` 的 Codable 结构、字段名、可选性两端必须完全一致
  - JSON 编码固定 `.sortedKeys` + `.iso8601`（与 `PersistenceStore` 现状一致）
  - 加密方案选跨平台可实现的（AES-GCM + 用户口令派生密钥），**不要用 CryptoKit 独有能力或 Keychain 封装的密钥**
  - 文件头写入 `coreVersion`（§6.6），导入时版本不匹配要明确报错而非静默降级
- 黄金文件（§6.4）必须覆盖 `AppSnapshot` 的**编码 / 解码往返**，尤其是那十余个可选字段的「键缺失」语义——`DomainModels.swift:1206` 起的注释逐条说明了为什么每个字段必须是 optional，任何一处在另一端写成非 optional 都会让旧存档解码失败。

### 5.4 文件保护 **【已定】**

约束 10 的 `.completeFileProtection` 在 Android 上映射为：

- `state.json`、导出配置、二维码 PNG 一律写内部存储（`context.filesDir` / `cacheDir`），**不进外部存储**
- 用 Jetpack Security `EncryptedFile` 包一层
- `android:allowBackup="false"`，并在 `dataExtractionRules` 里排除配置目录（防 adb backup 和云备份把明文密码带走）
- 临时目录清理逻辑照搬 iOS 的 5 分钟策略

### 5.5 测延迟 **【待验证】**

`NodeLatencyService` 用 ICMP + 端口回退。Android **非 root 不能发原始 ICMP**，只能：

- `InetAddress.isReachable()`（内部可能走 ICMP，可能退化成 TCP echo，行为不稳）
- 直接 TCP connect 到节点端口测握手耗时（推荐，与 iOS 的端口回退路径语义一致）

约束：批量并发要保持 iOS 的 8 个一批（见 `NodeRuntimeBatch`），不要在 Android 上放开。

### 5.6 剪贴板 **【已定：降级为手动】**

约束 11 要求打开添加面板时自动读一次剪贴板。Android 12+ 读剪贴板会弹系统 Toast 提示，13+ 更严格。自动读取在 Android 上会变成一个用户可见的、每次开面板都出现的提示——体验上可能不可接受。

**已定：Android 侧降级为仅保留手动「从剪贴板粘贴」按钮**，不做打开面板时的自动读取。

iOS 侧行为**不变**，约束 11 继续完整生效。这是两端有意分叉的一处，原因是系统行为差异而非产品意图变化，`AddSourceSheet` 的 Android 对应实现里要写明这一点，避免以后有人"对齐"回去。

---

## 6. 双端同步机制

**「两端同时发版」是错误目标**，它会逼你为了对齐而砍功能。正确目标是**契约层同步、发布层解耦**。

### 6.1 单仓库 **【已定】**

```
tower/
├── ios/            现 Tower.xcodeproj 及 Tower/、TowerTests/
├── android/        新增
├── core/           TowerCore SwiftPM package（Phase 2A）
├── shared/
│   ├── resources/  IPCountry、ACL4SSR、WorldMap、RuleCatalog
│   └── conformance/黄金文件（§6.4）
├── Scripts/        双端共用
├── docs/
└── CLAUDE.md       约束只有一份
```

分仓是漂移的头号来源。一个 PR 同时改两端，约束文档只有一份。

### 6.2 代码生成扩展到 Kotlin **【已定】**

`Scripts/update_country_table.py` 现在只产出 `Tower/Services/CountryTable.swift`（213 行），让它同时产出 `CountryTable.kt`。所有生成物照此办理。

**这类同步成本为零且不可能漂移**，优先把能生成的都生成掉。

### 6.3 文案单一来源 **【已定】**

`Tower/Localizable.xcstrings`：**631 条 × 15 种语言**（ar de en es fr id ja ko pt-BR ru th tr vi zh-Hans zh-Hant）。

新增 `Scripts/xcstrings_to_android.py`，导出到 `android/app/src/main/res/values-*/strings.xml`。注意事项：

- `%@` → `%s`，`%lld` → `%d`，多参数要补位置索引 `%1$s`
- 复数走 `<plurals>`，不要平铺
- `'`、`"`、`&`、`<` 必须转义，否则 aapt2 静默产出错字符串
- 语言目录映射：`zh-Hans` → `values-zh-rCN`，`zh-Hant` → `values-zh-rTW`，`pt-BR` → `values-pt-rBR`
- 生成文件加 `<!-- generated, do not edit -->` 头，并在 `.gitattributes` 标 `linguist-generated`

翻译源头**永远只有 xcstrings 一份**。`Scripts/check_localization.sh` 保持只管 iOS；Android 侧用 lint 的 `MissingTranslation` 兜底。

同时注意 CLAUDE.md 已记载的坑：被 Xcode 标成 `stale` 的条目不要删（ACL4SSR 方案名走 `String(localized: String.LocalizationValue(name))` 运行时本地化，静态提取器看不见）。导出脚本必须把这些也导出去。

### 6.4 黄金文件契约 **【已定，两条分支都要】**

`shared/conformance/` 存放语言中立的行为契约：

```
shared/conformance/
├── cases/
│   ├── 001-mixed-protocols/
│   │   ├── input.json          订阅原文 + 用户设置（节点勾选、规则方案、策略）
│   │   └── expected/
│   │       ├── surge.conf
│   │       ├── clash.yaml
│   │       ├── quanx.conf
│   │       └── ...             七种目标全覆盖
│   └── ...
└── README.md
```

`ConfigurationGenerator` 的输出是确定性文本，天生适合黄金文件。

**走 Phase 2A（共享核心）也必须有这套**：它是验证 JNI 桥没把 UTF-8、换行、数字格式搞坏的唯一手段，而约束 9（`confName` / `yaml()` 折换行）正是这类问题最容易破的地方。

必须覆盖的高危用例，从现有测试提取：

- 节点名含换行 / `#` / `;` / YAML 特殊字符（约束 9）
- 带 SIP003 plugin 的 SS —— 期望被拒绝并计入跳过数（约束 12）
- QuanX 全节点 benchmark 不含 `direct`（约束 13）
- 导入 `RuleScheme` 与内置预设的分组机制不混用（约束 14）
- 刷新订阅后用户取消勾选的节点仍被排除（约束 22）—— 需要「刷新前 / 刷新后」两份订阅原文
- IPv6 字面量节点不带方括号
- 地区识别：名称优先于 IP 库，且两处给出同一国家（约束 19）

### 6.5 CI 门禁 **【已定】**

一条规则，比任何流程文档都管用：

> 改动 `shared/` 或 `core/` 的 PR，iOS 与 Android 的测试必须同时绿，否则不许合并。

外加：黄金文件的 `expected/` 发生变化时，PR 描述必须说明为什么——防止有人用「更新期望值」的方式让失败的测试变绿。

### 6.6 版本策略 **【已定】**

- `AppSnapshot` 里加 `coreVersion` 字段，与 App 版本号解耦
- 两端 App 版本号各走各的节奏，只保证 `coreVersion` 一致
- 哪端 UI 还没跟上，用 feature flag 藏掉入口，**不要拖着不发**
- iOS 的 `CURRENT_PROJECT_VERSION` 递增流程见 `docs/RELEASING.md`，Android 侧另建 `docs/RELEASING-ANDROID.md`

---

## 7. 23 条约束在 Android 上的映射

CLAUDE.md 的约束逐条过一遍。**标「核心内」的条目在共享核心方案下自动成立，这正是共享核心的价值所在。**

| # | 约束 | Android 状态 |
| --- | --- | --- |
| 1 | 内容只在本机处理 | **继续，且更需警惕**。见 §5.3，不要为了功能对齐引入服务器 |
| 2 | DNS 可解析域名，国家识别查离线库 | 继续（核心内） |
| 3 | 127.0.0.1 + 45 秒临时服务 | **改写**为 FileProvider 单次授权，见 §5.2 |
| 4 | QuanX 不做完整导入 | Android 无 QuanX，条目失效；核心逻辑保留 |
| 5 | 地区组延迟优选 + 父级手动入口 | 继续（核心内） |
| 6 | 策略组名只一个前置 Logo | 继续（核心内） |
| 7 | 首页无顶部滑入过渡、无「显示更多节点」 | **重新落地**到 Compose，语义保留 |
| 8 | 自绘点阵世界地图，不用 MapKit | 继续。Compose Canvas，禁用 Google Maps；点阵轮廓整体可点击 |
| 9 | 节点名过 `confName` / `yaml()` | 继续（核心内）**最高优先级，黄金文件必须覆盖** |
| 10 | 凭据文件 `.completeFileProtection` | **映射**为内部存储 + EncryptedFile + 关闭备份，见 §5.4 |
| 11 | 打开面板自动读一次剪贴板 | **两端有意分叉**：iOS 不变，Android 仅保留手动按钮（§5.6） |
| 12 | 无法忠实表达的节点拒绝并计数 | 继续（核心内） |
| 13 | QuanX benchmark 直接列节点，不用 `.*` | 继续（核心内） |
| 14 | `RuleScheme` 与内置预设两套机制不混用 | 继续（核心内） |
| 15 | `ACL4SSR_` 前缀 | 原因是 Xcode 拍平资源，Android 不需要；**但仍保留前缀**以共用同一棵资源树，且 `RuleRepository` 依赖它 |
| 16 | 只有主动才联网取规则；只接受 HTTPS | 继续。Android 侧另需 `usesCleartextTraffic="false"` + Network Security Config |
| 17 | 公开仓库不写敏感信息 | 继续。**新增**：`*.keystore`、`*.jks`、`local.properties`、`play-service-account.json` 加进 `.gitignore` |
| 18 | 流量取值顺序；`flag=clash` 只读响应头 | 继续（核心内） |
| 19 | 地区先按节点名，再查 IP 库 | 继续（核心内）。**Phase 1 需验证** Swift on Android 的 Emoji / 大小写行为一致 |
| 20 | 国旗用 Emoji，不自绘，不加圆底 | **行为会不同**：Android 通常有 TW 字形，iOS 没有。这是系统行为差异，不要为了对齐去自绘 |
| 21 | 第三方资源许可与 NOTICE | 继续。`THIRD-PARTY-NOTICES.md` 需覆盖 Android 构建产物；Swift runtime 随包分发时也要列 Apache 2.0 |
| 22 | `carriedOverExclusions` 保住取消勾选的节点 | 继续（核心内）**最高优先级，失效是静默的，黄金文件必须覆盖** |
| 23 | `apply()` 恢复 `lastLocalEditAt` | 继续（核心内）。若 Android 不做云同步（§5.3 选 A），本条在 Android 上不可观测，**但核心代码不许因此简化掉** |

---

## 8. 明确不要做的事

1. **不要先建 Android 工程**。Phase 0 在现有仓库里完成，它单独就有价值，失败也无沉没成本。
2. **不要为了 Android 修改 `ClientTarget` 的 `rawValue`**，它已进 `state.json` 存档。
3. **不要在 Android 上重新实现 `LANSubscriptionServer`**。
4. **不要引入任何远程配置转换服务或 IP 查询服务**，两端都一样（约束 1、2）。
5. **不要把黄金文件的 `expected/` 改成实际输出来让测试变绿**。
6. **不要在 Android 侧复制一份资源文件**，走 `shared/resources/`。
7. **不要手改 `CountryTable.*`**，改 `Scripts/update_country_table.py`（约束 19）。
8. **不要因为 Android 不做云同步就删掉核心里的 `updatedAt` / `lastLocalEditAt` 逻辑**（约束 23）。
9. **不要用 grep 手写本地化提取**，CLAUDE.md 已说明正则覆盖不全且插值无法还原。

---

## 9. 给 Codex 的第一批任务

按顺序执行，每项独立可验收。

### 任务 1：`TowerCore` target 拆分（Phase 0）

按 §4 Phase 0 的四步做，验收标准照 §4 写的三条。

**先只做第 1 步和第 2 步**（移文件 + 消除六处依赖），做完报告 `TowerCore` 实际行数和测试结果，再继续第 3 步的协议反转。第 3 步会动 `AppModel` 的构造路径，风险高于前两步。

### 任务 2：可移植性验证脚本

写 `Scripts/check_core_isolation.sh`，扫描 `TowerCore` 源文件的 import，出现 Apple 框架就退出码非 0。接进 CI 和任务 1 的验收。

### 任务 3：黄金文件契约骨架（§6.4）

从现有 `TowerTests/ConfigurationGeneratorTests.swift`、`ConfigurationCredentialTests.swift`、`SubscriptionRefreshTests.swift` 提取用例，建 `shared/conformance/`，并让 iOS 侧新增一个 `ConformanceTests` 跑这套文件。

**必须先覆盖 §6.4 列出的七个高危用例**，其余用例后补。

### 任务 4：`Scripts/xcstrings_to_android.py`（§6.3）

即使 Android 工程还不存在也先写，输出到 `shared/localization/android/`。631 条 × 15 语言，转换规则见 §6.3。写单元测试覆盖转义和复数。

### 任务 5：Phase 1 spike **【闸门】**

前四项完成后再做。产出一份结果写回本文档 §4 Phase 1，三个指标和五个风险点**逐条给结论**。

分支由 §4 Phase 1 的「闸门判定」表决定，不需要再问。但**跑完必须先提交 spike 报告并等待确认，再开始 Phase 2**——判定表只覆盖预期内的失败组合，出现表外情况（例如 1 和 2 同时失败、或出现未列出的 Foundation 缺口）一律停下来问。

---

## 10. 决策记录

**2026-08-25，项目所有者已拍板，原「待拍板」四项全部关闭。目前无未决事项。**

| # | 事项 | 决策 | 影响 |
| --- | --- | --- | --- |
| 1 | 导出目标命名（§5.1） | **改展示名**：Surfboard / Clash Meta / sing-box | 新增 Phase 0 任务：展示属性移出核心；`generate()` 加 `displayName` 参数 |
| 2 | 云同步（§5.3） | **A：仅加密文件导出**，不做 Drive，不自建服务 | `CloudSyncStore` 反转成协议；导出格式两端互通；黄金文件覆盖快照往返 |
| 3 | 剪贴板（§5.6） | **Android 降级为仅手动按钮**，iOS 不变 | 约束 11 成为两端有意分叉的一处 |
| 4 | `Observation` 不可用时（§4 Phase 1） | **`AppModel` 单独 Kotlin 重写，其余核心仍共享**（Phase 2A′） | 闸门判定表已固化；2A′ 的数据模型重复风险见该节 |

后续若产生新的待定事项，追加到本节并同步更新 `AGENTS.md` 的对应段落。
