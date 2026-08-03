# 塔台

塔台是一款原生 SwiftUI iOS App，用来在设备本地管理机场订阅和自有节点，使用 Self-Configuration 分流规则，并生成 Surge、Clash、Shadowrocket、Loon、Quantumult X 配置。

## 开发交接

- [Claude 接手指南](CLAUDE.md)：工程约束、常用命令和验收门槛。
- [当前开发状态](docs/HANDOFF.md)：TestFlight、远程归档、已知问题和后续任务。
- [技术架构](docs/ARCHITECTURE.md)：模块职责、数据流、配置生成和测试结构。

## 当前能力

- 添加、启用、更新和删除 HTTPS 订阅
- 添加 SS、SSR、VMess、VLESS、Trojan、Hysteria 2、SOCKS5 自有节点
- 首页节点与订阅都可展开查看地址、协议、地区和测试方式
- 节点行使用服务器 IP 的离线国家识别结果显示地区 Logo，并列出协议、传输、TLS 与 UDP 能力
- 首页直接使用 MapKit 嵌入可旋转、缩放和调整视角的圆形地球，优先按服务器 IP 的离线国家结果聚合节点，并显示 Apple 地图中的国家、城市与边界标注；IP 暂不可解析时才参考节点名称
- 地球支持“地图标注、简洁、深空、蓝色星球、卫星原色”五种样式；默认使用带位置名称的地图标注样式并记住本机选择
- 展开地球或订阅时自动进行真实 ICMP 延迟测试，也可单独或批量重测
- 读取常见 Base64 节点订阅和 Clash YAML，包括仅含 HTTP(S)/SOCKS 的 Base64 列表与 Clash 嵌套 WebSocket 选项
- 内置 Self-Configuration：覆盖 AI、YouTube、全球流媒体、Telegram、Google、Apple、Microsoft、国内外流量与广告过滤
- 生成 Surge / Clash / Shadowrocket / Loon / QuanX 完整配置
- 在导出前预览配置，并明确显示目标客户端不兼容而跳过的节点
- Surge、Clash、Shadowrocket、Loon 支持点击主按钮后通过 URL Scheme 一键打开并导入
- 主导入按钮固定在标签栏上方，滚动预览时仍可随时操作
- Quantumult X 通过系统分享接收本地 `.conf` 文件

## 隐私设计

转换、规则匹配和 IP 国家查询全部在设备上完成。订阅地址使用 iOS 完整文件保护写入 Application Support；App 不调用第三方订阅转换或 IP 地理位置服务，也不会上传用户节点。域名节点只通过系统 DNS 解析地址，随后查询 App 内置的离线数据库。

延迟测试优先向节点地址发送 ICMP Echo。部分机场或网络会屏蔽 ICMP，此时塔台会退回节点端口握手，并在界面明确标成“端口”，不会把它伪装成 ICMP 延迟。测试结果只保存在本次运行内。

Surge、Clash、Shadowrocket 和 Loon 的配置导入 Scheme 都需要客户端可读取的 URL。塔台会在导入时启动一个仅绑定到 `127.0.0.1` 的临时服务，并在 45 秒后自动关闭，所以配置不会上传到互联网。临时地址不用于后续自动刷新；规则或节点变化后，需要回到塔台再次一键导入。

Quantumult X 官方公开的 URL Scheme 只能添加或替换远程资源，没有完整本地配置导入接口。塔台对 QuanX 保留系统文件分享，避免只导入节点却遗漏策略组和本地规则。

## 规则来源

规则结构来自 [ClashConnectRules/Self-Configuration](https://github.com/ClashConnectRules/Self-Configuration)，配置版本 `fb658cc85802`。模板引用的规则提供者已固定到明确版本并转换为本地 `.list` 快照，来源、版本、规则数量与 SHA-256 记录在 `Tower/Resources/SelfConfiguration/manifest.json`，App 运行时不会联网下载规则。

需要更新快照时运行 `python3 Scripts/update_self_configuration_rules.py`。脚本会读取固定版本的 Self-Configuration 模板，下载其声明的规则提供者并原子替换本地资源。

## IP 国家库

离线国家数据来自 [sapics/ip-location-db](https://github.com/sapics/ip-location-db/tree/main/geo-whois-asn-country) 的 `geo-whois-asn-country`，版本 `2.3.2026061719`，依据 CC0 许可随 App 打包。`Scripts/update_ip_country_db.py` 可下载指定版本并重新生成紧凑的 IPv4/IPv6 二进制索引，来源说明位于 `Tower/Resources/IPCountry/NOTICE.txt`。

## 运行

1. 使用 Xcode 26 或更新版本打开 `Tower.xcodeproj`。
2. 选择 iOS 17 或更新版本的模拟器/设备。
3. 运行 `Tower` Scheme。

测试覆盖订阅解析、Clash YAML 嵌套字段、IP 优先国家地区聚合、网络延迟链路、本地规则资源、一键导入 Scheme，以及五种配置生成器。Loon 的 VMess/VLESS/Trojan/Hysteria 2 参数按其[节点文档](https://nsloon.bid/document/node)生成；Surge 的 TLS 与 WebSocket 参数按其[代理策略文档](https://manual.nssurge.com/policy/proxy.html)生成。

## 已知边界

- 机场厂商自定义的非标准节点字段可能需要增加兼容适配。
- 如果目标客户端未安装或没有接管对应 Scheme，塔台会自动退回系统分享。
- Quantumult X 是否直接出现在分享列表中，取决于其声明的文件类型；未出现时可先存到“文件”再从客户端导入。
- 当前未连接安装了 Surge、Shadowrocket、Loon、Quantumult X 的真机做最终接收测试；生成格式与兼容跳过逻辑已有自动测试。
