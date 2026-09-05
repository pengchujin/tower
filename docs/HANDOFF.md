# 当前交接

更新：2026-09-05。产品约束以 [CLAUDE.md](../CLAUDE.md) 为准；本文只记录当前状态，不再叠加历史开发日志。

## 版本与工作区

- **1.0.6 (41)** 已于 2026-09-05 在家中 Mac mini M2 使用正式版 Xcode 26.6 完成 Release 归档并上传 App Store Connect，发布提交 `327c940`。远程归档、导出上传均成功，脚本退出码为 0；归档版本、Bundle ID、签名及团队匹配已核验。
- App Store Connect 已显示 build 41，当前仍在处理；尚未确认可供测试或加入测试群组。
- build 41 包含 Clash Mi / Karing、客户端筛选与局域网统一排序、代理集合，以及[项目审查修复](../plans/2026-09-05-project-audit.md)。
- 客户端选择不再强制居中；完整可见的卡片保持位置，被裁切的卡片以短动画最小滚动至完整可见，遵循减少动态效果设置。
- 内置 ACL4SSR 更新至 `864e3f3856347f67f4125505365295a7cc0490e7`，MRS/SRS 固定到不可变产物提交；发布前全量校验。
- 审查修复覆盖异步来源提交、iCloud 比较、导出统计/缓存、地图更新、可打断排序、大字号和无障碍。真机触摸手感仍需按 DEVELOPMENT 清单验收。
- build 41 发布前验证：TowerTests 929 通过、0 失败、1 跳过；发布脚本及规则更新脚本测试通过；77 个远程规则产物全量回读校验通过；本机 Xcode Beta 签名构建已覆盖安装并在 iPhone 启动。
- 本版更新日志见 [1.0.6 (41)](RELEASE-NOTES-1.0.6-41.md)。

## 功能边界

- 轻点客户端切换；直接横滑浏览；长按卡片后拖动排序。筛选页右侧手柄直接拖动。两个入口共用持久化顺序，局域网是导出入口而非新的配置格式。
- 勾选订阅或自有节点不改变首页排序。刷新迁移节点排除状态，旧请求不得覆盖新编辑或已删除来源。
- 代理集合默认关闭：支持的完整配置直接引用原始订阅 URL，由客户端更新远端节点。协议筛选和本地节点统计不代表远端实际内容。
- 代理集合支持 Stash、Clash、Clash Mi、Karing、Surge、Loon、QuanX、Egern；Shadowrocket、Hiddify、V2Box、sing-box MT 保留本地展开。不要把社区 sing-box fork 的 provider 扩展视为所有客户端支持。
- 原始链接可能含凭据；只在用户主动开启时写出。iCloud 同步也须单独授权，默认关闭。
- 一键导入的本机服务仅绑定 127.0.0.1，45 秒失效；局域网共享是独立、用户主动开启的前台服务。二者不能混为长期后台订阅托管。
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
