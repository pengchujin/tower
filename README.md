# 塔台

塔台是一款原生 SwiftUI iOS App，用来在设备本地管理机场订阅和自有节点，选择本机规则或手动下载 Self-Configuration，并生成 Surge、Stash、Clash、Shadowrocket、Loon、Quantumult X、Hiddify、sing-box MT 和 Egern 完整配置，以及 V2Box 节点订阅。

## 开发交接

- [Claude 接手指南](CLAUDE.md)：工程约束、常用命令和验收门槛。
- [当前开发状态](docs/HANDOFF.md)：TestFlight、远程归档、已知问题和后续任务。
- [技术架构](docs/ARCHITECTURE.md)：模块职责、数据流、配置生成和测试结构。
- [发布流程](docs/RELEASING.md)：TestFlight 归档、上传和本地配置。

## 当前能力

- 添加、启用、更新和删除 HTTPS 订阅
- 解析 SS、SSR、VMess、VLESS、Trojan、Hysteria、Hysteria 2、TUIC、WireGuard、AnyTLS、Snell、SOCKS5、HTTP(S) 节点
- 添加 SS、SSR、VMess、VLESS、Trojan、Hysteria、Hysteria 2、TUIC、WireGuard、AnyTLS、Snell、SOCKS5、HTTP(S) 自有节点
- 首页节点与订阅都可展开查看地址、协议、地区和测试方式
- 节点行使用服务器 IP 的离线国家识别结果显示地区 Logo，并列出协议、传输、TLS 与 UDP 能力
- 首页使用自绘的平面点阵世界地图，保留完整日期变更线范围；节点按名称优先、服务器主机名其次、离线 IP 回退的统一结果聚合，密集地区标签会按权重多方向避让
- 展开地图或订阅时自动进行真实 ICMP 延迟测试，也可单独或批量重测
- 读取常见 Base64 节点订阅和 Clash YAML，包括仅含 HTTP(S)/SOCKS 的 Base64 列表与 Clash 嵌套 WebSocket 选项
- Surge 配置形式的订阅目前只从 `[Proxy]` 读取 `ss=` 节点；其他 Surge 代理行会计入“跳过”，不会被误识别成 HTTP 链接
- 规则页底部提供 Self-Configuration 手动下载，只有用户点击后才从项目上游获取
- 内置 ACL4SSR 默认、精简、全分组三套规则，按配置原有的策略组结构还原
- 当前方案可搜索并勾选服务分组；最终兜底与被引用的基础策略自动保留
- 可新增、编辑和停用本地自定义规则流，内置 Tailscale 示例，刷新上游方案不会覆盖
- 输入链接导入 Clash YAML、subconverter（`.ini`）或 Surge 远程配置，下载到本机后离线使用，可刷新或删除
- 生成 Surge / Stash / Clash / Shadowrocket / Loon / QuanX / Hiddify / sing-box MT / Egern 完整配置
- 生成 V2Box Base64 节点订阅并通过其公开 URL Scheme 一键导入；V2Box 默认排在目标客户端列表最后
- 在导出前预览配置，并明确显示目标客户端不兼容而跳过的节点
- Surge、Stash、Clash、Shadowrocket、Loon、Egern、Hiddify、sing-box MT 和 V2Box 支持点击主按钮后通过 URL Scheme 一键打开并导入
- 主导入按钮固定在标签栏上方，滚动预览时仍可随时操作
- 十个目标客户端和“局域网共享”均可长按拖动排序；sing-box MT 默认位于客户端顺序第 5 位，旧快照会一次性迁移且保持其他客户端相对顺序，后续拖动仍会保存
- Quantumult X 通过系统分享接收本地配置文件
- 导出页可按需开启带随机密钥的局域网订阅，供 OpenClash、Windows 和 Mac 客户端自动识别或指定格式读取
- 设置页可由用户主动开启续费提醒；授权后在机场到期前 24 小时发送本地通知
- 设置页可开关“优先使用规则集”；兼容的客户端引用远程规则集以减小配置，不兼容的资源自动保留本地转换

## 隐私设计

转换、规则匹配和 IP 国家查询全部在设备上完成。App 不调用第三方订阅转换或 IP 地理位置服务，也不会上传用户节点。域名节点只通过系统 DNS 解析地址，随后查询 App 内置的离线数据库。

规则联网的边界：三个 ACL4SSR 快照随 App 打包，**完全离线**。Self-Configuration 不在源码或 App 包内，只在用户点击规则页底部的「手动下载」后直接从上游获取；导入其他规则链接或刷新已导入方案同样只在用户操作时联网。下载内容保存在本机，之后生成配置不再联网。

iCloud 同步是塔台里唯一会让数据离开这台设备的功能，因此默认关闭，且只在您明确开启时生效。开启后，订阅地址和节点密码会存进**您自己的** iCloud 账户，用于在同一 Apple 账户的设备之间同步；它们不会发给塔台或任何第三方。两台设备都改过时以最后保存的那份为准。关闭同步时可以选择一并删除 iCloud 上的副本，关闭之后也能在设置页随时删除。

写入磁盘的三类文件都使用 iOS 完整文件保护：Application Support 中的订阅快照、分享用的临时配置文件，以及分享用的临时二维码 PNG。后两类还会在再次生成时清理超过 5 分钟的旧文件，不会在 `tmp` 中长期堆积明文凭据。

打开添加面板时，塔台会按产品设定自动请求一次系统剪贴板权限；只有识别到支持的订阅或节点链接才会自动填入。也可以随时点击“从剪贴板粘贴”手动读取。

延迟测试优先向节点地址发送 ICMP Echo。部分机场或网络会屏蔽 ICMP，此时塔台会退回节点端口握手，并在界面明确标成“端口”，不会把它伪装成 ICMP 延迟。测试结果只保存在本次运行内。

Surge、Stash、Clash、Shadowrocket、Loon、Egern、Hiddify、sing-box MT 和 V2Box 的导入 Scheme 都需要客户端可读取的 URL。塔台会在导入时启动一个仅绑定到 `127.0.0.1` 的临时服务，并在 45 秒后自动关闭，所以配置不会上传到互联网。sing-box MT 使用官方 `sing-box://import-remote-profile` 入口接收完整 JSON 配置；V2Box 接收的是 Base64 节点订阅，不包含塔台规则和策略组。临时地址不用于后续自动刷新；规则或节点变化后，需要回到塔台再次一键导入。

导出页的局域网订阅与上述临时服务完全分开：它默认关闭，只在用户主动开启时监听 Wi-Fi，并用随机访问密钥保护路径。`target=auto` 会按 OpenClash/Clash、Surge、Shadowrocket、Loon、Quantumult X、Hiddify 或 Egern 的 User-Agent 生成对应格式，也可以在界面里复制指定格式的链接。客户端拿到的是塔台当前本地快照的转换结果，链接和 HTTP 响应都不包含机场原始订阅地址；因此需要自定义 UA 或 DNS 的机场仍由塔台请求，电脑和路由器不会接触机场密钥。受 iOS 后台限制，客户端刷新时需要让塔台保持在前台并与客户端位于同一 Wi-Fi。

Quantumult X 官方公开的 [URL Scheme](https://github.com/crossutility/Quantumult-X/blob/master/url-scheme.md) 只能添加或替换远程资源（`server_remote` / `filter_remote` / `rewrite_remote`），策略组不在其中，因此没有完整本地配置导入接口。塔台对 QuanX 保留系统文件分享，避免导入一份引用了不存在策略组的配置。

## 规则来源

规则页底部提供 [ClashConnectRules/Self-Configuration](https://github.com/ClashConnectRules/Self-Configuration) 的手动下载入口。App 不再分发它的配置或规则列表；点击后读取上游 `Clash.yaml`，解析策略组并把引用的规则列表保存到当前设备。删除该方案会同时删除本地下载内容。

### ACL4SSR

[acl4ssr-sub.github.io](https://acl4ssr-sub.github.io) 提供的默认、精简、全分组三份配置同样随 App 打包，资源位于 `Tower/Resources/ACL4SSR/`，固定提交号、来源与 SHA-256 记录在 `ACL4SSR_manifest.json`。打包前用 `python3 Scripts/update_acl4ssr_rules.py --latest` 拉取上游最新提交；完整发布步骤见 [发布流程](docs/RELEASING.md)。

这三份配置各自声明了自己的策略组（精简 5 组、默认 11 组、全分组 29 组），塔台按原样还原，其中的地区组沿用配置里的节点名正则。

ACL4SSR 的全部资源保留 `ACL4SSR_` 前缀，便于在 Xcode 拍平后的 bundle 根目录中识别来源，也让旧版本迁移保持稳定。

### 导入自己的规则

规则页的「导入规则链接」支持 Clash YAML、subconverter（`.ini`）和 Surge 配置。塔台只接受 HTTPS 地址，会下载配置和它引用的全部规则列表并保存到本机（完整文件保护），之后生成配置不再联网。已导入的方案可以随时刷新或删除。

选择方案后，「当前规则定制」可以搜索并勾选其中拥有实际规则的服务分组，例如国外媒体或 AI。取消分组不会破坏配置：末尾兜底和被引用的节点选择、自动选择等基础策略会按依赖自动保留。

「添加自定义规则流」把用户规则单独保存在 App 状态中，而不是写回下载的方案。每行接受 `TYPE,VALUE`，也可以粘贴带旧策略的客户端规则；塔台会统一改用界面里选择的流向并保留 `no-resolve`。因此刷新 Self-Configuration 或其他上游方案后，Tailscale 等自定义规则仍然存在，并会进入所有完整配置目标。

## 多语言

App 内置简体中文、繁体中文、英语、日语、韩语、西班牙语、法语、德语、巴西葡萄牙语、俄语、阿拉伯语、土耳其语、印尼语、泰语和越南语，共 15 种语言。系统会自动跟随 iOS，也可以在“设置 > App > 塔台 > 语言”里只修改塔台的显示语言。

界面、错误提示、通知权限说明和国家/地区名称会本地化；用户自己的订阅名、节点名和导入规则名保持原文。字符串位于 `Tower/Localizable.xcstrings` 和 `Tower/InfoPlist.xcstrings`。新增界面文案后先用 Xcode 导出简体中文源目录，再运行 `Scripts/generate_localizations.py --source-catalog <导出的 Localizable.xcstrings>`，最后执行完整测试；`LocalizationTests` 会检查所有文案是否覆盖全部 15 种语言。

## IP 国家库

离线国家数据来自 [sapics/ip-location-db](https://github.com/sapics/ip-location-db/tree/main/geo-whois-asn-country) 的 `geo-whois-asn-country`，版本 `2.3.2026061719`，依据 CC0 许可随 App 打包。`Scripts/update_ip_country_db.py` 可下载指定版本并重新生成紧凑的 IPv4/IPv6 二进制索引，来源说明位于 `Tower/Resources/IPCountry/NOTICE.txt`。

## 运行

1. 使用 Xcode 26 或更新版本打开 `Tower.xcodeproj`。
2. 选择 iOS 17 或更新版本的模拟器/设备。
3. 运行 `Tower` Scheme。

测试覆盖订阅解析、Clash YAML 嵌套字段、名称优先的国家地区聚合与离线 IP 回退、网络延迟链路、本地规则资源、各客户端一键导入 Scheme、九个完整配置目标，以及 V2Box 节点订阅。Loon 的 VMess/VLESS/Trojan/Hysteria 2 参数按其[节点文档](https://nsloon.bid/document/node)生成；Surge 的 TLS 与 WebSocket 参数按其[代理策略文档](https://manual.nssurge.com/policy/proxy.html)生成。

## 已知边界

- Shadowsocks 的 SIP003 插件只支持 simple-obfs（`obfs`/`obfs-local`）。`v2ray-plugin` 等其余插件会被明确拒绝并计入“跳过”，不会伪装成可用的裸 SS 节点导入。
- Snell 只有 Surge 和 Shadowrocket 全版本支持，Clash/Stash 仅到 v3，sing-box MT 只接受 v4 以上，Hiddify、Loon 和 Quantumult X 不支持——不支持的目标会计入“跳过”。
- WireGuard 只接受能够完整保留密钥、本机地址、对端和路由的单 Peer 配置；多 Peer 配置会明确计入“跳过”，不会静默压成错误节点。QuanX 不支持 WireGuard，Shadowrocket 的仅节点订阅也会跳过它，完整配置仍可写入。
- Hiddify 与 sing-box MT 都接收 sing-box JSON，但保留各自的客户端身份、导入 Scheme 和协议能力矩阵。
- V2Box 当前接收 SS、VMess、VLESS、Trojan、WireGuard、Hysteria 2、SOCKS5 和 HTTP(S) 节点订阅，不生成或替换规则与策略组；其余协议会明确计入“跳过”。
- 机场厂商自定义的非标准节点字段可能需要增加兼容适配。
- 如果目标客户端未安装或没有接管对应 Scheme，塔台会自动退回系统分享。
- Quantumult X 是否直接出现在分享列表中，取决于其声明的文件类型；未出现时可先存到“文件”再从客户端导入。
- 当前未连接安装了 Surge、Shadowrocket、Loon、Quantumult X 的真机做最终接收测试；生成格式与兼容跳过逻辑已有自动测试。

## 许可证

源码以 [MIT](LICENSE) 发布。

`Tower/Resources/` 下随 App 打包的规则列表和 IP 数据库来自第三方，**保留各自原有条款，不适用 MIT**：

| 资源 | 来源 | 许可证 |
| --- | --- | --- |
| ACL4SSR 规则 | [ACL4SSR/ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) | CC BY-SA 4.0 |
| IP 国家库 | [sapics/ip-location-db](https://github.com/sapics/ip-location-db) | CC0 1.0 |

详见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。Self-Configuration 由用户从其上游手动下载，不属于随 App 分发的资源。

塔台只在本机把订阅转换成各客户端的配置文件，**不含 VPN 或代理功能，不接管任何流量**。
