# Tower agent instructions

开始工作前先阅读 `CLAUDE.md`，产品约束与完整验收要求以该文件及 `docs/HANDOFF.md` 为准。

## 任务分流

先判断任务属于哪一端，再决定读什么、用什么工具链：

| 任务 | 必读 | 工具链 |
| --- | --- | --- |
| iOS 功能、修复、构建、发布 | `CLAUDE.md` + `docs/HANDOFF.md` | 本机 Xcode Beta，见下节 |
| Android 移植（任何阶段） | `CLAUDE.md` + **`docs/ANDROID-PORT.md`** | Phase 0 仍在 Xcode 内完成；Android SDK/NDK 尚未配置 |
| 配置生成、解析、规则、地区识别 | `CLAUDE.md` + `docs/ARCHITECTURE.md` | 与端无关，改动同时影响两端 |

`CLAUDE.md` 的 23 条产品约束**对 Android 同样有效**，逐条映射见 `docs/ANDROID-PORT.md` §7。下节的 Xcode Beta 规则只适用于 iOS 构建，不要套用到 Android 任务上。

## Android 移植：接手前必读

完整方案在 `docs/ANDROID-PORT.md`（442 行，含实测可移植性地图）。以下是不能只靠链接传达的硬性规则，**违反其中任何一条都要先停下来问，不要自行判断**。

### 执行顺序

- 按 `docs/ANDROID-PORT.md` §9 的五项任务顺序执行，**不要先建 Android 工程**。Phase 0（拆 `TowerCore` target）在现有仓库内完成，即使 Android 版最终不做也有价值。
- 任务 1 先只做「移文件 + 消除六处非 Foundation 依赖」，报告 `TowerCore` 实际行数和测试结果后再继续协议反转。
- **Phase 1 spike 跑完必须停下等决策**，逐条给出三个指标和五个风险点的结论，不要自行决定走共享 Swift 核心（2A）还是 Kotlin 重写（2B）。

### 禁止事项

- **不要修改 `ClientTarget` 的 `rawValue`**，它已写进 `state.json` 存档，改动破坏用户数据兼容。只能改展示层。
- **不要在 Android 侧重新实现 `LANSubscriptionServer`**，改用 FileProvider 单次授权（约束 3 的 Android 映射）。
- **不要把黄金文件 `shared/conformance/*/expected/` 改成实际输出**来让失败的测试变绿。期望值变化必须在 PR 里说明原因。
- **不要在 Android 侧复制一份资源文件**，两端共用 `shared/resources/`。
- **不要手改 `CountryTable.swift` / `CountryTable.kt`**，改 `Scripts/update_country_table.py`（约束 19）。
- **不要因为 Android 可能不做云同步，就删掉核心里的 `updatedAt` / `lastLocalEditAt` 逻辑**（约束 23，删掉会静默破坏 iOS）。
- **不要为任何一端引入远程配置转换服务或 IP 查询服务**（约束 1、2）。

### 已定决策（2026-08-25，不要重新讨论）

四项产品决策已拍板，完整记录见 `docs/ANDROID-PORT.md` §10：

1. **导出目标改展示名**：`surge`→Surfboard、`clash`→Clash Meta、`hiddify`→sing-box；其余四个在 Android 隐藏。`rawValue` 不动。
2. **云同步走「仅加密文件导出」**：不做 Google Drive，不自建同步服务。
3. **剪贴板 Android 侧仅保留手动按钮**，iOS 行为不变——这是两端**有意分叉**，不要"对齐"回去。
4. **`Observation` 不可用时走 Phase 2A′**：`AppModel` 单独 Kotlin 重写，其余核心仍共享。

由决策 1 和 2 派生的硬性要求：

- **展示属性必须移出 `TowerCore`**：`ClientTarget` 的 `name` / `subtitle` / `symbol` / `appIconAssetName` / `brandSymbol` / `brandColorHex` 归平台层。
- **改展示名前先改 `ConfigurationGenerator`**。`target.name` 被写进生成配置的注释头（`:434`、`:1968`），直接改名会让两端产出字节不同的配置、黄金文件立刻失效。做法固定为：`generate()` 增加 `displayName` 参数由平台层传入，黄金文件固定传 iOS 现值。
- **`CloudSyncStore` 反转成 `CloudSyncing` 协议注入**，Android 注入不可用实现。**不要在核心里加 `#if os(Android)` 分支。**
- **加密导出不得依赖 CryptoKit 独有能力或 Keychain 封装的密钥**，格式必须两端可实现、可互通。

### 仍需停下来问的情况

- Phase 1 spike 出现「闸门判定」表**未覆盖**的结果组合（如 1 和 2 同时失败，或出现表外的 Foundation 缺口）。
- 需要新增第三方依赖、联网端点，或触碰 `CLAUDE.md` 任何一条约束的语义。
- 任何会改变 `state.json` 存档兼容性的改动。

## 本机 Xcode 工具链

- 本机开发、测试、真机构建、安装和启动固定使用 `/Applications/Xcode-beta.app/Contents/Developer`。
- 运行任何 `xcodebuild` 或 `xcrun` 命令前，先执行：

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  ```

- 本机 `xcode-select` 可能指向正式版 Xcode；不要依赖它，也不要因为正式版 Xcode 读不到账号或团队就判断用户未登录。先用 `xcodebuild -version` 确认当前命令来自 Xcode Beta。
- 开发账号和团队已登录在 Xcode Beta，真机签名优先使用自动管理。不要擅自退出账号、撤销证书或切换全局 `xcode-select`。
- 远程 TestFlight 归档使用单独的构建机配置，不沿用本机 Beta 规则；按 `docs/RELEASING.md` 执行。
- 仓库公开，文档和日志中不得写入设备 UDID、团队 ID、描述文件 UUID、个人邮箱或签名凭据。
