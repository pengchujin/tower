# 当前交接

## 1.0.27（66）双平台 TestFlight 与 Mac 分发发布（2026-10-11）

- 用户授权双平台 TestFlight 与 GitHub Mac 分发发布；包含新图标、iCloud 自定义规则缺少下载内容时的就绪状态与手动刷新入口修复。更新日志见 [1.0.27](releases/1.0.27.md)。
- 正式 Xcode 27.0（27A266a）；iOS 全量 1,333 项 XCTest（6 跳过、零失败）及 106 项 Swift Testing 通过。Mac 全量 1,333 项 XCTest（36 跳过）中 3 项本地服务测试因与 iOS 同时占用端口失败；iOS 结束后单独重跑 DirectImportServiceTests 全部 29 项通过，Mac 其余测试及 106 项 Swift Testing 通过。
- 本地化 1,122/1,122、发布脚本测试、规则更新器 20 项测试及 77 个远程规则产物验证通过；ACL4SSR 固定提交仍为上游最新。实体 iPhone 已覆盖安装并成功启动 1.0.27（66）；用户检查新图标、规则列表和导出后确认正常。
- 构建及私有日志保存在本机 `~/Builds/Tower-1.0.27-66/`；测试证据在忽略目录 `.artifacts/release-1.0.27-66/`。
- 发布源码 `84290cc` 已推送；正式 Xcode 双平台 Release 归档成功，版本、构建号、Bundle ID、签名与 Mac arm64 / x86_64 校验通过。asc 上传两端并写入中文测试说明，Apple 处理均为 VALID，内部测试群组已关联，均为 IN_BETA_TESTING；本版本未提交外部 Beta 或 App Store 正式审核。
- Mac Developer ID 公证、票据取回、严格签名、Hardened Runtime、Gatekeeper 与 DMG 挂载检查通过。GitHub [v1.0.27](https://github.com/pengchujin/tower/releases/tag/v1.0.27) 已公开并设为 Latest，含通用 DMG 和 SHA256SUMS.txt；公开回下载 SHA-256 与本机一致：`07e28fc32598c6f902795e59a6cdb5b02305939bb7dc1b529f33f9d4afa3dacf`。

- README 下载入口及 Homebrew cask 已同步；tap 提交 `b529ac0` 已推送。brew style、audit、实际升级与安装后版本、签名、公证、Gatekeeper 检查通过，本机 Mac 新版已启动并持续运行。

## 1.0.26（65）双平台 TestFlight 与 Mac 分发发布（2026-10-09）

- 用户授权使用 asc 上传 iOS / Mac TestFlight，并发布 GitHub 新版本。纳入代理导入与分享问题 #41–#44、引导页勾选交叉淡化，以及 Mac 规则页展开后滚动卡住修复；更新日志见 [1.0.26](releases/1.0.26.md)。
- 正式 Xcode 27.0（27A266a）；两端 TowerTests 各 1,332 项 XCTest（iOS / Mac 分别跳过 6 / 36 项，零失败），各 106 项 Swift Testing 通过。iOS 收尾诊断采集停顿，仅终止本轮 simctl diagnose 后 xcodebuild 返回 0；两端均有 TEST SUCCEEDED。
- 本地化提取 1,120/1,120 通过，发布脚本测试、规则更新器 20 项测试通过。实体 iPhone 已覆盖安装并启动 1.0.26（65）；用户随后在实体 iPhone 检查导入、分享及引导页并确认正常。
- 发布包及私有日志位于本机 `~/Builds/Tower-1.0.26-65/`；测试证据位于忽略目录 `.artifacts/release-1.0.26-65/`。发布源码 `607e63d` 已推送。
- 正式 Xcode 27.0 完成双平台 Release 归档；iOS 首轮因同时归档共用 DerivedData 导致中间文件冲突，改用独立构建目录后成功。版本、构建号、Bundle ID、签名团队与严格签名校验通过；Mac 包含 arm64 / x86_64。
- 使用 asc 上传两端，Apple 处理均为 VALID，内部测试群组均已关联，状态为 IN_BETA_TESTING。未提交外部 Beta 审核或 App Store 正式审核。
- Mac 已完成 Developer ID 导出、公证及公证包取回，Hardened Runtime、严格签名、stapler、Gatekeeper、双架构及 DMG 挂载检查通过。GitHub [v1.0.26](https://github.com/pengchujin/tower/releases/tag/v1.0.26) 已公开并设为 Latest，含 DMG 与 SHA256SUMS.txt；公开回下载 SHA-256 为 `23c73c4088b4217197ec206c5d49363062ce38f8cf1f2551517c278932387bbf`，与本机一致。
- README 下载入口及 Homebrew tap 已同步，tap 提交 `639e043`；brew style、audit、实际升级与安装后签名、公证、Gatekeeper 检查通过，本机 Mac 应用已启动并持续运行。

## 1.0.25（64）双平台与 Mac 分发发布（2026-10-07）

- 用户授权双平台 TestFlight、GitHub Release 与 Homebrew 更新。纳入工作区的添加订阅、导入规则分段控件与文案、键盘收起图标、管理页返回时保留 tab bar，以及对应交互测试调整；版本统一为 1.0.25（64）。更新日志见 [1.0.25](releases/1.0.25.md)。
- ACL4SSR `802e3ab` 仍为上游最新版本，77 个远程产物摘要回读通过；同步修正更新器默认提交号、Mihomo / sing-box 版本与现有快照的一致性，规则更新器 20 项测试及发布脚本测试通过。Xcode 本地化提取 1,120/1,120 通过。iOS / Mac TowerTests 各 1,321 项 XCTest（分别跳过 6 / 36 项，零失败）及 106 项 Swift Testing 通过。真机 UI 自动化三次均在测试宿主建立 IDE 连接前退出（exit 74），全新构建目录仍可复现，没有执行测试用例；模拟器四项交互（剪贴板自动填充、手动输入收起键盘、导入完整规则文本、策略组增删计数）全部通过；实体 iPhone 1.0.25（64）已覆盖安装并成功启动，用户随后在实体 iPhone 检查上述操作并确认「都正常」。

- 发布源码 `1174e45` 已推送。正式 Xcode 27.0 完成 iOS / Mac Catalyst Release 自动签名归档；版本、构建号、Bundle ID、签名团队及严格签名验证通过，Mac 为 arm64 / x86_64 通用包。两端分别于北京时间 15:02 / 15:05 上传成功，两个导出命令均返回 0。
- Safari App Store Connect 的 iOS / macOS 上传记录均已显示 1.0.25（64）「完成」。这证明 Apple 上传处理完成；本轮未操作测试群组、外部 Beta 审核或 App Store 正式审核，群组可用性没有另外验收。
- 同一 Mac 归档完成 Developer ID 导出、Apple 公证及公证包取回；Hardened Runtime、严格签名、stapler、Gatekeeper、DMG 挂载版本检查通过。公证包本机启动后持续运行。
- GitHub [v1.0.25](https://github.com/pengchujin/tower/releases/tag/v1.0.25) 已公开并设为 Latest，附 `Tower-1.0.25-64-macOS-universal.dmg` 和 `SHA256SUMS.txt`；回下载 SHA-256 一致：`c9867d18342ddbb2897e0e047993d73247a8fae3c6a57fad46649ad99ae86025`。README 下载入口已更新。
- Homebrew tap 提交 `6ba7f85` 已推送，cask 为 `1.0.25,64`；style、audit、实际升级全部通过。本机 `/Applications/塔台.app` 版本、Developer ID、严格签名、公证票据、Gatekeeper 与双架构复核通过，安装后已启动并持续运行。
- 归档与私有日志位于本机 `~/Builds/Tower-TestFlight-1.0.25-64/`、`~/Builds/Tower-TestFlight-1.0.25-64-mac/`、`~/Builds/Tower-Direct-1.0.25-64/`；测试材料在忽略目录 `.artifacts/release-1.0.25-64/`。

## 1.0.24（63）双平台上传（2026-10-07）

- 用户要求将 iOS 与 Mac TestFlight 均更新到 1.0.24（63）。相对 62，本轮不修改应用功能代码。
- 按发布门禁将 ACL4SSR 固定至最新上游 `802e3abf065f8609e7d9073ba506158dbe2ba6e7`；32 份规则内容及 77 个 MRS/SRS 二进制与上一快照一致。产物已独立发布于 `a49747b`；使用本机 Mihomo 1.19.31 / sing-box 1.14.2 重新生成并进行回读校验。
- 本机正式版 `/Applications/Xcode.app` 当前为 Xcode 27.0（27A266a）；已在 Accounts 界面确认账号与团队。iOS / Mac TowerTests 均通过 1,321 项 XCTest（分别跳过 6 / 36 项，0 失败）及 106 项 Swift Testing；两个 xcodebuild 测试命令均返回 0。iOS 收尾时模拟器诊断采集停顿，仅终止本轮 simctl diagnose 后正常结束，测试结果已保留。发布源码 `be14455` 已推送 `origin/main`。

- 发布脚本测试、规则更新器 20 项测试、上游新鲜度、77 个远程产物 SHA-256 回读校验通过。实体 iPhone 已覆盖安装并成功启动 1.0.24（63）。

- iOS / Mac Catalyst Release 自动签名归档均成功，核对 `com.jzb.tower`、1.0.24（63）及签名团队，严格签名验证通过；Mac 包包含 arm64 / x86_64。两端分别于北京时间 13:16 / 13:18 上传成功，导出命令均返回 0，Apple 回报「Uploaded package is processing」。归档与私有日志位于本机 `~/Builds/Tower-TestFlight-1.0.24-63/` 及 `~/Builds/Tower-TestFlight-1.0.24-63-mac/`。

- Safari 的 App Store Connect 已分别确认 iOS 与 macOS 的 1.0.24（63）上传记录，最后核对均为「正在处理」。尚未确认处理完成或测试群组可用性；本轮未操作测试群组、外部 Beta 审核、App Store 正式发布、GitHub Release 或 Homebrew。

## 1.0.24（62）双平台上传（2026-10-07）

- 发布源码 `2283ffd` 已推送 `origin/main`，工作区干净。本机正式 Xcode 27.1 自动签名完成 iOS / Mac Catalyst Release 归档，两端均为 `com.jzb.tower`、1.0.24（62）；严格签名验证通过，Mac 包包含 arm64 / x86_64。
- iPhone、Mac 分别在北京时间 10:51、10:54 上传成功，两个 `xcodebuild -exportArchive` 均返回 0，App Store Connect 回报「Uploaded package is processing」。上传成功不等同于处理完成或外部 Beta 审核通过；本轮不操作测试群组、外部审核、App Store 正式发布、GitHub Release 或 Homebrew。
- 本机 `Config/release.local.sh` 未填团队；按文档从未过期且匹配 `com.jzb.tower` 的描述文件确认唯一团队（与 Xcode 账号一致），只保存在当次进程变量中。归档和日志位于本机 `~/Builds/Tower-TestFlight-1.0.24-62/` 与 `~/Builds/Tower-TestFlight-1.0.24-62-mac/`。

## 1.0.24（62）发布准备（2026-10-07）

- 用户要求推送 iOS 与 Mac TestFlight 1.0.23（62）；1.0.23 已获批、预发布通道关闭，首次 iOS 上传被 App Store Connect 拒绝，经用户确认改为 1.0.24（62）。本版本包含下列 10-06 名称草稿修复及以下改动；上传结果见本节后续补充。
- **iCloud 同步启动闪退（真机复现）**：iCloud 日志清理只删快照、保留每条记录的 id 与父链接，记录只增不减。`CloudSnapshotJournal.ancestors` 每条记录递归一层，约 420 条时撑爆协作线程 512 KB 栈，每次启动同步后数秒闪退；1.0.23（61）及更早版本都有此问题，使用越久越早触发。改为显式栈迭代（保留缺记录与成环报冲突），最近公共祖先改为单次扫描父链接（原为立方复杂度）。新增 5,000 条历史在 512 KB 栈线程上合并、成环冲突、菱形历史去重三项测试。
- **引导页重做**：四个动画场景（塔台做什么、添加订阅、分流（新增 AI 🇸🇬 通道）、交给客户端）；首页中央为塔台图标（`TowerLogo` 由自有 App 图标缩制）；最后一页点哪个客户端，就从哪个图标飞入导出按钮。减少动态效果时显示静态总览。
- **首页**：统计与地图合为一张卡片，统计在上并各带图标与颜色，订阅显示「启用/总数」；延迟图例缩为 `100 ━ 350 ms`，有测速结果后才出现。首次打开（无订阅、无自有节点）只显示添加卡片，不再显示空地图和重复的介绍卡。Mac 统计栏同序同图标，并移到地图上方。
- **设置**：iCloud 卡片两行（开关行状态内含「立即同步」，删除 iCloud 副本移到恢复备份页底部，仅关闭同步且已登录时显示）；配置名称整行可点、编辑时显示清除按钮，结束编辑或关闭设置页后在动画结束后保存（同帧保存曾导致键盘与设置页关闭无动画）。导出筛选的地区、协议、名称三行同构对齐并显示当前值。
- **Mac**：App 图标按 macOS 网格单独出图（修复 Dock 白边）；Surge Mac、Clash Verge、ClashMac、Mihomo Party 图标按 180/144 放大铺满底板（修复导出页白边）。
- ACL4SSR 固定至上游 `7102021bafc77e8d19377603d8b39d3a37cc0264`（规则内容未变，仅固定提交号变化），77 个远程二进制绑定不可变产物提交 `605fc2609171e445959bd570ac40ec40c65019c4`，重新生成结果与已推送产物逐字节一致。
- 最终源码 iOS 27.0 模拟器 TowerTests 1,427 项（6 跳过、0 失败），Mac Catalyst 1,427 项（36 跳过、0 失败）；发布脚本测试、规则更新器测试、本地化 1,117/1,117 通过。模拟器首轮有 6 项源码结构断言仍固定前几轮已改掉的旧写法（添加方式 62pt 方块、飞机图标、批量操作栏 50pt、中性底色次要按钮等），已按新设计更新断言并保留触控尺寸等原意。真机已覆盖安装验证启动同步不再闪退及各界面改动。

## 未发布：恢复备份后配置名称被旧草稿覆盖（2026-10-06）

- 修复 [DEVICE_AUDIT_2026-10-01.md](DEVICE_AUDIT_2026-10-01.md) 问题三，1.0.23（61）仍带此问题。根因：设置页打开时复制的名称草稿在关闭时无条件写回，期间被恢复或 iCloud 拉取替换的名称会被覆盖。
- `ConfigurationNameDraft` 记录载入时的已保存名称：未编辑时跟随 `model.configurationName` 的变化，用户正在输入的名称优先。进入「恢复同步备份」前先提交草稿，使输入中的名称进入恢复前备份，所选版本的名称不再被草稿覆盖。删除未使用的 `loadPersistedNameIfNeeded`。
- 三处测试的本地 `.artifacts` 证据写入改为尽力而为：Mac Catalyst 测试进程沙盒无法写仓库目录时不再判失败，断言不变。
- Mac Catalyst TowerTests 1,320 项 XCTest（36 跳过、0 失败）及 106 项 Swift Testing 通过。iOS 27.0 模拟器 `CloudRecoveryInteractionTests` 2 项通过；撤掉 App 修改时恢复用例按预期失败（`-QA塔台` ≠ `塔台`）。尚未真机验收；未递增版本、推送或发布。

## 1.0.23（61）Mac 直接分发补充（2026-10-02）

- 用户补充要求更新 GitHub Release 和 Homebrew。复用发布源码 `48889b4` 的 Mac 通用归档，完成 Developer ID 签名、Apple 公证与票据取回；严格签名、stapler、Gatekeeper、arm64 / x86_64 和 DMG 挂载版本检查通过。
- DMG：`Tower-1.0.23-61-macOS-universal.dmg`，SHA-256：`100bd0156d7609752f6a276683cef6b9c7a574b472f3cb97f972d7119f3a6f3a`。
- GitHub Release `v1.0.23` 已公开并设为 Latest，附 DMG 与 SHA256SUMS.txt；公开链接回下载 SHA-256 一致。README 下载入口已更新，Homebrew tap 提交 `c31ab30` 已推送，cask 版本为 `1.0.23,61`。
- 本机未安装 Homebrew；cask Ruby 语法检查通过，不能宣称本机 brew style / audit / upgrade 已验证。cask 仅改版本、构建号与哈希，保留原兼容语法。
- 首次公证上传因 S3 网络超时失败；临时延长公证上传超时后成功，相关临时设置已删除恢复。原始日志和包位于忽略目录及本机 Builds，未纳入公开仓库。

## 1.0.23（61）双平台上传（2026-10-02）

- 发布源码 `48889b4` 已推送 `origin/main`。正式 Xcode 26.6（17F113）自动签名完成 iOS / Mac Catalyst Release 归档，两端均为 `com.jzb.tower`、1.0.23（61）；签名验证通过，Mac 包包含 arm64 / x86_64。
- iPhone、Mac 分别在北京时间 11:47、11:49 上传成功，两个 `xcodebuild -exportArchive` 均返回 0。App Store Connect 已分别显示两端 1.0.23（61），截至北京时间 11:51 均为「正在处理」，未出现错误；上传成功不等同于处理完成或外部 Beta 审核通过。本轮不操作测试群组、外部审核或 App Store 正式发布。
- ACL4SSR 固定至上游 `7ec917109533597bd7f646cf2c01ad8f1db6c88d`，77 个远程二进制绑定不可变产物提交 `5c908fceae071caebeaf5b61113d6467669848f8`；全部远程哈希、上游新鲜度检查、20 项更新器测试和发布脚本测试通过。
- 同一最终源码：iOS 模拟器 1,318 项 XCTest（7 跳过、0 失败），Mac Catalyst 1,318 项（37 跳过、0 失败），两端各 106 项 Swift Testing 通过。真机全量单元测试曾因设备不可读取宿主源码路径产生 84 项环境失败，随后改用模拟器完整验证；未把该次真机运行记为通过。界面真机验收沿用下方各修复记录。
- 归档和上传日志保存在本机 `~/Builds/Tower-1.0.23-61/`，测试证据在忽略目录 `.artifacts/release-1.0.23/`。测试审计 Markdown 见 [DEVICE_AUDIT_2026-10-01.md](DEVICE_AUDIT_2026-10-01.md)。下方“未发布”条目记录各开发阶段当时状态，其本轮改动现已包含于该版本。

## 1.0.23（61）发布准备（2026-10-02）

- 用户授权推送 GitHub 并上传 iPhone、Mac TestFlight。包含大配置预览无障碍读取阻塞修复、节点测速详情高度稳定、手机引导客户端网格整理，以及恢复备份列表最终结果一次发布与日期含义澄清。
- 本机正式 Xcode 26.6 的 Accounts 已确认登录并显示 Admin 团队。版本统一为 1.0.23（61），使用自动签名归档上传。
- 发布前更新 ACL4SSR 到最新快照，先发布不可变二进制产物，再绑定 App 清单。最终测试、源码提交与 Apple 处理状态以发布完成记录为准。

## 未发布：恢复列表不再显示会被替换的临时版本（2026-10-02）

- 用户真机反馈推翻上一轮“本地先显示、云端后补齐”的体验验收：初始当前版本与后续去重排序后的历史看起来像同一个备份日期变化。实际行日期取自快照 `updatedAt`（配置修改时间），并非备份文件创建时间；不同来源的同内容版本可能带有不同日期。
- 恢复列表改为明确加载状态，后台读取本地与云端并去重排序，完成后一次发布最终列表；失败时同样一次发布本地回退。当前使用的配置明确标为「当前使用」，不显示容易被误认成备份日期的当前修改时间；历史版本标明「配置修改时间」，使用完整绝对日期时间。时间相同时按版本 ID 稳定排序。
- 上一轮本地先发布的实现与验收结论已被本次方案替代。保留离开页面取消和过期请求不覆盖新列表的保护；未更改恢复、写盘或同步算法。
- 慢云端回归改为断言云端未返回前不发布临时版本，最终完整结果可用；Mac Catalyst 全量 1,318 项 XCTest（37 跳过、0 失败）及 106 项 Swift Testing 通过，本地化 1,116/1,116 PASS。真机最终列表出现、当前使用标签、连续读取结果稳定与正常返回均通过；已覆盖安装并正常启动。未递增版本、提交、推送或发布。证据位于 `.artifacts/device-audit-2026-10-01/recovery-stable-*`。

## 未发布：测速详情、恢复页首屏与手机引导（2026-10-02）

- 节点展开详情移除测速完成后才插入的重复「测试方式」行；方式仍保留在延迟数值旁。共享节点详情组件的真机回归覆盖测速后不新增该行、测试按钮纵向位置不变（2pt 容差）。
- 恢复备份列表先发布当前本地配置，再异步读取本地备份并后台去重，随后补齐云端历史；加载期间有进度反馈。取消／新一轮读取后旧结果不回写列表。慢云端替身回归验证云端尚未返回时本地配置已可用；没有改变恢复、同步或备份内容。
- 手机引导首页移除末行单独的 Karing 图标，保留三行十二个图标；Mac 引导和实际客户端支持保持原样。
- 最终 Mac Catalyst 全量 1,318 项 XCTest（37 环境跳过、0 失败）及 106 项 Swift Testing 通过；本地化提取 1,114/1,114 PASS。真机引导翻页／完成／重播、节点详情测速与地区选择通过。恢复页真机打开后列表在 3 秒断言窗口内出现，正常返回通过；最终包已覆盖安装并正常启动。
- 未递增版本、提交、推送或发布。证据位于忽略目录 `.artifacts/device-audit-2026-10-01/polish-*`。

## 未发布：大配置预览的无障碍读取阻塞（2026-10-02）

- 真机 5000 节点预览此前在 UIAccessibility 对高亮 UITextView 按段枚举时阻塞；主线程采样 20.688 秒中 96.83% 位于该路径。
- 增加独立 UIKit 无障碍容器，以完整纯文本提供静态文本语义，隐藏内部高亮文本视图的无障碍子树，避免重复枚举富文本段落；保留 TextKit 2、视觉选择／复制、动态字体，并转发无障碍上下滚动。传入的仍是预览已打码文本，工具栏复制逻辑未改。
- 5000 节点真机已读取完整 909,560 字符，单次 AX label 查询约 0.121 秒；小样本复制反馈通过。完整验证结果见 `docs/DEVICE_AUDIT_2026-10-01.md` 修复复测节。
- Mac Catalyst 全量 1,317 项 XCTest（37 跳过、0 失败）及 106 项 Swift Testing 通过，包含新增完整内容／更新／滚动边界回归。未实际开启 VoiceOver 验证朗读和转子体验，不能将自动化快照通过等同于完整 VoiceOver 验收。
- 未递增版本、提交、推送或发布；其余审计问题不在本次修改范围。

## GitHub 同步批次（2026-10-01）

- 按用户要求提交本轮全部源码、测试与审查文档：规则页后台准备及 iCloud 统计防闪烁、首页回弹与添加/分享收回性能、设置分组和 Emoji 菜单文案。
- 提交前使用正式 Xcode 27.1 全量复核：1,315 项 XCTest（6 跳过、零失败）和 106 项 Swift Testing 通过。此前真机交互与性能结果及其验收边界保留在下文。
- 版本保持 1.0.22（60）；本批为代码同步，不包含新的 App Store / TestFlight 发布。构建产物、原始设备日志和本机私密资料不纳入提交。

## 未发布：首页分享面板收回的共用布局优化（2026-10-01）

- 用户继续反馈首页订阅/节点分享下拉收回卡顿，要求与添加面板一起处理。上一轮只限制屏幕外 `List`，未覆盖首页不同滚动位置的分享；靠近自有节点区域仍有多份完整列表同时布局，不能据添加面板的结果宣布所有弹窗已解决。
- 共用 `CardSwipeDeletion` 改用 `CardSwipeRow`：单行、不滚动的原生 `UITableView` + `UIHostingConfiguration`，保留系统左右侧滑、禁止整段滑动直接删除，点击删除后仍先确认。父卡片提供真实高度，仅高度改变才更新行高；继续保留隐藏测量及上下各一屏预热，维持底部回弹和动态字号布局。模型、颜色模式、字号、方向、语言和启用状态传递给托管内容。没有更改分享内容、二维码生成、订阅或规则数据。
- **同一真机、1,000 节点隔离样本、每组 3 次松手事件测量**：订阅分享 71.706/72.978/74.035 ms → 50.965/51.354/50.154 ms（均值 73 → 51 ms）；自有节点分享 110.501/108.920/109.741 ms → 61.642/60.320/61.922 ms（110 → 61 ms）；展开订阅中的节点分享 49.291/48.011/50.737 ms → 43.019/44.714/44.513 ms（49 → 44 ms）。这些是主线程松手处理耗时，不是整段动画时长或零掉帧承诺。忽略安全区域的试验无改善，已撤回；临时探针已删除。
- 真机底部回弹、本地节点删除与菜单、订阅双向侧滑、三种分享收回均通过；底部及侧滑截图核对通过。添加面板首次因第三方键盘没有「完成」工具栏而使测试失败，录屏确认输入已聚焦且键盘可见；测试改为兼容键盘焦点检查。系统分享第一次合成拖动未关闭面板，调整为从预览头部快速下拉，真机复查通过（17.900 s）。添加补测另遇顶部系统提示和真实剪贴板授权框；录屏及 SpringBoard 中断日志已保留，测试增加仅处理「不允许粘贴」的提示监视，避免导入用户真实剪贴板。添加带键盘下拉最终真机复查通过（62.689 s）；用例时长不作为动画耗时。
- 全量 1,315 项 XCTest（6 跳过）初次有 1 项 loopback 测试因 `Address already in use` 失败，未改网络代码，单独复测通过（0.058 s）；其他项目及 106 项 Swift Testing 通过。失败结果保留，不记录为一次全量零失败。
- 正式 Xcode 27.1 / `Scripts/install_device.zsh` 覆盖安装 1.0.22（60）成功、正常启动成功，保留用户数据；原始结果仅在本机忽略目录 `.artifacts/share-sheet-dismiss/`。未递增版本、提交、推送或发布。用户实际数据的观感仍待复测。

## 未发布：首页添加面板下拉收回卡顿（2026-10-01）

- 用户日志记录 345 ms 的 Completed Runloop Hang；主线程集中在手势松开、系统 sheet 布局和首页多份 `UICollectionViewListCoordinator` 更新。首页每张卡片为原生侧滑单独承载一个 `List`，屏幕外卡片也参与交互式收回时的布局。
- `CardSwipeDeletion` 保留所有卡片的尺寸测量，只在可视区域及上下各一屏范围内挂载原来的原生 `List`。初始保持显示；布局暂时为零时保留上次可见状态。首页继续使用原有 `VStack`，不改变页面总高度、双向侧滑删除及确认流程，不修改订阅、规则或 iCloud 数据逻辑。
- **真机对照**：同一手机、隔离的 1,000 节点样本（16 份订阅、40 个本地节点），带键盘下拉收回时，旧实现松手事件主线程耗时 352/367/367 ms，平均 362 ms；修复后 54/55/56 ms，平均 55 ms，降低约 85%。这是松手事件处理耗时，不是整段动画时长或零掉帧证明。测量探针和临时对照开关已从最终源码移除；用户真实数据和同步偏好未用于测试。
- 最终源码全量 1,315 项 XCTest（6 跳过、零失败）和 106 项 Swift Testing 通过。模拟器回归 11 项中 10 项通过，覆盖无键盘下拉、取消、剪贴板预填、草稿取消、底部回弹、本地节点删除、订阅双向侧滑及规则页 3 项；底部和双向侧滑截图已核对。一项已有的手动添加键盘测试连续两次在立即检查 `isHittable` 时失败，但随后点击和键盘消失断言成功；改为等待工具栏按钮可点击后，单独复跑通过（19.230 s）。移除探针后的最终源码带键盘下拉复查也通过（85.038 s）。这些用例总时长不作为性能结论。
- 正式 Xcode 27.1 / `Scripts/install_device.zsh` 已覆盖安装 1.0.22（60）并成功启动，保留数据。原始日志和测量证据仅保存在本机忽略目录 `.artifacts/add-sheet-dismiss/`。未递增版本、提交、推送或发布；用户真实数据下的下拉收回观感仍待复测。

## 未发布：仅恢复两处用户选定的界面改进（2026-09-30）

- 整轮设计方案已按用户要求回退；本轮仅重新应用设置分组，以及规则菜单文案。
- 设置按「订阅与提醒」「节点与配置」「连接」分组，移动现有控件，不改绑定、默认值、开关含义与配置名称草稿提交。设置入口仍只在导出页。
- 规则菜单改名「方案选项」；Emoji 已开启时显示「隐藏策略组 Emoji」，关闭时显示「显示策略组 Emoji」，保留原有切换逻辑。Mac 隔离演示实例已实际切换两次，核对菜单及图标恢复。
- **2026-10-01 文案调整**：用户要求菜单标题改回「编辑」，动作缩短为「隐藏 Emoji」/「显示 Emoji」。仅改显示文字，仍随当前状态变化，设置分组保持不变。 65 项相关测试零失败，本地化提取 1,114 条 PASS；正式工具链覆盖安装 1.0.22（60）并启动成功，保留数据。
- 全量 1,315 项 XCTest（6 跳过、0 失败）及 106 项 Swift Testing 通过；3 项 UI 回归通过（引导重看、规则菜单/规则编辑、设置中的 Tailscale 添加）；Mac 构建通过；本地化提取 1,113 条 PASS，仅增加本轮 3 个键，其余翻译条目不变。
- 真机：正式版 Xcode / `Scripts/install_device.zsh` 覆盖安装 1.0.22（60） 成功，保留数据。脚本首次自动启动返回失败，随后单独使用 `devicectl` 启动返回 success，安装和启动已分别确认；未据此宣称完整真机界面验收。
- 本轮只修改两个产品界面组件与必要的翻译、测试和交接记录；此前的 Mac 侧栏、全局设置入口、颜色、图标、规则卡片、大字号与隐私文案等设计改动保持回退。未递增版本、提交、推送或发布。原始验证证据只在本机忽略目录 `.artifacts/design-two-changes/`。

## 未发布：规则统计在 iCloud 同步后再次闪动（2026-09-30）

- **用户实机反馈推翻前轮验收**：冷启动进入规则，真实数字已显示，1–2 秒后统计行仍闪动；用户确认开启 iCloud。首屏就绪和静态截图不能证明随后同步期间稳定。
- **已复现的原因**：`synchronizeWithCloud()` 即使合并后规则未变也会调用 `apply()`；该函数无条件清空展示摘要及规则缓存。界面因此从真实条数回到占位，再异步恢复。新的本地 CloudSyncStore 回归复现条数 3,529 → nil，UI 回归也复现“已可见的统计随后消失”。UI 隔离样本在进入后 2 秒触发真实同步路径，并放慢重算以暴露中间态；仅 Debug + 有效测试 UUID 启用，使用独立本地云端替身，不连接用户 iCloud。
- **修正范围**：应用快照前后比较实际规则输入；输入不变保留已准备的统计、语义缓存与正在执行的准备任务。输入确实改变时使语义缓存失效，导出立即使用新规则；已有展示保留到新统计就绪，已删除方案的摘要移除。同步、合并、备份、写盘和同步偏好均保持原逻辑。
- **验证结果**：旧实现的两项模型回归和一项延迟同步 UI 回归均先失败。修复后 Mac Catalyst 全量 1,315 项 XCTest（37 跳过、零失败）与 106 项 Swift Testing 通过；iOS 26.5 的首屏、返回编辑、延迟同步 3 项 UI 回归通过。延迟同步用例连续 6 秒检查真实条数及组数不消失，单独复核再次通过，系统日志确认同步完成，测试附件核对 3,529 条、11 组。simctl 录制未可靠覆盖测试中的规则界面，不作为帧级无闪烁证据。本轮仍使用隔离修复副本，不包含同期其他任务的设计改动。
- **安装与边界**：正式 Xcode 27.1 / `Scripts/install_device.zsh` 覆盖安装 1.0.22（60）成功、启动成功，保留数据，未发布。用户手机的实际 iCloud 同步后观感仍待复测；不能用本地云端替身或最终截图宣称真机动画验收。证据仅在本机忽略的 `.artifacts/rules-performance/sync-flash-*`。

## 未发布：规则标签首次进入的主线程阻塞（2026-09-30）

- 用户报告冷启动后点击底部「规则」明显卡顿。列表卡片原先同步读取规则文件、拆分条目、合并定制并计数，已有缓存只能改善后续进入。
- `AppModel.prepareRulesPage()` 在后台按值快照准备预览、有效方案和计数，再一次发布。取消或规则 revision 已改变时丢弃结果；再次切回复用已准备数据。没有启用的自定义规则流时，不为策略组预览读取上游规则全文。分组选择改变时也清除条数缓存，缓存命中仍参与 Observation。
- **用户再次反馈统计行闪动，上一轮验收不足**：移除整页加载指示、固定统计宽度只消除了布局变化，仍会发生「— → 真实条数」以及原始组数 → 定制组数的替换。延迟加载时只断言卡片几何稳定没有覆盖这一问题。新增 UI 回归已在旧实现复现：页面首次可见时缺少真实条数且存在占位文字。
- **本轮修正**：在根页面后台预备统计；用户进入规则页前等待同一 revision 的真实摘要准备完毕，保证条数与策略组数量第一次可见时已就绪。等待期间原标签可操作；用户切去其他标签时取消待进入操作。预热和点击共用一个后台任务，避免重复解析；规则变更取消旧任务，已有展示摘要在刷新时保留。Debug 隔离 UI 测试可以延迟后台准备 8 秒，普通使用和 Release 不启用延迟。本轮验证结果见下一条。
- **本轮统计首帧回归通过（隔离修复副本）**：旧实现先复现失败（首次显示缺少真实条数且存在占位；模型提前切到规则标签），修正后 iOS 26.5 模拟器的首次真实统计、返回与编辑 2 项 UI 测试通过。首屏截图核对为 3,529 条、11 组，无占位条数。Mac Catalyst 全量 1,313 项 XCTest（37 项平台/环境跳过、零失败）及 106 项 Swift Testing 通过；覆盖待进入取消、预热与导航共用一次准备、旧 revision 丢弃和主线程响应。测试副本不包含同期其他任务的设计改动，不能作为完整工作区验收。
- 十万条本地规则的模拟器回归：原卡片同步路径约 130.69 ms；准备完成后的同路径约 0.10–0.16 ms。这只衡量卡片数据读取，不是页面完整呈现耗时或手机帧率。测试同时确认准备期间主线程能运行、取消后可重试、旧结果不能覆盖新定制、匹配顺序和条数保持正确。
- 正式 Xcode 27.1 / iOS 26.5 模拟器：TowerTests 1,311 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过。冷启动点击规则 → 切走再返回 → 打开编辑，以及编辑中移除目录规则的 2 项 UI 回归通过；列表截图已核对。新增 UI 用例首次使用的按钮标识未暴露给 XCTest，改为已有用例使用的可访问名称后通过。
- 闪烁修复复核：同期另一轮设计修改正在改相同文件，且共享模拟器曾被重装打断测试，随后编译遇到未完成的 `TowerDesktopCommand` 依赖。因此在本机 `.artifacts/rules-flicker-checkout/` 基于 `21b6ad4` 加入本次修复，未混入同期设计改动；独立 iPhone 17 / iOS 26.5 模拟器全量 1,311 项 XCTest（7 项跳过、0 失败）和 106 项 Swift Testing 通过。2 项 UI 回归通过，包含延迟加载前后卡片位置、高度和顶部组数横向位置不变，以及冷启动进入、切走再回和打开编辑。测试结果仅覆盖该修复副本，不代表同时变化中的完整工作区。
- **本轮安装完成**：同一统计首帧修复副本使用正式 Xcode 27.1 和 `Scripts/install_device.zsh` 覆盖安装 1.0.22（60），脚本分别确认安装成功和启动成功，保留原有数据；未递增版本或发布。用户真实规则数据的首屏观感仍待手机复测，不能以模拟器截图代替。证据为本机忽略目录中的 `statistics-*.log` 和 UI 测试附件。
- 上一轮防闪烁副本 1.0.22（60）已通过其 `Scripts/install_device.zsh` 覆盖安装到连接的 iPhone 并启动，保留数据；用户真实规则数据的冷启动卡顿与闪烁复测待反馈。没有递增版本、提交、推送或发布。原始测试与安装日志只在本机 `.artifacts/rules-performance/`。

## 接手入口（2026-09-28）

给新接手的人（包括 Codex）先看这一段，再按需往下读。本文按时间倒序，越往下越旧；同一主题后面的段落可能已被前面的推翻，以靠前的为准。

- **最近一次正式发布**：1.0.21（59），2026-09-18。工程里的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 仍是 1.0.21 / 59，之后的改动全部未发布。发布前按 [RELEASING](RELEASING.md) 递增版本号。
- **未发布的主要内容**（详见下面各段）：
  - sing-box DNS 的国内提示（最新）。
  - 空策略组、Anywhere AnyTLS 与参考转换器对比。
  - 规则导入修复与拦截规则改为跳过。
  - 分流规则导出审计修复。
  - Tailscale 内网。
  - SSH 与 TrustTunnel 两种新协议。
  - 协议与导出格式审计第一轮（解析和各客户端字段修复）。
  - MASQUE 在各客户端的补齐。
  - iCloud 同步时机与存储瘦身。
  - 地图和列表的性能与动画。
  - 持续节点名称筛选。
- **发布前必须处理**：
  - `ProxyKind` 没有未知值兜底。旧版塔台（例如 Mac 上的 1.0.21）读到含 SSH、TrustTunnel 或 MASQUE 节点的快照，会整体解码失败。
  - 旧版不认识新增字段（例如 `tailnets`、节点名称筛选），写回时会把它们丢掉。所以 Mac 版要和 iOS 一起更新，否则 iCloud 同步会丢字段或来回覆盖。
- **已知失败的测试**：
  - `CloudRecoveryInteractionTests` 和 `testPersistentExportNameFilter` 在未改动的 main 上同样失败，与近期改动无关。
  - `testManualDoneDismissesKeyboard` 偶发失败。
  - 本地服务器相关的 XCTest 偶有一次失败，单独重跑通过。
- **容易误读的命名**：
  - `ClientTarget.clash` 是 **Stash**，`.clashApple` 才是名为 Clash 的客户端。
  - `.singBox` 是 sing-box MT。
- **测试服务**：测试 VPS 上保留协议审计服务。Tailscale 的测试 Headscale 已删除，见 [LOCAL_TEST_INFRASTRUCTURE](LOCAL_TEST_INFRASTRUCTURE.md)。地址和凭据只在本机私密目录，不写进仓库。
- **待办**：见 [TODO](TODO.md)。

## 1.0.22（60）已发布 GitHub 与 Mac 包（2026-09-29）

- 下面标为「未发布」、日期在 2026-09-18 之后的各节都已包含在本版：Tailscale、SSH / TrustTunnel / MASQUE、协议审计、iCloud 与性能、规则导出审计、DNS 拆分、issue #40 / #7、Codex 审查四项、首页修复等。
- 用户可见的更新日志见 `docs/RELEASE-NOTES-1.0.22-60.md`，同时也是 GitHub Release 的说明。
- 提交：
  - `4aba1e6`：本轮工作。
  - `7753bda`：ACL4SSR `bd00af4` 的 MRS / SRS 产物。上游只更新了 GFWList，塔台用到的规则产物与上一版逐字节相同。
  - `c912f26`：版本号、固定到 `7753bda` 的规则清单、更新日志。
  - 均已推送。
- 规则：`--verify-published` 远端 77 个产物全部校验通过；`--check-latest` 显示已是上游最新。
- 测试：TowerTests 1307 项（6 项跳过、0 失败），Swift Testing 106 项通过；本地化检查和发布脚本测试通过。
- Mac 包：
  - 本机 M4 正式版 Xcode 27.1 归档通用包（arm64 + x86_64），Developer ID 公证后取回。stapler、严格签名、Gatekeeper 和 DMG 挂载核对都通过。
  - DMG SHA-256：`53a076dd1f929069c6dcdb3ce9cdd5ab3b246ab06c2bcd51cd0753be0dc8e20a`。从公开链接回下载后哈希一致。
- GitHub Release `v1.0.22` 已公开，附 DMG 与 SHA256SUMS.txt，并标为 Latest。README 的 Mac 下载按钮已指向新版。
- Homebrew：tap 更新到 1.0.22（60），`brew style` / `brew audit` 通过，本机 `brew upgrade` 后的签名与 Gatekeeper 验证通过，已推送。
- iOS：用户随后要求上传 TestFlight。本机 M4 正式版 Xcode 27.1 用 `release_testflight_remote.sh --aqua` 按提交 `a748352` 归档 1.0.22（60），日志显示 Upload succeeded。App Store Connect 的处理状态、测试说明和测试组要到后台确认；未提交外部 Beta 审核或 App Store 审核。

## 未发布：mihomo 子规则 SUB-RULE / sub-rules（issue #7，2026-09-29）

- **问题**：[pengchujin/tower#7](https://github.com/pengchujin/tower/issues/7) 反馈 echs-top/proxy 的配置无法导入。实测 `mihomo.yaml` / `mihomo_smart.yaml` 能解析，但塔台把 `SUB-RULE,(条件),sub-telegram` 里的子规则名当成了策略组，所有客户端导出都报「规则目标不存在」。
- **修复**：`RuleSchemeParser` 读取顶层 `sub-rules:`，把子规则按原顺序展开成普通规则：
  - 子规则里每条 `条件X,策略` 写成 `AND,((外层条件),(条件X)),策略`。
  - `MATCH,策略` 写成 `外层条件,策略`；外层条件是 `RULE-SET` 时走原来的远程规则集路径，选项放在策略名后面。
  - 嵌套的 `SUB-RULE` 递归展开，最多 8 层；引用不存在的子规则或循环引用时拒绝导入。
  - 子规则都不匹配时继续匹配下一条，展开后的顺序与此一致。
  - Clash 规则的解析抽成 `appendClashRule`，普通规则路径不变。
- **表达不了的部分**：`RULE-SET` 出现在 `AND` 里面（这份配置里是「列表 + QUIC」这一组）时，塔台的模型没有对应写法。这些规则保留在方案里，导出时按 CLAUDE.md #25 跳过，并在兼容性提示里逐条列出「无法转换规则」。
- **实测**：
  - echs-top/proxy 两份配置导入后，Clash Mi 导出通过 `mihomo -t`。
  - Surge / sing-box / Loon / QuanX 仍然被阻止导出，原因是「代理QUIC」组默认用 mihomo 独有的 `PASS-RULE`（跳过本条、继续匹配），其他客户端没有等价写法；换成 REJECT 会扩大拦截范围。
  - 这份模板的规则集全是 MRS，本来也只有 mihomo 系能用。
- **测试**：新增 `SubRuleImportTests`，共 4 项。全量 1307 项 XCTest（0 失败），106 项 Swift Testing 通过。

## 未发布：sing-box ECS 提示改用 1.14 新写法（2026-09-29）

- 用户在 iPhone 上用 sing-box 实测时，列表外的国内网站确实走了直连，但 App 弹出「弃用警告」，告诉用户「配置文件已过时，请联系配置提供者」。原因是 ECS 提示那条 DNS 规则用了 1.14 起弃用的地址过滤写法。
- `SingBoxDNSPolicy`：改为 `evaluate`（仅 A / AAAA，带 `client_subnet`），后面跟 `match_response` + `rule_set: tower-geoip-cn` + `respond`。严格保护下直连域名的投影规则是普通的 `route` 加 `client_subnet`，不受影响。
- 官方 sing-box 目标从此要求 1.14 及以上。Hiddify 目标不加 ECS 提示，不受影响。
- 验证：1303 项 XCTest（0 失败）。sing-box 1.14.2 `check` 无弃用警告，标准和严格保护实跑结果与改前一致。详见 RULE_EXPORT_AUDIT。
- 真机（2026-09-29，用户）：iPhone 官方 sing-box 1.14 导入新配置后不再弹弃用警告，volcengine.com 仍然走 DIRECT。

## 未发布：Codex 审查的四个问题（2026-09-29）

审查报告和复现测试在本机 `.artifacts/codex-review/`，不在仓库里。四项都已确认、修复，复现测试已收进 `TowerTests/CodexReviewRegressionTests.swift`。

- **P1：严格保护的 DNS 因策略组结构静默回退到国内解析**。
  - 原因：mihomo 系要找一个「只含节点」的组给 `#组名` 用。像 `Proxy = select,Test,DIRECT` 这种每个组都带 DIRECT 的方案找不到，于是 `nameserver` 退回国内 DoH，远程 DNS 整个消失，严格路由却照开。
  - 修复：有节点或订阅集合、但找不到可复用的组时，新增一个隐藏的 url-test 组「DNS 自动选择」（`dnsProxyGroupName`，`hidden: true`），DNS 经它走代理。
  - 标准保护也用这个组，所以最后那条 GEOIP 同样能去掉 `no-resolve`。组名含 `#` / `&`、或只从订阅集合取节点的方案也由它兜住。
  - 完全没有节点时仍保留国内解析和 `no-resolve`；这种情况本来也不能导出。
- **P2：sing-box / Hiddify 把 `GEOIP` / `IP-ASN` 的 `src` 当成目的地址**。
  - sing-box：国家和 ASN 规则集加 `rule_set_ip_cidr_match_source: true`（1.10+），`LAN` 用 `source_ip_is_private`。
  - Hiddify（内联）：用 `source_ip_cidr`。
- **P2：空组识别误删显式写了 DIRECT 的组**。以前根据「最终成员只剩 DIRECT」反推空组，把 `Domestic = DIRECT, OptionalNode(无匹配)` 也当成空组，从父组里删掉，父组的默认值因此从直连变成了代理。现在 `resolveGroups` 只记录「确实没有成员、由生成器补 DIRECT」的组（`injectedFallbacks`）。
- **P2：Loon 通配符扩大拦截范围**。`*.example.com` 以前写成 `DOMAIN-SUFFIX,example.com`，会多拦 example.com 本身，违反 CLAUDE.md #25。现在写成 `AND,((DOMAIN-SUFFIX,example.com),(NOT,((DOMAIN,example.com))))`，依据是 Loon 3.1.7+ 的逻辑规则文档。
- **验证**：
  - 1303 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过。
  - 真实节点导出的严格 / 标准 mihomo 配置通过 `mihomo -t`，sing-box 配置通过 `sing-box check`。
  - Loon 只按文档写，没有客户端实测。

## 未发布：首页底部弹动与节点图标忽而国旗忽而协议（2026-09-29）

- **底部弹动**：首页外层 `LazyVStack` 里又嵌了「订阅」「自有节点」两个 `LazyVStack`。行高要等滚到附近才测量，接近底部时内容高度不断变化，页面就会弹一下。
  - 两个内层改回普通 `VStack`。9 月 7 日真机测量时就撤回过内层 LazyVStack，后来又被加回来了。
  - 订阅卡片展开后的节点列表仍保持懒加载：大机场有几百个节点。
- **节点图标**：名字看不出国家的节点，要等行滚进屏幕、异步 IP 查询返回后才从协议图标变成国旗，所以同一列表里两种图标混在一起。
  - 新增 `AppModel.seedKnownCountries(for:)`：服务器是 IP 字面量的，直接查离线库，同步完成、不联网；域名有未过期缓存的，直接用缓存。
  - 调用时机：启动、添加订阅、刷新订阅、添加或编辑自有节点。
  - IP 字面量走 `IPCountryLookupService.countryCode(forLiteralAddress:)`（nonisolated）。优先级不变：手动地区 → 节点名 → IP 库。
  - 没有缓存的域名节点，第一次仍要等 DNS 查询完成。
- **测试**：
  - 新增 `NodeCountrySeedingTests`（3 项）。
  - `ReviewFixTests` 里两项测主机缓存的用例改用域名 + 模拟解析：IP 字面量不再经过主机缓存。
  - 全量：1298 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过。
- **待真机确认**：首页滑到底不再弹动；自有节点的图标一打开就是国旗。

## 未发布：拖动策略组不再改变规则优先级（issue #40，2026-09-29）

- **问题**：[pengchujin/tower#40](https://github.com/pengchujin/tower/issues/40)。build 42（1.0.6）起，拖动策略组会把整张显示顺序写成 `rulePriorityOrder`，再按它重排全部规则。
  - ACL4SSR 的策略组显示顺序和规则顺序完全不同：「🚀 节点选择」显示在第一，它的 `ProxyGFWlist` 在规则里排在 AI、奈飞等专用列表之后。
  - 结果：哪怕只交换两个地区组，「节点选择」的大列表也会跳到最前，压过 AI、奈飞；「全球直连」「广告拦截」则掉到末尾。
  - 用户通过搜索添加的规则会插到第一条冲突规则前面，拖动后也会被挪走。
  - 默认没拖过的方案不受影响。
- **修复**：
  - `setRuleGroupOrder` 只写 `groupOrder`。
  - `RuleScheme.customized` 不再按优先级重排：匹配顺序 = 来源顺序 + 添加的规则插到冲突规则前面。
  - `AppModel.apply` 读到旧的 `rulePriorityOrder` 时清掉，每台设备只提示一次（`rulePriorityResetNoticeKey`）。旧版设备经 iCloud 同步回来的也会被清掉。
  - 规则定制页的列表标题从「当前规则」改为「策略组」，底部加「拖动排序只改变显示顺序，不影响分流。」
- 同时把 Anywhere 在客户端筛选里的副标题从一长串协议名改为「节点链接」。
- **测试**：
  - `testUserReorderChangesRulePriorityInEditorExportAndReload` 改为 `testGroupReorderChangesDisplayButNotRulePriority`。
  - 新增 `testACL4SSRFullKeepsSourcePriorityAfterAnyDrag`、`testSavedRulePriorityIsClearedOnLoadWithOneNotice`。
  - `testReorderingTwoAddedRuleGroupsSurvivesManualSave` 改为反向拖动后断言规则仍按添加顺序（后添加的先匹配）。
  - 全量：1295 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过；`check_localization.sh` 通过（1110 条）。
- **以后**：如果确实有人要调整优先级，按「策略组详情里的优先匹配开关」做：只把该组挪到与它重叠的规则前面，并先提示会让哪些组的规则失效。不要再做自由拖动。见 TODO。

## 未发布：国内 / 远程 DNS 拆分与保护模式调整（2026-09-29）

- 详见 [RULE_EXPORT_AUDIT](RULE_EXPORT_AUDIT.md#已实施2026-09-29用户确认其他的都改)。
- 模型：
  - `RuleSchemeNetworkSettings.remoteDNSServers` 为新字段，空值时用 `effectiveRemoteDNSServers` 回退到默认的 8.8.8.8 / 1.1.1.1 DoH。
  - 新增 `supportsClientSubnet`，判断哪些服务器支持 ECS。
  - Draft 新增 `missingRemoteDNS`。
- 导入：
  - Clash 的 `fallback`、以及 `nameserver` 里带 `#<代理组>` 的服务器归为远程 DNS。
  - `#h3=true` 还原成 `h3://`。
  - 文本编辑器写 / 读 `tower-remote-dns-server`。
- 界面：「加密 DNS」改名为「国内 DNS（直连）」，新增「远程 DNS（经代理）」分区。
- sing-box：
  - 远程服务器从远程列表生成（`singBoxResolver`）。
  - ECS 提示对所有「标准 / 严格」方案生效，不再只限默认 DNS。`chinaResolver` 优先用用户列表里支持 ECS 的服务器。
  - 严格保护下，直连域名改为经 `remote-cn` 带中国子网查询。
- mihomo 系：
  - 标准保护去掉 `fallback` / `fallback-filter`，内置预设同步。
  - 严格保护的 `nameserver` 写成 `…#<纯节点组>&ecs=…&ecs-override=true`（`clashStrictDNSTargets`，不含 Karing）。
- 测试：
  - 新增 `DNSSplitTests`，共 11 项。
  - `testCustomResolversGetNoChinaHint` 改为 `testFollowSchemeGetsNoChinaHint`。
  - `SingBoxModeTests` 现在允许末尾的 `tower-geoip-cn` 提示规则。
  - 全量：1289 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过；`check_localization.sh` 通过（1106 条）。
- 实测：
  - 16 份配置全部通过 `mihomo -t` 和 `sing-box check`。
  - mihomo 严格保护确认 DNS 经节点发出、带 ECS，列表外的国内网站拿到国内地址。
  - 已知局限：少数国内权威 DNS 不理会 ECS，例如百度。
  - 验收：远程 DNS 设置页、mihomo 标准和严格保护，Codex 在 Mac mini M2（FlClash / Clash Mi / Mihomo Party / 独立内核）测过，用户在 iPhone 上确认过（2026-09-29）。
- 未改：
  - 之后按用户决定调整了 D01：mihomo 系最后一条 GEOIP 去掉 `no-resolve`，标准保护也改为经代理 + ECS 解析，并加 `direct-nameserver`（`clashResolvesTerminalGeoIP`、`releasingTerminalGeoIP`），见 RULE_EXPORT_AUDIT「D01 调整」。
  - sing-box 1.14 起弃用的 DNS 地址过滤写法，暂时保留，见 TODO。

## 未发布：sing-box DNS 的国内提示（2026-09-29）

- 详见 [RULE_EXPORT_AUDIT](RULE_EXPORT_AUDIT.md#sing-box-的-dns2026-09-29)。
- `SingBoxDNSPolicy.apply` 新增参数 `chinaResolverHint`：在投影规则之后，追加 `rule_set: tower-geoip-cn` + `client_subnet` 的 DNS 规则，以及经代理的 Google DoH 服务器 `remote-cn`。内置方案和默认 DNS 的导入方案会开启它；用户自定义 DNS 的方案不开启。
- `RoutingRuleCapabilities.singBoxCondition(_:localRuleSets:)`：sing-box MT 的 GEOIP / IP-ASN 改为引用内联规则集，由 `attachLocalRuleSets` 统一补上定义（`localRuleSetDefinitions` 会递归扫描路由规则和 DNS 规则）。Hiddify 不变。
- 实测：列表外的国内网站从海外 CDN 变成国内地址，国外网站的结果不变；首次解析约多 70 ms。反证测试确认没有 DNS 泄露。
- 测试：
  - 新增 `testSingBoxAsksForChineseAnswersWithoutLeakingToTheLocalResolver`、`testCustomResolversGetNoChinaHint`。
  - 更新了 GEOIP 相关断言（sing-box 改为规则集引用；`ImportedSchemeGeoIPTests` 改为只禁止旧的 `"geoip"` 字段）。
  - 全量：1279 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过。
- 未改：Hiddify 的 DNS 仍然没有分流（它的内核版本和导入行为要单独验证）。mihomo 系的 fallback 已在下一节去掉。自定义 DNS 不加提示的限制也已在下一节取消。

## 未发布：空策略组、Anywhere AnyTLS 与参考转换器对比（2026-09-29）

- 起因：用户反馈 Anywhere 把 139 个 AnyTLS 节点全部跳过，并要求检查回退策略、对比 subconverter / Sub-Store。结论见 [RULE_EXPORT_AUDIT](RULE_EXPORT_AUDIT.md#与参考转换器逐项对比2026-09-28-深夜)。
- **空策略组**：`resolveGroups` 之后多一轮处理。没有可用节点的组仍然回退为 DIRECT，但父组不再引用它；父组因此变空时，逐层按同样方式回退。以前 ACL4SSR 的「🎥 奈飞视频」在没有奈飞节点时，默认会走直连。提示文字也换成了新的。
- **Anywhere**：
  - `AnywhereExport.unsupportedReason` 给出具体的跳过原因（跳过证书校验、证书固定、关闭 UDP、未知指纹、端口跳跃或插件、Reality / 传输方式），`skippedDetails` 会用它。
  - 指纹映射改成和 Anywhere 上游 `ClashProxyParser.mapFingerprint` 一致：`chrome`→chrome_133、`firefox`→firefox_148、`ios`→chrome_120；`random` 不写（Anywhere 的默认指纹）。
  - 带「跳过证书校验」的节点仍然跳过：Anywhere 总是校验证书，这类节点导出后会连不上（约束 12）。
- **节点参数补齐**（与 Sub-Store 对比时发现）：
  - sing-box 的非 Reality 节点也写 uTLS 指纹（以前全部丢失）。
  - QuanX 支持 `vless … obfs=http`（sample.conf 有这种写法）。
  - Egern 的 VLESS Reality over gRPC 写在 `transport.grpc.reality`（Egern 文档支持；9 月 27 日「只能配 TCP」的判断来自读文档，没有经过真机验证，已推翻）。
  - Loon 的 Reality 写 `tls-profile`。
- **没有改动的**：Loon 的 Hysteria2 固定写 `fast-open=true`（真机测试通过）。
- **测试**：
  - 新增 `NodeExportParityTests`（4 项）、`AnywhereTests.testFingerprintsAndSpecificSkipReasons`，以及 `RuleImportFidelityTests` 里的空组测试。
  - `ProtocolAuditTests` 的 Egern 断言改成 `testEgernPairsRealityOnlyWithTCPAndGRPC`。
  - 全量：1277 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过。
  - 30 个节点的对比输出复验通过：mihomo 系、sing-box、Surge 全部通过官方校验。

## 未发布：规则导入修复与拦截规则改为跳过（2026-09-28 晚）

- 起因：用 10 份公开的真实配置（ACL4SSR、第三方 `.ini`、Loyalsoldier、Repcz、666OS、qichiyuhub、Stash 示例、两份 Surge）走完整的导入和导出流程，发现导入这一侧有 6 个问题和 1 个设计取舍。详见 [RULE_EXPORT_AUDIT](RULE_EXPORT_AUDIT.md#导入这一侧真实配置测试2026-09-28-晚)。
- **拦截规则改为跳过**（用户决定）：以前只要有一条拦截规则转不过去，整份导出就被阻止；现在改为跳过，并在兼容性提示最前面插入「N 条拦截规则无法在 X 中表达，已跳过：这些请求不会被拦截」。不支持的内置策略（例如 `CELLULAR`）仍然阻止导出。
- **MRS**：
  - `RuleSchemeRuleset.isBinaryRuleSet`（`format: mrs` 或 `.mrs` 后缀）不进 `remoteRulesetURLs`，不下载。
  - 规划器对 mihomo 系（不含 Karing）总是远程引用；其他目标记入 `Plan.unreadableResources`，每个规则集给一条提示。
  - `RuleSchemeImportService.ruleListText` 拒绝带 NUL 字节的下载内容。
- **导入**：
  - `parseRuleset` 认识 subconverter 的五种类型前缀和末尾的更新间隔。
  - Clash 导入把 `type: direct` / `reject` / `reject-drop` 的代理映射成内置策略（`builtinAliases`）。
- **选项与策略**：
  - `RuleResourceContent.applying` 按 Surge 手册，只把 `pre-matching` / `extended-matching` 加到支持它们的规则类型上。
  - `FINAL` 的 `dns-failed` 和通知类参数在非 Surge 客户端上去掉并提示。
  - `REJECT-DROP` 在 QuanX、Egern、sing-box 上换成 `REJECT`。
- **改写**：
  - Loon 的 `DOMAIN-WILDCARD,*.x` 改写成 `DOMAIN-SUFFIX,x`，不含通配符的改写成 `DOMAIN`。（2026-09-29 按 Codex 审查改为 `AND,((DOMAIN-SUFFIX,x),(NOT,((DOMAIN,x))))`，不再多匹配 x 本身。）
  - sing-box 的 `IP-ASN` 用内置 ASN 库展开（`IPASNDatabase.cidrs(forASN:)`）。
- **DNS**：Surge 的 `h3://` 在 mihomo 系写成 `https://…#h3=true`，在 Stash / Shadowrocket / Karing 写成 `https://`，在 sing-box 用 `h3` 类型；编辑器和网络设置也接受 `h3://`。
- **本地化**：新增两条提示（MRS 跳过、拦截规则跳过汇总），15 种语言人工翻译，`check_localization.sh` 通过。
- **测试**：
  - 新增 `RuleImportFidelityTests`，共 9 项。
  - 更新了 `RoutingResourceTests` 和 `LocalRoutingRuleEditorTests` 里原来「阻止导出」的断言。
  - 全量：1271 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过。

## 未发布：分流规则导出审计修复（2026-09-28）

- 审计报告：[RULE_EXPORT_AUDIT](RULE_EXPORT_AUDIT.md)。待真机验证的项目在 [TODO](TODO.md#分流规则导出待真机验证2026-09-28)。
- **Loon / Shadowrocket 改走 `RoutingRuleCapabilities`**：以前它们走 `mappedRule` 的逐字段拼接路径，现在和 mihomo、Surge、Stash 共用同一套条件树转换。`mappedRule` 的旧路径只剩 QuanX 在用。
  - 选项一律写在策略名后面。Shadowrocket 保留 `no-resolve` / `extended-matching` / `pre-matching`，Loon 只保留 `no-resolve`。
  - AND / OR / NOT 会做方言转换：Loon 用 `DEST-PORT`、`PROTOCOL`；Shadowrocket 用 `DST-PORT`，`PROTOCOL` 只能写在逻辑规则里。
  - 规则类型只输出文档列出的（`RoutingRuleCapabilities.loon` / `.shadowrocket`）。`PROCESS-NAME`、`SUBNET`、`SRC-IP`、`RULE-SET,SYSTEM` 等跳过并提示。
  - 带逗号的值只有 Surge 会保留，其他目标一律跳过。
  - 规划器里两者的远程列表也按同一套白名单判断。
- **Loon 过滤器**：`loonScheme` 只为有对应远程订阅的组登记「塔台筛选」过滤器。以前 ACL4SSR 全分组在默认设置下，8 个组会引用不存在的过滤器，这是 1.0.10 起就有的问题。
- **远程规则集的顺序**：Loon 和 QuanX 总是先匹配本地规则、再匹配远程列表。所以 `RuleSetEmissionPlanner.plan` 会把排在某条本地规则前面的远程列表改成内联（用 `inlineFallbacks` 展开）。
  - 实际效果：ACL4SSR 最后一条是本地的 `GEOIP,CN`，所以它在这两个客户端上总是全部内联。
  - QuanX 仍保留 `filter_remote` 时，不再写 `host-keyword, .` 兜底，否则它会挡住远程列表的域名规则。
- **来源 IP**：带 mihomo `src` 的规则，在 QuanX、Loon、Shadowrocket、Egern 上跳过并提示，不再退化成按目的地址匹配。
- **sing-box / Hiddify 的 GEOIP**：用内置 IP 国家库展开成 `ip_cidr`（`IPCountryDatabase.cidrs(forCountry:)`，按国家缓存，先合并相邻区间再拆成 CIDR）；`LAN` / `PRIVATE` 转成 `ip_is_private`。
  - 数据许可是 PDDL，不需要额外署名。
  - ACL4SSR 全分组的 `GEOIP,CN` 约 1.16 万条，sing-box 配置因此从 570 KB 涨到 924 KB。
  - 内置方案的 `includeGeoIPCN` 以前写成了 `ip_is_private`，现在改成 CN 的 CIDR（内置方案目前没有启用这个开关）。
- **规则列表缺缓存**：任何远程 `RULE-SET` 在本机没有下载缓存时，都会提示「部分规则还没下载完成 · 刷新规则」并阻止导出。
  - 规则缓存不随 iCloud 同步，第二台设备以前会静默丢掉这些列表。
  - 按约束 16，不会自动联网补下载。
- **内置拒绝策略**：`RoutingBuiltinPolicies.substitute(for:target:)` 在 `generate(scheme:)` 开头替换，并给出「已将内置策略 X 转换为 Y」的提示。
  - `REJECT-TINYGIF` 在 Loon 上换成 `REJECT-IMG`，其他目标（包括 QuanX）换成 `REJECT`。QuanX 的 `reject-img` 只能用在重写规则里，分流里写它，客户端会报「未知策略或节点」并拒绝整份配置（手机实测）。
  - `REJECT-NO-DROP` 换成 `REJECT`。
  - Shadowrocket 原生支持这两个，保持原样。
  - `CELLULAR` 这类 Surge 专属策略仍然阻止导出。
- **只影响 Surge 的选项**：`RoutingRuleCapabilities.ignorableOptions`（`extended-matching`、`pre-matching`、`notification-*`、`always-capture`）在不支持的目标上直接去掉，并汇总成一条「已忽略当前客户端不支持的规则参数」。以前带这些选项的 REJECT 规则会阻止 Clash 系、Stash 和 sing-box 导出。
- **Egern**：`egernRule` 改为基于条件树的递归实现。
  - 补齐 `asn`、`domain_wildcard`、`domain_regex`、`user_agent`、`ip_cidr6`（即以前的 B11），以及 `and` / `or` / `not`（`not` 下面跟单个映射）。
  - `protocol` 的值转成小写。
  - `no_resolve` 只写在顶层的 IP 规则上。
- **mihomo 系**：不再输出 `UID`。它只在 Linux / Android 上可用，在其他平台上会让整份配置加载失败。
- **Stash**：不再输出文档里没有的 `SRC-PORT` 和 `IN-PORT`。
- **本地化**：新增两条提示，15 种语言均为人工翻译，`check_localization.sh` 通过。
- **测试**：
  - 新增 `RuleExportAuditFixTests`，共 18 项。
  - 按新行为更新了 `SurgeConfigurationImportTests`（补规则列表缓存）、`RuleSetGenerationTests`、`LocalRoutingRuleEditorTests`、`NativeRoutingRuleTests`。
  - 复验方法同审计报告，临时生成测试已删除。
  - 全量结果：1262 项 XCTest（6 项跳过、0 失败），106 项 Swift Testing 通过。

## 未发布：Tailscale 内网（2026-09-28）

- 各客户端官方写法、塔台实现、为什么不自动获取 Auth Key，见 [TAILSCALE](TAILSCALE.md)。
- 目的：代理客户端开着时也能访问家里电脑和局域网。`TailnetConnection` 不是节点：
  - 它不进任何策略组、测速组或地区组。目的地不在 tailnet 里时直接失败，不会回退直连。
  - 它只接收置顶规则：`100.64.0.0/10`、`fd7a:115c:a1e0::/48`、MagicDNS 后缀和用户填写的子网。
- 代码位置：
  - 模型：`Tower/Models/TailnetConnection.swift`。
  - 钥匙串：`Tower/Services/TailnetAuthKeyStore.swift`。测试和 UI 测试沙盒用 `InMemoryTailnetAuthKeyStore`。
  - 导出：`Tower/Services/TailnetConfigurationWriter.swift`。
  - 设置界面：`Tower/Features/Settings/TailnetSettingsView.swift`。
  - AppModel 里的相关方法：`saveTailnet`、`deleteTailnet`、`reconcileTailnetAuthKeys`、`maskingTailnetAuthKeys`、`currentTailnetExports`。
- 入口：设置 → 节点与配置 → Tailscale 内网。
  - 字段：名称、控制服务器、Auth Key（可选）、家里子网、MagicDNS 后缀、设备名。控制服务器留空为官方 Tailscale，只收 HTTPS，可以填 Headscale。
  - Auth Key 是单个输入框：打开时从钥匙串带出已保存的值并打码，点眼睛图标可查看，原地修改或清空后保存，即替换或删除。
- 存储：
  - `tailnets` 随快照同步。
  - Auth Key 只存本机钥匙串（`ThisDeviceOnly`、不可同步），不进 state.json，也不进 iCloud。
  - 快照恢复时，删除没有对应连接的孤立 Key。
  - Key 计入配置缓存键：改 Key 会让导出重新生成。
- 导出：`TailnetConfigurationWriter.apply` 在生成完整配置之后改写文本，内置方案和导入方案共用这一处。「仅节点」模式不写。

  | Flavor | 目标 | 写法 | Auth Key |
  | --- | --- | --- | --- |
  | `.surge` | Surge、Surge Mac | `tailscale` 策略 + `[Tailscale <stableSlug>]` 段，固定 `interactive-login = true` | **永不写**：Surge 按 Key 的哈希保存身份，写了会在已交互登录的设备旁边再注册一台 |
  | `.stash` | `.clash`（即 Stash） | `type: tailscale` | 写。Stash 的客户端内登录尚不可用（开发者说明 OAuth 仍在开发，实测确认） |
  | `.mihomo` | Clash、Clash Verge、ClashMac、FlClash、Mihomo Party、Clash Mi | `type: tailscale`，另加 `state-dir`、`udp`、`accept-routes` | 写。没有 Key 时，登录链接只打印在日志里 |
  | `.singBox` | sing-box MT | `tailscale` endpoint；填了 MagicDNS 后缀时再加 `tailscale` DNS 服务器；路由规则放在 sniff / hijack-dns 之后、`resolve` 之前 | 写 |
  | 无 | Shadowrocket、Loon、QuanX、Hiddify、Egern、Karing | 跳过，在「兼容性提示」里说明 | — |
  | 无 | V2Box、Anywhere | 仅节点客户端，不提示 | — |

  - `stableSlug` 取自连接 UUID。Surge 的交互登录状态和 mihomo / sing-box 的状态目录都挂在它上面：**改了它，每次重新导入都会多一台设备**。
  - 设备名按客户端加后缀（`tower-surge`、`tower-stash`……），让每个客户端注册成各自的设备。
  - 策略名和现有节点或策略组重名时，加序号。
- 兼容性提示（`notes`）：
  - Surge 不提示，在客户端里登录是正常流程。
  - 其他客户端没有 Key 时，提示在塔台里填写 Auth Key。
  - Stash 总会再加一条：它默认把 `100.64.0.0/10` 和私有网段放在跳过代理 / 跳过路由列表里，按 IP 访问不会进 Stash，要用 MagicDNS 名字访问。没填后缀时，这条改成明确警告。
- 配置预览：Auth Key 显示为等长圆点（`maskingTailnetAuthKeys`），「复制」仍然拿到完整配置。
- 实测：
  - 测试 VPS 自建 Headscale（带内置 DERP），Mac mini 以 userspace 模式加入并发布家里子网。手机上的 Surge、Stash 3.4、Clash Mi、sing-box MT 三项都通过：tailnet IP、MagicDNS、家里子网。
  - Surge 和 Stash 重复导入两次，控制服务器上仍然只有一台设备。
  - 本机 mihomo 1.19.31 和 sing-box 1.14.2 用塔台实际生成的完整配置连通。mihomo 冷启动后第一个请求会超时，官方文档说明这是正常现象。
  - 官方 Tailscale 账户：Surge（交互登录）按 IP 和按名字都能访问家里 Mac；Stash（Auth Key）按名字能访问，按 IP 被默认跳过列表挡住。
- 已评估、不做：
  - 塔台代用户登录 Tailscale 并自动拿 Auth Key。原因见 [TAILSCALE](TAILSCALE.md#为什么塔台不能自动获取-auth-key)。
- 未做：
  - 出口节点（`exit-node`）。
  - Shadowrocket 格式（官方没有公开字段）。
  - 用官方账户验收 Clash Mi 和 sing-box MT。
- 测试：
  - `TailnetTests` 16 项。其中 `testWritesProfilesForLocalCores` 只在设置了输出目录时运行，用法见 [DEVELOPMENT](DEVELOPMENT.md#tailscale-导出给本机内核联调)。
  - `TailnetInteractionTests` 覆盖在设置里新增连接、校验子网和保存。
  - 2026-09-28 文档交接时复跑：1243 项 XCTest（6 项跳过、0 失败）和 106 项 Swift Testing 通过。
  - 设置卡片的 `node-export-settings-card` 标识会覆盖卡片内每一行的标识，所以界面测试只能按标签找行。

## 未发布：新增 SSH 与 TrustTunnel（2026-09-28）

- 模型：`ProxyKind.ssh`、`.trustTunnel`（rawValue `trusttunnel`），`SSHOptions`（内联私钥、口令、主机公钥、主机密钥算法）、`TrustTunnelOptions`（`quic` 走 HTTP/3）。两者都没有分享链接格式：输入来自 Clash YAML（`type: ssh` / `trusttunnel` / `trust-tunnel`，Stash 的 `user` 同样接受），分享输出 mihomo `proxies:` 片段（`clashShareSnippet`），输入识别把单节点片段识别为该协议节点。手动添加表单支持两者（SSH 可填私钥与服务器公钥，TrustTunnel 有 HTTP/3 开关），新增 7 条文案已人工翻译 15 种语言。
- Clash 解析器补上 YAML 块标量（`|`、`|-`、`>`）：以前 `private-key: |` 下的 `-----BEGIN` 行被当成列表项，整段节点被拆坏。mihomo 允许的私钥文件路径、缺用户名或凭据的节点拒收。
- 导出：SSH → Surge（仅密码，`server-fingerprint` 固定主机公钥；私钥需 `[Keystore]` 暂不写，跳过）、Stash（`user`；不能固定主机公钥，带公钥的跳过）、mihomo 系与 Shadowrocket、Clash Mi（`username`、`private-key` 以 `\n` 转义的双引号字符串）、Egern 2.20（`ssh:`；不支持口令）、sing-box / Hiddify、Karing。TrustTunnel → Surge（`trust-tunnel`，`h3=true`）、Stash、mihomo 系、Shadowrocket；官方 sing-box、Egern、Karing、Loon、QuanX 不支持，Hiddify 仅在未发布的内核分支里有，暂不导出。Shadowrocket / Hiddify 仅节点遇到两者改用 YAML / JSON。
- 测试服务（VPS）：`tower-audit-sshd`（端口 24055，用户 `towerssh` 只允许端口转发、无 shell，授权密钥在 `/etc/ssh/tower-audit/`），`tower-audit-mihomo`（mihomo 1.19.31 TrustTunnel 入站 24056，TCP + UDP，证书复制在其主目录）。实测 mihomo 7/7、sing-box 4/4 连通（密码、私钥、主机公钥、Stash `user`、TrustTunnel HTTP/2、HTTP/3、UDP）；把主机公钥换成错误值后两者都拒绝连接。
- 手机实测（2026-09-28）：Surge SSH 密码与 TrustTunnel H2/H3 通过（H3 在家庭 Wi-Fi 被拒、5G 正常）；Egern SSH 4/4；Clash Mi 7/7；Stash SSH 通过，TrustTunnel 仅 HTTP/3 通过，HTTP/2 加不加 `alpn: [h2]` 都超时（同一服务器 HTTP/2 在 Surge、Shadowrocket、Clash Mi 正常），现对 Stash 只导出 `quic: true` 的 TrustTunnel；Shadowrocket TrustTunnel 3/3、SSH 密码通过，私钥节点在认证前被它自己断开（sshd 日志只有 `Connection closed … [preauth]`，同一私钥在 mihomo/Egern/Clash Mi 登录成功），现对 Shadowrocket 跳过带私钥的 SSH。
- 风险：`ProxyKind` 没有未知值兜底，旧版塔台（例如 Mac 1.0.21）读到含 SSH / TrustTunnel（以及此前的 MASQUE）的快照会整体解码失败；发布前 Mac 端需同步更新。
- `SSHTrustTunnelTests` 9 项；`SourceInputDetectorTests`、`SymbolAvailabilityTests`、`ManualNodeDraftTests` 覆盖新协议。1227 项 XCTest 与 106 项 Swift Testing 通过。

## 未发布：协议与导出格式审计第一轮（2026-09-27）

- 方法：在测试 VPS 上保留原 25 个实验入站，另建 `/opt/tower-audit`（sing-box + Xray，systemd 服务 `tower-audit-sing-box`、`tower-audit-xray`；UDP 24060–24069 经 iptables `TOWER_AUDIT` 链转发到 24042，重启后失效），补充 gRPC、HTTP/2、HTTPUpgrade、SS2022（三种算法）、ShadowTLS v3、Hysteria2 Salamander 与端口跳跃、Reality + gRPC/XHTTP、WebSocket 早期数据、HTTP/1.1 伪装、VLESS 加密、Naive。节点经塔台 `LocalCompatibilityCorpusTests`（新增输出跳过原因）导出全部目标，再用 mihomo 1.19.31、sing-box 1.14.2 绑定 en0 绕过本机 Surge，逐节点经 VPS 请求测试地址。服务器地址、凭据和导出文件只在本机 `.artifacts/protocol-audit/` 与 `docs/LOCAL_TEST_INFRASTRUCTURE.md`。
- 修复（均已实测失败 → 修复后通过，或按客户端文档确认无法表达）：
  - 解析：VLESS/Trojan 链接 `type=http` 按 Xray 规范为 HTTP/2；`type=tcp&headerType=http` 与 VMess `net=tcp,type=http` 的 HTTP/1.1 伪装以前被丢弃，导出后变成普通 TCP。分享链接改为标准写法（VMess `net:tcp,type:http`；VLESS/Trojan `type=tcp&headerType=http`），不再写会被读成 HTTP/2 的 `net:http`。
  - 原生 SS TLS 只有 Shadowrocket（`tls: true`）和 QuanX（`obfs=over-tls`）能表达；Surge、Loon、Clash Mi、Karing 和 V2Box/Shadowrocket 分享链接以前都丢掉 TLS 写成普通 SS，现统一跳过。Shadowrocket 仅节点遇到此类节点改用 YAML。
  - Clash Mi（mihomo 内核）补入 AnyTLS/SOCKS5/HTTP Reality 跳过规则，与交接中 09-06 用户反馈的 07/09/10 失败一致；Loon 与 Karing 跳过 SOCKS5/HTTP Reality（Loon 文档没有该字段，Karing 用户实测失败），Karing 跳过 SOCKS5 TLS。
  - Loon：Hysteria2 以前漏写 `salamander-password`，混淆节点永远连不上；补上并写 `server-ports`，非 Salamander 混淆跳过。Trojan 只保留 ws（Loon 把 `transport=http` 当 WebSocket）。
  - Egern：Reality 只能配 TCP，gRPC/HTTP2 固定普通 TLS、HTTP/1 不带 TLS，以前 VLESS Reality + gRPC 会丢 Reality；Trojan 只支持 WebSocket，以前其他传输被写成普通 TCP Trojan。
  - WebSocket 早期数据 `?ed=`：sing-box/Hiddify 与 Stash 改写为 `max_early_data` / `max-early-data` 字段并去掉路径参数（sing-box 服务端会按完整路径拒绝）；Surge、Loon、QuanX、Egern 去掉该参数；mihomo 与 Shadowrocket 保持原样。
  - sing-box/Hiddify 的 `http` 传输在有 TLS 时是 HTTP/2、无 TLS 时是 HTTP/1.1，无法表达的另两种组合跳过。
  - Hysteria2 端口跳跃：以前只有 Clash YAML 保留，现补 Surge `port-hopping`、Loon `server-ports`、sing-box `server_ports`、Egern `port_hopping`。
  - 新增 `ProxyNode.vlessEncryption`：VLESS `encryption=mlkem768x25519plus…` 以前被当作 none 导出。现从链接和 Clash YAML 读取，仅导出到 mihomo 系目标（已实测连通），其他目标跳过。
- 第二轮（与最新 Sub-Store 逐节点字段对照后修复）：
  - 新增按客户端的 SS 加密算法白名单（Surge 手册、Loon/Egern 文档；QuanX、Stash 参照 Sub-Store）。`2022-blake3-chacha20-poly1305` 以前照样导给 Surge、Loon、QuanX、Stash；Egern 不支持 aes-192-gcm、xchacha20-ietf-poly1305。算法缺失时仍按 aes-256-gcm 写出。
  - Stash 按其文档改写字段：Hysteria2 用 `auth`，Hysteria 1 用 `up-speed` / `down-speed`，TUIC 写 `version: 5`（缺省按 v4 解析）。mihomo 系保持 `password` / `up` / `down`。
  - Loon 的 VMess/VLESS 补 `udp=true`；QuanX 的 VMess、VLESS、Trojan、SOCKS5、SSR 补 `udp-relay`。两者缺省都不转发 UDP，以前只有 SS / Trojan（Loon）或 SS / AnyTLS（QuanX）会转发。
  - 对照中确认没有问题的差异：Egern `local_ipv4` 可写纯 IP；QuanX VMess 方法名与 AEAD 缺省已由用户实机验证。WireGuard 在多个客户端失败，更可能是国内网络拦截握手（本机直连同样超时，经代理可通）。
- 第三轮（服务器写 IP、SNI 另指域名的节点，机场「优选 IP」常见写法）：
  - Clash YAML 的 Trojan 以前把 SNI 写成 `servername`（只有 Stash 写 `sni`）；mihomo 的 Trojan 只认 `sni`，结果发送 IP 作 SNI，实测失败。现在所有 Clash 系目标都写 `sni`，并补写 Trojan ALPN。
  - mihomo 与 Stash 的 SOCKS5 没有 SNI 字段（mihomo 源码 `ServerName: option.Server`），SNI 与服务器地址不同的 SOCKS5 TLS 节点在这两类目标上跳过。
  - VMess/VLESS/Trojan 的 WebSocket、HTTP/2、HTTPUpgrade 在开启 TLS 但没有 SNI 时，按 v2rayN 的约定用 Host 作 SNI：Surge、Loon、QuanX、Egern 以前会把 IP 当 SNI。mihomo 与 sing-box 本来就会这样处理（实测连通）。
- 第四轮：Hysteria 2 官方 URI 可把端口跳跃写在地址里（`host:443,20000-30000`），以前整条链接被当作无法识别；现取第一个端口为主端口、完整列表为端口跳跃（含 IPv6）。往返测试：塔台导出的 54 条分享链接重新导入后全部解析，mihomo 实测除 WireGuard 外全部连通。
- AmneziaWG（mihomo `amnezia-wg-option`、链接中的 `jc`/`jmin`/`jmax`/`s1`/`s2`/`h1`–`h4`）以前被当作普通 WireGuard 导入，导出后必然握手失败；现在拒收并计入无法识别。
- 手机实测（Loon 3.5.1）：带 Salamander 的 Hysteria 2（42/52/54/55）全部失败，不带混淆的 13/73 正常。塔台给 Loon 写的 `salamander-password` 带引号，Loon 文档示例和 Sub-Store 都不带；引号会被当成密码的一部分。现改为不加引号，值里含分隔符时跳过。同轮 WireGuard（15）、HTTP 伪装（49/50）、IP + SNI（60/61/70–73）、早期数据（45）在 Loon 上均正常；19 VMess WS TLS 失败待单独重测（同服务器的 77 正常）。
- 手机实测第二轮：Loon 修复后全部通过，QuanX 全部通过。Stash 的 77/78（服务器写 IP、只有 Host）超时：Stash 不像 mihomo 那样把 WebSocket Host 当 SNI，现在 Clash 系写入器也显式写 `servername`。Stash 的 WireGuard（15）超时而同一手机 Loon 可连，待用对照配置区分 `allowed-ips` 与 `dns` 的影响。
- 手机实测第三轮：Surge、Shadowrocket、Egern 全部通过。Surge、Egern 的 Hysteria/Hysteria 2/TUIC 在家庭 Wi-Fi 下被拒（`Connection refused` / 超时），切到 5G 全部正常，属网络问题；各客户端 WireGuard 受运营商拦截。Egern 冷启动时会丢弃导入链接（第一次点击无反应，第二次成功），塔台无法补救，导出页对 Egern 增加一句「刚启动没有新配置时再点一次」的提示（15 种语言人工翻译）。
- 手机实测第四轮（Karing 1.2.25）：HTTP/2（32/37）、HTTPUpgrade（33/34）、Trojan Reality（08/47，与 09-06 用户反馈一致）失败，同一文件在 mihomo 上连通；WebSocket、HTTP/1.1 伪装、gRPC、XHTTP 与其余协议正常。Karing 的传输白名单收窄为 ws/http/grpc/xhttp，并跳过 Trojan Reality。Karing 的 `scheme_handler.dart` 遇到已存在的 URL 直接「already exists, skip add」，因此塔台固定的本机地址只在删除旧配置后才能再导入；现在给 Karing 的导入地址加每次不同的 `tower-import` 参数（服务端匹配时忽略查询），导出页提示旧配置可删除。Karing 的备注名也要求唯一（「备注已存在」），名称后追加导出时间（`MM-dd HH:mm:ss`）。Clash Mi 仍用固定地址原地更新。
- 手机实测第五轮（Hiddify、V2Box、Anywhere）：Hiddify 完整配置把 ShadowTLS 辅助通道 `tower-shadowtls-N` 列成可选节点并测速失败，现在 Hiddify 完整配置也加 `§hide§`（官方 sing-box 只列组成员，保持原样）。V2Box 的 HTTP/2（32/37）超时，Xray 已删除该传输，V2Box 不再导出。Anywhere 把服务器写 IP、只有 Host 的 78 判为不安全；「无 SNI 用 Host」规则移到 `ProxyNode.withTransportHostAsSNI`，配置写入器和分享链接共用。13/73（24013 端口）在家庭 Wi-Fi 下多客户端超时、42 正常，与 Surge/Egern 一致，属网络问题。
- 验证：`ProtocolAuditTests` 17 项；`testKaringYAMLPreservesRealityOnlyWhereItConnects`、`testNativeShadowsocksTLSIsSkippedWithoutLosingPlainSS` 按新规则更新。第二轮后 1208 项 XCTest（5 跳过、0 失败）与 106 项 Swift Testing 通过，`ProtocolAuditTests` 第二轮增至 21 项、第三轮 24 项（1211 项 XCTest 全部通过），`TUICHysteriaTests` 两项改为分别断言 mihomo 与 Stash 字段。实测：mihomo 目标 41/42、sing-box 目标 38/39 连通，唯一失败为 WireGuard（直连时握手超时，经代理路径可通，判断为本地运营商拦截）。
- 未完成：图形客户端（Surge、Loon、Shadowrocket、QuanX、Stash、Egern、Karing、V2Box）尚未在 Mac mini 上实测；SSH 通道没有截屏与辅助功能权限。缺失协议评估见本轮报告。

## 未发布：刷新进度与提示统一到顶部，协议筛选行不再折行（2026-09-27）

- 批量刷新订阅的进度原来显示在底部标签栏上方，而完成提示（「17 个订阅已全部更新」）和规则更新提示显示在顶部，两者位置不一致。现在进度改由根层的 `ToastOverlay` 显示（`towerToast(showsRefreshProgress: true)`），与所有提示共用同一个 `StatusSurface` 外框和 `StatusBadge`。进度徽标是确定进度的圆环；刷新完成时，同一个外框原地换成完成提示，不再先消失再出现。外框按内容宽度显示，停在「管理」和「+」之间，不挡导航按钮。只在订阅页显示；单个订阅刷新时仍由卡片上的按钮转圈。移除了 `subscriptionRefreshProgress()` 修饰符和底部的胶囊进度条。UI 测试 `testSubscriptionRefreshShowsTopStatusAndCanCancel` 检查进度位于顶部、不遮挡两个导航按钮，并可以取消；测试用抓取延迟由 8 秒改为 15 秒。
- 协议筛选：已选协议列表放不下时，不再折成三行夹在分隔线之间，而是在同一行显示「已选 x/y 种」（新增文案，15 种语言已人工翻译）。只有特大字号才上下排列，并留出上下间距。保留既有决定：数值使用主文字色，不显示右箭头。另外修正了「全部协议」的翻译：原来的机器翻译是 “All agreements”，已按“协议＝protocol”改正全部语言。
- `testFilterAtAccessibilityTextSize` 在改动前的代码上同样失败，与本次改动无关，尚未处理。

## 未发布：客户端选择只存本机，压缩本机和 iCloud 存储（2026-09-27）

- 客户端选择：浏览导出页时切换客户端，不再写入 `state.json`，也不触发 iCloud 同步。选择只保存在 `UserDefaults` 里，键名按平台和存储路径区分（`selectedClientTarget.phone|mac.<路径>`）；启动或套用快照时优先读取本机记录。快照中的 `selectedTarget` 保留旧值，旧版本读取时不会出错。只有在选中一个之前隐藏的客户端时，才需要保存客户端列表。新增 `testBrowsingClientsIsNotSaved`。
- 存储：快照改为紧凑 JSON（不再缩进），约减少 1/4 体积。本机备份改用 LZFSE 压缩（`.json.lzfse`），仍能读取旧的 `.json` 备份。本机和 iCloud 的保留份数从 10 份降到 5 份（`CloudSnapshotJournal.retentionLimit`）。清理 iCloud 时，较旧的快照只有在包含与已保留快照不同的用户决定时才保留；同步没有产生新内容时，也会调用 `compact()` 清理一次。首次进入前台时会在后台整理一次本机备份，删除超过保留份数的旧备份。
- 保留未动：iCloud 上的 `.pruned` 标记（每个几百字节，三方合并需要它们判断分支；删除后，旧设备可能重新上传已删除的内容）；导入的规则文件（`ImportedRules`，导出配置需要）。iCloud 上的快照继续使用未压缩的 JSON，否则 Mac 上的 1.0.21 读不了。
- 清理 iCloud 时，当前各分支的共同基线（`mergeBases`）一律保留，不参与去重；否则两台设备的并发修改会因为找不到基线而判为冲突。「重置所有配置」同时清除本机记录的客户端选择。1187 项 XCTest（5 项跳过、0 失败）与 105 项 Swift Testing 全部通过。
- 刷新规则方案只会重新下载本机缓存的规则列表，并更新 `RuleScheme.updatedAt`。这个时间戳不再计入同步签名，因此手动刷新规则、以及保存自建配置后的自动刷新，都不会再生成新的 iCloud 版本。本机照常显示刷新时间；其他设备要等下一次有实际修改的同步才会拿到新时间。新增 `refreshingARuleSchemeIsNotAChange`。
- 预计效果（以实测数据估算）：本机备份由约 7.1 MB 降到 1 MB 以内；iCloud 快照由 10 份约 9 MB 降到最多 5 份约 3.5 MB，内容重复的快照会进一步减少。

## 未发布：追查无修改仍同步，规则缓存不再被每次保存清空（2026-09-27）

- 第三次录制共发生 5 次由保存触发的同步（6.1、18.7、38.3、47.4、83.9 秒），用户期间没有做修改；触发它们的保存来自订阅刷新写回和普通保存（例如浏览导出页时切换客户端）。每次同步都走到了提交和清理，说明签名比较被判为“有变化”。可能的原因有三种：套用后被规范化、同步失败后反复重试、与 Mac 上 1.0.21 旧版同步逻辑来回覆盖。在干净的测试数据下无法复现（新增测试 `testSyncedStateIsNotReportedAsChangedWithoutAnEdit` 通过）。
- 修复与观测：已同步签名改为用套用后重新生成的快照计算；如果和合并结果的签名不同，会记一条日志。同步失败后，由修改触发的自动同步退避 10 分钟。新增 `Logger(subsystem: "com.jzb.tower", category: "CloudSync")`，记录同步原因、是否上传、失败原因和跳过原因，不记录任何订阅内容；这些日志可以在控制台（Console）和 Instruments 的系统日志表中查看。需要下一次真机录制来确认是哪种原因。
- 注意：Mac 上安装的是 1.0.21 正式版，仍是旧的同步逻辑，而且不认识新增字段（例如节点名称筛选）。如果它与新版本同时使用，可能在同步时丢掉这些字段，或者引发来回同步。发布前需要让 Mac 版同步更新。
- 规则性能：`materializedScheme` 和 `customizableScheme` 的缓存以前每次保存都会清空，规则页和导出请求都要重建方案、重读全部规则列表（录制中 159–342 毫秒）。现在只有方案、定制、自定义规则、本地规则集、选中策略组或 Emoji 设置变化时才清空；在载入和套用快照后调用 `recordRuleInputs()` 记录当前输入。域名集的逐行转换改由 `DomainSetLineCache` 缓存。新增 `RuleSchemeCacheTests`。
- 1186 项 XCTest（5 项跳过、0 失败）与 105 项 Swift Testing 全部通过。

## 未发布：第三次真机录制与 iCloud 历史读取缓存（2026-09-27）

- 录制结果：掉帧从 191 次降到 102 次，每帧离屏渲染最多从 55 次降到 36 次，iCloud 同步只占主线程 40 毫秒。前台剩余的卡顿都在规则相关界面：`resolvedRuleLines` 342 毫秒、打开规则定制 180 毫秒、`customizableScheme` 159 毫秒、导出页准备请求 165 毫秒、`ruleCount` 111 毫秒，尚未处理。
- 录制中发生 3 次由修改触发的同步，每次在后台线程消耗约 1.5 秒 CPU：iCloud 历史目录共有 333 个文件（10 份完整快照、323 个清理标记，标记只增不减）。每次同步要把目录完整读 4–5 遍，每个文件都查询一次下载状态，并重新解码 10 份完整快照。
- 修复：新增 `CloudCommitCache`，按“路径 + 修改时间 + 大小”缓存已解析的历史记录（记录写入后不会再变，清理标记使用单独的文件名），只读取新出现的文件，已删除的文件同时从缓存中移除。清理标记仍然全部保留，“清理标记优先”和“延迟分支安全失败”的规则不变。
- 1184 项 XCTest（5 项跳过、0 失败）与 105 项 Swift Testing 全部通过，新增缓存跟随新标记和删除的测试。

## 未发布：重新设计 iCloud 同步时机与 IP 识别频率（2026-09-27）

- 问题：同步快照里混有会自动变化的数据（刷新拉下的节点及其重新生成的 ID、订阅的更新时间/流量/错误、按服务器缓存的 IP 国家码和时间戳、当前查看的客户端）。刷新订阅或识别国家都会调用 `persist()`，2 秒后触发一次完整同步；只要内容有差异，就会往 iCloud 追加一份完整快照，并在本地备份一份，最近 10 份历史很快被这些自动版本占满。IP 识别在识别不出国家时每 30 秒重试（包括解析到了 IP、只是离线库里没有这个国家的情况），成功的结果每小时整批重新解析，结果写回时还会触发 iCloud 同步。
- 同步签名 `CloudSnapshotMerge.signature`：对快照中用户做出的决定取 SHA-256，不包括订阅拉下的节点、订阅状态、IP 缓存、编辑时间和当前查看的客户端。订阅节点的排除记录和手动指定的地区，改用 `订阅 ID + nodeStableIdentity` 表示，不随刷新变化；自有节点全部计入。`sameContent` 用于比较两份快照是否相同。
- 使用签名的地方：修改后的同步延迟从 2 秒改为 5 秒，到时签名与 `lastSyncedCloudSignature` 相同就不同步；合并结果与云端签名相同时不提交新版本，本地基线直接记为云端保存的那一份（`cloudContent`），避免下一次三方合并把云端较旧的节点当成远端修改覆盖回来；本地备份、备份去重和恢复副本列表都按签名判断，只差状态或缓存的版本不再占用名额。回到前台时最多每 10 分钟检查一次（`cloudForegroundCheckInterval`，默认 600 秒，测试可以传 0），“立即同步”不受限制。关闭同步或删除云端副本时清空已同步签名。
- IP 识别：识别服务成功结果缓存 24 小时；解析到 IP 但离线库里没有这个国家也算确定结果，同样缓存 24 小时；只有 DNS 解析失败才按 10 分钟重试。模型层识别不出国家的节点 10 分钟后才会再次尝试。识别结果通过 `persistLocalCache()` 只写本机文件，不记为用户修改，也不触发同步。网络组织与国家识别共用服务器解析缓存，结果没变时不重复写入。
- 新增 `CloudSyncSignatureTests`（4 项）；iCloud、备份、合并与地区识别相关的 31 项 XCTest 和 14 项 Swift Testing 通过；全量 1184 项 XCTest 中只有已知的本地服务器偶发失败。真机效果待用户确认。

## 未发布：第二次真机录制与前台卡顿修复（2026-09-27）

- 录制中的严重卡死都发生在 App 离开前台时（保存后被系统挂起，或系统拍多任务界面快照），不是前台卡顿；上一轮对导出页 1.09 秒卡顿的归因已据此修正。iCloud 合并已不占用主线程，离屏渲染从每帧最多 112 次降到约 55 次。
- 修复：刷新、删除和 IP 解析写回改为每个可观察集合只修改一次（`forgetRuntimeState(of:)`）；节点筛选页的分组结果缓存，勾选状态改为集合查询；规则条数缓存只在规则相关的输入变化时才清空。
- 注意：真机上装的是 Debug 构建，App 自身代码未经编译优化。1184 项 XCTest 与 100 项 Swift Testing 通过，相关界面测试 4 项通过。详见 animation-plans/README.md「第七轮」。

## 未发布：真机 Instruments 定位日常卡顿（2026-09-27）

- 真机录制 91 秒，发现 iCloud 同步在主线程上合并（三次 160–230 毫秒无响应，全程 558 毫秒）、首次进入导出页卡死 1.09 秒（大尺寸图标解码与界面构建）、阴影导致每帧 55–112 个离屏渲染。
- 修复：iCloud 合并、比较、备份和编码移到后台线程，后台计算期间有新修改时在主线程重做最后一步；客户端图标缩放到 180 像素，已更新第三方说明和 NOTICE；阴影只加在背景形状上。
- 1184 项 XCTest 与 100 项 Swift Testing 通过，导出页界面测试 7 项通过。详见 animation-plans/README.md「第六轮」。需要再录一次真机做对比。

## 未发布：地图缩小与居中卡顿第二轮（2026-09-27）

- 模拟器打点确认，从最大缩放“恢复默认”时，`Canvas` 在缩放动画中被 SwiftUI 重画了 4 次整张世界图。改为 `WorldDotRasterizer` 在后台线程画成位图，动画期间只由 GPU 重新采样；复测动画期间的重画次数为 0。
- 用 Time Profiler 按 App 进程挂载测量，再结合代码：地区列表不再按国家 ID 重建，避免切换国家时两份列表叠加渲染；节点列表滚进视野的动作延后到居中动画结束后。点国家居中的 CPU 指令从 1,898 万降到 1,650 万 kI（最初为 2,124 万）。
- 1184 项 XCTest（5 项跳过、0 失败）与 100 项 Swift Testing 通过；地图界面测试 4 项通过。详见 animation-plans/README.md「第五轮」。真机手感待用户确认。

## 未发布：地图拖动与居中卡顿（2026-09-27）

- 用户反馈放大后拖动、点国家居中都明显卡顿。原因有三处：按下和松手时整张底图在两个渲染器之间来回切换并重画；选中国家的颜色画在底图里，导致居中动画中途整张重画；标签每帧重新排版，且每个标签都带阴影。
- 修复：只保留一个底图渲染器，只在画面静止后才重画（`settleRasterIfIdle`）；选中国家单独放一层小画布（`WorldDotSelectionCanvas`）；手势期间冻结标签位置；标签阴影改为细描边。计划见 animation-plans 006–008。
- 1182 项 XCTest 与 100 项 Swift Testing 通过（一项本地服务器测试偶发失败，单独重跑通过）；地图界面测试 4 项通过；新增两条模拟器性能对照测试，结果记录在 animation-plans/README.md。真机手感待用户验收。

## 未发布：去掉刷新遮罩、地图惯性和导出标题的折中（2026-09-27）

- 整批刷新改用标签栏上方的非阻塞胶囊（进度和取消），不再显示全屏遮罩；卡片单独刷新只在卡片上转圈。整批刷新可以接管卡片刷新，整批期间点其他卡片也会刷新。失败报告仍是居中卡片。界面测试已改名为 `testSubscriptionRefreshShowsFloatingProgressAndCanCancel`。
- 地图松手按手指速度滑行：指数衰减投射，减速率 0.99，上限为短边的 40%，每秒 80pt 以下不滑行；临界阻尼 0.4 秒弹簧，并限制初速度，避免越过边界。原来的 4% 动量系数删除。
- 导出页空闲时预生成左右相邻客户端的配置；冷生成超过 200ms 才把标题淡变为“正在转换…”，并把图标调淡。
- 1181 项 XCTest（5 项跳过、0 失败）与 100 项 Swift Testing 全部通过；本地化 1035/1035；相关界面测试 11 项全部通过。细节见 [animation-plans/README.md](../animation-plans/README.md) 的「第三轮」。

## 未发布：动画审查剩余 6 项（2026-09-27）

- 详情见 [animation-plans/README.md](../animation-plans/README.md) 的「第二轮实施结果」。浮层动画统一使用 `TowerMotion.surface` / `surfaceTransition`；订阅卡片长按菜单改用缓存计数；订阅和地区列表的节点行轻点打开详情；删除死代码；地图选中国家后把节点列表滚进视野；由测速按钮发起的整批测速完成时给成功触感。
- `CardSwipeDeletion`：模拟器对照显示，滚动自有节点区域时 CPU 指令约多 70%，主要来自每张卡片各自的 List。去掉隐藏副本的方案只省约 3%，未采用。原生滑动删除保留，等真机数据再决定。真机测量需要在 iPhone「设置 → 开发者」里打开「启用 UI 自动化」，然后运行 `testPerformanceAuditLocalNodesWithCardSwipe` / `WithoutCardSwipe`。隐藏副本里重复的触感和 IP 查询已修复。
- TowerTests 1178 项 XCTest（5 项跳过、0 失败）与 100 项 Swift Testing 全部通过；本地化检查 1035/1035。界面测试提前停止，失败项已单独复核：两项是偶发失败，`testPersistentExportNameFilter` 是 `bac4ff9` 上就存在的过期断言（等待已不显示的“筛选持续生效”）。

## 未发布：动画与交互审查修复 5 项（2026-09-27）

- 审查报告与五份实施计划见 [animation-plans/README.md](../animation-plans/README.md)。此前工作区的未提交改动已原样提交为检查点 `bac4ff9`，本轮修复单独提交在它之后。
- 修复内容：节点名称导出筛选改用独立的名称匹配缓存，勾选节点时不再重跑正则，筛选失败时导出页显示原因；定制未选中的规则方案时，提示当前导出所用方案并提供“改用此方案”；延迟徽标使用固定槽位并做局部淡变，批量测速时节点名称不再抖动；添加面板等剪贴板读取结果出来后再决定是否聚焦；输入识别结果缓存，大文本放到后台识别。
- 新增 3 条文案，15 种语言为人工翻译。正式版 Xcode 27.1 模拟器：1178 项 XCTest（5 项跳过、0 失败）与 100 项 Swift Testing 全部通过；本地化提取 1034/1034 通过。
- 已用正式版 Xcode 27.1 覆盖安装并启动连接的 iPhone，保留数据，版本仍为 1.0.21（59）；未推送、未发布。批量测速观感、剪贴板与键盘表现待用户真机验收，操作步骤见各计划的 Feel check。

## 未发布：Clash 系 MASQUE 节点内 DNS（2026-09-27）

- Clash、Clash Mi、Clash Verge、ClashMac、FlClash、Mihomo Party 的密钥 CONNECT-IP 节点缺省输出 remote-dns-resolve: true 与 dns: [1.1.1.1, 8.8.8.8]。完整配置和仅节点共用节点生成器；不修改全局 DNS、规则、策略组，不依赖任何固定组名。
- 增加可选 remoteDNSResolve 存储字段及 Clash YAML 解析/校验，保留用户显式 false 和自定义 DNS；旧数据缺省 nil 兼容。编辑、编码、导入再导出保留设置。Shadowrocket 不自动启用新默认值；Stash 生成分支包含相同默认逻辑，但仍由能力和生成器门禁拒绝 MASQUE，暂不声明支持。Surge/sing-box 不套用此设置。
- 全量 1177 项 XCTest（5 跳过、0 失败）及 100 项 Swift Testing 通过；新增六目标完整/仅节点字段往返、显式关闭与自定义 DNS、持久化/编辑、非法布尔值、Stash 仍禁用和 Shadowrocket 无默认项回归。
- 临时真实文件用例读取用户节点，实际生成六个目标完整配置；临时用例已移除。六份配置均经 Mihomo 1.19.27 语法检查，并在隔离 SOCKS、固定 MATCH 到测试节点的运行验证中访问 YouTube 返回 200。全局 DNS 未替换；不能将同一内核验证称为六个图形客户端逐个验收。
- 正式 Xcode 已覆盖安装并启动连接的实体 iPhone，保留数据。未新增界面文案，版本仍为 1.0.21（59），未推送发布。git diff --check 通过。

## MASQUE 与其他协议 DNS 对照实测（2026-09-27）

- 同一 Mihomo 1.19.27、原 VPS 既有服务、固定物理出口、仅回环 SOCKS 入口，以域名交给代理（socks5h）访问 YouTube / example.com / 公网 IP HTTPS。用 MATCH 固定测试节点，隔离分流规则差异；未修改服务端、系统代理或 VPN。
- 覆盖 MASQUE CONNECT-IP、Snell（Mihomo v4 对接服务器 v5）、Shadowsocks、VMess TCP、Trojan TLS、VLESS WS TLS、AnyTLS，以及 MASQUE 节点级 remote-dns-resolve 变体。
- 分别使用用户原配置 DNS 与刻意不可用的客户端 DNS，逐个重启内核排除进程 DNS 缓存。两轮共 48 次请求，4 次失败均为原 MASQUE 的两个域名；所有节点公网 IP HTTPS 均成功。Snell 等六种域名代理及 MASQUE 节点 DNS 变体，两个域名均 HTTP 200。
- 日志确认原 MASQUE 错误为 dns resolve failed；验证差异是该 CONNECT-IP 路径需客户端获得目标 IP，而其他测试 TCP 代理可直接传域名给服务器。不是所有 MASQUE 变体的普遍结论，也不表示其他协议不会遇到 DNS 故障；节点服务器域名解析、IP 规则或其他 UDP/直连路径仍可能依赖客户端 DNS。本轮未测试 WireGuard、TUIC、Hysteria。
- 私密脚本配置与原始日志保存在忽略目录 .artifacts/masque-dns-matrix，测试内核已全部停止。本轮仅诊断，未修改 App 代码。

## MASQUE 用户原始导出 DNS 对照（2026-09-27）

- 用户提供实际 Clash / ACL4SSR 配置。隔离 Mihomo 1.19.27 保留全部分组规则测试：YouTube 正确匹配国外媒体，但 DNS 解析失败；百度、哔哩哔哩直连成功，Apple 代理成功，gstatic 测速 204。尚未复现手机国内网站也失败。
- 只对 nameserver 与 fallback 的 DoH URL 指定现有节点选择组，保留 proxy-server-nameserver 直连以避免解析代理服务器时循环依赖；节点、全部策略组与 ACL4SSR 规则保持原样。YouTube、百度、哔哩哔哩、Apple 返回 200，测速 204；日志确认国内仍 DIRECT、YouTube 仍国外媒体。
- 私密修正版仅放 Downloads，未修改用户原文件。等待 clash.md 手机使用该原方案修正版验证；尚未更改 App 的通用 DNS 生成策略，不能将个别测试节点名硬编码到产品。

## MASQUE Clash 无法上网诊断（2026-09-27）

- 用户反馈 clash.md 最新版测速成功但无法上网。用 Mihomo 1.19.27、同一测试节点、隔离的本地 SOCKS 入口复查；保留之前塔台生成配置的 DNS 段，强制 MATCH 到测试节点，以排除分组选择差异，未修改系统 VPN/代理。
- 公网 IP HTTPS 成功，Apple 返回 200，gstatic 测速地址返回 204；Google、YouTube、Cloudflare、example.com 失败，日志显示直连的 DoH fallback 超时。最小无 DNS 配置还受到本机已有 VPN 的系统 DNS 地址影响，不能把它当成手机根因。
- 单项对照：保持节点及 DNS 服务列表不变，仅给 DNS 上游加测试代理指定。五个域名 HTTPS 均返回 200。由此确认本机测试的 DNS 出口路径问题，不能据此断言用户 clash.md 中的完整配置也相同。
- 已生成本机私密 Downloads/Tower-MASQUE-DNS-Test.yaml，移除本机 interface-name，供用户直接导入 Clash 对照；测试配置强制所有流量走测试节点，不是生产分流方案。待对照结果或实际导出配置与失败日志后再确定产品修复，未盲改全局 DNS 策略。

## 未发布：MASQUE Clash 入口与 Stash 调整（2026-09-26）

- 按用户反馈暂停 Stash 的 MASQUE 导出，能力列表与生成器均拒绝；保留节点导入与已有数据。以下旧记录的 Stash 放行状态由本节覆盖。
- 名称为 Clash 的独立入口（clashApple）此前未放行，本轮加入密钥 CONNECT-IP 完整配置与仅节点导出名单，供用户验证实际客户端内核。Mihomo 内核实测不能替代该图形客户端验收。
- 导入仍自动识别 Surge、Clash YAML 和 sing-box JSON，保留认证与隧道变体；不能将密钥/密码或 CONNECT-IP/CONNECT-UDP 强制互换。
- 全量 TowerTests 通过：1176 项 XCTest（5 跳过、0 失败）与 100 项 Swift Testing。客户端矩阵覆盖 Clash 放行和 Stash 跳过，git diff --check 通过。正式 Xcode 已覆盖安装并启动连接的 iPhone，版本仍为 1.0.21（59）。

## 未发布：MASQUE 客户端补齐与手机测试文件（2026-09-26）

- 在下方既有方言边界上补充 Shadowrocket 密钥式 CONNECT-IP 的完整配置和仅节点导出；含该类型时仅节点输出 Clash YAML，混合普通节点仍保留，不能包进普通 URI Base64。依据 Sub-Store 04f44c2 的 Shadowrocket producer，实际手机客户端连接仍待用户测试。
- Surge / Surge Mac 使用 Basic CONNECT/CONNECT-UDP；Stash、Shadowrocket 和已放行的 Mihomo 客户端使用密钥 CONNECT-IP；sing-box 1.15 使用 Basic masque-client endpoint。三类分别导入，不能互相强转；Hiddify、Karing、Hako 等未确认目标仍不放行。
- 全量 1176 项 XCTest（5 跳过、0 失败）及 100 项 Swift Testing 通过。三个私密测试文件另经临时真实文件用例验证可导入且对应目标可生成，临时用例已移除。无新文案、无版本变更、无发布。
- 之前的 VPS 新增独立 CONNECT-IP 测试服务，七天自动停止；仅为测试子网添加 NAT，启用 IPv4 转发，服务结束清理本次规则并恢复原转发值。静态密钥地址与 Basic 动态地址分开。Mihomo 1.19.27、sing-box 1.15.0-alpha.8 的公网 HTTPS 和 UDP DNS 均通过；本机 SOCKS 测试没有修改系统代理。
- Surge 方言探测器重验：HTTP/3 握手、TCP CONNECT、UDP DNS 均通过；首次 UDP 超时，延长单阶段超时重测通过，不宣称手机客户端连接已验收。
- 三份用户测试文件存于本机 Downloads/Tower-MASQUE-Tests，含私密测试凭据，不提交仓库。手机正式 Xcode 覆盖安装并启动成功，仍为 1.0.21（59），保留数据。外部手机客户端实际导入与连接待用户验收。

## 未发布：Mihomo / sing-box MASQUE CONNECT-IP（2026-09-26）

- 在既有 Surge Basic CONNECT/CONNECT-UDP 之外，新增显式的密钥 CONNECT-IP 与 Basic CONNECT-IP 数据类型，保存、去重、手动编辑已有节点和分享往返保留各自参数；旧快照继续兼容。手动新建表单仍创建 Surge 变体，新增两种通过结构化配置导入。
- Clash YAML 导入密钥式 MASQUE，支持 P-256 DER 私钥/公钥、IPv4/IPv6 隧道地址、SNI、UDP、MTU、DNS 与 QUIC/H2。为 Clash Verge、ClashMac、FlClash、Mihomo Party、Clash Mi 生成 Mihomo 写法，Stash 使用 h3/h2 写法。完整配置和仅节点路径均覆盖。需要客户端内核实际支持 MASQUE，未逐个图形客户端验收。
- sing-box 支持单个 masque-client JSON、数组及配置 endpoints 中的 Basic CONNECT-IP；按 endpoint 输出并供策略组引用，不能放入 outbounds。保留用户名/密码、路径、HTTP 版本、版本回退设置、请求头、TLS/CA、SNI、ALPN 和 MTU；使用内部网络栈。要求 sing-box 1.15，目前验证版本为 1.15.0-alpha.8，稳定版 1.14.2 不支持；Hiddify、Karing、Hako 未据此放行。sing-box 原有仅完整配置的产品边界保持不变。
- 不跨认证/隧道方言强转；代理链、系统网卡、广告路由及尚未建模的参数拒绝计数。不是通用 sing-box 全配置导入，其他未支持的真实端点/出站记录计入跳过。
- Mihomo 1.19.27 与 sing-box 1.15.0-alpha.8 均通过塔台生成的完整配置检查；sing-box 有既有 TUN stack 弃用警告。使用独立测试实例、仅本地 SOCKS 监听和 en0 出口，分别通过隧道内 TCP HTTP 页面与 UDP 回显测试；没有把语法检查当作手机连接验收，也未以此宣称公网出口测试完成。
- 测试服务器的 Basic 认证需要 Proxy-Authorization，sing-box 的该 HTTP/3 路径首次返回认证错误；在测试输入显式添加该请求头后连接通过，塔台仅保留输入，不全局注入认证头。两个测试客户端需独立运行以避免测试服务的分配地址碰撞。
- 验证：1175 项 XCTest（5 跳过、0 失败）与 100 项 Swift Testing 通过；包含全部目标客户端边界、预设/规则方案两条生成路径、保存/编辑/分享往返及非法/未知参数拒绝。git diff --check 通过。未新增界面文案、未更改版本、未发布。
- 正式 Xcode 已覆盖安装到连接的实体 iPhone，保留数据，版本仍为 1.0.21（59）。首次启动及重试被系统 Locked 拒绝；最后补充 Surge 布尔值校验、7 项 MASQUE 定向回归通过后，再次覆盖安装并启动成功。手机代理客户端实际导入/连接仍待用户验收。
- 临时 CONNECT-IP、HTTP、UDP 测试服务及本地内核已停止；未修改服务器全局转发或 NAT。
- 官方依据：https://wiki.metacubex.one/config/proxies/masque/ 、https://stash.wiki/en/proxy-protocols/proxy-types 、https://sing-box.sagernet.org/configuration/endpoint/masque-client/ 。

## 未发布：MASQUE HTTP Basic / Surge（2026-09-25）

- 新增 MASQUE 节点类型、手动添加、Surge 单行/[Proxy] 配置导入、节点分享、完整配置和仅节点导出；保留用户名、密码、SNI、ALPN、证书 SHA-256 pin 及证书校验设置。
- 本轮仅启用 Surge iOS 5.22.0+ / Mac 6.9.0+ 的 HTTP/3 CONNECT + CONNECT-UDP / HTTP Basic 变体。Mihomo/WARP 的密钥式 CONNECT-IP 不是同一配置，其他导出目标仍跳过并计数，能力覆盖参数也不能强行放行。
- 未建模的端口跳跃、代理链、客户端证书、独立证书校验名等输入拒绝；包含 INI 分隔符的凭据暂不导入，不静默删字段。后续应按真实样例逐项扩展，不要以协议同名直接跨客户端转换。
- 新增解析/存储/手动编辑/分享往返、证书 pin、全部客户端完整及仅节点边界、非法输入回归；既有所有协议符号断言同步增加 MASQUE。
- 独立测试实例使用 masque-server v0.13.0，发布归档 SHA-256 已核对；只启用 HTTP Basic 的 TCP/UDP，不创建 TUN、不改现有服务。实例设置 7 天自动停止，私密配置与凭据不进入仓库。
- 本机 masque-probe 实测 HTTP/3/TLS/ALPN、TCP CONNECT 请求和 UDP DNS 应答均通过。初次经当前系统代理路径遭连接拒绝，绑定物理网卡后通过；服务端本地探测也通过。本机 Surge 6.4.4 低于要求，未声称 Surge 客户端连接已验收，手机由用户测试。
- 已尝试执行正式 Xcode 的真机安装脚本；Xcode 当前没有可用实体 iPhone，CoreDevice 唯一 connected 的 iPhone 是模拟设备，安装未进行。连接并解锁实体 iPhone 后运行 `Scripts/install_device.zsh`。
- 验证：1171 项 XCTest（5 项跳过、0 失败）及 100 项 Swift Testing 通过；本地化提取 1031 项全部覆盖。
- 官方依据：https://manual.nssurge.com/policies/masque.html 、https://manual.nssurge.com/policies/tls.html 、https://wiki.metacubex.one/config/proxies/masque/ 。


## 未发布：Shadowrocket VMess JSON 批量导入（2026-09-25）

- 用户提供混合备份文件，本地临时用例实际读取验证：160 条中导入 3 个 VMess、跳过 157 条；113 个 SS+ShadowTLS、34 个 VLESS（带 publicKey、tlsProfile、xtls）、7 条 Subscribe 尚未适配此 JSON 方言，另 3 个 SS 条目缺少密码和加密方式。原文件不复制进仓库，临时绝对路径用例已移除。仅验证现状，未增加这些协议适配。

- 用户回传原生 JSON 格式后，先复现无法识别，再补单个对象、数组和空白分隔的连续对象导入；剪贴板检测共用解析入口。host 为服务器、obfsParam 为 WS Host、password 为协议 UUID，不能使用 Shadowrocket 记录 uuid。
- 支持普通和 JSON 形式的 WS Host，保留 TLS/SNI/路径/alterId/UDP，处理转义斜杠。带无法表示的证书、链路及自定义 TLS 参数或其他协议 JSON 计入跳过，不宣称通用 JSON 导入。
- 验证三节点批量、单行单节点检测、数组、保存读取、字符串大括号/引号、畸形 JSON 和不支持记录统计。全量 XCTest 1168 项（5 跳过、0 失败）及 Swift Testing 100 项通过；最后路径兼容补充后 LegacyVMessTests 16 项通过。已覆盖安装并启动连接的 iPhone 1.0.21（59），保留数据；实际剪贴板粘贴交互待用户确认，未发布。

## 未发布：VMess WebSocket Host 与手动证书指纹（2026-09-25）

- 用户回传 Shadowrocket 分享的三个虚构 VMess WS+TLS 样例：obfsParam 均为普通域名。实际批量导入、保存读取、再次分享解析均通过，LegacyVMessTests 14 项通过；这些样例没有 JSON Host，不能单独证实原邮件 JSON 变体的来源。此次仅增加回归测试，未改 App 代码、未重复安装。

- 用虚构节点复现旧式 VMess URI 的 JSON obfsParam 被原样当成 Host 保存；WebSocket 分支复用已有 VLESS Host 解包器，支持普通域名、JSON Host 及嵌套 headers。未取得反馈者原始片段，不宣称所有来源格式均已验证。
- 手动 TLS 节点增加可选证书 SHA-256 指纹，编辑已导入节点时保留指纹；校验 64 个十六进制字符，允许冒号/短横线，非 TLS/REALITY 不带入。这里是证书指纹，不是 PEM 正文或公钥 pin，不混用客户端指纹。
- 回归先复现 Host 保存异常及手动编辑丢指纹，再验证批量导入/JSON 编解码、指纹校验和已有导出用例。正式版 Xcode 27.1：XCTest 1165 项（5 跳过、0 失败），Swift Testing 100 项通过；本地化提取 1031/1031 通过。已覆盖安装并启动连接的 iPhone，仍为 1.0.21（59），保留数据；Shadowrocket 批量复制往返与界面体验待真机确认。未推送发布。

## 未发布：搜索时保留导航栏内容（2026-09-25）

- 用户授权接入隔离验证中的方案。管理页使用系统 searchPresentationToolbarBehavior(.avoidHidingContent)，搜索时保留导航内容，避免取消搜索同时恢复隐藏导航栏。保留默认下拉搜索、List 及原 safeAreaInset 操作栏；iOS 17.0 保留系统默认行为，17.1 起使用此 API。
- TowerInteraction 2 项通过：空搜索连续三次取消并断言搜索时管理标题仍存在；有结果/无结果/再次搜索取消后节点、操作和键盘状态恢复。完成模拟器录屏检查；功能断言不等于真机动画验收。正式版 Xcode 27.1 真机构建、覆盖安装和启动成功，版本 1.0.21（59），数据保留。git diff --check 通过；动画观感待用户真机确认。

## 已撤回：管理页取消空搜索跳动（2026-09-24 晚）

- 2026-09-25 隔离验证：仅系统 List + 两段 Picker + 静态 30 行 + searchable 的临时页面（无 AppModel、底部操作栏或自定义动画）仍能录屏观察到取消时列表先下移再回弹。范围缩小到系统搜索/导航栏与列表布局协作，尚不能断言 Apple 内部具体根因。avoidHidingContent 对照会改变搜索时导航栏表现，未采纳为正式修复。实验页面及入口已移除，手机保持已安装并启动的回退版 1.0.21（59），原问题未解决。
- 2026-09-25 用户真机反馈仍不正确，已撤回操作栏移出 List 的改动。此前将 safeAreaInset 认定为根因的结论证据不足，不再作为已定位原因；重新隔离验证。
- 新增订阅管理空搜索连续取消用例，录屏复现取消时分段按钮及列表先下移再回弹；此前只验证结果恢复的用例不足以证明动画正常。
- 保留 searchable 默认下拉搜索和全部操作栏内容，将底部操作栏从 List.safeAreaInset 移到同级 VStack，避免键盘与搜索导航栏恢复时重复调整列表滚动几何；不使用上次已撤回的固定搜索栏或隐藏操作栏方案。修改前后模拟器录屏对照未再观察到原明显回弹，真机观感仍待用户确认。
- 正式版 Xcode 27.1，TowerInteraction 空搜索三次取消、导出筛选有结果/无结果/再次搜索取消共 2 项通过；git diff --check 通过。真机构建及覆盖安装成功，首次自动启动失败后单独重试启动成功，数据保留，版本 1.0.21（59）。未推送发布。

## 已撤回：批量管理搜索动画调整（2026-09-24）

- 用户真机确认原动画问题仍在，并新增进入页面搜索框背景短暂缺失、布局变化。已按要求撤回本轮固定搜索栏、搜索期间隐藏操作栏、移动禁用动画范围三项改动，恢复此前页面布局；保留名称筛选及此前其他修改。
- 回退后正式版 Xcode 真机构建通过，已覆盖安装并启动 iPhone 1.0.21（59），保留数据；git diff --check 通过。
- 原搜索取消动画问题仍待定位。此前 UI 用例通过只证明搜索结果及键盘状态恢复，不能作为动画观感通过的证据。

## 未发布：持续节点名称筛选（2026-09-24）

- 名称入口改成与国家/协议一致的 48pt 最小高度，状态移至右侧。导出名称编辑器只提供包含/不包含关键词，移除大小写开关，常规关键词忽略大小写；旧大小写敏感及高级匹配保留为正则。新增排除关键词的字面匹配、多关键词、大小写、换行名称及往返保存回归：NodeNameFilterTests + NodeSelectionTests 21 项通过；本地化提取检查通过。已覆盖安装并启动 iPhone 1.0.21（59），视觉交互待用户确认。
- 再次真机反馈后：名称筛选弹窗从多个 Section 的 Group 移到稳定的外层 List，避免列表重建影响展示；名称图标统一为 primary。节点选择缓存改为输入属性变更时失效，避免每行读取时重复比较整份集合。正式版 Xcode 真机构建、覆盖安装及启动成功，仍为 1.0.21（59）；git diff --check 通过。本轮定向模拟器测试未返回结果，已中止，不宣称回归通过；流畅度及弹窗表现待真机验收。
- 真机反馈后：入口关键词摘要移至右侧横向排列，增加上下内边距；删除全部关键词后允许保存，空白条件规范为无筛选并持久化，保留手动排除。NodeSelectionTests 6 项通过；UI 用例增加删除最后关键词再保存步骤。
- 订阅管理 → 导出筛选增加「节点名称」入口，复用关键词/正则编辑器与异步匹配预览。保存后显示条件摘要；名称不匹配的节点标明原因，清除条件保留手动排除。
- 名称条件保存至可选快照字段，并接入共用 enabledNodes 和配置请求缓存；订阅刷新新增节点自动匹配，完整配置、仅节点和局域网生成共用该结果。由目标客户端自行获取的远程代理集合不受本地筛选影响，界面明确说明。
- 正式版 Xcode 27.1 完整 TowerTests：1256 通过、5 跳过、0 失败；最后补充全客户端各支持导出模式、清除后保留手动排除断言后，NodeSelectionTests 6 项通过。本地化提取 1027/1027 通过。新增 UI 用例覆盖保存、重启和清除，但本轮模拟器停在主屏幕，测试未完成，不作为界面验收；2026-09-24 已用正式版 Xcode 27.1 覆盖安装并启动连接的 iPhone 1.0.21（59），保留数据；界面效果待用户验收。未推送或发布。

## 未发布：地区与协议筛选连续多选（2026-09-23）

- 国家地区与协议菜单均设置 menuActionDismissBehavior(.disabled)，逐项勾选或操作「全部」后保持展开；各自的「完成」操作关闭菜单，仍可点击菜单外关闭。节点排除、计数与持久化逻辑保持不变。
- 地区筛选此前已通过正式版 Xcode 真机构建及本地化检查（1019/1019），已覆盖安装并启动 iPhone 1.0.21（59）。本次协议筛选变更通过 Xcode 27.1 模拟器构建、本地化检查（1019/1019）及 git diff --check；2026-09-23 已用正式版 Xcode 27.1 覆盖安装并启动连接的 iPhone，保持 1.0.21（59）。连续多选的实际点击效果待用户验收；未推送或发布。

## 未发布：局域网格式菜单图标圆角（2026-09-19）

- 原生菜单提取图片时会丢弃 SwiftUI 外层 clipShape；为菜单预渲染并缓存带透明圆角的客户端图片，保持 20pt 尺寸、原色与原生选择交互。普通页面图标保持原样。
- 正式版 Xcode 模拟器构建通过；已明确选择连接的实体 iPhone，覆盖安装并启动 1.0.21（59），保留用户数据。菜单视觉效果待用户确认。未推送、未发布。

## 1.0.21（59）本机正式发布（2026-09-18）

- 用户确认 M4 已升级正式版系统，改用本机正式版 Xcode 27.0（27A266a）完成 Mac 通用归档、公证及 iOS TestFlight 上传。AGENTS、开发和发布文档已改为本机优先、M2 远程备用。
- 正式版工具链全量 TowerTests：1255 通过、5 跳过、0 失败；存在已有编译警告，不宣称零警告。源代码归档提交为 6044cf1。
- GitHub v1.0.21 已公开，附通用 DMG 与 SHA256SUMS.txt；公证取回、stapler、严格签名、Gatekeeper 及 DMG 挂载验证通过。DMG SHA-256：420cb665dacf2ac6e57bf0b8ff12f7c9891b60690c1e0280c8c4aa3b5bdff235。
- iOS 上传日志确认 Upload succeeded；App Store Connect 已显示 1.0.21（59）处理完成、准备提交，关联既有内部测试组。已填写简短测试说明；未提交外部 Beta 审核或 App Store 审核。
- Homebrew style / audit 均通过；本机 brew 升级至 1.0.21（59），安装后签名与 Gatekeeper 验证通过，tap 已更新。README 已指向新版 DMG。
- 远端 M2 流程已停止；本轮公开包及 iOS 上传均来自本机正式版 Xcode。


## 1.0.21（59）发布准备（2026-09-18）

- 汇总 ShadowTLS 导入、分享及各目标客户端导出；Karing 按用户连接失败反馈保持跳过。
- 版本更新后全量 TowerTests：1255 通过、5 跳过、0 失败；本地化检查及发布脚本测试通过。内置 ACL4SSR 最新，77 个远程产物校验通过。
- GitHub 通用 Mac 包及 TestFlight 交由正式版 Xcode 发布机制作；发布状态以随后记录为准。

## 当前结论：撤回 Karing ShadowTLS（2026-09-18）

- 用户真机反馈 Karing 无法连接，并要求暂不支持。撤回刚添加的能力放行；完整配置（预设及自定义方案）和仅节点均跳过 ShadowTLS，不降级为普通 SS。Karing 普通 SS 及其他客户端的 ShadowTLS 支持保留。
- 官方示例和生成器测试不足以证明客户端可用；失败根因未定位，不宣称是 Karing 本身不支持。重新开放需真实导入/连接验收。
- 增补 v1/v2/v3 在三种导出路径下的跳过、计数和普通 SS 对照回归。ShadowTLS 专项测试通过，git diff --check 通过。已覆盖安装并启动 iPhone 1.0.20（58）；未推送或发布。


## 已撤回的尝试：Karing ShadowTLS（2026-09-18）

- 根据 Karing 官方 Clash 示例开放 SS + ShadowTLS v1/v2/v3，完整配置（含自定义方案）及仅节点 YAML 均保留两层密码、SNI、版本与 client-fingerprint。跳过证书校验尚无明确依据，继续跳过该组合；不扩大到其他客户端。
- 全量 TowerTests 1255 通过、5 跳过、0 失败；覆盖所有目标能力矩阵及 Karing 三个版本的双模式、IPv6、指纹、独立密码、协议筛选和不兼容选项拒绝。git diff --check 通过。
- 已覆盖安装并启动 iPhone 上的 1.0.20（58），保留用户数据。Karing 手机导入和实际连接待用户验收；未提交、推送或发布。


## 未发布：ShadowTLS 仅节点订阅补齐（2026-09-18）

- Shadowrocket 含 ShadowTLS 的列表输出 proxies-only YAML；Hiddify 输出 outbounds-only JSON，以 §hide§ 隐藏辅助 TLS 通道。没有 ShadowTLS 的订阅继续使用原来的 URI 格式。保留版本、指纹、证书校验和 UDP 限制，不静默降级普通 SS。
- 用户此前已确认 Shadowrocket 完整配置连接可用；该结论不自动涵盖本次仅节点订阅，手机导入与连接待验。
- 全量 TowerTests：1254 通过、5 跳过、0 失败。覆盖混合列表、独立密码、SNI、辅助通道隐藏、规则缺席、协议排除和原有 URI 路径。
- 使用生成器实际导出的合成 Hiddify 节点文件通过 sing-box 1.14.0 check；这是配置校验，不是新路径实际连通验收。已覆盖安装并启动连接的 iPhone，版本保持 1.0.20（58）；未提交、推送或发布。


## 未发布：Shadowrocket ShadowTLS v3 完整配置（2026-09-17）

- 用户已确认 Loon/Egern 的手机导出连接可用；这是用户真机确认，不是此前单元测试或内核测试的推断。
- 按官方 v3 更新记录与 Sub-Store 的 SS YAML 输出，开放 Shadowrocket 完整配置的基础 ShadowTLS v3 组合：保留 plugin/plugin-opts、SS 密码、ShadowTLS 密码、SNI 和版本。自定义规则方案同样生效。仅节点 URI 独立待验，仍跳过并提示使用完整配置。
- 不扩大放行 v1/v2、显式 TLS 指纹及跳过证书校验；不将已有连接失败归因于客户端不支持，也不宣称新写法已连通。
- 全量 TowerTests 1253 通过、5 跳过、0 失败；包括 YAML 导出重解析、原始两层密码保留、自定义方案、URI 跳过及不可表达参数拒绝。git diff --check 通过。iPhone 已覆盖安装并启动 1.0.20（58），客户端导入/连接待用户测试；未发布或推送。

## 未发布：补充 Loon / Egern ShadowTLS 导出（2026-09-17）

- 对照官方文档及 Sub-Store 07d94ef 的 producer，独立补充 Loon v2/v3（完整配置及仅节点）和 Egern v3（完整配置）；SS 与 ShadowTLS 密码分开保留。未引入第三方转换器代码或在线转换服务。
- Loon ShadowTLS 密码为裸字段，保留原始百分号；会产生配置分隔歧义的字符拒绝输出并计入跳过。Egern 使用 shadow_tls.password/sni，版本不是 v3 时不导出。自定义 TLS 指纹、跳过 ShadowTLS 证书校验等未验证组合保持跳过。
- Sub-Store 存在 Loon、Egern、Surge、Mihomo、sing-box、Shadowrocket 相关处理；原版 Subconverter a0d4eab 的 src 未发现 ShadowTLS 实现。完整证据链接见 CLIENT-COMPATIBILITY.md；未将原版结论推广到社区 fork。
- 新测试在原实现下失败；修复后全量 TowerTests 1252 通过、5 跳过、0 失败，git diff --check 通过。实体 iPhone 已通过 Xcode 27.2 Beta 覆盖安装并成功启动，仍为 1.0.20（58），未推送/发布。Loon/Egern 手机导入和实际连接待用户验收，本轮未宣称通过内核连接实测。
- Shadowrocket 保留原有限制：官方及 Sub-Store 有支持记录，但用户这组配置连接失败未定位；本轮不扩大支持范围。未变更 Karing 等尚未验证的导出路径。

## 未发布：Shadowsocks + ShadowTLS（2026-09-17）

- 用户授权使用其订阅与本地内核验证。原订阅的 58 个节点均为 SS2022 + ShadowTLS v3，旧解析器因不支持插件而拒绝。已新增独立 Codable 参数，隔离两层密码、版本、SNI，纳入节点身份键；旧无插件节点身份不变。
- 导入 SIP003 URI、Clash YAML（缩进及行内 plugin-opts）、Surge SS ShadowTLS 参数；修正缩进插件字段污染外层密码，以及 Surge 标量重复百分号解码。分享保留插件、转义和显式客户端指纹。
- 导出支持 Stash、Mihomo 系列、Surge，以及 sing-box MT/Hiddify 完整配置。sing-box 使用内部 detour，辅助通道不进入策略组。不支持的目标/参数组合跳过，具体边界见 CLIENT-COMPATIBILITY.md；没有往 App 内引入代理内核。
- 原始 URI 和 YAML 均由实际解析/生成路径产生私有测试配置。Mihomo 1.19.29 校验 7 种 YAML 目标通过；sing-box 1.14.0 校验两种完整 JSON 通过；Surge Mac CLI 检查返回 OK。这不等同于 Stash、Hiddify 等图形客户端导入验收。
- 3 个实际节点：上游原配置、塔台 Mihomo 导出和 sing-box 导出各返回 3 次 HTTP 204；替换 ShadowTLS 密码后两个内核均失败。仅使用回环 SOCKS 入口，没有启用 TUN、修改系统代理或替换用户客户端配置；没有对全部 58 个节点逐一测速，也未验证 UDP。
- 全量 TowerTests 1250 通过、5 跳过、0 失败；最后补充指纹分享保留后，解析/分享/ShadowTLS 定向测试 33 通过、0 失败。手机已以 Xcode 27.2 Beta 构建并覆盖安装，自动启动被锁屏阻止，需解锁手动打开；版本仍为 1.0.20（58），未推送或发布。私有订阅、节点凭据和实际导出不入库。临时实订阅探针已移除，保留脱敏 ShadowTLSTests 回归。


## 排查中：手机版 YouTube 重加后当前规则未显示（2026-09-16）

- 用户报告手机显示添加成功，但“当前规则”没有 YouTube。尚未核实手机运行版本，以及关闭定制页再进入是否恢复。
- 1.0.20 源码下新增手机 UI 回归：文本导入含原生 YouTube 分组的规则方案，搜索、长按删除、从 ACL4SSR 目录重新添加，验证“已添加”及原分组无需重开立即出现。iPhone 17 / iOS 26.5 模拟器 TowerInteraction 定向测试 1 项通过。
- 该 UI 回归采用最小导入方案，不能替代用户已有 Self-Configuration 数据与真机验收。本轮没有修改生产逻辑、安装或发布，不宣称用户反馈已修复。

## 1.0.20（58）已发布 GitHub、已上传 TestFlight（2026-09-16）

- 源码35e2a8d已推送；GitHub v1.0.20已公开，含通用Mac DMG及SHA256SUMS。主要更新为导出页面与提示、Clash系列/Stash远程规则集、#33缺原文迁移及#36原有分组删除重加修复。
- iOS完整测试1240通过、5跳过、0失败；本地化1019条通过，ACL4SSR上游新鲜度及77个远程产物校验通过，发布脚本测试通过。新版预览已改为独立入口，原布局文本断言同步更新。
- M2正式Xcode归档通用Mac，Developer ID签名、公证、stapler、Gatekeeper通过；DMG挂载验证及GitHub公开下载回验通过。DMG SHA-256：52c36747e5a9ca5cceae09781e78037628ee73770fa025de6659c25af39b14c4。
- Homebrew更新至1.0.20（58）；实测发现旧版Homebrew将符号系统限制当成精确版本，已按主版本选择最低系统表达式。M2 style/audit及真实升级、安装后签名、公证与启动验证通过；本机Homebrew7 style/info通过。两版均保留macOS14及以上要求。
- iOS由M2正式Xcode归档并上传成功；App Store Connect已显示1.0.20（58）处理完成、准备提交，关联内部test测试组。未提交外部Beta审核，未发布App Store；未把上传等同于外部测试员可用。本轮未安装手机。

## 未发布：Issue #36 原方案分组删除后重加（2026-09-16）

- 规则目录复用原方案已有分组时，`generatedPolicyGroup` 为空；旧 upsert 只为新建分组清除删除标记，造成目录已勾选但有效方案仍隐藏分组。用户已确认原方案自带 YouTube 的删除/重加路径可复现。
- upsert 对目录条目同时使用其 policyName 恢复目标分组，清理目标原名及当前可见名的删除标记；不清空其他分组的删除状态。保留普通自定义规则原有行为。
- 增补原方案已有分组的下载/删除/重加、规则合并、重复添加不重复创建回归；扩展后来新建分组的删除/重加对照。模拟器 RuleCatalogTests、RuleCustomizationTests、Issue33ReproductionTests 共104项通过，0失败；未进行本轮真机UI验收、安装或发布。
- Homebrew两条弃用警告为既有修复回退：tap提交 b384239 修正过，随后 a4b65d2 发布1.0.19时恢复了 verified 和字符串形式 depends_on。已以 tap 提交 de766a4 恢复新写法并推送；brew style 与 brew info 通过且无这两条弃用警告。后续在 M2 运行 audit 发现旧版 Homebrew 5.1.5 仍要求跨域 verified；以 tap 提交76b610b将 homepage 改为官方 GitHub 仓库后，M2 style/audit 均通过，本机 Homebrew 7 style/info 无弃用警告。版本、下载地址、SHA-256不变；未重新安装。

## 未发布：Issue #33 缺原文旧方案迁移补修（2026-09-16）

- 将无绑定 Clash `use` 占位引用的清理从原文重解析条件中独立出来。旧方案的 `rawConfigurationText` 缺失、为空或不可解析时，也会修复；保留真实 `tower-source-bindings` 和明确 `tower-source-tags`，不扩大有效的来源限制。
- 不删除或重新下载方案；缺原文路径保留现有分组、规则、摘要与用户独立覆盖。已有 AppModel 快照加载入口自动调用迁移，重复迁移保持幂等。
- 回归测试先在修复前失败，再验证通过：旧方案 JSON 保存/读取、三种缺原文情况、全部 ClientTarget 的导出对照、真实来源绑定/标签保护。iOS 模拟器 Issue33ReproductionTests 与 RuleSchemeTests 共 40 项通过，0 失败；git diff --check 通过。
- 本轮只修改源码与测试，未安装、提交、推送或发布。尚未取得原报告者的旧方案数据，因此这是已复现迁移遗漏的修复，不等同于其真机复测确认。

## 未发布：导出页面合并与简化（2026-09-15）

- Mac 协议筛选弹窗过渡：仅手机使用中/大分段高度和可见拖动指示器；Mac 保留原模态弹窗，隐藏拖动条并使用可随窗口扩展的最小内容尺寸，避免把手机底部面板的控制带到桌面。未采用浮窗方案，未改变协议选择和生成逻辑。iOS 编译通过；最终 Mac 通用 Developer ID 包签名、公证、Gatekeeper 通过，已覆盖安装并启动，保留用户数据及协议选择。实际打开/关闭后窗口尺寸、内容和返回主页面正常；自动截图未捕获父窗口完整逐帧过渡，用户报告的瞬态横杠效果仍需其目视复核。包含上一轮状态头闪烁修正，版本仍为1.0.19（57），未发布。

- 2026-09-16 状态头闪动跟进：移除超过250ms就把已完成标题/对号替换成加载标题/转圈的计时任务；生成下一份配置时保留上次完成状态，当前请求完成后无动画更新，图标使用固定尺寸的同一视图。临时进入局域网目标不再清空已完成结果；旧结果仍不可预览/导出。iOS模拟器27项导出展示/缓存隔离测试通过，Surge切Stash后标题AX身份保持不变；实体iPhone已构建、覆盖安装、启动，未再次安装Mac。真机实际切换观感待用户确认。

- 2026-09-16 Mac 安装跟进：将当前未提交源码快照在正式 Xcode 发布机私有构建为 1.0.19（57）通用 Mac 包，Developer ID 签名、Apple 公证、stapler 与 Gatekeeper 均通过；覆盖安装至 `/Applications/塔台.app`，二进制核对一致并启动，新合并导出界面已确认。37 个旧安装/测试/解包副本移入本机废纸篓并注销原启动入口，未清理用户订阅、规则或 iCloud 数据；未发布 GitHub 或 TestFlight。

- 用户试用后撤回结果区双方块：已跳过/兼容性提示恢复为淡色文字折叠行，移除警告图标、方块背景和高亮边框；保留跳过节点和诊断详情，零项行隐藏。
- 结果区试版：已跳过与兼容性提示改为两个并列可展开方块，共用下方详情区，大辅助字号下纵向排列；零项方块不可展开，两项均为零时不占空间。生成结果增加跳过节点名称、协议和原因，复用实际输出的节点身份核对，排除由远程代理集合接管的节点，配置改名保留明细；原有筛选/导出行为未改变。两项回归验证协议过滤、证书pin、远程节点及改名保留通过；1019条本地化检查通过；模拟器sing-box筛掉SS后实际点测显示节点名和过滤原因，截图`.artifacts/export-redesign/result-tiles.png`。真机构建、覆盖安装、启动完成，未发布。
- 可读性迭代：规则方案、协议筛选、高级选项增加统一蓝色SF Symbols；右侧当前值采用主文字色。兼容性提示改独立展开区域，显示条数，每条左对齐、序号、行距和分隔线，支持选择复制；切换目标重置为收起。模拟器sing-box MT五条实际诊断已展开检查，长规则换行与对齐正常；真机覆盖安装及启动完成。
- 继续修正状态头闪动与高级选项：只读缓存命中直接展示当前配置，未命中的短更新延迟250ms显示忙碌状态，生成仍立即进行且导出须匹配当前请求；解除整表禁用动画，只对目标/生成变化取消动画，高级选项独立使用0.28秒无回弹弹簧及旋转箭头，外层改普通VStack以减少收起时的惰性布局重算。说明删去不支持客户端列表。1012条本地化、真机/模拟器构建通过；缓存模式隔离定向测试通过，模拟器展开收起前后卡片标题位置一致。手机已覆盖安装并启动，真实数据下滚动到底再收起的体感仍待用户确认。
- 切换闪烁修正：移除结果区域绑定目标和生成请求的双重淡入，隔离父层隐式动画；生成期间保留结果布局为不可操作占位，状态头持续存在并显示正在转换，避免先折叠再展开。旧结果不可预览或导出；移除规则方案/协议筛选右箭头，增加代理集合说明。1011条本地化与模拟器/真机编译通过；Stash及仅节点切换结果已点测，手机覆盖安装和启动成功。动画体感仍需用户在其实际数据下确认。
- 2026-09-16 按用户偏好恢复合并卡片内的“转换已就绪”标题和右侧绿色 checkmark.seal.fill，随后按用户要求移到合并卡片最顶部、导出模式上方，状态标题与右侧图标对齐，底部留18pt间距；仅有可导出节点或代理集合时显示成功状态，空结果继续显示无法导出提示。复用现有本地化文案。
- 后续真机反馈修正：高级选项改为独立展开按钮与完整宽度的开关区域，避免 DisclosureGroup 内容裁切；仅完整配置显示高级选项，生成器原有逻辑已限制代理集合仅用于完整配置。增加内容底部余量和操作栏间距。1010条本地化检查及iOS构建通过；模拟器Stash完整配置两个开关完整显示，仅节点隐藏高级选项已点测。已覆盖安装手机；启动被设备锁屏阻止，需解锁后手动打开。
- 保留客户端选择，将完整配置/仅节点、规则方案、协议筛选、导出选项、结果摘要与配置预览合并为一张卡片。协议开关放到独立 sheet，优先规则集与代理集合放在可展开选项中；去掉大型成功徽章、零跳过统计和重复说明卡片。警告和跳过原因继续可见；仅节点模式隐藏规则方案和规则数量。
- 切换目标或筛选后，等待当前请求生成完成才显示摘要与预览，避免短暂呈现上一个目标配置。底部主操作与实际导入方式保持原语义。
- 新增四条文案覆盖15种语言，本地化检查1008条通过。Mac Catalyst 定向 LocalizationTests 与 ExtendedMatchingRuleSetTests 通过，iOS 模拟器及真机编译通过；模拟器原生点测确认协议全部关闭时禁用导出、重新开启恢复、预览打开、仅节点模式与展开选项。浅色与深色常规字号已截图检查。UI自动测试运行器未完成，不记为通过；极大辅助字号下原有客户端横栏和底部标题仍有截断，尚未完成该字号的整页验收。
- 新版已覆盖安装并启动实体 iPhone，保留数据，版本仍为1.0.19（57）。Mac仅完成构建和定向测试，未替换已安装的公证版；未推送或发布。截图位于本机 `.artifacts/export-redesign/`。

## 未发布：Stash 远程 AI 规则集测试支持（2026-09-15）

- 按用户要求，Stash 目标也允许带合法 extended-matching 的域名列表保留为 classical text/YAML 远程引用。新增到同一组导出与非法参数保护回归，修复前测试失败；修复后规则集定向回归通过。全量1201通过、35跳过、3项本机HTTP服务启动失败，单独复跑仍失败；发现本机Surge连接占用65172端口，未干预用户代理，未将全量标为通过。此Stash补修尚未安装。
- 此变更仅证明塔台保留原 URL 与 RULE-SET；Stash 对该特殊参数的实际处理由用户继续实测，不宣称 Surge 扩展匹配语义已验证。不改变既有 MRS 加内联补充规则的优化策略。

## 未发布：Issue #30 Mihomo 系列远程 AI 规则集补修（2026-09-15）

- 用户确认 1.0.19 Surge 已恢复远程引用，但 Clash Verge 仍展开。本次覆盖 Clash、Clash Verge、ClashMac、FlClash、Mihomo Party、Clash Mi 六个 Mihomo YAML 目标；开启优先规则集时，带合法 extended-matching 的域名列表保留原 URL 与 RULE-SET。
- Mihomo 忽略该域名参数但保留普通域名匹配；不自动开启 sniffer，不宣称 Surge 扩展匹配语义等价。Stash、Karing 等未验证目标保持原限制；关闭优先规则集时的内联参数兼容问题仍待单独修复。
- 核心历史确认 text format 于 2023-04-14 的 e4926c83 加入，首个包含该功能的版本标签 v1.14.4。通用 Clash 导出按现代 Mihomo 能力定位，不能保证老 Clash 核心。
- 此前使用上游 AI.list 原始字节经本机 HTTP 服务测试 Mihomo 1.19.27，74 条规则加载成功，普通及四条带参数域名实际命中。未把核心测试宣称为每个 App 的 UI 验收。
- 六目标远程导出回归先失败后修复；Mac 完整 TowerTests 1204 通过、35 跳过、0 失败。修改后六目标真实生成配置均经 Mihomo 1.19.27 加载 74 条且五个测试域名命中（原字节本机 HTTP 控制源）。iPhone 自动签名构建完成，安装时设备未连接；Mac 正式发布机完成通用 Developer ID 签名和 Apple 公证；取回后验证签名、stapler、Gatekeeper，通过后覆盖安装至本机 /Applications/塔台.app，二进制与验证产物一致，启动进程确认成功。未知参数、策略字段、pre-matching、IP 规则误用参数等继续禁止直接引用。用户要求本机及真机覆盖安装测试，保留用户数据；未发布 GitHub 或 TestFlight。

## 1.0.19（57）已发布 GitHub 与 Mac 包（2026-09-15）

- 本版汇总下方 Anywhere、Issue #30、Issue #33、iCloud 多设备合并与备份去重改动。版本统一为 1.0.19（57）；用户可见更新日志见 `docs/RELEASE-NOTES-1.0.19-57.md`。Hiddify 导入与 dead10cc 崩溃仍未确认修复，不列为已解决。
- 用户仅要求推送源码并发布 GitHub / Mac 包；不上传 App Store Connect、不分发 TestFlight。
- 源码 `09b79be` 已推送，GitHub Release `v1.0.19` 已公开。正式发布机完成 Intel / Apple 芯片通用 Developer ID 公证包；签名、stapler、Gatekeeper、DMG 挂载及公开下载回验均通过。DMG SHA-256：`8246aa56577ae7b8a0f9de93c86e23f991d223ebdf6e366c82d7b14d07d719b9`。
- Homebrew tap 已更新至 1.0.19（57），补回下载来源 verified 声明与“Sonoma 及以上”的系统约束。发布机 style、audit 和真实升级验证通过，安装后的签名、公证及启动验证通过。M4 本机 audit 被另一份正式版 Xcode 版本诊断阻止，未更改全局 Xcode 配置；其 Homebrew Ruby json 依赖安装失败已修复。
- 发布审查补充修复：订阅刷新改名时，以来源隔离且跨快照唯一的完整连接身份保留节点 ID，避免取消勾选或重新勾选被旧 ID 丢弃。新增双向和歧义保护测试，11 项合并测试通过；独立复审通过。最终 Mac 全量 1203 通过、35 跳过、0 失败；iOS 全量 1230 通过、5 跳过、0 失败，随后补充修复的 iOS 11 项定向测试通过。本地化 1004 条及 77 个远程规则产物检查通过。

## 未发布：前台同步与恢复备份去重（2026-09-15）

- 启动任务和 scene 激活共用一次前台工作入口，在异步等待前占用本轮入口；只在进入 background 时重置，短暂 inactive 不重复检查。仍保留回到前台接收远端变化、编辑后 2 秒合并同步、手动立即同步。
- 同一次合并不会重复备份未变化的本地状态；本地备份写入按完整配置内容去重（忽略顶层 updatedAt），读取时清理已有重复文件，再应用 10 份上限。恢复列表跨当前、本地及云端历史去重，当前配置优先，其余按时间排序。云端合并所需的版本关系不因展示去重被删除。
- 重复内容占满备份名额的测试先失败；修复后 14 项定向测试通过，Mac 完整 TowerTests 1200 通过、35 跳过、0 失败。覆盖已有重复文件清理、前台重复调用、后台后接收远端修改、手动同步及恢复列表去重。测试使用隔离数据，不操作用户真实 iCloud。
- 用户要求重新安装后，已将本次同步去重修复版 1.0.18（56）覆盖安装到实体 iPhone 和 `/Applications/塔台.app`，保留现有数据，均留待用户手动打开。Mac 为正式版 Xcode 归档的 Intel / Apple 芯片通用 Developer ID 公证包，签名、stapler、Gatekeeper 与安装后二进制一致性验证通过。未提交或发布。

## 未发布：Issue #33 旧方案空分组修复与崩溃排查（2026-09-15）

- 已复现旧 Clash 规则模板迁移时重新引入 `use: all-proxies`，但持久化源文本已移除 proxy-providers，导致所有节点组变为空组并退化为 DIRECT/select。修复无 URL 哈希绑定的遗留占位来源，并覆盖已经完成错误迁移的历史方案；真正的订阅来源绑定、自定义成员、策略类型和规则顺序保留。
- 来源筛选抽取为生成器与异步名称预览共用的逻辑；预览按每条表达式的来源范围排除节点，不再只看正则。新增 370 节点、55 香港节点的三客户端对照，以及指定来源/排除条件的预览与导出一致性测试。
- Mac 完整回归 1146 项 XCTest（35 跳过、0 失败）及 85 项 Swift Testing 通过；最终保护性调整和新增测试后 16 项定向测试通过。iOS 模拟器 15 项定向测试通过；关键词/正则编辑、保存、重启恢复的 UI 回归通过。未以模拟器代替用户真实 TF 方案验收。
- TF Self-Configuration 应用组为空可能与此共因，但缺少反馈者的构建号和方案，尚未独立确认。无需删除用户方案即可在启动迁移时修复已识别的历史数据。
- Hiddify：监听 ready 后才打开客户端；旧的 onDisappear 停服问题早已修复。本次不修改导入方式，仍需即时/延迟导入、后台到期与 VPN 状态的真实跨 App 日志。
- macOS 27 的两份 dead10cc 日志仅能确认挂起持锁终止，未包含锁路径。核对实际 v1.0.15 未找到可确认的文件句柄泄漏，不把共享 URLSession 缓存或 iCloud 当作已确认根因；需受影响设备终止时间附近的系统诊断日志。第三份附件仍未取得。未将此项标为已修复。
- 用户要求安装后，包含本节修复及下方 10 份备份上限的 1.0.18（56）已覆盖安装到实体 iPhone 和本机 `/Applications/塔台.app`，保留现有数据，均留待用户手动打开测试。Mac 使用正式版 Xcode 归档的 Intel / Apple 芯片通用 Developer ID 公证包，签名、stapler、Gatekeeper 与安装后二进制一致性验证通过。未推送、发布或回复 GitHub issue。

## 未发布：同步备份上限 10 份（2026-09-15）

- 本地恢复备份与云端历史分别最多保留 10 份完整配置，写入新副本和读取恢复列表时清理超额旧配置；恢复页最多显示 10 条（含当前配置），其余按配置时间排序。
- 云端清理先原子写入 `.pruned` 版本关系标记，再删除旧 JSON 正文；标记仅含版本 ID 和父版本 ID，不含节点、订阅或规则。迟到的旧 JSON 不会覆盖清理标记；崩溃中断后下次清理继续删除正文。
- 保留当前并发分支；超过 10 个未解决分支时报告冲突，不为强行满足数量而丢弃尚未合并的用户数据。共同基线正文已被清理的迟到分支报告冲突，不退化为首次同步合并；仍在保留范围内的分支继续三方合并。
- 旧客户端不理解清理标记，可能提示历史尚未下载完成；参与同步的设备需更新。清理仅限制完整备份正文，少量版本关系元数据及旧格式迁移文件不计入 10 份。
- 4 项新增保留策略测试通过；Mac 全量 1143 项 XCTest（35 跳过、0 失败）及 85 项 Swift Testing 通过。测试使用隔离目录，不清理开发者真实 iCloud 文件。已随上方 #33 修复覆盖安装手机和 Mac，尚未发布。

## 2026-09-14 Anywhere 客户端（未发布）

- 增加 Anywhere 目标，手机默认排在 Clash 后面；旧顺序缺少此目标时插入，已有自定义位置保留。手机升级时显示新增目标，之后主动隐藏仍保持隐藏。
- 按上游 `NodePassProject/Anywhere@9ae49a73a0cf15317712545f9ead679da43cd308` 的订阅和 URI 解析器接入“仅节点”，输出逐行 URI，通过 `anywhere://add-proxy?link=` 和原有回环临时服务一键导入。URL 参数编码按源码实际的一次解码行为处理，不能只依据 README 的 verbatim 描述。
- 支持 Tower 已建模的 VLESS、Hysteria 2、Trojan、AnyTLS、Shadowsocks、SOCKS5。VLESS 可使用 TCP、WS、HTTP Upgrade、gRPC、XHTTP；Trojan 不输出 WS。AnyTLS 空闲会话参数映射为 ici / it / mis，gRPC Host 映射为 authority，保留 IPv6 方括号。
- 对该入口无法表达的证书 pin、逐节点跳过证书验证、SS UDP-off、SS plugin / native TLS、端口跳跃等计入跳过，不静默丢字段；不把 Naive 当作普通 HTTP，不声称支持完整策略组 / 规则配置。SS UDP-on 使用客户端本身的普通转发能力。
- 全量 TowerTests：1178 通过、34 跳过、0 失败；最终代码已覆盖安装并启动实体 iPhone 1.0.18（56），未提交或发布。iOS 模拟器导出页定向测试通过，已检查截图：Anywhere 图标、仅节点摘要、跳过计数及导入按钮正确。本地化 995 条通过；上游原始 DeepLinkManager 与 GRPCConfiguration 独立编译检查通过。客户端真实流量、IPv6 公网连接仍需 Anywhere 真机验收，不能把生成测试或安装塔台当作连接成功。

## 2026-09-14 Issue #30：Surge 远程规则集扩展匹配（未发布）

- AI.list 中含 `extended-matching` 时，旧的远程资源检查只接受无参数 / `no-resolve`，导致整份展开。该判断早于 1.0.18，不能将反馈时间直接当成引入版本。
- 调研与核心测试区分原样语法和嗅探功能：Surge 官方支持；Shadowrocket 2.2.80 原生 INI 导入将参数识别为扩展匹配开关，但 YAML/provider 路径尚未验收；Mihomo 1.19.27 对域名规则忽略此参数，HTTP Host 对照实验表明命中取决于独立 sniffer；sing-box 1.14.0 原生 JSON 拒绝该字段。其余客户端没有足够证据时标为未确认，未统一放行或删除参数。
- 仅修 Surge / Surge Mac 的远程判定，保持原资源 URL 和逐行内容，不向引用行增加全局参数。新回归先复现 8 处失败，修复后通过；Mac 全量 1123 项 XCTest（35 跳过、0 失败）及 85 项 Swift Testing 通过；iOS 26.5 模拟器 4 项定向回归通过。
- 用户要求安装后，发现实体 iPhone 与 iPad 同时在线，通用安装脚本因候选不唯一停止；依据 Xcode 实体设备清单明确选择 iPhone 后，修复版 1.0.18（56）已覆盖安装并成功启动。未推送、未发布、版本号未递增。详细矩阵、官方链接与实验日志位于本机 `.artifacts/issue30-extended-matching/`，不复制到 Release 更新日志。

## 1.0.18（56）源码与 Mac 发布（2026-09-13）

- 本版纳入下方 IPv6 分享链接 / SSR 解析、SS UDP 开关保留、Stash 证书指纹字段修复。导出页面布局尚未修改。更新日志见 `docs/RELEASE-NOTES-1.0.18-56.md`。
- 版本号和构建号统一为 1.0.18（56）。本次发布源码、GitHub 版本及 Mac 通用 DMG；TestFlight 由用户自行处理，不上传或分发。
- 内置 ACL4SSR 已是上游最新版本，77 个已发布远程产物验证通过；将更新脚本的默认固定版本同步为现有资源版本，防止默认更新回退。发布脚本测试、20 项规则脚本测试通过。
- 修复代码全量 Mac Catalyst XCTest 1119 项（34 跳过，0 失败），另 85 项 Swift Testing 通过。iOS 发布回归 XCTest 1119 项（4 跳过，0 失败），另 85 项 Swift Testing 通过。
- 1.0.18（56）已覆盖安装到实体 iPhone；启动被锁屏阻止，待解锁后核对。Stash 修复此前已获用户真机确认；Clash / Clash Mi IPv6 连通性仍未完整验收，不宣称全部解决。

- Mac mini M2 正式版 Xcode 26.6 从 `05fc874` 完成 Release 通用归档及 Developer ID 公证；已取回公证版，通过严格签名、stapler、Gatekeeper、DMG 校验与本机实际启动。DMG SHA-256：`d1cd2c342b0abbf6f4a15ff3a295a93c7c48272bce7a7ae33bf298cd89485667`。README 与 Homebrew 入口同步到 1.0.18（56）；同时将 cask 的系统约束从“仅 Sonoma”纠正为“Sonoma 及以上”，避免新系统被拒绝。GitHub 下载回验哈希一致；发布机 Homebrew style、audit 与安装验证通过，安装后的版本为 1.0.18（56）。

## 2026-09-13 Stash 证书指纹字段修复（未发布）

- 用户实机反馈：Stash 的 IPv4/IPv6 SS 可用但两个带 pin 的 Trojan 超时；Surge iOS 的 IPv6 可用、IPv4 握手超时；未确定具体 App/版本的 Clash 全红。这三种表现不能合并判定为同一个问题。
- 已定位并修复 Stash 字段错误：Stash 目标（`.clash`）输出 `server-cert-fingerprint`，其他 Clash 系目标保留 `fingerprint`；解析器支持导入 Stash 的字段并转成其他方言。没有放宽证书验证。依据：https://stash.wiki/proxy-protocols/proxy-types 。
- 复现测试修复前 26 处失败，修复后通过。全量 Mac Catalyst XCTest 1119 项、34 跳过、0 失败，另 85 Swift Testing 通过。
- 实测当前同一份测试订阅：Surge Mac 三个 IPv4 节点完成 HTTP 延迟测试；Clash 与 Clash Mi 目标的完整配置经 Mihomo 实测三个 IPv4 节点全部通过（仅隔离监听和 TUN，保留生成的 DNS、代理与策略组）。Surge 原配置和环境均已恢复。
- 用户已确认 Stash 修复后可用。手机截图也证明公网 IPv6 SS 及 Surge IPv6 Trojan 可用；开发机自身仍无 IPv6 路由。用户继续反馈 Clash / Clash Mi 的 IPv6 失败，尚未记为解决。
- 安装脚本重新建立设备连接后，最终修复版 1.0.17 (55) 已覆盖安装并启动到 iPhone；现场证据见本机 `.artifacts/client-pin-followup/`。未推送、未上传或发布。

- Clash Mi 最新源码 `a034641c4fb6157bd1f9a92562b5df0f508eba2a`：核心设置 IPv6 默认 false，`defaultConfigNoOverwrite()` 仍把该字段放入补丁，`getPatchContent()` 同步 DNS/TUN 的 IPv6 设置。Tower 实际导出的 Clash / Clash Mi 配置顶层均为 `ipv6: true`；需用户检查“核心设置 → IPv6 → 启用”并重连，不能把源码默认值当成已确认的用户设置。另一款 Clash 实际 App/版本尚未确认。


## 2026-09-13 IPv6 / SS UDP 修复（未发布）

- IPv6 标准节点/WireGuard URI 输出重新添加主机方括号，避免退回 `clash://local/...`；SSR 从右解析固定字段，保留 IPv6 主机。
- SS 保存 Clash `udp`、Surge/URI `udp-relay` 开关；同步结构化输出、分享、持久化和节点身份。普通 UDP relay 与 UOT 是不同功能，本次没有扩展 UOT。
- 全量 Mac Catalyst TowerTests：XCTest 1116 项、34 跳过、0 失败，另 85 Swift Testing 通过；随后补充的 6 项 IPv6/UDP 测试（含 17 个目标受支持模式矩阵）通过。
- 真实导出节点经 sing-box / Mihomo 验证 IPv4 TCP 和 UDP 开关；服务器上 sing-box 连接同机公网 IPv6 地址通过 TCP/UDP。开发机到公网 IPv6 无路由，外部 IPv6 网络端到端尚未验收。Surge 仅完成配置语法检查。
- 最终代码已用 M4 规定的 Xcode Beta 在连接的 iPhone 覆盖安装并启动；未逐一完成目标客户端真机导入及流量验收，版本号未递增、未上传或发布。
- 本机详细报告：`.artifacts/ipv6-ss-udp-report/测试报告.md`。测试地址和凭据不入库；使用修复版时先刷新订阅再导出，以恢复旧存档丢失的字段。


## 1.0.17（55）已发布 GitHub，已上传 App Store Connect（2026-09-12）

- 汇总首页订阅与自有节点双向删除、订阅测速菜单、长按整卡预览、展开长列表预览边界及勾选按钮布局修复；包含已提交的 Clash 系仅节点导出、证书指纹兼容修复和 Mac 引导调整。
- 订阅展开仍为连续的一张卡片，摘要单独作为有界长按预览，节点列表不进入快照。该最终交互已通过长列表 UI 回归和截图检查，并在实体 iPhone 安装测试。
- 本次将内置 ACL4SSR 更新到 `75f0101039d71724b6e998b34604c2e053580e0c`；77 个远程二进制先独立发布，再将 App 清单固定到对应提交，第三方署名同步更新。版本号统一为 1.0.17（55）。
- 发布回归：iOS 1,190 通过、6 跳过；Mac 1,160 通过、36 跳过，均零失败。本地化提取 995 条通过，规则最新检查、77 个远程产物验证和发布脚本测试通过。首轮两端同时运行时 Mac 有 3 项固定回环端口服务启动失败，分开重跑后通过。
- 源码提交 `3baa88d` 已推送；Air 正式版 Xcode 完成 iOS / Mac 1.0.17（55）Release 归档，两端 App Store Connect 上传均成功。未提交商店审核或上架，Apple 后续处理及 TestFlight 群组可用性未核实。
- [GitHub Release v1.0.17](https://github.com/pengchujin/tower/releases/tag/v1.0.17) 提供 Intel / Apple 芯片通用 DMG 与 SHA256SUMS.txt；严格签名、公证票据、Gatekeeper、DMG 挂载和 GitHub 回下载哈希验证均通过，公证版已实际启动。取回公证版首次网络中断，复用原归档重试成功。
- DMG SHA-256：`617704ae60f48915d91e216a31301c8a327403cf92449ad478254e63badd5341`。README 下载入口与 Homebrew cask 更新为新版。本机无 Homebrew，未运行 brew style / audit / upgrade；cask Ruby 语法检查通过。
- 归档与日志位于本机 `~/Builds/Tower-1.0.17-55/`，不进入公开仓库。下方“未发布”章节保留开发过程记录，最终发布状态以本节为准。

## 未发布：展开订阅的长按预览边界（2026-09-12）

- 用户反馈展开订阅后，整张超长卡片被系统长按预览压缩成白色细条。最终按用户要求，订阅摘要与展开节点列表共用连续的外框与背景，移除分卡间隙；摘要保留独立且有界的预览表面，长按与双向滑动仅作用于完整摘要区域（含圆角、留白、流量和操作区），展开节点不进入订阅菜单预览。收起状态仍是完整摘要卡整体抬起。
- 不自动折叠订阅，不复制长节点列表生成预览；取消菜单保留展开状态，节点列表保持原有懒加载、分享和滚动。
- 长列表定向 UI 回归通过，覆盖摘要下部滑动、展开后长按、预览文字宽度、取消保留展开，以及双向滑动删除的取消与确认。重新连接外框后再次通过同一长列表 UI 回归；已核对滑动与长按截图，卡片连续、摘要尺寸正常、节点列表留在背景，无白色细条。本轮无新增文案，尚未提交或发布。
- 最终版本已覆盖安装并启动实体 iPhone 1.0.16（54），保留用户数据，实际手感待用户体验。

## 未发布：自有节点布局与首页长按菜单（2026-09-12）

- 自有节点勾选不再单独禁用布局动画，节点行与卡片通过 geometryGroup 保持同一呈现坐标；收起期间裁剪退出内容，避免残留节点越过卡片边界。
- 自有节点标题行复用双向滑动删除和原有确认入口；按用户最终要求，长按编辑、删除放在完整卡片最外层，使用与订阅一致的圆角预览轮廓，背景、留白和内容整体抬起。订阅长按新增“测速”，调用原有批量延迟测试，仅传入当前订阅的节点。
- 初版自定义名称预览被用户指出缩成小胶囊，已移除；后续发现内层 List 预览遗漏外框与留白，将 contextMenu 移至完整订阅卡片最外层，指定与卡片一致的圆角预览轮廓，使背景、内边距与内容作为一个整体抬起；订阅、自有节点展开按钮取消与系统菜单重叠的缩放按压效果，保留系统原生菜单过渡及减少动态效果支持。
- 两项定向 UI 回归通过，覆盖订阅长按测速、自有节点勾选对齐、双向删除取消与确认，以及原有订阅滑动删除；自有节点整卡菜单调整后，增加长按截图检查并重跑菜单与删除流程通过。完整回归仅一条旧初始化写法源码断言失败，按新增回调参数更新后，52 项仓库一致性测试重跑通过。无新增本地化键。
- 整卡预览修正版定向 UI 测试通过，并核对长按截图：外框、留白与内容完整，没有原地残留的底框；整卡预览最终版本已覆盖安装实体 iPhone 开发版 1.0.16（54），自动启动因手机锁屏被阻止，用户解锁后可手动打开；实际动画手感待用户验收。尚未提交或发布。

## 未发布：首页订阅双向滑动删除（2026-09-12）

- 将规则卡片的原生双向滑动删除提取为共享 `CardSwipeDeletion`，首页订阅摘要区域复用；向左、向右均可显示红色删除按钮，不启用整段滑动直接删除。继续使用原有删除确认、取消与模型删除入口。
- 初版仅标题行可滑，用户反馈难以触发后扩大到整个订阅摘要（标题、流量、节点数量及操作按钮）；展开节点保留在外层滚动区域，避免整张长卡片横移。原有编辑、刷新、分享、删除上下文菜单保留。
- 初版 iOS 完整回归 1,196 项：1,190 通过、6 跳过、零失败；首页订阅与规则页两项定向 UI 测试通过，覆盖双向滑动、展开长列表、取消恢复与确认删除，已核对截图。复用原有文案，无新增本地化键。
- 摘要区域扩大后，补充从收起卡片的节点数量行滑动删除测试，并重跑展开状态双向删除、取消和确认，定向 UI 测试通过；最终版本重新覆盖安装并启动实体 iPhone 成功。
- 已覆盖安装并启动实体 iPhone 开发版 1.0.16（54），数据保留；实际手感待用户验收。尚未提交或发布。

## 未发布：补齐证书指纹导出（2026-09-12）

- 修复 Surge / Surge Mac 的 Trojan、TUIC、AnyTLS、TLS VMess、HTTPS、SOCKS5-TLS 指纹遗漏，Hysteria 2 复用同一输出路径；完整配置和仅节点都保留 `server-cert-fingerprint-sha256`，规范化冒号及连字符，不修改原 TLS 验证开关，不把普通 TCP 或 REALITY 当成证书固定校验。
- Loon / Quantumult X 补齐官方 `tls-cert-sha256` 字段；Trojan 重建节点分享/订阅 URI 时保留 `pinSHA256`。Egern、Clash 系原有字段输出保留。sing-box / Hiddify 只有公钥哈希能力，无法从证书哈希推导公钥哈希；这类节点现在明确跳过并计数，不静默丢指纹。
- 测试先复现遗漏再修复。全量 Mac Catalyst：1,111 项 XCTest（34 跳过、零失败）及 85 项 Swift Testing 通过；真实私有语料由最新解析器和生成器输出，新增 6 项回归覆盖协议/格式矩阵、纯 TCP、URI 回读及不支持的目标。
- Surge Mac 6.4.4 实际连接：Hysteria 2 与 Trojan 各自的普通/冒号正确指纹成功，错误/缺失指纹失败。负向测试必须使用独立服务端端口：同端口多个策略在本轮出现了正确连接建立后错误指纹也成功的现象，与连接复用有关，不计为可靠负向证据。Surge 原配置和运行时环境已恢复核对一致。
- 用户先前已用 iPhone 验证 Egern 两协议的正确/冒号指纹都成功；本轮 Loon、Quantumult X 仅完成官方字段和自动回归验证，未做真实客户端连接测试。临时独立端口服务已清理，用户取得的订阅和原测试服务保留至约定期限。
- 真机安装脚本未找到唯一可用的实体 iPhone，Xcode 将设备列为不可用，本轮尚未覆盖安装或启动修复版。源码随本次更新提交，尚未打包发布；用户可在另一台电脑拉取构建，安装后需重新导出。脱敏证据位于 `.artifacts/issue29-report/`。

## 未发布：Clash 系客户端仅节点导出（2026-09-11）

- Stash、Clash、Clash Verge、ClashMac、FlClash、Mihomo Party、Clash Mi、Karing 增加“完整配置 / 仅节点”，按客户端保存选择。仅节点复用对应客户端节点写入器，输出只有 `proxies` 的 YAML，不包含规则、策略组或远程代理集合；保留筛选、跳过计数、名称转义和去重，空列表输出合法 YAML。
- 主按钮与 Surge 仅节点一致复制聚合链接，供现有配置的 `proxy-providers` 引用；iPhone 使用原有 127.0.0.1 临时服务，Mac 使用原有局域网共享。链接固定客户端和节点模式，不随当前导出选择改变，服务刷新读取最新启用与勾选状态。补齐 `clash-apple` 的服务端格式映射。
- 全量回归 1,190 项：1,184 通过、6 跳过、零失败。覆盖全部 Clash 系目标的纯节点 YAML、解析回读、空列表，以及全部聚合链接的模式持久化、来源变化和筛选。首轮发现 Clash 显式目标缺少路由映射，补齐后全量重跑通过。
- Mac Catalyst Debug 构建通过；Stash 定向 UI 回归通过，验证切换仅节点、复制成功提示及恢复完整配置导出。
- 新增说明补齐 15 语言，Xcode 提取 995 条通过；生成器遇到 HTTP 429 后手工翻译并复核。已覆盖安装并启动实体 iPhone 开发版 1.0.16（54），保留数据；实际第三方客户端代理集合接入待真机验收。源码随本轮更新提交，尚未打包发布。

## 未发布：Hysteria 2 的 Surge 证书指纹（2026-09-11）

- pinSHA256 丢失反馈的目标客户端尚待确认。已确认 URI 导入和保存会保留证书指纹，Surge / Surge Mac 的 Hysteria 2 导出漏写，现补为 server-cert-fingerprint-sha256；带冒号指纹去掉分隔符，不与 uTLS fp 混用，不调整原 TLS 验证开关。其他客户端不因此视为已修复。
- 依据 Hysteria 官方 URI Scheme 与 Surge TLS 手册。新增链接导入、保存恢复、Surge 两端导出回归，覆盖普通与冒号指纹、uTLS 分离、无指纹节点，定向通过。
- 完整回归 1,182 通过、6 跳过，另有 1 条引导宽度源码检查失败；上轮 Mac 引导宽度恢复等价常量写法后，该检查补跑通过。尚未发布，真实客户端连接未验收。

## 未发布：Mac 引导客户端与布局（2026-09-11）

- 按用户指定，Mac 导出引导示例改为 Surge Mac 默认选中，其次 Clash Verge、ClashMac、sing-box MT。只调整引导示例，不修改用户实际导出偏好或 iPhone 客户端顺序。
- Mac 示例使用四列等宽卡片（辅助功能字号两列），避免自适应网格预留空列；桌面引导内容最大宽度 760pt、最大高度 760pt，在大窗口内居中，减少示例与底部操作之间的空白。
- Surge Mac / ClashMac 示例展示复制订阅路径，其余复用客户端实际导出标题；引导不探测已安装客户端、不执行导入。
- Mac Catalyst 构建通过；本机实际打开引导至末页，核对默认选择、顺序、卡片布局，并切换 Clash Verge 与 sing-box MT 验证示例文案，最后恢复 Surge Mac。源码随本轮更新提交，尚未打包发布；已发布的 1.0.16（54）不包含此项。

## 1.0.16（54）已发布 GitHub，已上传 App Store Connect（2026-09-11）

- 汇总首页刷新浮层、全界面 13 项动画以及管理页关闭搜索闪烁修正。源码提交 `2929485` 已推送，归档版本均为 1.0.16（54）；下方“未发布”章节保留实施过程，最终状态以本节为准。
- Air 正式版 Xcode 26.6 完成 iOS 与 Mac Release 自动签名归档，两端 App Store Connect 上传命令退出码均为 0，版本及 Bundle ID 已核对。未提交审核或发布商店版本，后续由用户操作；Apple 后续处理及 TestFlight 群组可用性未核实。
- iOS 全量 1,188 项中 1,182 通过、6 跳过；Mac 全量 1,188 项中 1,152 通过、36 跳过，均零失败。Mac 首次未签名测试有 3 项回环服务失败；由 Xcode 自动登记本机并生成开发描述文件，签名重跑全量通过。此前 8 项定向 UI 流程通过；994 条本地化提取通过，77 个远程规则产物哈希和发布脚本回归通过。
- GitHub Release `v1.0.16` 提供 Intel / Apple 芯片通用 DMG 和 SHA256SUMS.txt。Air 本机通过 Xcode 自动签名完成 Developer ID 分发与公证，取回带票据应用后，严格签名、stapler、Gatekeeper、DMG 挂载及 GitHub 回下载哈希检查均通过；公证版已实际启动。
- README 下载入口与 Homebrew cask 同步新版及 SHA-256。本机未安装 Homebrew，未运行 brew style / audit 或 brew upgrade；cask Ruby 语法检查通过，分发应用及挂载包独立验签通过。
- 归档和验证日志位于本机 `~/Builds/Tower-1.0.16-54/`，不进入公开仓库。

## 未发布：管理页关闭搜索闪烁（2026-09-11）

- 用户反馈管理 → 导出筛选输入后点右侧关闭，列表恢复时闪烁。将节点与批量管理计数动画限制在文字内部，搜索文本变化时屏蔽 List 的行增删动画，保留系统搜索栏及键盘收起过程；不修改节点顺序、勾选和筛选逻辑。
- 新增 300 节点 UI 回归，连续覆盖有结果、无结果、再次搜索后关闭，验证全部节点恢复、全选操作可用及键盘收起。测试通过，关闭过程录屏抽帧未见列表空白闪烁；前两次测试分别因未展开系统搜索栏、误用“取消”而非“关闭”的无障碍标签失败，修正测试后通过。
- 正式版 Xcode 26.6 构建并覆盖安装启动实体 iPhone 1.0.15（53），保留数据；实际手机触感待用户复验。本轮没有新增文案，未提交或发布。

## 未发布：全界面 13 项动画修正（2026-09-11）

- 用户批准审查清单全部实施。规则预览等待期间保留占位并标记旧结果，二维码统一尺寸且立即隐藏过期地址；导出内容、底栏、加载图标与正文局部淡变。
- 地图记录实际呈现中的缩放与偏移，新手势从当前位置接管；逐次消费拖动位移以消除边界反向死区。保留原有惯性和边界，栅格密度切换先归一化再应用统一呈现变换。
- 导入来源区域保持本次任务已占用高度；补齐引导减弱动态、Mac 引导浮层、说明展开、轻量按压与数字变化。详细范围见 `animation-plans/2026-09-11-motion-audit.md`。
- iOS 全量 1,188 项中 1,182 通过、6 跳过、零失败，包含 3 项新增地图数学回归。Mac Catalyst Debug 构建通过；Xcode 本地化提取 994 条通过。
- 7 项定向 UI 流程最终通过，覆盖刷新、引导、导出切换与预览复制、地图缩放、节点筛选和本地规则。首轮 5 通过、2 失败：预览按钮被底栏部分遮挡但 AX 报可点击，关键词测试未等待异步预览；补齐测试滚动可见区域与结果等待后，两项重跑通过。已核对地图、规则编辑与配置预览截图/录屏抽帧。
- 开发版 1.0.15（53）已覆盖安装并启动实体 iPhone，数据保留；手机触感与 Mac 引导实际操作待用户体验。本轮未提交、递增版本或发布。

## 未发布：首页刷新浮层动画（2026-09-11）

- 刷新浮层使用独立呈现快照与显式动画事务，进入和退出采用 0.36 秒响应、无回弹的轻微缩放加淡入淡出；进度和来源文字平滑切换。减少动态效果时只淡入淡出。
- 不再在刷新开始时禁用整个 TabView，由浮层遮罩接收触摸，保留系统下拉回位；浮层隐藏时明确关闭命中测试。
- 正式版 Xcode 编译测试数据遇到类型推断超时，拆分 Debug 性能样本的用量表达式后编译通过，数据含义不变。
- 13 项订阅刷新测试通过；模拟器 UI 回归通过，覆盖下拉显示、居中位置、取消、页面回位与再次完成。原测试手势在本机系统未达到刷新阈值，增大下拉距离后通过。
- 最终开发版 1.0.15（53）已覆盖安装并启动实体 iPhone，保留数据；真机触控手感待用户验收。本轮未递增版本或发布。

## 1.0.15（53）已发布 GitHub，已上传 App Store Connect（2026-09-11）

- 本版汇总居中导入进度、完整下载校验、单一确定按钮的错误浮层、订阅刷新进度与取消，以及规则导入链接图标恢复。下方过程记录中早期重试和原始地址按钮已按用户要求移除，以最终单按钮设计为准。
- 53 构建已覆盖安装并启动实体 iPhone，严格签名及版本核对通过。Mac mini M2 正式版 Xcode 26.6 已完成发布预检；内置 ACL4SSR 为上游最新快照，77 个已发布远程产物哈希验证通过，发布脚本回归通过。
- GitHub issue 核对：#18 的 sing-box 三模式、#26/#27 的名称关键词及正则筛选、#28 的 sing-box MT IPv6/DNS 调整已实现；#22 原始闪退已修复，但后续 Mac 中文输入重复拼音仍未修复，保持打开。
- Mac Catalyst 全量 1,100 项 XCTest（34 跳过）与 85 项 Swift Testing 通过；iOS 全量 1,100 项 XCTest（4 跳过）与 85 项 Swift Testing 通过，均零失败。iOS 首轮发现旧按钮本地状态源码断言与统一任务状态冲突，按现有设计更新后重跑全量通过。Xcode 提取 994 条本地化通过。
- 源码提交 `d53263d` 已推送；M2 正式版 Xcode 26.6 完成 iOS 与 Mac Release 归档及 App Store Connect 上传，两端命令退出码均为 0，已核对归档版本及 Bundle ID。Apple 后续处理、测试群组可用性未核实；未提交审核或发布商店版本，后续由用户操作。
- GitHub Release `v1.0.15` 已公开，包含通用 Mac DMG 与 SHA256SUMS.txt。公证提交后额外执行 `-exportNotarizedApp` 取回带票据应用；严格签名、stapler、Gatekeeper、DMG 挂载、GitHub 回下载哈希均通过。公证版已实际启动。
- README 下载按钮和 Homebrew cask 已同步新版本及 SHA-256；本机格式检查、M2 完整审计通过。本机审计被 Homebrew 对正式版 Xcode 26.6 的版本检查阻止，未更改全局工具链，转由 M2 完成。Homebrew 已将本机升级至 1.0.15（53），安装后签名、公证和启动通过。
- #18、#26、#27、#28 已逐条回复修复范围并关闭；#22 已回复剩余中文输入问题并保持打开。证据位于 `.artifacts/release-1.0.15/` 与 `.artifacts/direct-1.0.15-53/`。

## 未发布：导入错误统一浮层，单一确定按钮（2026-09-11）

- 移除导入表单顶部的错误 Section 及自动滚动，下载和解析错误均在原有任务层居中显示；共享加载卡片的材质、圆角、遮罩与辅助功能处理。错误详情限制高度并可独立滚动，表单位置保持不变。
- 按用户最终要求，错误浮层只保留一个“确定”按钮，关闭后保留全部输入。移除浮层内重试、原始地址、返回修改按钮及相关说明；不自动绕过镜像。后端严格下载完整性检查和原始地址转换 API 保留。
- 80 项导入、本地化与仓库一致性回归通过；最终单按钮版本完成截图中公开 Surge 配置的实际 UI 测试，验证多项 HTTP 404、浮层位置、错误滚动、唯一可点击按钮、关闭后草稿与表单位置保留、再次导入仍在浮层报错。较早的独立新测试被 Xcode 过滤为零项，不计为通过；复用既有测试入口后实际执行通过。
- Xcode 提取 994 条本地化通过；新增短标签补齐 15 语言。生成器翻译服务返回 HTTP 429 后人工补全并复核。证据位于 `.artifacts/import-failure-modal/`，本轮未发布。
- 最终单按钮版本 1.0.14（52）已重新覆盖安装并启动实体 iPhone，严格签名验证通过，安装包的确认按钮英文资源也已回读核对。手机实际触感待用户测试。

## 未发布：订阅刷新居中进度（2026-09-11）

- 下拉刷新、订阅卡片更新及管理页批量更新共用与规则导入一致的材质进度卡片，显示完成数量、当前订阅名称和取消按钮。前台任务独立于下拉手势，原生指示器及时收回；移除与系统回位冲突的手动滚动。自动刷新仍在后台进行。
- 取消会停止排队与正在进行的请求、使旧响应票据失效，并保存已经成功更新的订阅；取消不作为刷新失败报告。重置或应用新快照时同步清除浮层任务。
- 抽取共享 TaskProgressCard，保留减少动态效果、减少透明度、增强对比度和模态无障碍语义。新增两条文案补齐 15 语言并人工复核，Xcode 提取 991 条通过。
- 126 项定向回归（30 项环境跳过、零失败）通过；最终进度收尾调整后 13 项订阅刷新测试再次通过。模拟器 UI 测试通过，覆盖居中位置、取消、页面回位及再次刷新完成；已核对实际截图。测试使用隔离本地延迟数据，不请求真实订阅。证据位于 `.artifacts/subscription-refresh-modal/`。
- 实体 iPhone 已覆盖安装并启动 1.0.14（52）开发版，严格签名验证通过；实际手机触感由用户继续测试。本轮未发布，未调整规则下载超时或重试策略。

## 未发布：导入进度改为居中浮层（2026-09-11）

- 按用户反馈移除导入页顶部占位进度条，改为居中圆角材质卡片及轻量遮罩；表单不随进度出现而下移。卡片显示阶段、下载来源与取消按钮；多个来源可在限定高度内滚动。
- 进入和退出使用 0.3 秒响应、无回弹的轻微缩放与透明度过渡；减少动态效果时仅淡入淡出，减少透明度或增强对比度时使用实色背景。取消按钮整行至少 44 点可点击，保留输入草稿；背景从无障碍导航中隐藏，浮层标为模态。
- 65 项本地化/仓库一致性测试通过；Xcode 本地化提取检查 989 项通过。公开配置的模拟器完整 UI 测试通过，覆盖居中位置、取消按钮边缘点击、草稿保留、超时与原始地址重试。首轮 UI 测试把模态 Alert 错当成 Other 查询，修正查询后命令正常退出；已核对截图及录屏抽帧。证据位于 `.artifacts/import-progress-modal/`。
- 已重新覆盖安装并启动实体 iPhone 1.0.14（52）开发版，严格签名验证通过；手机触控观感待用户测试。本轮只改进度呈现与 UI 测试，沿用上一轮下载和失败恢复逻辑，未发布。

## 未发布：规则导入进度与下载失败恢复（2026-09-11）

- 链接、文本、文件导入统一报告配置下载、解析和引用规则下载阶段，显示完成数量及来源主机/文件名；导入时的取消停止请求并保留输入草稿。
- 新导入要求所有引用列表下载成功；任何列表失败均显示具体来源及原因，不保存或选中缺规则的方案。拒绝把返回的 HTML 网页缓存为成功规则列表，保留既有取消和重置代次校验。
- 失败页提供重试。对 `ghp.ci` 包装的 HTTPS GitHub Raw / Gist 文件，提供明确的“尝试原始地址”按钮；仅替换用户本次选择重试的失败引用。拒绝未知镜像、非 HTTPS 内层地址、凭据和额外查询参数。成功导入后原始地址同步进入缓存、方案模型及可编辑文本，刷新和导出沿用该地址；不更改策略、规则顺序和 provider 参数。
- 21 项定向测试通过；Mac Catalyst 全量 1,098 项 XCTest（34 项环境跳过、零失败）及 85 项 Swift Testing 通过。15 语言 Xcode 提取检查通过，共 989 项；人工修正镜像含义和韩语短标签。
- 使用用户此前提供的公开配置完成模拟器实际界面测试：显示镜像来源、取消保留输入、超时展示失败、原始地址重试成功，命令正常退出。截图已核对，恢复操作可直接点击。证据在 `.artifacts/rule-import-progress/`；可选 UI 测试通过 `TEST_RUNNER_TOWER_IMPORT_UI_URL` 显式指定公开配置。
- 实体 iPhone 已覆盖安装并成功启动 1.0.14（52）开发版，严格签名验证通过；手机网络下的导入触控验收待用户测试。本轮未递增版本、提交、推送或发布。

## 1.0.14（52）已发布 GitHub，已上传 App Store Connect（2026-09-11）

- 汇总规则兼容、链接/文本/文件导入、Mihomo YAML 模板、节点筛选编辑、导入 Emoji 原样显示、卡片交互与 sing-box MT DNS / IPv6 修复。下文“未发布”章节为开发验收记录，最终发布状态以本节为准。
- Mac Catalyst 全量 1,092 项 XCTest（34 跳过）及 85 项 Swift Testing，零失败。ACL4SSR 为上游最新快照，77 个远程规则产物哈希验证通过；发布脚本回归通过。
- iOS Simulator 全量 1,092 项 XCTest（4 跳过）及 85 项 Swift Testing，零失败；Xcode 本地化提取 981 项通过。正式构建来自提交 `13b4a42`，Mac mini M2 使用 Xcode 26.6，iOS 与 Mac 两端 Release 归档和 App Store Connect 上传均成功。网页会话未登录，Apple 后续处理状态及测试群组可用性未核实；没有提交审核或发布商店版本，由用户自行处理。
- GitHub Release `v1.0.14` 已公开，包含通用 Mac DMG 和 SHA256SUMS.txt。Developer ID 签名、公证后应用导出、stapler、严格签名与 Gatekeeper 均通过；DMG 挂载与 GitHub 回下载哈希通过。公证版已实际启动，本机 Homebrew 已升级至 1.0.14（52），安装后的签名与启动通过。
- Homebrew cask 已同步 1.0.14（52）及新 DMG SHA-256，补齐 verified 下载仓库声明；格式检查与发布机完整审计通过。本机 brew upgrade 安装及启动通过。
- 52 构建真机安装脚本未找到唯一可用实体 iPhone，未完成该构建的手机覆盖安装；上一开发构建已有用户手机测试记录。证据位于 `.artifacts/release-1.0.14/` 和 `.artifacts/direct-1.0.14-52/`。

### 未发布：导入策略组保留原有 Emoji 状态

- 撤销上一轮给展开预览自动匹配图标的改动，卡片恢复显示实际策略名称。导入方案的规则定制与候选策略列表只显示名称中已有的 Emoji，不再根据 Apple、Telegram、节点选择等词语推断图标，也不再放置默认拼图占位。
- 名称编辑页以原有 Emoji 初始化，允许留空并保存纯文本名称，避免仅改名称就写入推断图标。普通数字、#、* 不再当作前置 Emoji 从显示名称中移除。内置方案保留原有显示逻辑。
- 151 项规则目录、定制和仓库一致性测试通过。实体 iPhone 已覆盖安装并启动 1.0.13（51），严格签名验证通过；手机实际外观待用户验收。证据位于 `.artifacts/imported-rule-emoji/`。

### 未发布：sing-box IPv6 默认值与直连 DNS 修复

- Windows 实测先后暴露 IPv6 直连不可达，以及国内域名通过代理 DNS 解析后再本地直连导致访问慢的问题。sing-box MT 未指定 IPv6 时改为 IPv4 DNS 与 IPv4 TUN；明确保存的开关继续保留。Hiddify 和其他目标默认值不变。旧 preset 路径同样默认 IPv4。
- 网络编辑页 IPv6 改为“默认 / 开启 / 关闭”，保留未指定状态。仅修改 DNS 不会再把隐式 IPv6 默认值写成开启，也不改写已有明确设置。
- 标准与跟随方案模式的 DNS 按导出时的 selector 默认成员递归判断直连，支持 default 字段和嵌套组，不根据组名猜测，也不再因为组内存在代理候选就把国内解析全部送往代理。严格模式、全局模式及代理服务器启动解析保持独立保护；寻找安全代理 DNS 出口时仍检查全部候选，不能到达 DIRECT。
- 限制：当前核心 DNS 规则无法匹配 selector 的运行时选择。标准模式使用导出默认策略的静态 DNS 投影；客户端内手动切换或恢复缓存选择不会自动重写这些域名的 DNS 路径。全局代理 / 直接连接模式仍联动，已用真实核心验证；不宣称普通组动态跟随。
- Mac Catalyst 全量 TowerTests：1168 项，1135 通过、33 跳过、零失败，命令正常退出。Xcode 本地化提取 981 项通过，复用已有翻译。sing-box 1.14.0 macOS 核心检查 6 份生成配置通过；loopback 验证混合候选但默认直连的组、域名优先级、严格模式、代理 DNS 故障不回退、普通组切换的静态边界、全局 A/B 节点切换同时改变数据和 DNS 出口。Windows 1.15 实际网络验证仍由用户继续。
- 证据位于 `.artifacts/singbox-windows-dns/`。实体 iPhone 重新连接后，使用标准安装脚本再次覆盖安装并成功启动 1.0.13（51），命令正常退出；严格签名验证通过。Xcode 设备发现短暂不一致，使用通用真机构建和已连接 CoreDevice 完成安装，保留原有数据。用户需重新导出配置后在 Windows 验证；未发布。

### 未发布：恢复规则卡片原生长按外观

- 用户反馈上一轮自定义的 280 点摘要预览改变了原卡片外观。本轮移除自定义 preview，长按菜单直接附着于原始顶部控件区域，由系统预览原本的标题、来源、计数、选择状态和展开/刷新行。长按入口位于卡片顶部；展开列表不再成为菜单的预览源，避免整张长卡片缩成细长条。左右滑动仍使用上一轮已修复的顶部原生操作区。
- 58 项仓库一致性及动画测试通过，旧的“整卡长按”源码约束已按当前交互更新。40 组展开用例通过（109.499 秒），验证原生预览宽度、顶部双向滑动与取消、确认删除、底部可达和重启持久化；收起状态回归通过（63.515 秒），包含原卡片预览宽度、取消、双向侧滑删除和重启验证。UI 套件零失败，但 Xcode 结果收集超过 60 秒未退出，已停止收尾进程；单元测试命令正常退出。录屏及日志位于 `.artifacts/rule-native-menu/`。
- 手机和 Mac 1.0.13（51）已覆盖安装并启动，严格签名验证通过。实体手机触控外观待用户验收，未发布。

### 未发布：修正规则长卡片的删除手势与预览

- 上一轮恢复展开动画时新增的整卡横向 UIPan 导致展开内容一同横移，红色操作区撑满整张长卡片，删除按钮可能落到屏幕外。本轮移除此自定义手势，恢复系统原生双向 swipeActions，仅作用于卡片顶部摘要和展开/刷新操作区；展开的策略列表保持原位。
- 原生滑动行只承载高度有限的顶部控件，通过该控件的固有高度布局，保留动态字体。页面继续使用 ScrollView + LazyVStack，展开区仍为完整测量的 VStack，不恢复把长卡片放进自适应 List 行的旧结构。继续使用订阅卡片的共享展开动画与 geometryGroup。
- 滑动按钮使用红色普通 action，避免原生 destructive 行动画在确认前提前移除内容。实际删除仍由既有弹窗确认，取消后原生操作区归位；确认移除时使用共享动画及透明度过渡。长按菜单保留，预览改为方案名称、来源摘要和计数，避免整张展开卡片被压缩成细长条。
- 本轮证据保存在 `.artifacts/rule-delete-fix/`。130 项相关单元测试通过；首轮三项 UI 回归通过，包括 40 组展开后的双向滑动/取消、长按确认删除、末组和底部可达、重启持久化，以及收起状态删除和连续展开收起。补充紧凑长按预览后，收起删除再次通过；首次预览尺寸断言误用 SwiftUI 内容标识，系统实际暴露的是预览容器，已改用系统预览容器定位，补跑通过（102.415 秒），包含摘要预览尺寸、展开删除及重启持久化。首轮三项 UI 和 130 项单元测试命令正常退出；最后补跑套件通过后结果收集超过 60 秒未退出，已停止该收尾进程，不计为命令正常退出。
- 手机和 Mac 1.0.13（51）均已覆盖安装、启动及严格签名验证。Mac 实际 39 组长卡片展开和滚到底部已核对；实体手机完整触控观感仍待用户验收。未发布。

### 未发布：恢复规则卡片与订阅卡片一致的展开动画

- 用户反馈上一轮滚动修复后展开动画异常。模拟器录屏逐帧复现：原生 List 自适应行高与卡片内部几何动画叠加，标题先向下跳再返回，详情一度穿出背景。单独添加 geometryGroup / 顶部对齐仍有整体位移，禁用内部动画又使展开突变，均未作为最终方案保留。
- 最终恢复订阅页同样的 ScrollView + LazyVStack 容器，卡片共用 TowerMotion.disclosure、透明度过渡及 geometryGroup。详情保留普通 VStack 完整测量高度，不恢复上一轮导致布局循环的嵌套懒加载列表行。
- 长按删除保留；左右滑动通过卡片横向 UIPanGestureRecognizer 揭示删除按钮，纵向手势在开始前拒绝，仍由页面滚动处理。滑动本身不删除，点击后沿用确认弹窗。没有更改解析、导入内容或当前选中方案。
- 130 项相关单元测试通过；连续三轮展开/收起 UI 测试通过，检查标题及展开按钮坐标，另逐帧核对录屏。40 组配置已通过展开、最后一组/底部按钮可达及收起回归（75.260 秒）；长按、双向侧滑删除、取消与重启持久化回归通过（60.351 秒）。这两项套件完成后 Xcode 结果收集超过 60 秒未退出，已终止收集，不能记为该命令正常退出；连续展开用例和单元测试命令均正常退出。首轮测试受模拟器可选名称输入漏字影响，已改用默认名称并重跑，未将中断运行计为通过。证据位于 `.artifacts/rule-disclosure-motion/`。
- Mac 与手机 1.0.13（51）已覆盖安装并启动，严格签名验证通过。Mac 已对照订阅展开/收起与规则卡片，并使用实际滚轮到页面底部；实体 iPhone 触控观感仍待用户确认。未发布。

### 未发布：规则卡片展开后滚动与布局循环

- 用户反馈手机导入规则、展开卡片后无法滚到底。修改前新增 40 组的 UI 复现：点展开后 App 触发 `EXC_BREAKPOINT`，堆栈反复进入 `UICollectionView._updateVisibleCellsNow` / 布局失效路径，尚未执行到底部的断言即崩溃。崩溃符号摘要与复现日志在 `.artifacts/rules-scroll-fix/`。
- 规则页改为原生 List 后，原来的内置方案 `LazyVStack` 和卡片展开区 `LazyVStack` 仍嵌在自适应高度的行内。修复为内置卡片直接成为 List 行、展开区使用普通 VStack 一次测量完整高度；仅由外层 List 做懒加载。保留展开动画、长按及双向侧滑删除，不改导入解析、规则数量或用户已存方案。
- 验收：原 40 组复现用例通过，检查最后一组和底部按钮实际处于可点击的可视区域、收起后仍可滚到底；Xcode 命令正常退出。124 项规则定制/仓库一致性测试通过。Mac 对已有 Self-Configuration（27 组）和实际 config.yaml（2 组）展开、继续滚到页面底部实测正常。另补 2 组、内置方案和长按/双向滑动删除 UI 回归 3 项全部通过，包含点击底部按钮进入导出页、删除后重启验证。
- 手机与 Mac 1.0.13（51）覆盖安装并启动，两个平台严格签名验证通过；用户现有方案、导入内容未改写，无需重新导入。实体手机触控结果待用户测试。

### 未发布：Clash 规则方案导入与节点来源分离

- 按用户要求撤回上一轮新增的只读规则列表及专用名称元数据；保留先前的文本/文件导入、删除入口。
- 对照 Mihomo 文档确认四个独立部分：`proxy-providers` 是节点订阅集合，`proxy-groups` 是策略组，`rule-providers` 是规则集合，`rules` 决定匹配顺序和目标策略。Loyalsoldier 示例中的 CNIX 同时是节点提供器名称和真实策略组名称；不能仅按名字归类。没有把 apple/reject 等规则集创建为额外策略组。
- 修复规则方案导入场景：Clash 的 `use` 转换为使用塔台已选节点的名称筛选，保留原组名、组间引用、筛选和排除条件。源订阅不会被下载或添加到塔台；示例占位地址不再导致节点组为空并回落 DIRECT。普通解析/配置校验仍保留原订阅来源绑定；未声明的 `use` 提供器仍拒绝，避免拼写错误意外全选。
- 链接与本地 Clash 导入均持久化转换后的规则模型，避免编辑重开后从原 YAML 恢复旧订阅绑定。原路由顺序、DIRECT/REJECT、规则集引用继续保留；不增加远程规则内容的内联展开，不改用户已有方案或当前选择。旧导入需用户重新导入/刷新才应用新转换。
- 验收：全量首轮执行 1,083 项 XCTest（33 项跳过），发现 8 项旧界面断言与此前拆分文件/滑动删除需求不符，及新增用例把仅支持节点导出的 V2Box 纳入完整配置检查的错误；修正后相关 61 项重跑全部通过，首轮其余测试及 82 项 Swift Testing 通过。真实上游样本 11 个远程引用、原始目标策略顺序和 CNIX 实际节点池通过验证，Clash 引用式输出 4,167 字节并通过 Mihomo 1.19.27 校验；小样本覆盖全部支持完整配置的目标，额外核对 Surge / sing-box 的 CNIX 成员并通过各自本地核心校验。未把语法校验视为连接/实际流量验证。
- 本地化 Xcode 提取 981 项通过。手机与 Mac 1.0.13（51）覆盖安装、启动及严格签名验证通过，当前用户方案未修改；实体手机触控验收待用户试用。模拟器 1 项界面回归通过，覆盖三种导入入口、文本导入、打开规则组、长按/双向滑动删除及重启持久化；Xcode 在套件通过后持续停留于结果收集，已中断该收尾进程，不计作命令正常退出。证据目录 `.artifacts/provider-import-redo/`。

### 未发布：导入规则删除与入口一致性

- 分流规则页使用原生列表承载导入卡片，支持左滑、右滑显示删除；长按菜单覆盖整张卡片，包括底部策略组区域。删除仍需确认，共用已有方案删除流程，保留共享规则缓存和当前方案的默认回退。
- 导入页的链接、文本、文件切换改为与添加订阅页一致的图标按钮：62 点高度、加粗标题、蓝色选中态。三种输入各自保留草稿。
- 验收：14 项 Mac 定向测试通过（删除当前方案回退、共享规则缓存保留及 15 语言完整性），Xcode 本地化提取 978 项通过。模拟器完整文本导入、打开编辑、长按删除取消、双向侧滑删除取消/确认及重启持久化 1 项 UI 测试通过；Xcode 在测试套件通过后停留于结果收集，已终止收尾进程，未计作命令正常退出。Mac 实际核对卡片列表和三种图标入口；手机与 Mac 1.0.13（51）已覆盖安装、启动并通过严格签名验证，实体手机触控观感待用户测试。证据在 `.artifacts/rule-import-actions/`。


更新：2026-09-10。产品约束以 [CLAUDE.md](../CLAUDE.md) 为准；本文只记录当前状态，不再叠加历史开发日志。


## 未发布：Mihomo YAML 模板语法支持

- 规则配置解析补齐 `&anchor`、`*alias`、`<<` 单模板/模板数组合并、跨行 `{}` / `[]` 和尾随逗号。显式字段覆盖模板，合并数组中前面的模板优先；模板复用不修改原模板。保留正则、引号内注释字符、列表顺序，以及 Egern priorities 的原始顺序。
- 限制输入 8 MB、递归深度 64、解析/别名物化节点总量 200,000、累计文本预算 16 MB；未定义/递归引用、重复键、无效合并、多文档及显式标签仍拒绝。此处只解析本地 YAML 模板，不下载或展开 GEOSITE / MRS 数据库；不是完整 YAML 规范的所有构造（例如块标量）均已支持。
- 修复规则文本保存重开时把原文未填写的测速 URL、间隔、容差固化为默认值的问题；若用户修改了文本中的值，继续以修改值为准。链接、文本、文件导入复用同一解析器，订阅 provider 不当成策略组，也不会将示例订阅导入节点列表。
- 验收：原始公开 Mihomo 模板直接识别 30 个策略组、34 条规则声明；实际规则列表下载、持久化、文本重开和 Mihomo 导出检查通过，GEOSITE 引用保持原样。Mac Catalyst 全量 1,143 项通过、33 项跳过；Mihomo 1.19.27 用独立目录的既有 Geo 数据校验成功，未启动代理或修改系统网络。证据在 `.artifacts/yaml-support/`。
- 手机 1.0.13（51）已覆盖安装、启动并通过严格签名校验；实体手机完整重新导入触控流程尚需用户验收。本轮未修改 UI、递增版本、提交或上传。

## 已回退：Smart YAML / MRS 文本展开试验

- 用户反馈这轮改动导入约 17 万条规则，导致塔台卡顿以及目标客户端崩溃。按用户要求撤回本轮 YAML 锚点/合并、具名 direct/reject 别名、MetaCubeX MRS 文本替换及缓存读取改动，保留之前的分流规则、ACL4SSR 路径、任意检测间隔和动画修复。
- 之前的哈希一致与核心语法通过只能证明内容/语法，不代表客户端加载时的内存、响应时间与稳定性；此次缺少这部分验收。该试验不得作为已完成兼容能力发布。
- 电脑已恢复 ACL4SSR 默认方案，并通过界面删除本次导入的 `clash-all-smart.yaml` 及不再被引用的下载缓存。旧输出与试验源码仅留在本机 `.artifacts/smart-yaml-fix/`、`.artifacts/smart-yaml-rollback/` 供排查，不再作为推荐使用的配置。
- 回退后定向回归 20 项 XCTest、15 项 Swift Testing 通过。手机与电脑均已覆盖安装并启动回退版 1.0.13（51），签名验证通过；电脑重启显示 ACL4SSR 默认、3,529 条。只读核对手机保存数据仍有两份该大规则方案，当前均未选中，未擅自改写手机整个数据快照；已告知用户这些已导入数据不会随覆盖安装自动移除。安装日志在 `.artifacts/smart-yaml-rollback/`。

## 未发布：规则方案的文本与文件导入

- 规则页导入入口统一提供链接、文本、文件三种方式。文本支持系统粘贴按钮；文件通过系统选择器读取 UTF-8 / UTF-16 文本，支持常见 YAML、CONF、INI、JSON、TXT 扩展名，名称留空使用文件名或“导入的规则”。本地输入限制 8 MB，读取结束释放文件访问权限，不保存本地路径或书签。
- 复用既有解析器提取完整 Clash / Mihomo、Surge、subconverter 配置中的规则、策略组与支持的网络设置。内含节点不会导入订阅或节点列表；原节点名称转换为名称筛选，匹配塔台启用的节点。整理后的原文只保留规则模型，不存储 Proxy、MITM、Script 等无关源内容。复杂语法仍受既有解析器边界约束，不恢复 Smart YAML / MRS 展开试验。
- 本地配置引用的 HTTPS 规则列表继续走既有下载缓存与失败提示。文本/文件不设置来源 URL，链接刷新行为不变；导入保存复用取消、重置与代次校验，避免取消后异步写回。
- 验收：19 项导入/生命周期回归与 13 项本地化测试通过，含完整 Clash / Surge 配置的节点凭据剔除、UTF-8 / UTF-16 文件、持久化、已有节点/订阅不变，以及 Clash / Surge / sing-box 输出引用检查。模拟器三种方式切换与完整文本导入通过；首次文件按钮检查未等待切换完成，改为等待存在后通过。Xcode 在套件报告通过后停留于结果收集，已停止该收尾进程。Mac 系统文件选择器实际选取 Surge 配置后正确显示文件名并启用导入，临时草稿已取消。新增 13 项文案补齐 15 语言，Xcode 提取 978 项通过。手机与 Mac 1.0.13（51）覆盖安装、启动和严格签名通过；手机文件选择完整触控流程待用户试用。证据在 `.artifacts/scheme-local-import/`。

## 未发布：节点组自定义筛选（issue #27）

- 自定义节点组：两个候选策略入口共用创建页，在当前 NavigationStack 中编辑，入口位于所有可添加策略的末尾，无示例按钮。新建默认“包含关键词”，匹配方式菜单不再提供“匹配全部节点”，没有额外分段切换；关键词下方以小字提示 jp、hk 和任意匹配关系，不自动填入条件。 预览在未输入或已清空关键词时显示普通灰色提示“请添加关键词”，不再显示红色表达式无效警告；非空的无效正则仍显示错误。空表达式与无效正则禁止保存，删除最后一个关键词不会意外全选。已保存的 `.*` 仍按原始正则打开并保留语义。保存独立节点组后追加为候选，不改原首项默认策略；重名和保留名称禁止创建。用户创建的组单独持久化，继续支持改名、删除和另存方案；只将显式创建的节点组加入候选，不把业务规则组全部暴露为候选。
- 空白预览提示调整：关键词未输入或删除完后显示“请添加关键词”，以普通提示代替错误样式；非空非法正则仍报错。Mac 25 项筛选及本地化回归、1 项模拟器 UI 往返通过，新增文案补齐 15 语言，Xcode 提取 960 项通过。手机与 Mac 1.0.13（51）覆盖安装、启动和严格签名验证通过，证据在 `.artifacts/node-empty-prompt/`。
- 本轮关键词提示调整：Mac 25 项定向测试通过，覆盖默认包含关键词、jp/hk 匹配 JPN/HKG、关键词内的正则符号按字面处理，以及历史正则不被改写。新增提示补齐 15 语言，Xcode 提取 959 项通过。手机与 Mac 1.0.13（51）均已覆盖安装、启动并通过严格签名验证。Mac 实际界面核对默认值、菜单移除全选、提示布局及取消草稿通过，未保存测试修改。模拟器首次启动因系统 Accessibility 加载超时，重启后 1 项 UI 测试通过：确认默认包含关键词、无全选入口、提示可见，添加 hk 后保存重开保留，删除最后一项禁止保存。验收结果保留在 `.artifacts/node-keyword-hint/`。
- 前次菜单调整验收：Mac 25 项定向测试、958 项本地化提取与模拟器 UI 往返通过，两端 1.0.13（51）覆盖安装、启动及严格签名通过。该轮“匹配全部节点”菜单已按最新反馈撤去；历史证据在 `.artifacts/custom-node-match-style/`。
- 前次全选范围验收：Mac 24 项定向测试通过，包含全选组持久化、排除取消勾选节点与停用订阅、自动加入后续新增节点，以及所有完整配置目标的引用校验和 Clash / Surge / sing-box 的实际组成员核对。Mac 实际核对入口位于末尾、无示例、默认匹配 109 / 109、切到空名称筛选后不能保存；测试草稿已取消。新增 3 项文案补齐 15 语言，Xcode 提取 957 项通过。手机与 Mac 均已覆盖安装、启动 1.0.13（51），严格签名通过。证据在 `.artifacts/custom-node-all/`。
- 前一轮创建功能验收：新增模型回归先复现自定义组无法物化，修复后 Mac 95 项定向测试通过，含持久化、候选引用顺序、编辑、改名、删除、另存方案和所有完整配置目标的引用校验；额外检查 Clash / Surge / sing-box 的实际生成成员。模拟器创建英国示例→保存候选→重开节点组→删除关键词→保存重开流程通过。Mac 实际打开空白创建页、示例填充、预览及返回取消通过，未保存测试内容。新增 12 项文案补齐 15 种语言，Xcode 提取 954 项通过。证据在 `.artifacts/custom-node-groups/`。
- 本轮安装状态：Mac 1.0.13（51）已覆盖安装、启动并通过严格签名验证。手机重新连接后，本轮 1.0.13（51）已覆盖安装并启动，严格签名验证通过；完整实体手机触控流程待用户验收。未递增版本、提交或上传。

- 节点组设置与筛选编辑已合并成同一页，只保留一次保存。普通关键词使用可直接输入、删除的圆角标签，按文字宽度自动换行，视觉高度收紧但保留 44 点触控高度。“＋ 添加关键词”固定在标签下方左侧，不参与自动换行；大小写与正则切换直接展示，添加关键词与下方选项用分隔线及独立触控行分开。只有一个节点名称匹配区，移除整条筛选的新增、启停和删除入口；历史多个表达式仍保留各自的来源绑定，不为合并卡片而改写匹配语义。预览紧接编辑区，恢复方案默认值置于预览后。候选策略中新增“自定义节点筛选”入口，入口位于可添加策略的末尾，已移除示例；默认匹配方式为“匹配全部节点”，名称自动填入且可修改。
- 补充节点组保存修复：默认方案按候选策略引用自动补出的地区/手动组，过去在应用自定义覆盖之后才创建，导致已保存的关键词、策略类型和改名被忽略；上游声明的组不受影响。现在补出原始定义后立即应用该组覆盖，按需继续补齐引用，且不会重复覆盖已有组。已保存的删除直接生效，无需重新编辑。列表中的节点组摘要与编辑页共用策略类型名称（例如“延迟优选”），消除旧摘要“自动选择”的不一致。
- 预览基于已启用且勾选的本地节点，多个筛选合并后去重计数，只展示前 30 项；来源限制、额外排除条件与目标协议仍影响最终候选。后台延迟匹配，总匹配耗时限制 1 秒，无效/超时输入不能保存。任务由页面持有，不依赖下方预览是否滚动到屏幕内；输入后不按回车也会写入草稿。
- 自定义筛选持久化于方案覆盖，不修改内置快照；修改表达式和组名仍保留来源绑定。跨客户端转换保留来源排除条件，避免本地物化时重新选入已排除节点。普通 HK 本身就匹配 HKG，已在 Mac 的真实名称预览中核对。
- 上一轮 Mac 与 iOS 各 20 项定向回归通过，含 7 项筛选/合并预览与 13 项本地化测试；模拟器完整 UI 测试覆盖直接编辑标签、新增含空格/特殊字符标签、不按回车保存、重启读取、删除、正则报错取消与恢复默认。Mac 实际验证布局、自动换行、新增/编辑/删除及取消草稿，临时内容已清理。Xcode 提取 942 项通过，新增 5 项补齐 15 语言。前一轮全量基线为两端各 1,067 项 XCTest、82 项 Swift Testing 零失败。
- 紧凑布局本轮：Mac 20 项定向测试与 942 项本地化提取通过；iPhone 17 Pro 模拟器 UI 往返测试通过，新增检查预览无需滚动即可见、只有一个添加关键词入口且没有“添加节点筛选”。实际截图确认标签按文字宽度排列、加号靠左。测试替换文本改为明确选中文字，避免缩窄后点击中央使光标落在原文内部的测试假设。Mac 实际新增与取消通过，临时内容未保存。
- 补充组修复验收：旧版模型测试复现关键词恢复、策略类型重置与改名丢失；修复后 Mac 93 项定向测试通过，包含补充组重开、持久化、改名以及 Clash / Surge / sing-box 导出成员验证。模拟器两条完整 UI 流程通过：默认方案添加地区候选→自动补组→删除→保存→原页立即重开，以及上游声明组的标签编辑、重启读取、正则校验、取消与恢复默认；同步核对摘要名称一致和选项直接展示。Mac 实际界面确认展开布局与名称一致，未保存临时修改。本地化提取 942 项通过。最新两端构建已安装、启动并通过严格签名验证，证据在 `.artifacts/node-filter-save-fix/`。
- 此前紧凑布局与保存修复版本已在手机与电脑安装并启动 1.0.13（51），严格签名检查通过；实体手机完整触控流程由用户继续验收，不把安装启动计作真机 UI 自动化通过。未提交、递增版本、上传或发布。本次紧凑布局的构建、测试与安装证据在本机 `.artifacts/node-filter-compact/`，此前证据在 `.artifacts/node-filter-chips/` 与 `.artifacts/node-filter-ui/`。

## 未发布：“我的规则集”文本编辑与兼容提示

- 本地规则保存与物化改用共同条件解析器，完整保留 AND / OR / NOT、引号正则和参数。显式 DIRECT / REJECT 等内置动作随每条规则保留；普通粘贴策略名按本地规则集的既有绑定方式替换，并在编辑界面解释。无效规则显示原始行号并阻止覆盖，单行修改保留其他行、注释及 Windows 换行。
- 按最新反馈移除“条件预览与编辑”、逐条表单及其导航，只保留上方规则文本。文本下方直接显示“客户端兼容性”，汇总 Mihomo / Surge iOS 与 Mac / sing-box / Stash 能否完整转换全部规则；无效行提示原始行号，空白不宣称支持，远程链接提示以导出页为准。输入后延迟在后台检查；不下载或展开远程规则，不恢复已回退的 MRS 展开。
- 文本界面简化验收：8 项规则回归与 13 项本地化测试通过，包含整份文本兼容性汇总、混合不支持规则、无效行及远程链接。模拟器新建逻辑规则→查看下方兼容提示→保存→重开→重启读取通过，原始文本完全一致，无逐条编辑入口。测试套件已报告通过，xcodebuild 结果收集阶段超过两分钟未退出，已停止挂起的收尾进程，日志保留。新增 5 项文案补齐 15 语言，Xcode 提取 965 项通过。手机与 Mac 1.0.13（51）均已覆盖安装、启动并通过严格签名检查，未发布；证据在 `.artifacts/rule-text-only/`。
- 此前表单版本验收（表单现已移除）：Mac 实际验证中发现第三层 sheet 会关闭规则集草稿，改为同一个 NavigationStack 内逐层编辑。新建、嵌套端口修改、切换原文、保存重开、无效行阻止保存与放弃草稿已通过实际 UI 操作；临时验收规则已清理。iOS 模拟器 UI 自动化覆盖新建→修改→保存→重开→重启读取，已通过。
- 全目标回归发现 Loon / Shadowrocket 旧路径会将未转换的逻辑子条件透传，现明确报不兼容；拒绝规则阻止输出。未声称补齐这两种客户端的逻辑规则方言。
- Mac 全量 1,061 项 XCTest（33 跳过）、iOS 全量 1,061 项 XCTest（3 跳过），两端各 82 项 Swift Testing，均零失败。本地规则持久化后生成的三份小配置通过 Mihomo 1.19.27、Surge CLI、sing-box 1.14.0 语法检查；Mihomo / sing-box 本地回环各四种流量验证仅 OpenAI UDP 443 拒绝，TCP 443、其他端口/域名仍选择 OpenAI。Surge 未完成实际流量验收。本地化提取 911 项通过，新增 44 项文案补齐 15 语言。证据位于本机 `.artifacts/rule-ui/`。
- 实体 iPhone 已覆盖安装并启动 1.0.13（51）；真机 UI runner 在建立连接前以 code 74 退出，尚未执行界面操作，不能算真机 UI 通过。测试后已恢复启动正常用户数据的 App；模拟器 UI 使用独立临时数据。Mac 最终开发包已覆盖安装并启动，签名验证通过。未提交、递增版本、上传或发布。

## 未发布：Surge / Clash 分流规则兼容修复

- 普通 DIRECT / REJECT / REJECT-DROP 不再被规则组筛选或文本编辑器误删。新增递归 AND / OR / NOT、Surge ↔ Mihomo 协议/来源/端口/进程写法转换，保留引号正则、普通规则和 FINAL 参数；不可转换规则有提示，拒绝条件与兜底条件不能表达时阻止导出。用户要求的自动 no-resolve 设计保持。
- 保存 Clash provider 的 behavior / format / interval；内联、裸域名/CIDR、flow payload、远程引用与展开均按资源语义处理。补齐 Loon Remote Rule 与 QuanX 资源域名别名。Stash URL-REGEX 和 LAN Stash/Mihomo 路由分开。认证 header / exclude-filter provider 显式不支持，避免静默丢失。
- 本地 SubConverter 0.9.0 与 SubStore 2.38.4 各路径对比；复用 113 份配置、17 份资源和授权的 17 份订阅缓存（1,205 节点、546 份产物）。三核心检查 256 份非空输出，254 通过；Mihomo 1.19.27 的 REMATCH-NAME 版本限制、macOS UID 平台限制单列。Mihomo / sing-box loopback 各四种流量实测通过：仅 OpenAI UDP 443 拒绝，TCP 443、其他端口/域名继续选择 OpenAI。Surge 为 CLI 语法验证，不代表实际手机流量验收。
- Mac 全量 1,056 项 XCTest（33 跳过）与 81 项 Swift Testing 零失败；最终资源参数补修另有 15 项定向回归通过。本地化 Xcode 提取 867 项通过，新增文案覆盖 15 语言。iOS 全量 1054 项 XCTest（3 跳过）与 82 项 Swift Testing，零失败。
- Mac 与实体 iPhone 均已覆盖安装并启动最新 1.0.13（51）开发版，Mac 主窗口已确认；签名验证通过。未提交、递增版本、上传或发布。旧导入方案需重新导入/保存原文再导出，已经丢失的模型数据不能靠刷新远程规则还原。
- 完整修复范围、参考工具差异和剩余边界见 [兼容报告](RULE_ROUTING_COMPATIBILITY.md)。本机证据位于 `.artifacts/routing-fix/`，原 `.artifacts/rule-support-audit/report.md` 已覆盖为更新报告，修改前输出仍保留。

## 未发布：subconverter 单独数字检测间隔

- 按 [subconverter 策略组语法](https://github.com/tindy2013/subconverter/blob/master/README-cn.md#配置文件)，只在 `url-test`、`fallback`、`load-balance` 的测试 URL 后末尾字段解析 `interval[,timeout][,tolerance]`。单独数字与逗号形式均能保留检测间隔；不针对 180 写死，成员位置和 select 组内的数字、数字逗号正则保持筛选用途。
- 使用旧实现先复现间隔缺失与数字成员误判；新增 5 项回归覆盖多组类型、不同间隔、可选字段、文本编辑、各完整配置客户端输出及 Clash/Mihomo、Surge 候选成员。上游 33 份 ACL4SSR 配置的 75 个定时策略组间隔逐项核对通过，其中 6 个单独数字参数不再丢失。证据在本机 `.artifacts/timing-fix/`。
- 旧方案需重新导入或重新保存原配置文本，再重新导出，才能更新已经保存的错误解析结果；仅刷新规则列表不会重新解析策略组。
- iOS 全量 1,108 通过、3 跳过、零失败；Mac 全量 1,075 通过、33 跳过，另 3 项 loopback 启动失败，停止两端并行测试后该套件 28 项复跑全部通过（共用固定端口 65172）。最新开发签名包已覆盖安装 Mac 并确认主窗口正常，实体 iPhone 已覆盖安装，解锁后重试启动成功。两端仍为 1.0.13（51），未发布；安装启动不代替真实客户端的间隔计时验收。

## 未发布：ACL4SSR 本地路径配置导入

- 导入 ACL4SSR GitHub 配置链接时，`rules/ACL4SSR/Clash/*.list`（含子目录）会解析到官方仓库的 HTTPS 文件地址，沿用规则下载与本机缓存；来源固定到提交或分支时保留该版本。粘贴配置使用官方 master，未知本地路径明确拒绝，避免静默丢失规则。
- 官方 `ACL4SSR.ini` 修复前仅保留 2 项声明、0 个文件引用；修复后保留全部 14 项声明和 12 个文件引用。上游 33 份配置的声明数量检查均通过。此前已导入且丢失引用的方案需要重新导入。
- 新增 5 项回归覆盖 GitHub 链接导入、12 个列表下载缓存、持久化重读、各完整配置客户端输出，以及固定版本、文本编辑和无效路径。下载回归使用模拟 HTTP 响应；另用真实上游配置执行解析检查。Mac 全量 1,073 通过、33 跳过；iOS 全量 1,103 通过、3 跳过，均零失败。证据在本机 `.artifacts/acl-import-fix/`。
- 最新模拟器包已安装并启动至规则页；窗口自动化返回 `elementHasNoFrame` / `timeoutReached` / `noWindowsAvailable`，实际粘贴链接并下载的 UI 验收尚未完成。
- 手机重新连接后，最新开发签名包已覆盖安装并启动实体 iPhone；Mac 最新开发签名包已覆盖安装至 `/Applications/塔台.app` 并确认主窗口正常，安装二进制与本轮构建一致。两端均为 1.0.13（51），未发布；实际真机链接导入行为仍待验收。安装日志保留本机 `.artifacts/acl-import-fix/`。

## 未发布：局域网共享开关按钮回位

- 关闭共享会同步移除上方链接区域，按钮的按压回弹却继续使用旧位置，导致按钮经过「更换访问密钥」甚至卡片外部。仅在共享开关按钮增加 `geometryGroup()`，隔离外层布局位移与内部按压动画；保留原有按压反馈和服务生命周期。
- iOS 模拟器实际触摸录屏复现旧问题，修复后连续两轮开启/关闭的逐帧检查未再出现按钮越界或重叠。录屏保留本机 `.artifacts/lan-button-motion/`。1.0.13（51）开发包已覆盖安装并启动实体 iPhone；手机触摸动画仍待真机体验确认，未发布。
- 最终代码 iOS 全量测试 1,098 通过、3 跳过、零失败，`git diff --check` 通过。

## 1.0.13（51）发布状态

- 包含下方性能与导出布局、测速按钮动画、sing-box 中文模式/DNS 和 iPhone LAN 后台续时改动。
- 发布前完整回归：iOS 1,098 通过、3 跳过；Mac 1,068 通过、33 跳过，均零失败。sing-box 1.14.0 实核 loopback 的模式、DNS 故障、全局选 A/B 出口检查通过；本地化提取 865 项及发布脚本测试通过。ACL4SSR 上游快照最新，77 个远程产物摘要验证通过。
- 发布代码提交 `a156f78`；正式版 Xcode 26.6 分别归档并成功上传 iPhone / Mac TestFlight。App Store Connect 网页登录已过期，Apple 后续处理状态尚未确认；未手动分配内外测群组、提交 Beta/App Review 或上架。
- GitHub `v1.0.13` 已公开；Mac DMG 已通过双架构、Developer ID 签名、stapler、公证、Gatekeeper、DMG 校验及回下载 SHA-256 检查，正式包实际启动和导出页布局检查通过。README 下载与 Homebrew tap 更新；brew style 与实际 brew upgrade 通过，brew audit 被本机 macOS Beta 对默认 Xcode 版本的检查阻止，未修改全局工具链。iPhone 1.0.13（51）开发签名包已覆盖安装并启动。
- 下方分项记录保留开发时验收边界；已随本版发布，但真实 iPhone 后台共享时长及 sing-box 客户端内端到端行为仍不以模拟器/loopback 测试代替。

## 1.0.13：iPhone / Mac 切页与地图滚动性能

- 导出页两端统一为客户端选择→导出内容（支持时）→转换状态→协议筛选→导入说明/配置预览。只调整视图顺序，保留筛选更新、异步准备及底部固定导出行为；最新开发版已构建并覆盖安装、启动手机，已随 1.0.13 发布。
- 测速胶囊补充仅在开始/结束时触发的局部伸缩和内容淡入淡出，保持右边缘锚定；等宽数字预留总数宽度，批量进度不反复撑动按钮。减少动态效果时禁用伸缩，测速流程和地图动画不变。动画相关 6 项测试及本地化提取通过；Mac 实际启动测速与自然完成状态检查通过，最终开发包已在手机和 Mac 覆盖安装并启动；动画流畅度仍需用户在手机体验。
- 两端共用配置请求输入快照缓存、节点筛选/订阅计数/地区统计缓存；同一节点的内容、订阅启用状态、协议过滤、规则及设置变化均重新准备，未变化的切页复用结果。订阅和规则卡片改为按需创建。
- 地图输入未变化时复用地区分组及颜色准备结果，避免父视图更新重复刷新地图；操作期间冻结标签时跳过重复避让计算。地图绘制方式、缩放手势、弹簧参数、配色及展开动画保持原样。
- Mac Debug 合成基准：5,000 节点连续 10 次已缓存配置查询由 110.782ms 降至 0.057ms；1,000 节点由 23.487ms 降至 0.054ms。这是模型查询耗时，不是切页延迟、滚动帧率或 GPU 性能，不能换算为整页速度提升。
- Mac 全量 1,068 通过、33 跳过；iOS 模拟器 1,098 通过、3 跳过，均零失败。另有地图地区收起后的订阅流量布局 UI 回归通过。Mac 实际检查地区展开/放大/恢复视角、上下滚动及订阅→规则→导出→订阅，未见卡片错位或闪退；工具操作不代表稳定帧率。
- 最新 1.0.12 (50) 开发版已覆盖安装并启动手机和 Mac，待用户体验手机地图展开后的滚动。未发布。基准、测试及安装日志保留本机 `.artifacts/performance-fix/`。

## 1.0.13：sing-box 中文模式与全局节点选择

- 模式标识改为「规则判定 / 全局代理 / 直接连接」，默认规则判定；文件名不变。全局模式使用独立 selector，默认覆盖全部可用节点的自动选择，支持手动选择具体节点；对应 DNS 使用复制的原解析器配置并经该 selector 出站，规则模式的 DNS 路径独立。
- 保留用户同名组并给新增组加数字后缀；全局候选不含 DIRECT 或业务组，空节点继续拒绝。三个中文字符串是稳定的导出配置标识，不按塔台界面语言翻译。
- 新回归在旧实现复现三个断言失败；真实 sing-box 1.14.0 检查六份合成导出配置通过，loopback 实测先选 A 再选 B，普通 HTTP 与 DNS 同时换出口；直接连接不经过代理，标准/严格 DNS 故障无直连回退通过。未在真实 sing-box iPhone App 中导入实测。
- iOS 全量 1034 项 XCTest（3 跳过）与 64 项 Swift Testing 通过。最新真机签名包构建及签名校验通过；手机连接后，1.0.12 (50) 已覆盖安装并启动，未发布。实际 iPhone sing-box 重新导入后的行为仍待验证。

## 1.0.13：iPhone 局域网共享后台续时

- 1.0.9 引入的 scenePhase.background 立即停止 LAN 已移除；在 inactive 阶段申请系统后台执行时间，系统要求到期才关闭，没有额外固定倒计时。Mac 保持原行为；DirectImportService 的 3 分钟临时导入时限不变。
- 回到前台释放后台断言但保留服务和链接；显式停止、重置、启动失败均释放断言，旧到期回调不能关闭新的共享会话。iOS 不保证固定时长或无限后台运行。
- 共享相关 33 项测试通过；iOS 全量 1034 项 XCTest（3 项环境跳过）和 62 项 Swift Testing 通过。已覆盖安装并启动连接的 iPhone 开发版；真机 UI runner 两次在建立测试连接前退出（code 74），因此后台实际可用时长仍待真机验收。模拟器 UI 探针也未取得共享 URL，不能算端到端通过；临时探针仅保留在本机 .artifacts，未纳入正式测试套件。本轮未发布。

## 1.0.13：sing-box MT 模式与 DNS（#18 / #19）

- 官方 sing-box 导出增加 Rule / Global / Direct，默认 Rule；DNS 接管先于模式分流，普通目标通过 DNS 规则解析，节点启动解析独立。默认方案、自定义方案和 SRS 开关均覆盖；Hiddify 保持原行为。
- 标准保护按本机域名规则顺序分流 DNS；纯直连组使用直连解析，混合组保守使用代理。严格保护的 Rule 查询全部经代理，失败不回退直连；Direct 模式明确允许直连。跟随方案不强制所有 53 端口或 strict_route。递归验证代理组无法到达 DIRECT，必要时生成无直连候选的 Tower Proxy 自动组；无节点的 Global 拒绝连接。
- 10 项新增回归覆盖模式优先级、DNS 域名重叠、空节点、间接 DIRECT、名称冲突、严格/跟随设置和 SRS/内联一致性。先在旧实现复现 13 个断言失败，再修复。Mac 全量 1030 项 XCTest（33 跳过）及 62 项 Swift Testing 通过，最后生成器整理后的 10 项定向测试通过；iOS 全量 1030 项 XCTest（3 跳过）及 62 项 Swift Testing 通过，均零失败。
- 官方 sing-box 1.14.0 对 5 份真实生成的合成配置检查通过；`Scripts/test_singbox_modes.py` 保留生成的规则与代理组，在 loopback 替换上游传输，实际验证模式切换、域名优先级、拒绝、原组默认 DIRECT 以及代理故障时没有直连 DNS 请求。该测试未修改系统代理/TUN，也不代替 Apple NetworkExtension 或应用自带 DoH 的整机泄露测试。
- iPhone / Mac 开发版已覆盖安装并启动，仍为 1.0.12（50）；已有客户端需重新导出配置。未递增版本、提交、发布或回复 issue。测试日志在本地 `.artifacts/singbox-modes/`。

## 1.0.12（50）发布状态

- 包含 Surge 聚合节点订阅、3 分钟临时导入、Mac 规则重命名闪退修复及 Surge IP 规则 no-resolve 补修。
- Mac 核心测试 1049 项通过、33 项环境跳过；iOS 核心测试 1079 项通过、3 项环境跳过，均零失败；本地化提取 865 项通过，发布脚本测试通过，ACL4SSR 为上游最新且 77 个远程产物校验通过。
- 发布代码提交 `3383f19`，正式版 Xcode 26.6 分别归档并上传 iPhone / Mac TestFlight；两端均已处理完成。未手动分配内外测群组或提交 Beta 审核，现有内部组自动分发设置保持原样。
- GitHub `v1.0.12` 已公开，Developer ID 公证 Mac DMG 已通过 arm64 / x86_64 双架构、签名、stapler、Gatekeeper 及回下载 SHA-256 校验，发布版已在本机打开。README 下载链接及 Homebrew tap 同步更新，`brew style` 和实际 `brew upgrade` 通过；`brew audit` 被本机 macOS Beta 对默认 Xcode 版本的检查阻止，未修改全局工具链。

## Surge 网段规则 DNS 警告补修（1.0.12）

- 旧修复只给 GEOIP 补 no-resolve，Self-Configuration 等方案内联的 IPv4 / IPv6 网段仍可能出现在后续域名规则之前，触发 Surge 的额外 DNS 查询警告。
- Surge / Surge Mac 导出对内联 IP-CIDR、IP-CIDR6、IP6-CIDR、IP-ASN 补 no-resolve；保留已有标志、策略组和规则顺序，其他客户端维持原行为。未解析域名跳过这些 IP 规则，已知 IP 仍可匹配；不把此修改表述为托管 HTTP 400 修复。
- 新增回归先复现失败再修复，覆盖两端和其他目标的生成；Mac 核心测试 1049 项通过、33 项环境跳过、零失败。用户原配置及补齐标志后的本地副本均通过 Surge CLI 语法检查；该检查不能替代 iPhone 端实际导入验证。iPhone / Mac 开发版已安装启动，版本仍为 1.0.11 (49)，未发布。

## 临时导入链接有效期（1.0.12）

- 按用户要求，所有 DirectImportService 本机临时交接统一由 45 秒延长为 3 分钟（180 秒），包括一键导入和 iPhone 的 Surge 聚合节点链接。
- iPhone 的系统后台执行额度到期仍会提前关闭服务；3 分钟是塔台的自动关闭时限，不是系统保证的后台运行时长。Mac 持续局域网订阅的生命周期不受此次修改影响。
- 界面提示、15 种语言文案和相关说明同步更新；旧本地化条目保留。Mac 导入服务及本地化相关 41 项测试通过，Xcode 本地化提取通过（865 项）。iPhone 开发版已覆盖安装并启动，Mac 开发版已覆盖安装；本轮未发布。

## Mac 规则重命名闪退修复（1.0.12）

- 1.0.11 (49) 在规则定制中点击名称可触发 `No Observable object of type AppModel found`。本机用独立测试数据复现，崩溃发生在嵌套名称编辑面板创建时，尚未执行保存。
- `RuleGroupIdentityEditor` 改为显式接收父级模型，沿用“另存为新方案”的模型传递方式；重命名、引用更新与排序逻辑不变。
- Mac 实际鼠标操作已验证打开、取消、保存、重启及再次打开名称面板。Mac 全量 1029 项 XCTest（33 项环境跳过）及 52 项 Swift Testing 通过。Mac 自动 UI runner 启动失败，不能算通过。新增 iPhone 模拟器 UI 回归的打开、取消、保存及重启后列表名称断言通过，最后再次打开面板未找到输入框；无对应崩溃日志，需继续核对自动点击/弹窗时序。重试未进入测试执行，已停止，不能宣称 UI 全通过。实体 iPhone 已覆盖安装开发版并成功启动。本轮不递增版本或发布。

## Surge 聚合节点导出（1.0.12）

- 对应 GitHub #21：Surge / Surge Mac 增加“仅节点”，主按钮为“复制聚合的订阅链接”；完整配置导入保持原行为，客户端图标选择不变。
- 只聚合已启用、未排除且目标可表达的节点，使用 Surge `policy-path` 原生策略行，不包含规则、策略组或原始订阅 URL。WireGuard 依赖独立配置节，仍需完整配置。
- Mac 复制固定目标的前台 LAN 链接，`content=nodesOnly` 固定资源语义；切换客户端、规则、导出模式后不会变成完整配置，源启用和协议筛选变化可通过原链接更新。首次需局域网连接并保持塔台运行。
- iPhone 复制 127.0.0.1 临时链接，使用最多 3 分钟的临时交接（系统后台额度到期可能提前关闭），避免切换 Surge 时普通 LAN 服务立即关闭。节点 URL 按目标隔离，更新节点需重新复制后到 Surge 刷新；不是长期后台托管。
- 已核对 Surge Mac 的“策略 → 添加策略组 → 下一步 → 同时包含外部策略 → URL 或本地路径”入口，未保存用户配置；实际复制的 3 条演示节点经 HTTP 回读、模式切换和协议筛选验证，内联到校验配置后通过官方 CLI。CLI 对外部资源正负样例都报告 OK，不能把该检查算作外部订阅实际加载或连通验证。
- iOS / Mac 全量分别通过 1029 项 XCTest（环境跳过 3 / 33 项）及 52 项 Swift Testing。手机模拟器的模式切换、复制反馈和退后台返回 UI 回归通过。15 种语言提取检查通过。实体 iPhone 已覆盖安装最新开发代码，锁屏阻止启动，真机导入待验证。本轮未发布 TestFlight 或 GitHub Release。


## 版本与工作区

- **1.0.8 (46)** 发布准备：新版四页使用引导、设置内重看入口、AI 平台机器人示例；优化剪贴板异步读取与页面切换更新范围；修复地图地区节点收起时订阅流量信息错位。全量 1011 项 XCTest（3 跳过、0 失败）及 49 项 Swift Testing 通过，833 项界面文案本地化提取通过；内置规则为最新且 77 个远程产物回读通过。实体 iPhone 已覆盖安装并启动 1.0.8 (46) 优化 Debug。5 项引导、地图收起及剪贴板关键交互回归通过。发布提交 `17243b4` 已推送；M2 正式版 Xcode 26.6 Release 归档及上传成功，归档版本、构建号和 Bundle ID 已核对。App Store Connect 已出现 1.0.8 (46)，当前正在处理，测试群组与审核状态待确认。

- **1.0.7 (45)** 发布提交 `9839fec` 已推送；正式版 Xcode 26.6 Release 归档与上传成功，已核对归档版本、构建号和 Bundle ID。Apple 已处理至内部可测试状态，现有内部组显示“正在测试”，中文测试说明已保存；本轮未提交外部 Beta 审核。开发版已在实体 iPhone 覆盖安装并启动。

- **1.0.7 (43)** 已于 2026-09-06 在远程 Mac mini M2 使用正式版 Xcode 26.6 完成归档和上传，发布提交 `56d2fc9`，脚本退出码 0；归档版本已核对。Apple 已处理完成；外部审核提交返回 HTTP 422 / `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING`，已联系 Apple 支持，外部测试尚未恢复。
- build 43 修复 Self-Configuration 下载后缺少刷新按钮的问题；更新内置 ACL4SSR 至 `f7c4233b2bc706c89668753b18a9f899d7e9f9bf`，77 个 MRS/SRS 产物已回读校验。测试 937 通过、1 跳过、0 失败；本机未连接可用 iPhone，尚未真机安装。
- 1.0.6 (43) 上传被 Apple 以预发布通道关闭拒绝，改用 1.0.7 (43)。旧构建当前显示已失效，原因尚未确认。对外更新日志：修复一些bug。

- **1.0.6 (42)** 已于 2026-09-05 在家中 Mac mini M2 使用正式版 Xcode 26.6 完成 Release 归档并上传 App Store Connect，发布提交 `37c07ce`。归档、上传均成功，脚本退出码为 0；归档版本、Bundle ID、签名及团队匹配已核验。
- App Store Connect 已完成 build 42 的处理并批准外部测试；已关联现有内部和外部测试群组，外部群组显示「正在测试」，中文测试说明已保存。
- build 42 简化设置入口，拆分 iCloud 与重置；新执行的规则排序同时更新编辑文本和导出优先级，旧快照的纯展示排序不会自动改变路由，FINAL 始终最后。
- build 42 修复 sing-box 的 YAML null、WireGuard endpoint、Snell v5 映射及 TLS SOCKS 跳过；规则下载显式使用独立 DNS 解析；sing-box / Hiddify 保留方案 DNS、端口和 IPv6 设置。已有客户端配置需要重新导出。
- build 41 引入的 Clash Mi / Karing、客户端筛选与局域网统一排序、代理集合继续保留；客户端选择不再强制居中，边缘卡片以短动画最小滚动至完整可见。
- 内置 ACL4SSR 仍为上游最新提交 `864e3f3856347f67f4125505365295a7cc0490e7`，MRS/SRS 固定到不可变产物提交。
- build 42 发布验证：TowerTests 936 通过、0 失败、1 跳过；12 个客户端生成回归、180 次 sing-box 内核检查、独立冷启动/缓存/失败重试测试通过；77 个远程规则产物全量回读通过。本机以全新目录签名构建，已核对手机安装记录为 1.0.6 (42) 并成功启动。

## 当前未发布改动

- 地图地区节点展开再收起时，下方订阅卡片的流量文字、进度条曾与卡片移动不同步。仅在 `SubscriptionCard` 恢复 `geometryGroup()`，让内部元素随卡片整体移动，通用卡片不恢复全局分组。新增对应 UI 回归：模拟器 1 项通过、0 失败，并核对收起过程连续帧，未见流量区偏移。证据位于本地 `.artifacts/collapse-2026-09-07/`。1.0.7 (45) 优化 Debug 已签名安装到实体 iPhone 并成功启动，使用正常用户数据；真机 UI 测试 runner 两次在连接前以 code 74 退出，不能算作真机动画验证通过。本次修复未提交、归档或上传。

- 修复 Shadowrocket 实际 YAML 导出遗漏 AnyTLS/SOCKS5/HTTP Reality、SS 原生 TLS，以及 SOCKS5/HTTP SNI/ALPN/证书验证参数。旧代码回归18断言失败；全量968项XCTest（2跳过、0失败）和39项Swift Testing通过。实体iPhone已覆盖安装，命令启动被拒绝，待手动确认。协议实验覆盖13种协议、25个组合，关键4条实际导出参数外网请求通过；完整客户端验收另记本地报告。

- 补修 Clash VMess HTTP 数组 Host/path 原样输出的问题。真实旧配置字段连接失败，新生成字段连接通过；966 项 XCTest（1 跳过、0 失败）和 39 项 Swift Testing 通过。此补丁安装时未发现唯一可用实体 iPhone，最新补丁尚未覆盖安装。

- QuanX 官方 News 对照修复：补 SOCKS5 TLS、HTTP SNI、ALPN 与各 TLS 协议 Reality 字段；支持 VMess 明文 HTTP；补 ip-asn/host-wildcard 规则导入。全量 964 项 XCTest（1 跳过、0 失败）和 39 项 Swift Testing 通过；实体 iPhone 已覆盖安装并成功启动。另有 11 节点真实服务端测试通过独立内核外网请求，QuanX 加载与连接待用户测试。

- 修复 Quantumult X 本地地区延迟组只写 server-tag-regex、实际未载入的问题：导入方案和内置预设均明确列出过滤后的节点 tag，不额外包含 direct。远程代理集合仍保留资源筛选。

- 策略兼容改为导出时降级：不支持的 fallback / load-balance 转延迟优选；条件组转同名手动组并保留默认策略（无默认时保留候选）；relay / 未知类型转手动选择；不支持的附加参数忽略并提示。原始方案不改写，原生能力优先。类型或参数不兼容不再阻止导出；循环、重复名称和缺失引用仍做有效性校验。

- 修复 Loon 导入 Surge `DOMAIN-SET` 语法错误：旧方案中的域名列表也参与下载，非 Surge 目标展开为 DOMAIN / DOMAIN-SUFFIX；缺少缓存时提示刷新，避免漏规则。Surge 优先规则集模式保留原生引用。已有方案需主动刷新一次，再重新导出。回归：957 个 XCTest（1 跳过，0 失败）及 39 个 Swift Testing 测试通过。

- 支持导入 Surge Smart 组及 `include-other-group` / `include-all-proxies` / `policy-path` 节点池和正则筛选；规则模板的外部节点地址不主动获取，节点继续由塔台中选择的订阅提供。Surge / Egern 保留各自原生 `smart`；其他配置客户端将 Smart 降级为延迟优选并合并提示，保存的原方案不变。不支持的 `no-alert` 通知参数忽略并提示，不阻止导出。
- Smart 没有匹配节点时保留同名拒绝策略并提示；不存在的策略引用阻止导出。修复 `DOMAIN-SET` 的 `extended-matching` 被误识别为策略名。Smart 在策略编辑、持久化及规范文本中保留类型。
- 更正此前安装记录：Xcode 27 的 CoreDevice 列表含模拟器，旧脚本误选模拟器并安装了旧产物，先前“真机已安装修复版”的结论不成立。已增加实体设备交叉校验，强制 iOS 真机目标和 SDK；实体 iPhone 已重新覆盖安装并通过命令成功启动，设备安装记录复核为 1.0.7 (43)；实际 Surge 导出仍待用户确认。
- 验证：942 个测试通过、1 跳过、0 失败；本地化提取检查通过。已用反馈中的 Surge-Mac 模板生成配置并通过 Surge 官方 CLI `--check`（OK）。含保存原文的旧 Surge 方案在加载时自动恢复被旧解析器丢弃的 Smart 图，保留方案标识、元数据和独立自定义覆盖；“刷新”仍只更新规则列表。未保存原文的旧方案需要重新导入。

- 策略兼容性扩展：新增 fallback、带算法的 loadBalance、网络条件、独立代理链及未知类型；原生 QX / Egern / sing-box 方案导入与结构化 YAML 解析，保留来源、参数及规范文本元数据。旧方案从保留原文恢复丢失的策略语义，用户覆盖保持独立。
- 导出前校验重复名称、未知引用、循环、无效表达式及空组；空组以同名拒绝策略保留并提示。QX 资源标签、Clash provider、Egern 来源通过 URL 哈希匹配已启用订阅，本地与代理集合均限制到匹配来源，不自动获取新订阅。
- 同格式支持 Surge / QX / Egern 网络条件，以及 Loon 独立代理链；无法表达的跨格式规则、类型和参数明确拒绝。YAML anchors/tags 等未实现语法明确报错；不声称支持任意配置全文。

- 本轮验收：988 项通过（含 1 项本地真实模板审计）、1 跳过、0 失败；本地化 759 项提取检查通过。实际生成的 Mihomo fallback/轮询/哈希配置通过检查器与隔离运行；反馈 Surge 模板通过官方 CLI。实体 iPhone 已覆盖安装并成功启动 1.0.7 (43)。其他客户端逐项界面实测仍未全部完成，不等同于全平台实机验收。

## 界面与流程审核修复（2026-09-07）

- 本轮审核项均已修复：异步导入/规则保存取消与重置隔离、扫码权限及失败重试、手动节点键盘完成、保存型表单草稿保护、全屏复制反馈、空导出状态、iCloud 删除确认及互斥、直接导入失败时使用原配置快照。
- 添加方式切换淡入淡出、规则卡片按压反馈、Reduce Motion；补充隐藏批量选择说明、全量测速进度与停止、较小按钮的点击区域。iCloud 应用快照时清除旧规则刷新状态。
- 按后续界面反馈，导出摘要移除橙色诊断/跳过说明及三个空状态快捷入口；保留节点统计、无法导出状态及导出禁用逻辑。
- 完整配置预览保留 TextKit 2，并向无障碍提供不带语法高亮属性的全文，避免系统逐段转换动态颜色导致按钮查询超时；保留视觉高亮、全文与复制。
- 验证：1056 项单元测试通过、3 项环境跳过、0 失败；11 项 UI 回归分次通过；795 条源码文案与本地化目录一致，15 种语言齐全；`git diff --check` 通过。工作区原有改动已保留，本轮未提交、未归档或上传。
- 实体 iPhone 已覆盖安装并启动 1.0.7 (44)。相机实际识别、系统分享和外部客户端接收仍需真机使用验收；安装成功不能替代这些检查。本机详细证据位于 `.artifacts/ui-fixes-2026-09-07/report.md`。

## 功能边界

- 轻点客户端切换；直接横滑浏览；长按卡片后拖动排序。筛选页右侧手柄直接拖动。两个入口共用持久化顺序，局域网是导出入口而非新的配置格式。
- 勾选订阅或自有节点不改变首页排序。刷新迁移节点排除状态，旧请求不得覆盖新编辑或已删除来源。
- 代理集合默认关闭：支持的完整配置直接引用原始订阅 URL，由客户端更新远端节点。协议筛选和本地节点统计不代表远端实际内容。
- 代理集合支持 Stash、Clash、Clash Mi、Karing、Surge、Loon、QuanX、Egern；Shadowrocket、Hiddify、V2Box、sing-box MT 保留本地展开。不要把社区 sing-box fork 的 provider 扩展视为所有客户端支持。
- 原始链接可能含凭据；只在用户主动开启时写出。iCloud 同步也须单独授权，默认关闭。
- 一键导入的本机服务仅绑定 127.0.0.1，3 分钟失效；局域网共享是独立、用户主动开启的前台服务。二者不能混为长期后台订阅托管。
- 地图继续使用名称优先的离线识别和自绘 `WorldDotMapView`，不改用 MapKit 或联网定位。
- 同链接重新导入后的覆盖/重名行为由目标客户端决定；代理集合能减少节点更新后的重复导入，但塔台规则或自有节点变化仍需重新导出。

## 从哪里继续

换机后在干净工作区的 `main` 分支执行 `git pull --ff-only origin main`，再按该机器的 [AGENTS](../AGENTS.md) 设置 Xcode。先读本文及审查报告，未完成项见 TODO；不要依赖上一台机器的 DerivedData、签名资产或临时测试文件。

| 内容 | 唯一维护入口 |
| --- | --- |
| 产品能力与用户说明 | [README](../README.md)、[支持页](support.md) |
| 不可破坏的约束 | [CLAUDE](../CLAUDE.md) |
| 机器与工具链 | [AGENTS](../AGENTS.md) |
| 构建、测试、安装、真机清单 | [DEVELOPMENT](DEVELOPMENT.md) |
| 模块、数据流、资源边界 | [ARCHITECTURE](ARCHITECTURE.md) |
| 规则产物与 TestFlight 发布 | [RELEASING](RELEASING.md) |
| 未完成需求、待用户样本 | [TODO](TODO.md) |
| 本轮审查及验证 | [项目审查](../plans/2026-09-05-project-audit.md) |
| 上架成稿 / 隐私政策 | [APP-STORE](APP-STORE.md)、[privacy](privacy.md) |

旧过程记录留在 Git 历史，不再作为当前验收依据。公开文档不得记录设备标识、签名团队、描述文件 UUID、个人邮箱或凭据。


### 2026-09-06 Egern / Snell / QuanX MUX 修复

- 修复 Egern VLESS Vision 与 TLS/Reality 层级、Trojan WS、证书验证默认值及部分 TLS/协议参数；普通 SS-over-TLS 不再静默降成 SS。
- Mihomo 目标允许 Snell v4/v5，Loon 允许 Trojan HTTP。Stash 的 v4/v5 需要 iOS 3.6+；未提供客户端版本选择时按 v1–v3 兼容基线导出，其他版本跳过并计数，避免旧版整份配置加载失败。原节点版本不改写。 本次回归 1010 项通过、3 项跳过、0 失败；后续已覆盖安装并启动，最新 Stash 验证与暂缓决定见下文。
- ProxyNode 新增可选 pluginMux，YAML/URI 解析和分享/插件导出保留；QuanX 的 v2ray-plugin 仅明确无 MUX 时放行，旧订阅需刷新以取得该参数。
- 全量验证：972 XCTest（3 跳过、0 失败）及 39 Swift Testing 通过。客户端运行时复测与真机安装/启动是独立验收步骤。


### Karing 参数保留补修

Karing YAML 不再丢失 AnyTLS / SOCKS / HTTP 的 Reality 以及原生 SS TLS 参数。新增生成与解析回读回归，973 XCTest（3 跳过、0 失败）和 39 Swift Testing 通过。目标客户端能否握手仍以实机复测为准；Karing Trojan Reality、WireGuard 的既有失败未在本次确认根因。

### Stash 实机反馈兼容补修

- 当前导出策略只保留 VLESS TCP Reality；AnyTLS / Trojan / SOCKS / HTTP Reality、原生 SS-over-TLS 与 XHTTP 暂时跳过并计数，不静默改成普通 TLS/TCP。这里记录的是保守导出策略，不代表这些组合均已证实被 Stash 禁止。SS 的 v2ray-plugin 保持支持。
- Stash Trojan 使用官方 `sni` 字段。用户已确认测试节点 23（Trojan WS TLS）可连接；不将先前超时归因为 SNI。独立 Mihomo 对原字段和修正字段均返回 HTTP 204，不能代替 Stash 验收。
- 回归 1012 项通过、3 项跳过、0 失败。其余 6 个反馈节点的处理是兼容性跳过，不是恢复该协议连接。

### Stash 3.4：暂缓扩展，等待后续版本（2026-09-06）

- 用户确认当前使用的 Stash 为 3.4，并反馈这是目前可获取的最新版本；决定先记录，暂缓进一步调整。维持现有导出策略，不主动升级客户端或继续试改 Reality 参数。
- 官方协议文档列出的 Snell v4/v5、Trojan Reality、VLESS XHTTP 要求 iOS 3.6+。文档出现新能力不代表用户已能安装对应版本；恢复这些导出前须核对实际客户端版本并实机验证。
- AnyTLS Reality、SOCKS5 Reality、HTTP Reality：已确认塔台旧导出遗漏 Reality 参数，但 Stash 对这些协议组合的支持尚未验证。不能把“生成器漏字段”当作“客户端不支持”的证据；若后续确认支持，应补齐公钥、short-id 等参数并实测，而非永久跳过。仅补字段或其他内核连接成功也不等于 Stash 支持。
- 原生 SS-over-TLS 同样保持暂时跳过，支持能力待独立核对；不要与已可用的 SS WebSocket TLS 插件混淆。
- 测试节点当前跳过：07 AnyTLS Reality、08 Trojan Reality、09 SOCKS5 Reality、10 HTTP Reality、11 SS TLS、16 Snell v4、22 VLESS XHTTP TLS。05 VLESS Reality 与 23 Trojan WS TLS 已获用户客户端成功反馈；23 的先前超时根因未确认。
- 最新修复版塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并成功启动；1012 项通过、3 项跳过、0 失败。跳过节点不代表协议连接已修复。
- 后续工作入口见 [TODO](TODO.md#stash-34兼容性暂缓)。依据：[Stash 官方协议文档](https://stash.wiki/proxy-protocols/proxy-types)。

### sing-box SS WebSocket 导入修复（2026-09-06）

- 实机报 `outbounds[30].transport: json: unknown field "transport"`，对应测试节点 25（SS WebSocket TLS）。生成器已写 SIP003 `plugin` / `plugin_opts`，又错误添加顶层 V2Ray `transport`。
- 顶层 `transport` 限定为 VMess / VLESS / Trojan；SS 的 WebSocket、TLS、Host、path、MUX 继续保留在插件配置内，不跳过节点。覆盖 sing-box 与 Hiddify 生成回归。
- sing-box 1.14.0 对用户原文件复现报错；只删除多余字段后完整配置通过 `check`，该节点独立运行并访问外网返回 HTTP 204。全量测试 1013 项通过、3 项跳过、0 失败；不等同所有节点连接验收。

### sing-box 原生 SS TLS 过滤修复（2026-09-06）

- 用户反馈测试节点 11 无法连接。原生 SS-over-TLS 被旧生成器静默输出为普通 Shadowsocks，TLS 语义丢失。
- 已核对官方 Shadowsocks schema，并用 sing-box 1.14.0 对添加 `tls` 的节点执行 `check`，确认返回 `unknown field "tls"`；这与 SIP003 插件 TLS 不同。
- sing-box / Hiddify 对没有插件承载的原生 SS TLS 跳过并计数，不改写源节点；普通 SS、v2ray-plugin WebSocket TLS 及其他客户端已有输出保持。回归同时检查跳过计数、策略组引用清理及插件参数保留。
- 验证：1014 项通过、3 项跳过、0 失败；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并成功启动。处理结果是明确跳过不兼容节点，不是恢复原生 SS TLS 连接。

### Loon Reality 实机反馈（2026-09-06）

- 用户导入补参数诊断配置后，07 AnyTLS Reality 显示 70 ms、08 Trojan Reality 显示 72 ms，客户端分别识别为 anytls+reality / trojan+reality。确认旧生成器漏字段，不能归因为客户端不支持。
- 已将这两个协议的 `public-key`、`short-id`、`sni` 写入 Loon 导出，原节点保留。普通 AnyTLS / Trojan 输出不受影响。
- 01 SOCKS5 TLS、02 HTTPS、09 SOCKS5 Reality、10 HTTP Reality、11 原生 SS TLS、13 Hysteria2 在诊断配置中仍失败或超时。09 缺原始 Reality 公钥，此轮诊断未补齐；其失败不是客户端不支持的证据。其他未确认字段调整尚未合入生成器，未新增跳过策略。
- 02 的独立 sing-box 请求返回 HTTP 204；13 独立请求曾连接重置，重试返回 204。其他内核结果不代替 Loon 实测，需客户端版本和失败日志继续定位。

### Loon 3.5.0 用户名与 SOCKS5 TLS 修复（2026-09-06）

- 原日志显示 01 的 SOCKS5 认证失败。对照文件仅去掉 01/02/09/10 的简单用户名引号，用户反馈 01 恢复为 133 ms、02 恢复为 122 ms；源用户名和密码与 YAML 一致。
- 生成器对安全的简单用户名不加引号，密码仍按 Loon 格式加引号；含逗号等特殊字符的用户名维持转义。SOCKS5 TLS 写入已参与成功实测的 `over-tls`、`sni`、`alpn`；HTTPS 保留 `sni`、`alpn`。
- 09、10、11、13 仍未成功；13 日志为 `ERR_HANDSHAKE_TIMEOUT`，UDP 发出 10 个包、收到 0 个，尚未确认网络/服务端/客户端原因。不新增跳过策略，不把它们记录为已修复。
- 验证：1016 项通过、3 项跳过、0 失败；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并成功启动。

- Loon 后续状态：用户要求先记录、暂停排查，转查 Surge；剩余 09/10/11/13 不新增跳过，详见 TODO。

### Surge 实测与 Mac 版本边界（2026-09-06）

- 用户设备为 Surge iOS 5.21.1 (3810)。13 Hysteria2 / 14 TUIC v5 在原网络失败，关闭 ECN 对照仍失败；换网络后用户确认两者恢复。原网络相关因素待确认，不能推断为协议不支持。成功时沿用 ECN 关闭对照，尚未单独验证 ECN 默认值。
- 11 原生 SS-over-TLS：原导出遗漏 TLS 层。仅为该节点添加 `tls=true` 与 `sni` 的诊断配置通过 Mac 检查器，但用户手机仍失败。没有证据证明 Surge 已按该字段启用原生 SS TLS；不把参数被接受等同于协议生效，也不把失败直接写成所有版本均不支持。
- 本机实际安装 Surge Mac 6.4.4 (10661)，明显早于用户粘贴日志中的 6.7.0 / 6.8.0；未升级、未切换电脑正在使用的配置。此前 `surge-cli --check` 只证明旧版本接受配置，不是新版/手机的连接验收。
- 用户提供更新日志：6.7.0 提到 TLS 代理 ALPN 自定义；6.8.0 提到独立证书校验名称、ECN 自动回退、TLS 1.3 可靠性及 Hysteria/TUIC 分片握手响应修复。日志开头另列 MASQUE、HTTP/2 CONNECT UDP、TrustTunnel HTTP/3 和 `http probe` 等，但开头未提供版本标题，不能直接归到某版本。
- 该更新日志未明确声明新增原生 Shadowsocks-over-TLS。TLS/ShadowTLS/其他协议的修复不是 SS 原生 TLS 支持的证据。11 暂保留待研究；未将本轮 Surge 诊断参数写入塔台生成器。

### Hiddify SOCKS TLS 导入修复（2026-09-06）

- 用户 Hiddify 4.0.0 dev 报 `outbounds[11].tls: json: unknown field "tls"`。该出站为 01 SOCKS5 TLS；09 SOCKS5 Reality 同样带有非法 TLS 字段。
- 旧代码仅对官方 sing-box 做 SOCKS TLS 过滤，遗漏 Hiddify。现在两目标都对 SOCKS TLS / Reality 跳过并计数，生成策略组时同步移除引用；普通 SOCKS5 与 HTTPS 保留，不把 TLS 静默改成明文。
- 已生成用户样本的修复副本，移除两个不兼容出站，JSON 与策略组引用检查通过；完整 Hiddify 导入和其他协议运行仍需客户端验证，不以官方 sing-box 内核替代 Hiddify fork 验收。

### V2Box 实机反馈待验证（2026-09-06）

- 截图中 03 Trojan TLS、08 Trojan Reality、24 SS TCP 有延迟；04 VMess HTTP、11 原生 SS TLS 超时。02 HTTPS、10 HTTP Reality 显示为订阅卡片，疑似 HTTP URI 被识别为订阅地址，不能据此认定协议不支持。
- 代码检查：VMess 分享器直接输出 `net=http,type=none`；v2rayN 分享格式用 `net=tcp,type=http` 表达 TCP HTTP 伪装。已依据本地测试样本生成 04 对照链接，尚待 V2Box 实机验证；不得把 HTTP/2 与 TCP HTTP 伪装混为一谈。
- SS 分享器未编码无插件的原生 TLS，11 被输出为普通 SS；V2Box 可接受的原生 TLS 表达方式仍待确认，不记录为已修复。
- 本轮未修改生成器，也未安装新构建。参考：https://github.com/2dust/v2rayN/wiki/Description-of-VMess-share-link 。

### Clash Mi 实机反馈（2026-09-06）

- 用户截图：07 AnyTLS Reality、09 SOCKS5 Reality、10 HTTP Reality、11 原生 SS TLS 未显示延迟，仅显示闪电图标；05 VLESS Reality、08 Trojan Reality、12 Hysteria、13 Hysteria2、14 TUIC 有延迟。闪电图标本身不是具体错误日志。
- 当前 Clash Mi 导出路径未给 07/09/10 输出 Reality 参数，11 未输出原生 TLS，存在语义丢失。尚未取得本次实际 YAML 和 Clash Mi 内核版本，不能把代码检查当作用户文件逐项验证。
- Mihomo 官方 AnyTLS 文档明确不支持 AnyTLS+Reality；此项不能通过仅添加 reality-opts 解决。09/10/11 仍需结合具体内核字段与实际配置确认，不笼统推断所有 Reality 不支持。来源：https://wiki.metacubex.one/config/proxies/anytls/ 。
- 本轮仅记录诊断，未修改导出过滤或生成器。

### Clash / Hako 本地内核复现（2026-09-06）

- 官网 clash.md 指向 TokenPLS/Hako，独立于直接运行 Mihomo。本轮从官方仓库编译 CLI，固定提交 `e6ac1ee1f6cdff5aa61f7dd0e8a3fd735a56c97d`；不代表已确认手机安装版本对应此提交。
- 使用此前用户提供测试节点参数，逐节点运行独立内核，仅监听本机回环随机端口，以 HTTPS generate_204 请求验证；没有切换系统代理或修改服务器。并非本次手机导出 YAML 的逐字复现。
- 对照 08 Trojan Reality、24 SS TCP 均返回 HTTP 204。07 AnyTLS Reality、09 SOCKS5 Reality、10 HTTP Reality 均 curl 35 / HTTP 000，11 原生 SS TLS curl 28 / HTTP 000。
- 为 07/10 补入用户 JSON 中的真实 Reality 公钥、short ID 与 chrome 指纹，仍 curl 35；为 11 补 tls、sni、servername 后仍超时。全部配置检查返回 0，说明检查通过并不保证字段生效。
- 源码：AnyTLSOption、HttpOption、Socks5Option 以及各自握手路径没有 Reality 接入；ShadowSocksOption 没有顶层原生 TLS 字段，插件 TLS 与其不同。因此在该提交上不能靠补上述字段恢复这些原生组合。09 的现有源文件没有真实 Reality 公钥，本轮没有伪造或复用其他节点公钥做补参数对照。
- 生成器仍存在把这些组合静默导出为普通 TLS / SS 的问题，本轮未修改生产代码或安装新构建。源码依据：https://github.com/TokenPLS/Hako/tree/e6ac1ee1f6cdff5aa61f7dd0e8a3fd735a56c97d/adapter/outbound 。

### Clash / Hako 导出修正（2026-09-06）

- `.clashApple` 对 AnyTLS/SOCKS5/HTTP Reality 及无插件的原生 SS TLS 跳过并计数，避免降级成普通 TLS 或明文 SS。源节点不变，组成员按同一过滤结果生成。
- 普通协议、Trojan/VLESS Reality 以及 SIP003 WebSocket TLS 保留；本轮不扩展到尚未做对应内核验证的其他客户端。
- 新增回归在旧实现上失败，验证跳过数量、组引用清理和受支持组合保留；修复后执行全量测试与真机安装。
- 验证结果：1018 项通过、0 失败、3 跳过；真机构建已完成。安装步骤失败后重新枚举未找到唯一可用实体 iPhone，因此本轮尚未安装或启动新版，需重新连接设备后继续。

### Hiddify WireGuard 字段修正（2026-09-07）

- 用户重开 Hiddify 后，本地连接错误消失，转为 `outbounds[22].address: unknown field`，对应 15 WireGuard。
- 旧式 WireGuard outbound 必须使用 `local_address`，之前误用了新版 endpoint 的 `address`。修正共享旧式出站生成路径并补 IPv4 /32、IPv6 /128 缺省前缀；sing-box 新版 endpoint 保持 address。保留节点及凭据，不新增跳过。
- 用户样本已生成本地修复副本；回归测试在旧实现上失败，覆盖旧式字段、地址前缀与新版 endpoint 区分。尚待 Hiddify 手机实际导入和流量确认。
- 验证完成：1018 项通过、0 失败、3 跳过；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并启动，包含此前 Clash/Hako 过滤修正。Hiddify 本次导入仍待用户验证。

### Hiddify SSR 实机不支持（2026-09-07）

- WireGuard 字段修正后用户进入代理页，17 SSR 明确返回 `ShadowsocksR is deprecated and removed in sing-box 1.6.0`；65535 ms 是失败显示，不是有效延迟。
- Hiddify 能解析配置不代表其运行内核支持 SSR。修正目标支持列表排除 SSR，源节点保留，导出跳过并计数，策略组同步清理；其他客户端不变。
- 回归验证目标能力声明、跳过计数与无悬空引用，旧实现已复现失败；生成本地兼容副本继续保留 WireGuard 修正。
- 验证：1019 项通过、0 失败、3 跳过；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并启动。需重新导出替换 Hiddify 已有配置，旧配置不会自动移除 SSR。

### Issue #20 粘贴协议入口统一（2026-09-07）

- https://github.com/pengchujin/tower/issues/20 反馈 wireguard://、wg:// 在底层能解析但粘贴入口不识别。本地回归确认旧入口返回 unknown。
- SourceInputDetector 移除重复协议白名单，非 HTTP(S) 单节点统一使用 SubscriptionParser.parseURI；HTTP(S) 保留订阅与节点的歧义判定。Snell 代理行仍交给同一解析器识别。
- 新增全部 ProxyKind 的规范分享链接识别、WireGuard 两种 scheme、空白、多行节点、hy/hy2/socks 别名与无效 URI 回归；使用合成凭据，不写入此前测试服务器秘密。全量测试包含之前协议导入导出回归，不能等同真实剪贴板 UI 或网络连通验收。
- 额外边界修正：WireGuard URI 拒绝空主机（例如只有 wg://）；多行测试使用不同端点，避免正常去重影响计数。
- 最终验证：1020 项通过、0 失败、3 跳过；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并启动。已从此前节点 15 生成本地 wireguard/wg 两份测试链接，实际系统剪贴板交互待用户验证；未在 GitHub 评论或关闭 issue。

### 1.0.7 (44) 发布准备（2026-09-07）

- 整合上述策略组、客户端兼容性及粘贴识别修正。1020 项通过、0 失败、3 跳过；763 条本地化检查通过；规则快照最新，77 个远程规则产物全量校验通过。发布脚本、规则更新器及设备选择脚本测试通过。
- 1.0.7 (44) 已覆盖安装到实体 iPhone 并启动；正式归档上传状态后续记录。更新日志见 RELEASE-NOTES-1.0.7-44.md。

### 1.0.7 (44) 上传完成（2026-09-07）

- 发布代码提交 `9a22e32` 已推送 main；正式发布机使用 Xcode 26.6，在图形会话完成 Release 归档及上传，ARCHIVE / EXPORT 均成功，退出码 0。
- App Store Connect 已确认 1.0.7 (44) 上传处理“完成”，已加入内部测试组；中文测试内容已保存。外部测试状态为“准备提交”，本轮未提交外部 Beta 审核。
- 真机覆盖安装及启动、测试与规则校验结果见上节；归档对应上述代码提交，后续发布记录更新不改变已上传二进制。

### 地区识别和离线网络组织（2026-09-07，build 44 后开发改动）

- 修复服务器 `.uk` / `.jp` 后缀及域名关键词抢先决定国家的问题。统一优先级：用户手动地区 → 节点名称 → 离线服务器 IP 国家库 → 未知；列表、地图和地区导出共用 resolver。
- 节点详情增加手动地区选择、自动识别恢复及离线网络组织（ASN）。紧凑节点行长按进入独立详情弹层，列表仍保持静态；不提供实际代理出口检测。
- 手动地区随快照保存，订阅刷新按唯一身份迁移；歧义时不套用。DNS 同 host 请求合并，成功一小时、失败/冲突30秒；多地址国家不一致不选第一个。数据库版本变化会使旧持久国家缓存失效；排队与在途结果核对节点/服务器和快照代次。
- 离线国家库更新为 server-country，新增 origin-asn，快照2026-09-06T22:31Z；来源固定 asset ID、SHA-256 和 PDDL 声明见 IPCountryManifest.json / NOTICE。无在线 IP 查询服务。
- 数据原始净增16,294,942字节（15.54MiB），独立数据ZIP9净增6,214,165字节（5.93MiB），不代表App Store下载或整个安装包增量。ASN使用18/42字节范围记录和去重UTF8池，按需映射；macOS独立组件4000次查询约7.3ms，单进程峰值RSS约21.0MiB，对照空进程5.5MiB，不能等同iPhone App内存。
- 此前测试样本的真实DNS地址在新旧库均为SG，ASN为Amazon；英国误判来自域名推断。本机开启代理时系统DNS返回198.18/15虚拟地址，无法离线定位，应显示未知，不能将其当真实入口或出口。
- 验证：1030项通过、0失败、3跳过；7项数据生成/校验测试通过；模拟器真实点击完成地区搜索、指定和恢复自动，并检查截图。真机开发版1.0.7(44)已覆盖安装并启动。真机自动交互运行器启动前退出（code74），未完成手机交互验收；TestFlight上传包仍是此前发布内容。

### 订阅刷新地区图标闪回修正（2026-09-07）

- 用户实机反馈刷新先显示协议图标再恢复新加坡；说明此次国家解析可成功，不能据此归因为手机虚拟DNS。旧实现更换节点ID时清空地区，需视图异步再次回填。
- 新节点发布前按当前服务器复用未过期的国家缓存，同时继承原始缓存时间；不延长TTL，不把旧服务器结果复制到新服务器。
- 回归先复现立即读取新ID国家为nil，修复后通过。全量1031通过、0失败、3跳过。开发版1.0.7(44)已重新覆盖安装到实体iPhone并启动，刷新观感待用户确认。

### 重新测速测试方式闪烁修正（2026-09-07）

- 用户实机反馈详情中点击重新测试延迟，“测试方式”行闪烁。强制测速原先删除上次结果，条件渲染随之移除该行，完成后再插入。
- 测速期间保留上次完成的结果，现有测速中指示继续显示；新结果（包括不可达）返回后替换，取消不清空上次结果。
- 异步回归先复现旧结果在探测中为 nil，修复后验证保留旧方式及新方式/延迟替换。全量1032通过、0失败、3跳过；开发版1.0.7(44)已覆盖安装到实体iPhone并启动，手机上的闪烁观感待用户确认。

### 规则定制默认编辑与取消添加同步（2026-09-07）

- 规则定制进入即显示编辑及拖动排序，左上角菜单改为“编辑”，右上角仅“完成”。名称/Emoji 和策略选择分别可点，长按删除仍保留；搜索时禁止拖动，避免过滤索引影响完整顺序。
- 移除编辑期间忽略分组变化的限制；排序立即保存，添加/取消/删除同步编辑草稿。另修复规则展示缓存命中不建立观察依赖的问题：缓存失效发布可观察版本，避免勾选已取消而“当前规则”残留旧分组。
- 回归先复现缓存命中后取消规则不通知观察者；模拟器实际添加 OpenAI、取消、完成再进入验证无残留，并检查默认编辑截图。全量1033项通过、0失败、3跳过；771条本地化检查通过。
- 开发版1.0.7(44)已覆盖安装到实体iPhone并启动。手机上的编辑及拖动手感待用户确认；未推送或更新TestFlight。

### 规则页分组数量口径统一（2026-09-07）

- 用户反馈顶部总览11组、同一方案卡片14组。总览原先读取原始方案 groups，卡片读取定制后的 groups；总览改为共用 customizableScheme，统计包含用户增删改的全部当前分组。
- 实际UI回归验证添加OpenAI后总览与卡片均为12组，取消后总览恢复11组，重新进入无残留；数量源回归通过。此次小改未重复全量测试，上一轮全量1033项通过。
- 开发版1.0.7(44)已覆盖安装到实体iPhone并启动，未更新TestFlight。

### 规则策略入口对比度（2026-09-07）

- 用户反馈右侧策略名称像禁用状态；移除按钮标签的 secondary 层级色，文字和箭头使用完整强调色及 plain 按钮样式。
- 模拟器交互回归通过并检查截图，策略入口已为正常蓝色；开发版1.0.7(44)已覆盖安装到实体iPhone并启动。此次仅颜色调整，未新增测试或重复全量测试。

### 补齐手动切换候选策略（2026-09-07）

- “可添加策略”默认提供“🚀 手动切换”；已有手动切换/手动选择及英文同类名称时复用，编辑自身不提供自引用。只有保存引用后才补建 select 分组，以 .* 匹配导出时已启用节点；保持原默认候选顺序，不修改上游方案。
- 回归先复现缺少候选及引用后未生成分组。修复后全量1034通过、0失败、3跳过，覆盖全部支持完整配置导出的目标；模拟器真实点击添加手动切换并保存后验证分组出现。
- 本轮安装脚本未检测到唯一可用实体iPhone，在构建前停止；本次改动尚未安装手机，未上传TestFlight。
- 后续用户重新连接手机后，补齐手动切换的开发版1.0.7(44)已覆盖安装到实体iPhone并启动；本轮安装完成。

### 大量订阅勾选卡顿优化（2026-09-07）

- 地区解析对每个候选和每批返回结果都遍历全部节点检查身份，造成平方级主线程工作。改为惰性 UUID→服务器索引，节点集合或字段变动时失效，仍核对服务器及快照代次，防止过期结果写回。
- 地区结果每批只发布一次，未知结果不重复写入相同值；订阅勾选不再清空无关规则展示缓存，无变化的单个勾选直接返回。
- 同机模拟器离线5,000节点解析测试：优化前8.641秒，优化后0.075秒；该指标包含地区处理，不是手机帧率、DNS网络延迟或完整交互耗时。订阅勾选缓存回归先失败后通过。
- 全量1036通过、0失败、3跳过，包含在途地区查询遇到节点变更的竞态回归；开发版1.0.7(44)已覆盖安装到实体iPhone并启动。用户实际订阅下的滚动和勾选手感待真机反馈，未上传TestFlight。

### 首次勾选订阅时定位提示闪烁（2026-09-07）

- 地图异步生成期间，不再用上一份或初始空的地图结果显示“还不能定位节点”。只有与当前节点、国家结果和查询完成状态匹配的展示快照才可显示定位失败提示。
- 将尚未完成查询的节点与查询完成但仍不能定位的节点区分；失败查询即便没有新增国家代码，也会触发地图展示更新。
- 增加回归覆盖：查询中不计入无法定位，查询失败后正常计数，成功后显示国家，完成状态改变会更新展示版本。
- 验证：NodeRegionResolverTests 定向测试及 Tower 全量测试通过，git diff --check 通过。开发版 1.0.7 (44) 已覆盖安装到连接的 iPhone 并启动；首次勾选的实际视觉效果仍待用户真机复测。未上传 TestFlight。

### 延迟测试精简（2026-09-07）

- 仅保留自动、ICMP、TCP；默认仍为自动。移除对代理端口发送 HTTP HEAD 的选项与实现。
- 自动模式先 ICMP，失败后对 TCP 协议回退端口测试；VPN 路由下继续避开可能代答的 ICMP。Hysteria、Hysteria2、TUIC、WireGuard 不尝试 TCP，不能据此判定节点不可用；手选 TCP 时提示不适用。
- 保留实际测量方式标注。这是服务器地址/端口延迟，不是完整代理协议连通性验证；客户端导出配置中的 URL 测速设置不受影响。
- 验证：全量 1038 通过、0 失败、3 跳过；772 条本地化提取核对通过。开发版 1.0.7 (44) 已覆盖安装到连接的实体 iPhone 并启动，实际网络下测试效果待用户复测；未上传 TestFlight。

### 地图延迟配色和实时测速（2026-09-07）

- 地区点阵、节点延迟采用统一色阶：≤100 ms 青绿、101–200 ms 蓝、201–350 ms 琥珀、>350 ms 珊瑚橙；未测灰蓝、不可达紫红。选中保持原色系并加深、加密，浅色/深色均适配。
- 国家颜色与标签数值取已成功测量节点的延迟中位数；全部有失败结果才标不可达，未完成或不适用 TCP 不当作失败。重测保留已有结果，国家标签用省略号表示测速中，失败附感叹号，地图下提供数值图例和统计口径。
- 延迟批次首个结果立即发布，后续密集结果以 100 ms 合并，最后剩余结果补发；不再等整批最慢节点结束才显示最快节点结果。点阵概览缓存包含色阶，放大细节点阵使用同一配色；测量不触发地区重新解析。
- 回归覆盖：色阶边界、中位数、部分失败/待测/不适用、重测保留色阶、快节点在慢节点完成前发布。生成并检查浅色/深色及选中/未选中四张地图渲染截图。
- 验证：全量 1042 通过、0 失败、3 跳过；773 条本地化核对通过；最终图例布局与不适用提示微调后，地图/运行批次/延迟服务定向测试通过。检查模拟器实际首页截图，图例按窄屏分为两行。
- 真机状态：主体功能的开发版 1.0.7 (44) 已覆盖安装并启动。随后图例窄屏固定宽度、深色图例匹配，以及不适用 TCP 的紧凑标记微调尚未覆盖安装，安装脚本检测不到唯一可用实体 iPhone。未上传 TestFlight。
- 后续连接手机后，已将上述最终图例与紧凑提示微调一并覆盖安装到实体 iPhone，开发版 1.0.7 (44) 启动成功。

### 测速中地图缩放卡顿与二级标签（2026-09-07）

- 地图国家名称后移除延迟数字，保留颜色、测速中/失败标记。二级及细节视图由上下两个避让位置扩展为八个近邻位置；横向偏移以细引线连接国家，保持非重叠约束。
- WorldDotGrid 加载时建立国家→点位索引；着色不再按色阶反复遍历全球陆地点。WorldDotPaint 在后台准备，输入只包含位置、选中状态、色阶；相同色阶内的延迟变化或进度不会重建着色。
- 缩放、拖动及选中回中动画期间复用已绘制点阵，暂停色阶重建；动作结束补上最新结果。细节点阵只在静止后启用。
- 概览及细节 Canvas 都把点汇成最多 13 个颜色/选中路径，替代每个点一次 fill；不是减少实际地图点数。
- 同机模拟器 60 国家、100 轮六组着色点位查询：优化前 0.494 秒，优化后 0.056 秒（查询微基准，不是手机帧率）。全量 1045 通过、0 失败、3 跳过；包含扩展标签不重叠、进度不改变着色输入及国家索引回归。
- 模拟器点测速后执行地图捏合放大的交互测试通过，并检查放大截图：国家名称不再带延迟数字。开发版 1.0.7 (44) 已覆盖安装到实体 iPhone 并启动。以上不是手机 FPS 测量，大量真实订阅场景的手感仍待用户复测；未上传 TestFlight。

### 地图下方说明精简（2026-09-07）

- 按截图移除地图下的中位数说明与无法定位节点数提示，保留配色图例。定位与延迟计算不变。
- 真机构建通过，开发版 1.0.7 (44) 已覆盖安装并启动；git diff --check 通过。本轮仅移除说明文案，未重复全量测试。

### 放大地图选中清晰度与测速标签（2026-09-07）

- 国家名称移除测速省略号，也不再为测试中状态预留宽度；测速进度仍由按钮与地图色阶表达。
- 二、三级视图选中时保持当前倍率，只平移居中。清晰点阵按当前倍率栅格化并缓存，平移不重新逐帧计算全球点位，也不再切回概览后恢复细节，去掉模糊到清晰的切换。选中着色可在回中期间更新。
- 本节替代前文“细节点阵只在静止后启用”的选中回中行为；实际捏合/拖动仍复用手势底图。
- 验证：主体改动全量 1046 通过、0 失败、3 跳过；补充二级倍率保持后地图定向 60 项通过。模拟器测速、两次捏合并分别选中日本/香港的交互测试通过，检查动画落定截图；git diff --check 通过。
- 最终开发版 1.0.7 (44) 已覆盖安装到实体 iPhone 并启动。真实千节点测速中的动画手感待用户复测，本轮未测手机 FPS，未上传 TestFlight。

### 国家名称移除不可达叹号（2026-09-07）

- 地图名称仅显示国家/地区文字，移除不可达叹号和对应宽度预留；不可达继续用色阶表示，避免状态变化影响标签布局。
- 真机构建通过，开发版 1.0.7 (44) 已覆盖安装并启动；git diff --check 通过。仅移除展示标记，未重复全量测试。

### 千节点测速滚动并发（2026-09-07）

- 根因：AppModel 复用地区解析的 8 个一批调度，测速必须等整批最慢节点才启动下一批；自动模式失败依次等待 ICMP 1.2 秒和 TCP 1.8 秒会放大批次等待。
- 测速独立使用最多 32 个滚动并发，完成一个立即补一个，地区解析批次不变。保留原探测超时、UDP 不适用规则、100 ms 结果合并和重测期间旧结果；取消后不再启动后续节点。
- 回归：阻塞首个探测时第三个仍可补位；1157 个模拟节点全部产生结果且并发不超过 32。全量 1049 通过、0 失败、3 跳过；git diff --check 通过。模拟操作验证调度，不代表真实网络耗时。
- 开发版 1.0.7 (44) 已覆盖安装到实体 iPhone 并启动，实际订阅总耗时待用户复测；未上传 TestFlight。

### 1.0.7（45）发布准备（2026-09-07）

- 合并 build 44 后的地区识别/离线 ASN、地图与千节点测速优化、规则定制和导入导出交互修复；更新日志见 RELEASE-NOTES-1.0.7-45.md。
- 全量 1056 通过、0 失败、3 跳过；795 条本地化提取核对通过；发布脚本回归通过，IP 数据更新器 7 项通过，内置 ACL4SSR 最新及 77 个远程文件校验通过。
- 发布提交 `9839fec`；正式版 Xcode 26.6 归档和上传成功（退出码 0），归档版本与 Bundle ID 已核对。App Store Connect 内部组显示 build 45“正在测试”，中文测试内容已保存；本轮未提交外部 Beta 审核。

- build 45 补充验证：地图、地区设置、规则定制共 4 项界面回归通过。正式发布由 Mac mini M2 的 Aqua 会话执行，未修改钥匙串密码或签名配置。

### 四步使用引导（2026-09-07）

- 首次欢迎页改为用途介绍、添加节点、选择规则、导出到客户端四屏；明确塔台不提供节点、不建立代理连接，导入后需在客户端开启连接。保留本机处理与 iCloud 默认关闭说明，详细安全与开源内容继续在设置提供。
- 支持下一步、上一步、跳过与完成；沿用 hasSeenWelcome，已完成欢迎的旧用户不强制再次展示。设置顶部新增“使用引导”，可独立重看与退出。
- 首次引导和主界面条件切换，避免隐藏底层界面的修饰器影响引导点击和无障碍。设置有限卡片改用 VStack，修复本轮模拟器发现的滚动重复布局。
- 验证：1056 项单元测试通过、3 项环境跳过；最终引导 UI 回归通过，覆盖四屏、返回、完成后重启、设置重看/退出及滚动。814 条本地化提取核对通过，15 种语言齐全；检查四屏模拟器截图，git diff --check 通过。小屏极大字号与 VoiceOver 实机朗读尚未逐项验收。
- 最终开发版 1.0.7（45）已覆盖安装到实体 iPhone 并成功启动；未提交、归档或上传。截图与日志保存在本机 .artifacts/onboarding/。

- 引导首屏按反馈增强：展示全部 12 个客户端的实际图标与名称，补充“添加订阅 → 选择规则 → 导出使用”流程卡片；V2Box 仅节点范围单独注明。大字号网格改为两列，流程宽度不足时纵向排列，内容可滚动。
- 本次增量编译与完整引导交互回归通过，819 条本地化提取检查通过，检查更新后的首屏截图；最终开发版 1.0.7（45）再次覆盖安装到实体 iPhone 并启动。仅引导展示调整，未重复全量单元测试，未上传。

### 引导示例与分页动画（2026-09-07）

- 按截图移除首页底部说明、V2Box 范围小字与最后一页底部提示。第二页标题改为“先添加订阅或节点”，展示示例链接、添加方式与勾选节点；第三页展示内置方案及服务到代理/直连/拦截的示例关系。示例不读取真实数据或请求权限。
- 内容改为原生横向分页；按钮采用 0.5 秒、0.2 bounce 的 spring 选择动画，固定返回/下一步占位，沿用按压反馈，进度胶囊连续移动。减少动态效果时仅淡入淡出。补充横向手势识别，目标按手势起始页计算，避免纵向 ScrollView 接走手势及双重翻页。
- 最终 UI 回归通过：明确触点左右滑动、前后按钮、完成后重启、设置重看/退出、设置上下滚动。检查第二/三页截图及按钮翻页录屏逐帧画面；832 条本地化核对通过，git diff --check 通过。此次界面调整未重复全量单元测试，减少动态效果与极大字号尚未逐项实机验收。
- 最终开发版 1.0.7（45）已覆盖安装到实体 iPhone 并启动；手机上的实际动画手感待用户使用确认。未提交、归档或上传。

### 2026-09-07 — 引导导出预览与元素动画
- 最后一页改为可交互导出示例：四个客户端卡片、完整配置/仅节点切换、联动的目标图标与配置摘要；所有示例状态仅在视图内，不生成配置或启动客户端。
- 顶部三步流程使用共享几何选中背景，页内卡片与行按 40ms 间隔进入；保留原生分页、固定导航按钮，水平手势统一在分页容器解析。减少动态效果时取消位移与缩放。此前要求删除的小字保持删除。
- `testOnboardingPagesAndReplay` 增加 Egern 选择、仅节点模式及预览联动验证；完整回归通过（43.541s，0 失败），本地结果 `.artifacts/onboarding/export-motion-verified.log`。832 条本地化检查通过。
- 最新模拟器截图与录屏位于 `.artifacts/onboarding/export-page.png`、`export-selected.png`、`export-flow.mp4`。真机安装脚本本次未检测到唯一可用实体 iPhone，尚未完成本轮真机安装和启动；不要将上一轮安装记录视为本轮完成。未提交、未归档或上传。

### 2026-09-07 — 最后一页收紧为一屏
- 按反馈移除引导页的“导出内容”卡片、完整配置/仅节点选择器和中间箭头；保留客户端选择、转换已就绪摘要与“一键导出到所选客户端”的示意。实际导出功能不变。
- UI 回归改为不滚动检查最后一页标题、目标客户端及导出区域可见，并检查导出区域位于底部导航上方。多语言检查通过；本轮真机安装尝试仍未检测到可用实体 iPhone。
- 完整引导 UI 回归通过（包含上述一屏边界断言），截图 `.artifacts/onboarding/compact-export.png`，测试日志 `.artifacts/onboarding/compact-export-ui.log`。本轮尚未完成真机安装与启动。

### 2026-09-07 — 流畅度真机检查与多地区测试数据

- Debug 隔离 UI 数据扩展为 30 个地区、16 个订阅、960 个订阅节点和 40 个自有节点，覆盖 6 种协议及用量/到期字段。仅 `TOWER_UI_TEST_RUN` 搭配 `TOWER_PERFORMANCE_NODE_COUNT` 启用，不改用户存储、不代表网络连通性验证。
- 去掉所有卡片统一的 geometryGroup；标签触觉反馈移入独立视图，减少根层观察。默认震动保持开启，Debug 可用 `--disable-tab-haptics` 做 A/B。真机 A/B CPU 均值 1.122 / 1.112 秒，差异小于轮间波动，未证明震动为主因。
- iPhone 17 Pro / iOS 27 beta 实测多订阅首页减速阶段约 81–83 FPS；Instruments 检测到短卡顿，不宣称稳定 120 FPS。Info.plist 高刷新率开关没有改善，已撤回；内部订阅 LazyVStack 虽降低 CPU，但采集卡顿增加，也已撤回。
- 性能测量同时保留减速历史指标，增加拖动＋减速指标及 iOS 26+ 标签切换 hitch 指标。原始 xcresult/trace 含设备信息，仅保留本机 .artifacts/performance-2026-09-07/；结论和证据边界见其中 REPORT.md。
- 19 项 ReviewFixTests 通过；较早完整 15 项 UI 用例通过，但 xcodebuild 在测试后清理挂起，已停止，不记为编排退出码 0。832 条本地化检查通过。真机后续复测与安装结果另行补充；未提交、归档或上传。
- 撤回内部 LazyVStack 后真机首页滚动与多订阅导航用例均通过（退出 0）；35 秒 Instruments 复测 2 次卡顿/37.50 ms，拖动与减速约 82–84 FPS，非稳定 120。
- 真机导航检查额外定位到同步剪贴板阻塞：spindump 469 个主线程样本均在 AddSourceSheet → UIPasteboard.string → semaphore wait，约 60 秒未运行。改为 NSItemProvider 异步文本/URL 读取，保留自动请求与手动粘贴；用户编辑、切换模式和面板消失会取消读取，回调校验代次与原内容，避免迟到覆盖。模拟器编译通过，真机回归结果待下条补充。
- 最终剪贴板真机回归：自动复制订阅链接→自动填充→取消关闭通过；草稿编辑与取消、多订阅导航通过。键盘聚焦→完成收起用例通过，最后两项退出 0（33.41 秒）。第三方键盘的 XCTest 文字注入不稳定，键盘用例限定焦点/收起，不声称其所有输入行为已覆盖；此前权限弹窗和前台切换导致的失败保留在本机报告。
- 最终 1.0.7（45）优化 Debug（-O / wholemodule）已通过签名验证，覆盖安装到实体 iPhone 并成功启动，当前打开独立的 30 地区/16 订阅/1000 节点测试数据（含 40 自有节点）。正常手动重启不带测试参数时恢复用户原存储；未提交、归档或上传。git diff --check 通过。

### 2026-09-08 — Mac 客户端与平台排序

- 开启 Mac Catalyst 开发构建，保留原来的客户端图标卡片、横向滚动、筛选、拖动排序及底部导出操作。Surge 手机版与 Surge Mac 独立保留；新增 Clash Verge、ClashMac，沿用完整 Mihomo 配置生成及兼容性边界。
- Mac 默认前五项为 Shadowrocket、局域网共享、Surge Mac、Clash Verge、ClashMac；手机默认隐藏后三个 Mac 专用目标，可从筛选手动添加。手机旧字段与可选 Mac 偏好分别保存，交替写回不会覆盖另一端的排序、可见目标或选中客户端，已覆盖持久化回归。
- Mac 支持原生保存配置文件；Surge Mac 使用 surgeconfig、Clash Verge 使用 clash-verge 导入入口。旧版 Surge Mac 回退保存文件；ClashMac 使用文件或局域网订阅导入。局域网共享支持 Mac 有线网络和切换 App 后持续运行，修复共享启动期间取消的竞态，并完整读取分包 HTTP 请求头。
- 本机实测：Clash Verge 2.5.2 本机一键导入和局域网订阅成功；ClashMac 27.1.4 文件导入成功，Mihomo 配置检查通过；Surge Mac 6.4.4 文件回退成功，surge-cli --check 返回 OK。Surge 手机版独立入口可打开对应客户端。使用演示节点，未宣称真实代理流量连通或 Surge Mac 6.7+ 的运行时验证。
- 最终 Mac 和 iOS Simulator 均通过 1,016 项 XCTest + 49 项 Swift Testing，零失败；平台限制分别跳过 33 / 3 项 XCTest。841 条本地化提取检查及 git diff --check 通过。Mac 图标排序与手机版默认隐藏已在界面检查；最终 1.0.8（46）已再次签名覆盖安装到实体 iPhone 并启动。
- 本机开发版位于用户 Applications 下的 Tower Mac.app，使用本地临时签名。未变更版本号、提交、归档上传或进行 Mac 分发/iCloud 签名验收。原始测试与客户端验证材料仅保留在忽略目录 .artifacts/mac-adaptation/。

### 2026-09-08 — Mac 首页与重复导入跟进

- Mac 宽窗口的首页概览和地图并排；窄窗口限制地图宽度，避免地图随窗口无限放大而将订阅卡片挤出首屏。手机保持原有纵向排列，客户端图标选择设计保留。本机宽窗口已实测首屏显示订阅与自有节点。
- Clash Verge 2.5.2 的 URL Scheme 源码每次执行 append，未提供按 URL 覆盖入口。导出增加“新建配置 / 更新已有配置”选择；更新仅重新开放同一个 3 分钟本机地址，用户在 Verge 原有同名卡片点刷新。改名需重新导入，持续更新可使用局域网共享。不会读取或修改客户端私有配置来实现覆盖。
- 真实客户端验证：独立 Tower QA Refresh 演示配置首次导入后，关闭 VMess 再执行准备更新并点击 Verge 刷新；卡片保持一张，客户端存储的新 YAML 不再包含 VMess。用户已有两张配置保留，未切换活动配置或修改系统代理。
- 连续准备导出回归发现固定端口未释放时重启可能失败，现等待旧 listener 取消完成再启动；新增测试确认原 URL 可获取更新后的内容。
- Surge Mac 官方从 6.7 起支持 URL Scheme；本机 6.4.4 不注册该入口，已补明确版本与文件回退提示。ClashMac 27.1.4 未注册 URL Scheme；官方 CLI 的 profile 命令只列出和切换配置，未发现新增配置入口，继续使用文件或订阅。
- 最终 Mac / iOS Simulator 均通过 1,017 项 XCTest + 49 项 Swift Testing，零失败（平台分别跳过 33 / 3 项）；849 条本地化提取检查通过。最新 1.0.8（46）再次覆盖安装并启动实体 iPhone，Mac 开发版已替换到用户 Applications。未升级第三方客户端、上传或发布。

### 2026-09-08 — 撤回未采用的 Mac 交互方案

- 按用户反馈撤回 Clash Verge 的“新建 / 更新已有配置”选择及手动刷新提示，恢复按钮直接调用导入 Scheme。
- 撤回 Mac 首页左右并排和固定地图宽度，恢复此前纵向布局。此前宽屏地图过大的问题仍待新的设计方案处理，上一条布局验收不代表该方案被采用。
- 保留 Mac 客户端、两端默认排序与显示偏好、Surge Mac 版本说明，以及连续导出等待端口释放的修复。

### 2026-09-08 — Mac 订阅首页重新排版

- 按 apple-design 的内容层级和桌面任务优先原则重新设计 Mac 首页：紧凑统计条、直接呈现订阅列表、尾部轻量继续操作。节点地图改为明确按钮打开的独立面板，保留地图选择、节点详情和测速；首页仍解析离线国家信息，统计不依赖打开地图。
- 空状态隐藏零值概览和空地图，突出添加来源；订阅、规则与导出页共用 Mac 内容最大宽度，避免卡片随宽屏无限拉伸。手机版保留原有概览与地图布局，客户端图标、排序和导入方式保留。
- 本机检查了正常数据、空状态、普通演示及 16 个订阅 / 1,000 节点，验证订阅展开、地图打开、地区选择和关闭。测试数据使用独立临时存储，最终已回到正常数据。
- Mac 与 iOS Simulator 的 TowerTests 全量通过，851 条本地化提取检查通过，git diff --check 通过。最新 1.0.8（46）覆盖安装实体 iPhone后首次启动未成功，单独重试 devicectl 已确认启动成功。用户 Applications 下的 Tower Mac.app 已替换为本轮开发构建；未上传或发布。

### 2026-09-08 — Mac 地图改为首页内展开

- 按后续反馈将“节点地图”从独立面板改为首页内展开，位于紧凑统计条上方；默认收起，再次点击收起，箭头与选中状态同步，支持减少动态效果。
- 核实手机和 Mac 全新安装均选择 acl4ssr-default（ACL4SSR 默认），增加两种平台的启动默认值回归测试；保留已有安装保存的规则选择。
- Mac 与手机共用首次启动使用引导，hasSeenWelcome 默认 false，完成后不再弹出；设置的“使用引导”可重看。
- Mac 相关测试通过，本机确认地图原位展开与收起，实体 iPhone 1.0.8（46）覆盖安装并启动成功。用户 Applications 下的 Mac 开发版已更新；本轮没有新增文案，未上传或发布。

### 2026-09-08 — Mac 地图对齐与导出生成响应

- Mac 内联地图移除 720 点宽度限制，与统计和订阅卡片共用内容宽度；仅在 Mac 隐藏“还不能定位节点”的空状态提示，保留地图图例、地区节点与测速操作。
- 导出页不再在 body 中同步生成完整配置。配置请求捕获不可变输入，后台生成后回到主线程写缓存和呈现；任务按请求变化取消，旧任务不发布预览。生成中仍保留客户端与协议选择，暂不提供旧配置导入操作。
- 同步配置接口继续共用同一请求与缓存，供局域网、其他导出入口及测试使用。增加后台线程、缓存复用和切换后输入快照一致性测试。
- Mac TowerTests 全量通过（1,017 XCTest，33 跳过；50 Swift Testing），新增后台测试随后定向通过；iOS 全量通过（1,017 XCTest，3 跳过；52 Swift Testing）。本机验证全分组和默认方案切换到导出后的结果，未进行帧率或 Instruments 定量测量。
- 本机 Mac 应用已更新；实体 iPhone 1.0.8（46）安装并启动成功。未新增界面文案、上传或发布。

### 2026-09-08 — FlClash 与 ClashMac Scheme 实测

- 新增 FlClash 客户端图标、Clash/mihomo 配置能力、局域网目标别名和专属 flclash://install-config?url= 导入。Mac 默认排在 ClashMac 后，已有 Mac 偏好首次升级补入该位置并显示；用户后续隐藏或排序会保留，手机默认隐藏。
- 官方 FlClash 0.8.96 在本机实测成功：专属链接弹出添加配置确认；塔台使用演示节点生成完整配置，FlClash 成功下载并显示“塔台.yaml”。两份本次 FlClash 测试配置已清理，未启用演示代理或进行代理流量测试。
- ClashMac 27.1.4 未注册 URL Scheme。使用本地有效测试订阅，指定 ClashMac 打开 clash://install-config 没有导入提示、HTTP 请求或新增配置；直接打开通用 clash:// 链接由本机 Mihomo Party 接收并请求订阅。因此 ClashMac 继续文件/局域网导出，不冒用通用 Scheme。
- Mac / iOS TowerTests 均通过：1,019 XCTest（分别跳过 33 / 3）与 52 Swift Testing。实体 iPhone 1.0.8（46）覆盖安装并启动成功，本机 Mac 开发版更新并退出演示模式。未上传或发布。

### 2026-09-08 — Mihomo Party 与卸载后 Scheme 复测

- 新增 Mihomo Party（Mac 默认位于 FlClash 后，手机默认隐藏），包括原应用图标、Clash/mihomo 配置、局域网别名及 mihomo://install-config?url=…&name=… 专属导入。新客户端补入已有 Mac 排序，之后保留用户排序和隐藏偏好。
- 导入语法依据 https://clashparty.org/docs/guide/urlscheme ，本机实测专属链接唤起 Mihomo Party 并成功请求无凭据测试订阅；未启用测试配置或验证代理流量。
- 用户授权卸载 Mihomo Party 以排除 Scheme 抢占。命令行移动因应用权限失败后，使用 Finder 移到废纸篓成功；确认 /Applications 原应用不存在，保留 Application Support 配置数据。
- 卸载后通用 clash:// 链接实际由 Stash 接收（LaunchServices 查询为 /Applications/Stash.app），不是 ClashMac；显式指定 ClashMac 27.1.4 打开时仍无对应 HTTP 请求或新增配置。因此不改变 ClashMac 文件导入回退。
- Mac / iOS TowerTests 各通过 1,020 XCTest（分别跳过 33 / 3）及 52 Swift Testing。本机正常数据验证 ClashMac、FlClash、Mihomo Party 排序；Mac 开发版更新，实体 iPhone 1.0.8（46）安装并启动成功。未上传或发布。

### 2026-09-08 — Mac 共享菜单、默认二维码与订阅复制

- 共享格式 Picker 使用 inline 样式去除 Mac 菜单中的额外“链接格式”子层；Mac 二维码默认展开，手机维持按需展开。
- Surge Mac 通过声明 surgeconfig 查询白名单和 canOpenURL 检测安装后的导入能力，而非读取或猜测版本号；有专属入口时一键导入，未检测到入口时主按钮改为“复制订阅地址”。返回前台重新检测，打开入口失败也回退复制。ClashMac 在 Mac 上直接使用复制订阅地址。
- 复制启动持续的局域网订阅服务，复用访问密钥和固定端口，保持塔台运行时可刷新，不受一键导入 3 分钟时限影响。显式 surge-mac / clashmac 路由保留对应客户端的能力和协议筛选；通用局域网格式入口不变。
- 本机旧版 Surge Mac 验证复制操作，ClashMac 同一地址先包含 VMess、关闭该客户端 VMess 后再次读取即移除。共享菜单单层、默认二维码通过界面验证；高版本能力分支通过单元测试，未安装新版本 Surge 进行实测。
- Mac / iOS TowerTests 通过，852 条本地化提取检查通过，实体 iPhone 1.0.8（46）安装并启动成功；Mac 应用已更新并恢复正常数据模式。未上传或发布。

### 2026-09-08 — 平台引导与订阅导入说明

- 引导首页固定为 12 个客户端。手机恢复原来的移动端列表；Mac 优先 Shadowrocket、Surge Mac、Clash Verge、ClashMac、FlClash、Mihomo Party，补充 Stash、Hiddify、V2Box、sing-box MT、Clash Mi、Karing。
- Mac 重看引导改为主窗口中的居中面板（最大 720 × 960，随窗口可用空间缩小），避免嵌套设置弹窗限制高度。保留页内滚动和固定底部导航，手机仍使用原来的全屏引导。本机验证四页导航与完成退出。
- Mac 回退操作统一为“复制订阅”，说明分别列出 Surge Mac 的“更多 → 配置 → 从 URL 安装配置”和 ClashMac 的“配置 → ＋ → 导入订阅”，补充粘贴、安装/完成、选择配置和刷新时保持塔台运行。ClashMac 路径依据 https://clashmac.app/guide/dashboard/profiles 。
- 19 项 MotionDesign / Localization 测试通过，855 条本地化提取检查通过；Mac 构建通过并更新开发应用，最终版已在实体 iPhone 覆盖安装并启动。未上传或发布。

### 2026-09-08 — 引导底色与 Mac 客户端顺序

- Mac 引导底部移除独立 regularMaterial，沿用整页背景，消除灰绿色矩形色差；手机材质不变。
- Mac 引导仍为 12 个，Mihomo Party 后紧接 sing-box MT、Clash。导出默认顺序同步调整；仅迁移旧默认顺序，保留自定义排序。
- ClientOrder / MotionDesign 测试通过，Mac 实际界面确认底色与两处排序；开发版已更新，实体 iPhone 已安装并启动。未发布。

### 2026-09-08 — Mac 客户端选择器鼠标滚动

- Mac 横向客户端列表增加滚动条独立留白，保持原图标卡片设计。使用仅接收 discrete scroll、禁用触摸输入的 UIPanGestureRecognizer，将普通鼠标纵向滚轮映射到横向偏移；触控板连续输入仍走原生滚动，手机不启用此处理。API 依据 https://developer.apple.com/documentation/uikit/uipangesturerecognizer/allowedscrolltypesmask 。
- 本机界面测试向下滚轮显示尾部客户端、向上返回开头，页面纵向位置保持不变；列表外滚轮正常滚动页面。最终界面确认滚动条与选中边框分离。
- ClientOrder / MotionDesign 测试及 Mac 构建通过，开发应用已更新；实体 iPhone 覆盖安装并启动。未发布。

### 2026-09-08 — 手机切换客户端时的闪动

- 异步配置生成期间原实现会移除 safeAreaInset 导出栏，并将结果/预览区域替换成较矮的加载提示，引起可用视口及内容高度反复变化。
- 非局域网目标始终保留导出栏；保留上一份结果的布局直到新请求完成。等待期间禁止预览、导出、分享或复制旧结果，所有操作仍只接受与当前请求匹配的配置。
- iOS 模拟器 ExportPresentation / AuditScale 的 26 项测试通过；新增 1,000 节点客户端切换 UI 测试通过，验证反复切换后导出栏和选择器纵向位置稳定。这不是实体设备帧率测量。
- 真机安装脚本未检测到唯一可用的实体 iPhone，本次尚未覆盖安装/启动；需连接手机后完成真机验收。未发布。
- 后续用户连接手机后重试成功：切换闪动修正版 1.0.8（46）已覆盖安装并启动到实体 iPhone；手机实际切换观感待用户确认。

### 2026-09-08 — 1.0.9（47）双平台 TestFlight 准备

- 用户授权推送代码，分别归档 iOS / Mac Catalyst 并上传 TestFlight；不提交新的 App Store 正式审核。更新日志见 releases/1.0.9.md。
- Mac 使用独立 entitlement 文件启用 App Sandbox、出站/入站网络与用户选择文件读写；iOS entitlement 保持不变。归档使用发布机正式版 Xcode。
- 855 条本地化检查、发布脚本测试、最新 ACL4SSR 检查和远程规则摘要校验通过；1.0.9（47）已在实体 iPhone 安装并启动。上传与处理状态需另行核对。
- 后续完成：提交 `7654b21` 已推送；iOS 与 Mac Catalyst 均由正式版 Xcode 26.6 分别归档、上传并完成 Apple 处理，自动关联内部测试组，两个平台的测试说明均已保存。用户自行提交外部测试；没有提交新的 App Store 正式审核。
- 完整回归：iOS 1,022 项 XCTest（3 跳过）与 52 项 Swift Testing，Mac 1,022 项 XCTest（33 跳过）与 52 项 Swift Testing，均无失败。

### 2026-09-08 — Mac 直接下载版 1.0.9（47）

- 复用提交 `7654b21` 的正式版 Xcode 26.6 Mac 归档，使用 Developer ID 自动签名导出；启用 Hardened Runtime，保留沙盒、网络、用户选择文件和 iCloud 签名授权。最低 macOS 14，包含 arm64 / x86_64。
- Apple 公证完成，公证凭证附加及验证通过。发布机实际启动并确认进程持续运行；开发机和 DMG 挂载内容均经 codesign strict/deep、Gatekeeper（Notarized Developer ID）及 stapler 验证。iCloud 跨设备同步未进行本次分发包专项实测。
- GitHub Release `v1.0.9` 已公开，含 `Tower-1.0.9-47-macOS-universal.dmg` 与 `SHA256SUMS.txt`；上传后回下载的 DMG 哈希校验通过。下载地址：https://github.com/pengchujin/tower/releases/tag/v1.0.9 。暂不含应用内自动更新。

### Mac 规则整行排序修正（1.0.11）

- 已回退两次仅在右侧把手绑定 SwiftUI 拖动的实现。规则列表与候选策略列表保留原生 `onMove`，Mac 鼠标从整行发起 UIKit 交互移动；iOS 继续使用原生触摸排序。
- Catalyst 系统拖拽会抢占并取消列表移动。只在这两类 Mac 列表禁用外部拖拽，以鼠标手势驱动原生移动；在按下时记录偏移，松开时补交目标位置，覆盖快速拖动没有中间事件的情况。
- Mac 实际 App 回归：名称、空白、右侧策略文字和把手连续往返拖动；候选策略非编辑和编辑状态；保存后默认项、放弃更改、完成后重启持久化均已核对。最终交付包另做整行拖动复测。自动化只拖把手不再作为整行排序验收。
- Mac TowerTests：1023 项 XCTest（33 跳过，0 失败），52 项 Swift Testing 通过；iOS 候选策略交互回归 1 项通过；实体 iPhone 已安装并启动。独立 Mac 测试包已本机构建，未归档或发布。

### 1.0.11（49）发布准备

- 包含 Mac 整行排序、内置规则自定义副本下载就绪状态修复，以及空策略组 DIRECT 回退。
- 本轮仅上传 iPhone / Mac TestFlight 构建，不操作内外测群组和审核；直接分发 Mac 版走 Developer ID、公证、GitHub Release 与 Homebrew。
- 当前源码 Mac / iOS 全量测试通过，ACL4SSR 最新版本检查与 77 个远程产物回读通过。正式归档与上传状态以发布完成记录为准。

### 1.0.11（49）发布完成

- 发布源码提交 `b8cd487`。正式版 Xcode 26.6 分别归档并上传 iPhone / Mac，版本、构建号与 Bundle ID 核对通过；App Store Connect 两个平台均已出现 49，最后核对时仍在处理。本轮未操作内外测群组、Beta 审核或 App Store 审核。
- Mac Developer ID 公证、stapler、Gatekeeper、arm64 / x86_64 与 DMG 回读 SHA-256 均通过；正式签名包已启动并验证整行和候选策略拖动。GitHub `v1.0.11` 已公开，README 下载入口及 Homebrew cask 已更新，issue #24 已回复。
- Homebrew style 检查及实际升级、安装版本 / 签名验证通过；audit 被本机 Homebrew 对已安装正式版 Xcode 26.6 的版本检查阻止，不能记为 audit 通过。未更改全局 Xcode 选择或发布机工具链。
- iOS 全量 1023 项 XCTest（3 跳过、0 失败）与 52 项 Swift Testing 通过；1.0.11（49）已安装到实体 iPhone，启动被锁屏状态拒绝。


### iCloud 清空配置修复（2026-09-15，开发验证）

- 复现空设备修改设置后以整份较新快照覆盖云端，另一设备同步后节点与规则被清空；改为共享基线三路合并，首次同步合并所有拥有的项目，明确删除只对基线中已有项目生效。
- 云端改为不可变版本图，保留并发分支和恢复历史；旧版 `state.json` 只读迁移，不再回写。所有设备须更新，旧客户端的后续改动不会自动进入新同步历史。
- 同字段冲突停止自动覆盖，设置新增恢复备份。应用替换前保存本地副本，明确重置清除本地备份，删除云端副本清除云端历史。
- 同订阅刷新产生的等价节点重新映射到同一 ID，并同步映射排除状态；自动更新时间、流量和地区缓存不作为用户编辑冲突。
- 测试宿主默认持久化路径与同步偏好隔离，私有兼容语料只有显式环境变量授权才读取。真实用户 iCloud 数据不作为自动测试数据。
- 跨设备真实 iCloud 传输仍需用户保留数据后验收；文件注入与单元测试不等同于真实云端往返成功。

- 验证：最终 Mac Catalyst 全量 TowerTests 1189 通过、35 跳过、0 失败；iOS 26.5 模拟器完整恢复交互测试通过（选择配置、确认恢复、生成保留副本、关闭页面）；本地化提取 1004/1004 无缺项。跳过包含需真实设备能力及明确 opt-in 的私有兼容语料。
- 安装：最终修复代码覆盖安装到连接的实体 iPhone；Mac 使用正式 Xcode 生成 Developer ID 签名、公证的通用包，覆盖安装至系统 Applications，安装后 Gatekeeper 通过。两端仍为 1.0.18 (56)，均未主动启动真实 App，保留用户配置；未推送或发布。
- 恢复入口使用设置中的导航页面，避免嵌套 sheet 在弹窗时重建、丢失确认事件。临时诊断记录已从源码移除。
