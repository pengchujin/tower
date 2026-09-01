# Claude 接手指南

这是“塔台”iOS App 的仓库级入口说明。开始修改前，请依次阅读：

1. `README.md`：产品能力、隐私模型和已知边界。
2. `docs/HANDOFF.md`：截至 2026-08-03 的实现状态、TestFlight 状态和优先事项。
3. `docs/ARCHITECTURE.md`：模块、数据流、配置生成和测试结构。

## 工程基线

- 原生 SwiftUI，最低 iOS 17，建议使用 Xcode 26 或更新版本。
- **按三台机器固定 Xcode**：出门使用的 MacBook Air M2 用正式版 `/Applications/Xcode.app/Contents/Developer` 开发调试、真机安装、归档，并可在出门时完成 App Store Connect / TestFlight 上传；家中的 Mac mini M4 用 `/Applications/Xcode-beta.app/Contents/Developer` 开发调试；家中另一台 Mac mini M2 用正式版 `/Applications/Xcode.app/Contents/Developer` 作为固定发布机。运行 `xcodebuild`、`xcrun simctl` 或 `xcrun devicectl` 前必须按所在机器显式设置 `DEVELOPER_DIR` 并用 `xcodebuild -version` 复核；不要依赖或切换全局 `xcode-select`。2026-09-01 已在 Air 上完成 `1.0.5 (38)` 的自动签名、归档和上传；此前的 `Failed to Use Accounts` 是正式版 Xcode 未登录 Apple Account，不是证书、描述文件或 App Store Connect 角色问题。相同错误先检查 Xcode **Settings ▸ Accounts**，登录后复用已有归档，不要无谓重打包。
- 工程：`Tower.xcodeproj`；Scheme：`Tower`。
- Bundle ID：`com.jzb.tower`。
- App Store Connect App ID：`<App Store Connect App ID>`。
- 规则快照和 IP 国家库都随 App 打包，运行时不依赖远程转换服务。
- `DEVELOPMENT_TEAM` 故意没有写死在工程里；本地运行时由 Xcode 或命令行覆盖。

## 不可破坏的产品约束

1. 订阅内容、节点和生成配置只在本机处理，不上传到第三方转换或 IP 查询服务。
2. 域名节点可以使用系统 DNS 解析，但国家识别必须继续查询内置离线 IP 库。
3. Surge、Stash、Shadowrocket、Loon 的一键导入继续使用仅绑定 `127.0.0.1`、45 秒自动失效的临时服务。
4. Quantumult X 没有完整本地配置导入 Scheme，保持系统文件分享，不要伪装成完整一键导入。依据是官方 [url-scheme.md](https://github.com/crossutility/Quantumult-X/blob/master/url-scheme.md)：`update-configuration` 和 `add-resource` 的 `remote-resource` 只接受 `server_remote` / `filter_remote` / `rewrite_remote` 三种**远程资源地址**，`[policy]` 策略组不在其中。只导节点和规则会得到一份引用了不存在策略组的配置。
5. 国家/地区组默认使用延迟优选，同时保留父级策略中的手动选择入口；不要让地区组互相引用或引用包含自己的上级组。
6. 策略组名称只显示一个前置 Logo。生成配置时可附带各客户端支持的图标字段，但不要把同一个 Emoji 再拼进可见名称。
7. 首页订阅展开不使用从顶部滑入的过渡；节点列表不再提供“显示更多节点”。
8. 首页使用自绘的点阵世界地图（`WorldDotMapView`），不用 MapKit。地图数据是 `Tower/Resources/WorldMap/WorldDotMap.txt` 陆地点阵和 `WorldDotCountries.txt` 国家归属层，用 `Scripts/update_world_dot_map.py` 一并重新生成；有节点覆盖的国家直接显示绿色地图点，选中国家使用更深、更密的绿色且名称保持中性文字；覆盖国家的整个点阵轮廓必须可直接点击，不再叠加独立绿色定位点。
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
19. 节点地区**先按节点名判断**（国旗 Emoji → 中英文国名/别名/城市 → 大写国家代码），名字看不出来才查内置离线 IP 库；策略分组和界面用同一个顺序，不要让两边给出不同的国家。国家表由 `Scripts/update_country_table.py` 生成到 `Tower/Services/CountryTable.swift`，不要手改。
20. 国旗一律用 Emoji 正常渲染，不要为个别地区自绘图形；iOS 没有字形的（例如 TW）就显示成两个字母，这是系统行为。列表里国旗外面不加圆形底。
21. `Tower/Resources/` 下的第三方数据不适用源码的 MIT 许可。新增或更新打包资源时，必须同步更新 `THIRD-PARTY-NOTICES.md` 和对应目录的 NOTICE，注明来源、固定版本和许可证。`LICENSE` 里「仅覆盖源码」那段说明不要删除，即使 GitHub 因此把许可证识别成 `Other`。
22. 刷新订阅必须保住用户「取消勾选」的节点。节点 id 每次解析都会重新生成，机场又常把剩余流量、倍率写进 remark，塔台自己也会给纯国旗节点重编号——所以不能只按含 name 的精确 identity 匹配。`AppModel.carriedOverExclusions` 是唯一的判定入口：先精确匹配，失配再用去掉 remark 的宽松键，且只有该键在刷新前后都唯一时才认。丢失排除的后果是静默的——节点直接回到每一份导出配置里。
23. `AppModel.apply()` 必须把 `snapshot.updatedAt` 恢复到 `lastLocalEditAt`。不恢复的话，启动后第一次前台同步会拿 `.distantPast` 去和 iCloud 比，任何远端快照都赢——包括更旧的那份，然后覆盖本地文件。离线时改的订阅会在下次启动被静默丢弃。

## 常用命令

```sh
# 当前出门使用的 MacBook Air M2 使用正式版 Xcode；可开发、真机安装、归档和上传
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 家中 Mac mini M4 开发调试时改用 Xcode Beta
# export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# 家中 Mac mini M2 作为固定 App Store Connect / TestFlight 发布机时仍使用正式版 Xcode
# export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 查看可用模拟器
xcrun simctl list devices available

# 模拟器测试（设备名称可按本机修改）
xcodebuild -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derived-data-sim \
  test

# 不签名编译检查
xcodebuild -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derived-data-audit \
  build

# 更新固定版本的规则和 IP 国家库
python3 Scripts/update_self_configuration_rules.py
python3 Scripts/update_ip_country_db.py --help

# 检查有没有「源码能显示、目录里没有」的文案
bash Scripts/check_localization.sh
```

更新规则或 IP 库后，必须同时检查对应 `manifest.json` / `NOTICE.txt`、资源哈希和自动测试；不要只替换二进制资源。

## 改动验收

- 每次提交至少通过 TowerTests；配置生成相关修改要覆盖全部七种目标客户端。
- 新增或修改界面文案后跑 `Scripts/check_localization.sh` 发现缺口，再用 `Scripts/generate_localizations.py --source-catalog <Xcode 导出的 Localizable.xcstrings>` 填补，短标签和无障碍文案需人工复核。`LocalizationTests` 只校验「目录里已有的条目是否 15 种语言齐全」，对「源码有、目录没有」完全无感——这类缺口不会报错，只会在其余 14 种语言下直接显示中文。该脚本用 Xcode 自己的提取器比对，不要改用 grep 手写：`Text`、`Label`、`.navigationTitle`、`.accessibilityHint`、弹窗标题等位置手写正则覆盖不全，插值也无法还原成 `%@` / `%lld`。
- 目录里被 Xcode 标成 `stale` 的条目**不要删**。内置 ACL4SSR 方案名和简介来自 manifest，运行时经 `String(localized: String.LocalizationValue(name))` 本地化，静态提取器看不见它们。
- 涉及导入、分享、剪贴板、地图、ICMP、动画或大文本预览时，模拟器结果只算基础验证，必须再用真机验收。
- 发布新包前递增 `CURRENT_PROJECT_VERSION`，归档并核对 Bundle ID、版本号和签名团队。
- 不提交 `.artifacts`、DerivedData、归档、IPA、证书、描述文件、App Store Connect API Key 或任何密码。
- 加密合规：当前实现没有自研或非标准加密，只通过 Apple 系统网络栈使用 HTTPS。App target 的 Debug/Release 都已设置 `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`，构建不会再在 App Store Connect 留下待回答的出口合规问题；新增 target 时记得一并设置。

真机回归清单、待办任务与发布信息见 `docs/HANDOFF.md`。
