# 塔台开发交接（2026-08-03）

## 1. 当前结论

塔台已完成可运行的原生 SwiftUI 主流程：导入订阅/自有节点、节点解析和地区识别、MapKit 地球、ICMP/端口测速、本地 Self-Configuration 规则、五种客户端配置生成、配置预览及导入/分享。

当前代码版本为 `1.0 (1)`，Bundle ID 为 `com.jzb.tower`。已在远程 Mac 使用 Apple Development/Distribution 环境完成 Release Archive，并上传到 App Store Connect。上传完成时 Apple 返回的 Delivery UUID 为 `596f07bc-00b8-4d69-a80b-192088b52aaf`；当时构建处于 Processing，接手后应以 App Store Connect 页面为准重新确认最终状态。

这个仓库快照的重点不是继续堆功能，而是做一次真机回归、补齐 TestFlight 元数据和修正仍可复现的性能/兼容问题。

## 2. 产品目标与确定的交互

### 首页

- “+”统一添加机场订阅和自有节点，弹出后尝试读取剪贴板，提示同时覆盖订阅 URL 和节点协议链接。
- 顶部统计项“订阅、节点、覆盖地区、自有节点”可滚动到对应内容。
- 订阅可展开节点，但不显示“更多节点”，展开使用透明度/布局变化，不从顶部滑入。
- 节点行显示 IP 国家/地区 Logo、名称、协议/传输/UDP 信息和真实延迟。
- 订阅和单节点都可以分享；单节点导出协议链接和二维码。
- 页面直接嵌入圆形 MapKit 地球，显示带 Emoji 的节点标注，不单独设置“地球”标签页。

### 规则页

- 默认规则只有 ClashConnectRules/Self-Configuration。
- 策略组只保留一个前置图标，不在名称内重复 Emoji。
- “手动切换”“自动选择”“全球直连”等使用中文可见名称并匹配图标。
- 香港、日本、美国、新加坡等国家/地区策略位于业务策略之后。
- 地区组本身默认延迟优选；业务策略仍可手动选择地区组。
- 生成器必须避免地区组、节点选择和业务策略之间的循环引用。

### 导出页

- 目标客户端使用对应 App Store 图标，横向滚动选择。
- 主按钮固定在标签栏上方，一次点击就通过客户端 Scheme 导入。
- Surge、Stash/Clash、Shadowrocket、Loon 使用本地临时 URL；Quantumult X 使用文件分享。
- 支持配置摘要和完整预览，但不要在客户端切换动画中同步重复生成大文本。

## 3. 已完成的关键实现

### 本地规则

- 上游：`ClashConnectRules/Self-Configuration`。
- 固定修订：`fb658cc85802`。
- 本地资源：`Tower/Resources/SelfConfiguration/`。
- 版本、来源、数量和 SHA-256：`manifest.json`。
- 更新脚本：`Scripts/update_self_configuration_rules.py`。

运行时不拉取规则，保证离线可用并避免上游改动导致同一版本生成结果漂移。

### IP 国家库

- 上游：`sapics/ip-location-db` 的 `geo-whois-asn-country`。
- 当前版本：`2.3.2026061719`。
- 二进制索引：`Tower/Resources/IPCountry/`。
- 更新脚本：`Scripts/update_ip_country_db.py`。

节点是域名时先用系统 DNS 获取地址，再查询内置库。只有失败时才参考节点名称，因此 Amsterdam、Spain、Israel 等英文名称不再决定最终国旗。

### 一键导入

目标客户端不能读取塔台沙盒文件路径，所以 `DirectImportService` 会启动仅绑定 `127.0.0.1` 的 token 化 HTTP 服务，45 秒后关闭，再把临时 URL 放进各客户端 Scheme。该服务不监听局域网地址，不上传配置。

Quantumult X 的公开 Scheme 只覆盖远程资源操作，无法可靠导入完整本地节点、策略组和规则，因此保留文件分享。

### 策略组

当前生成器按 IP 识别结果创建地区组，为地区组建立延迟优选，同时让节点选择/业务策略引用这些地区入口。历史上出现过以下回归，修改时必须保留测试：

- 地区组互相引用导致 Surge/Shadowrocket 报循环。
- 节点选择间接包含自身。
- 策略名称自带 Emoji，同时 UI/客户端图标字段再显示一次，造成重复。
- 地区组只有手动选项或只有自动组，不能兼顾默认延迟优选和人工覆盖。

## 4. 当前 TestFlight / App Store Connect 状态

### 已确认

- App 名称：塔台。
- App Store Connect App ID：`6797458927`。
- Bundle ID：`com.jzb.tower`。
- SKU：`com.jzb.tower`。
- 版本/构建：`1.0 (1)`。
- 签名 Team ID：`G63LDXL9QJ`。
- Release Archive 和上传流程成功结束。

### 接手后立即确认

1. App Store Connect 中 build 1 是否已经结束 Processing，是否有邮件或页面警告。
2. “App 加密文稿”选择是否已经保存。按当前代码，应选择“不属于上述的任意一种算法”：App 没有 CryptoKit、CommonCrypto、SecKey 或自研算法，只通过 Apple 系统框架访问 HTTPS；Base64 只是编码。
3. 下个 build 在生成的 Info.plist 中加入 `ITSAppUsesNonExemptEncryption = NO`，减少重复询问；提交前仍要按当时功能重新判断。
4. TestFlight 的测试信息、联系邮箱、Beta App 描述和内部测试组是否完整。
5. 若要外部测试，补齐 Beta App Review 信息和登录说明；本 App 当前不需要账户。

## 5. 远程 Mac 归档说明

远程构建机位于同一局域网，主机为 `jzb@192.168.1.214`，已经登录 Apple 开发者账号。凭据和登录密码不写入仓库，也不应发给接手模型保存。

该机器的默认 `xcode-select` 曾指向 Command Line Tools，构建命令需要显式指定：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

SSH 非交互归档曾因钥匙串上下文返回 `errSecInternalComponent`。成功方式是在交互 SSH 会话中手动解锁 login keychain，然后在同一会话执行归档。不要把钥匙串密码放进脚本、Shell 历史或 Git。

归档命令基线：

```sh
xcodebuild -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Tower-1.0-1.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=G63LDXL9QJ \
  CODE_SIGN_STYLE=Automatic \
  archive
```

导出使用 `app-store-connect`、`destination=upload`、Automatic signing、Team ID `G63LDXL9QJ`。本地 `.artifacts/` 中可能有归档和 IPA 备份，但已被 `.gitignore` 排除；它们不是源码交接的一部分。

每次重新上传前必须增加 `CURRENT_PROJECT_VERSION`，不要重复上传 build 1。

## 6. 优先任务

### P0：发布闭环

1. 确认 build 1 的 Processing/合规状态并加入内部 TestFlight 测试组。
2. 在至少一台 iOS 17+ 真机完成启动、订阅导入、地图、测速、规则和导出主流程。
3. 为下个构建补 `ITSAppUsesNonExemptEncryption = NO`，构建号增至 2。

### P1：性能和崩溃回归

1. 反复展开/关闭“配置预览”，使用包含数百节点的大订阅观察是否仍闪退。
2. 快速横向切换五个目标客户端，确认图标和配置不重复加载、动画不掉帧。
3. 第一次打开节点/订阅分享 Sheet，确认二维码生成和 Activity View 不阻塞主线程。
4. 如仍卡顿，先用 Instruments 的 Time Profiler / Allocations 复现，重点排查：
   - SwiftUI body 中重复生成完整配置。
   - 大字符串在 `Text`、剪贴板、分享 payload 之间产生多份副本。
   - 客户端图标在滚动时重复解码。
   - 二维码在主线程同步生成。

### P1：五客户端真机兼容

准备安装相应客户端的测试机，分别验证：

- Surge：代理、策略组、图标、规则和一键导入。
- Stash/Clash：YAML 语法、proxy-groups、URL-test 和图标 URL。
- Shadowrocket：节点协议链接、策略环路、规则和 Scheme 接收。
- Loon：VMess/VLESS/Trojan/Hysteria 2 参数及策略组。
- Quantumult X：分享文件能否出现在目标列表；若不能，验证“存储到文件”后手动导入。

### P2：解析兼容

- 收集不能识别的真实机场样本时，先脱敏密码、UUID、token 和域名。
- 每修复一种格式都加入最小自动测试。
- 对 HTTP 错误页、登录页和空订阅保持明确错误，不把它们解析成节点。

## 7. 真机回归清单

### 首页

- [ ] 首次点击“+”时剪贴板权限文案正常，订阅和节点都能自动识别。
- [ ] 四个统计项跳到正确位置。
- [ ] 订阅展开没有从顶部滑入或列表勾选漂移。
- [ ] 节点国旗与服务器 IP 匹配，失败时回退合理。
- [ ] 地球为圆形 globe，国家/城市标注和节点 Emoji 正常。
- [ ] ICMP 与“端口”回退标识准确。
- [ ] 节点和订阅分享、二维码、协议链接可用。

### 规则

- [ ] 只显示 Self-Configuration 默认规则。
- [ ] 策略列表仅一个前置 Logo，不重复 Emoji。
- [ ] 地区策略位于业务策略之后。
- [ ] 地区默认延迟优选，业务策略可手动选择地区。
- [ ] 展开/收起时选择标记不漂移。

### 导出

- [ ] 五个 App Store 图标立即出现，横向滚动与切换流畅。
- [ ] 摘要中的节点数、跳过数、规则数正确。
- [ ] 完整预览多次展开不闪退。
- [ ] 固定主按钮不被底部标签栏遮挡。
- [ ] 安装客户端时一键打开；未安装时回退分享。
- [ ] 本地临时 URL 只能从本机访问，并在约 45 秒后失效。

### 恢复与隐私

- [ ] 杀掉 App 后订阅和自有节点恢复。
- [ ] 日志中没有订阅 URL、节点密码、UUID 或完整配置。
- [ ] 飞行模式下仍可查看已保存内容并生成配置。

## 8. 自动测试与提交门槛

至少运行：

```sh
xcodebuild -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derived-data-sim \
  test
```

配置生成器修改需要额外人工打开五种输出，检查：

- 所有组引用存在且无环。
- 地区组只含对应节点，空地区不产生死组。
- 节点名称转义、去重和协议跳过正确。
- 规则顺序与末尾兜底未改变。
- 图标字段符合目标客户端语法，显示名称不重复 Emoji。

提交前执行 `git diff --check`，确认没有把 `.artifacts`、`.derived*`、证书、描述文件或 API Key 加入暂存区。

## 9. 文档与代码入口

- 产品说明：`README.md`
- 接手约束：`CLAUDE.md`
- 架构：`docs/ARCHITECTURE.md`
- 中央状态：`Tower/AppModel.swift`
- 领域模型：`Tower/Models/DomainModels.swift`
- 配置生成：`Tower/Services/ConfigurationGenerator.swift`
- 一键导入：`Tower/Services/DirectImportService.swift`
- 订阅解析：`Tower/Services/SubscriptionParser.swift`
- 首页：`Tower/Features/Subscriptions/SubscriptionsView.swift`
- 规则页：`Tower/Features/Rules/RulesView.swift`
- 导出页：`Tower/Features/Export/ExportView.swift`
- 自动测试：`TowerTests/`

## 10. 交接原则

- 先复现、记录输入规模和设备，再修性能或崩溃。
- 不以模拟器成功代替客户端 Scheme 和真机网络验收。
- 不为了“一键导入”引入公网中转或上传用户配置。
- 不追踪生成产物和签名材料。
- 功能、测试、文档与 build number 同步提交，避免下一位接手者从聊天记录猜状态。
