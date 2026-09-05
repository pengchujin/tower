# 开发与验证

先读 [CLAUDE.md](../CLAUDE.md) 的产品约束。机器对应的 Xcode 以 [AGENTS.md](../AGENTS.md) 为准，不切换全局 xcode-select。

## 工具链

```sh
# MacBook Air M2 / 发布用 Mac mini M2
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# 开发用 Mac mini M4 改为 /Applications/Xcode-beta.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
```

## 日常验证

在仓库根目录运行；模拟器名称按本机调整，复用 DerivedData，不要每次 clean。

```sh
xcodebuild -project Tower.xcodeproj -scheme Tower -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derived-data-sim test

xcodebuild -project Tower.xcodeproj -scheme TowerInteraction -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derived-data-sim test

bash Scripts/check_localization.sh
bash Scripts/tests/release_testflight_test.sh
python3 Scripts/tests/update_acl4ssr_rules_test.py
```

- TowerTests 验证解析、生成、持久化、异步竞态及排序几何；TowerInteraction 用实际轻点、横滑、长按拖动验证界面。源码结构守卫不能代替交互测试。
- UI 测试的 Debug 专用 UUID 沙盒隔离真实数据，并可跨启动验证持久化；不将测试入口带入 Release。
- 新文案必须覆盖 15 种语言。按检查脚本给出的 Xcode 提取目录运行本地化生成器，人工核对短标签和无障碍文本。不要删除 catalog 中的 stale 方案名。
- 凭据文件保护与网络权限有平台差异；模拟器跳过项不能视为真机通过。

## 真机增量安装

连接并解锁一台已配对、开启开发者模式的 iPhone，然后：

```sh
zsh Scripts/install_device.zsh
```

脚本先检查连接，再从匹配 Bundle ID 的开发描述文件读取唯一团队，使用自动签名、复用 .derived-data-device，覆盖安装并启动。覆盖安装保留数据；不要先卸载 App。

- 找不到设备就停止，不反复编译。优先检查数据线、解锁、配对和开发者模式。
- 不从证书列表“第一项”猜团队，不同时设置自动签名和固定描述文件。
- 本地资产缺失/过期时，检查规定的 Xcode 的 Settings → Accounts；需要时由 Xcode 更新签名资产，不擅自撤销证书或退出账号。
- 安装成功和启动成功是两个阶段，分别确认。构建版本号相同也不能证明手机上是最新代码。
- 正常路径不打印私有标识；Xcode 错误日志可能含团队或描述文件路径，转贴前必须脱敏。

## 真机回归清单

- 导出：轻点切换、从卡片中间横滑、长按跨槽排序、边缘自动滚动、松手后立即再点/拖；退出筛选后当前选择可见。
- 筛选：整行空白处添加、移除、跨不同高度行排序、快速连续操作、重启后恢复；至少保留一个客户端，局域网入口也可隐藏排序。
- 布局：小屏、辅助功能大字号、长语言、VoiceOver、减少动态效果；检查手柄与删除按钮完整显示。
- 数据：刷新中编辑/删除来源、切换 iCloud、取消勾选后刷新、地图改名与分享；不得恢复旧凭据或丢失排除状态。
- 导出方式：文件、二维码、剪贴板、各客户端一键导入；代理集合分别测试仅远端与混合本地节点。
- 网络：本机服务 45 秒失效；局域网密钥轮换、关闭/切后台、权限拒绝；ICMP/DNS 及无网场景。
- 性能：使用 1,000 / 5,000 节点检查地图、切换目标和滚动；记录设备、数据规模和 Instruments 证据，不把模拟器耗时当成手机帧率。

发布另见 [RELEASING.md](RELEASING.md)。只有用户要求发布时才递增版本、推送、归档或上传。
