# 塔台

塔台是在 iPhone 本机管理订阅、自有节点与规则，并生成客户端配置的原生 SwiftUI App。它不建立网络隧道、不接管流量、不提供服务器或节点。

## 能做什么

- 解析 SS、SSR、VMess、VLESS、Trojan、Hysteria、Hysteria 2、TUIC、WireGuard、AnyTLS、Snell、SOCKS5、HTTP(S)。
- 管理订阅、自有节点和单节点勾选；刷新保留排除状态，勾选不改变首页顺序。
- 名称优先识别地区，无法判断时回退离线 IP 国家库；点阵地图、ICMP 测速及明确标注的端口测试。
- 内置 ACL4SSR 默认、精简、全分组三套离线规则；手动导入 HTTPS 规则方案、添加自定义规则流。Self-Configuration 仅提供手动下载，不随 App 分发。
- 预览、分享或一键交给客户端；筛选客户端、拖动排序，局域网共享可一起显示/隐藏和排序。
- 支持 15 种界面语言，以及默认关闭的到期提醒、打开时刷新订阅、iCloud 同步和代理集合。

## 客户端与导出

| 配置类型 | 客户端 |
| --- | --- |
| 完整配置 | Shadowrocket、Stash、Surge、Loon、QuanX、Clash、sing-box MT、Hiddify、Egern、Clash Mi、Karing |
| 仅节点订阅 | V2Box |
| 前台局域网共享 | 按客户端 User-Agent 自动识别，或手动指定支持格式 |

QuanX 使用系统文件分享；其他目标通过客户端 URL Scheme 导入，无法打开时回退分享。Hiddify 和 sing-box MT 虽然同为 sing-box JSON，身份与协议能力分别处理。无法无损表达的节点会跳过并计数，不会伪装成另一种协议。

**代理集合**默认关闭。开启后，Stash、Clash、Clash Mi、Karing、Surge、Loon、QuanX、Egern 的完整配置可包含原始订阅 URL，由客户端自行更新远端节点。Shadowrocket、Hiddify、V2Box、sing-box MT 保持本地展开。

远端来源必须返回目标兼容的格式；远端节点不受塔台的逐节点勾选、协议筛选、名称追加和自定义 DoH 控制。协议筛选与节点计数只作用于本地输出；摘要另外列出远端来源数。塔台规则或自有节点变化后仍需重新导出。

## 隐私与网络边界

转换、规则匹配、地区查询在本机完成，没有第三方在线转换或 IP 查询服务。订阅凭据默认留在设备；主动开启 iCloud 后存入自己的 iCloud，主动开启代理集合后原始 URL 随配置交给目标客户端。分享文件也会分享其中的凭据，请只交给可信接收方。

- 本机一键导入使用仅绑定 `127.0.0.1`、45 秒失效的临时 HTTP 服务，不是长期订阅托管。
- 局域网共享是独立的前台服务，主动开启后允许同一网络的设备凭随机密钥获取配置；关闭或轮换密钥可撤销访问。代理集合开启时，这份配置也可能含原始订阅链接。
- 凭据类快照、配置文件和二维码使用完整文件保护；临时导出文件会清理。
- 内置规则不会在运行时联网更新；只有用户导入或刷新规则时才获取 HTTPS 地址。
- 添加面板请求一次剪贴板读取，仅识别受支持链接；相机与本地网络按使用场景请求权限。

详见[隐私政策](docs/privacy.md)及[使用与支持](docs/support.md)。

## 规则与已知边界

自定义规则在本机生成，不即时编译 MRS/SRS。内置 ACL4SSR 的已验证二进制可供兼容客户端引用：Stash / Clash / Clash Mi 使用 MRS，sing-box MT 使用 SRS；其他目标沿用兼容文本或内联。内容与编译源不一致时回退，不复用旧二进制覆盖新规则。发布流程固定源版本、哈希和不可变产物 URL。

SS 插件仅支持 simple-obfs；WireGuard 多 Peer 不做有损压缩；Snell 等协议按各目标能力判断。Surge 输入目前仅解析 `[Proxy]` 中的 SS 行，其他行计入跳过。客户端是否接收分享、重复导入是否覆盖，由客户端决定，不能由生成成功推断连通。

## 开发入口

最低 iOS 17；打开 `Tower.xcodeproj`，运行 `Tower` Scheme。

- [CLAUDE](CLAUDE.md)：产品约束与验收门槛
- [当前交接](docs/HANDOFF.md)、[未完成任务](docs/TODO.md)
- [开发、测试与安装](docs/DEVELOPMENT.md)、[架构](docs/ARCHITECTURE.md)
- [规则更新与 TestFlight 发布](docs/RELEASING.md)

## 许可证

源码以 [MIT](LICENSE) 发布。第三方资源不适用源码 MIT：ACL4SSR 为 CC BY-SA 4.0，离线 IP 国家库为 CC0；其他来源与版本见 [THIRD-PARTY-NOTICES](THIRD-PARTY-NOTICES.md) 和资源目录 NOTICE。不得删除或改写原许可义务。
