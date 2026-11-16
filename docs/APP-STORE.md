# App Store 文案

发布前核对成稿与当前实现。这里不记录首发备选稿、旧版本营销文案或未经核验的审核推断。隐私细节以 [privacy.md](privacy.md) 为准。

## 搜索字段

App Store 站内搜索只读名称、副标题、关键词（另有开发者名），描述不参与。三处的词会合并检索，同一个词只需出现一次；关键词用半角逗号分隔、不加空格。英文（美国）元数据会被多个国家/地区的商店一并检索，不要留空。

| 字段（上限） | 简体中文 | 繁体中文 | 英文（美国） |
| --- | --- | --- | --- |
| 名称（30） | 塔台 Tower - 订阅转换与规则配置 | 塔台 Tower - 訂閱轉換與規則設定 | Tower - Config Converter |
| 副标题（30） | 本机生成配置，节点测速与分流 | 本機產生設定，節點測速與分流 | Subscriptions, Rules & Latency |
| 关键词（100） | 策略组,延迟,地区,离线,隐私,批量,扫码,导入,导出,流量,到期,格式,YAML,INI,JSON,局域网,地图,自建,二维码,iPad | 策略組,延遲,地區,離線,隱私,批次,掃碼,匯入,匯出,流量,到期,格式,YAML,INI,JSON,區域網路,地圖,自架,QR Code,iPad | yaml,ini,json,policy,group,routing,ruleset,node,offline,privacy,import,export,qr,map,ping,format |

- 名称和副标题只在提交新版本时能改；关键词也随版本提交。提交前在 App Store Connect 里看实际计数。
- 关键词不写第三方 App 名称或商标（审核规范 2.3.7），也不写「VPN」「翻墙」「机场」：审核风险高，而且和「不含 VPN 功能」的定位矛盾。
- 名称固定写「塔台 Tower」，和 README、使用指南站、GitHub 保持一致；单写「塔台」或「Tower」在搜索引擎里都太泛。

## 宣传文本（170，可随时改，不需要提审）

- 简体：一份订阅，生成多款客户端的配置。按地区看节点、测延迟，定制分流规则，一键导入常用客户端。全程在本机完成，不经过在线转换服务。
- 繁体：一份訂閱，產生多款用戶端的設定。依地區檢視節點、測延遲，自訂分流規則，一鍵匯入常用用戶端。全程在本機完成，不經過線上轉換服務。
- 英文：Turn one subscription into ready-to-import configs for the clients you use. Group nodes by region, test latency, tune routing rules. Everything runs on your device.

## 描述成稿

描述不参与 App Store 站内搜索，但 Google 会收录商店页面，所以第一段要说清用途。不写具体的协议或客户端数量，以免随版本过时。

### 简体中文

塔台是在 iPhone 和 iPad 本机运行的订阅与配置转换工具。它管理你已有的订阅、自有节点和分流规则，生成其他客户端能直接导入的配置文件。

■ 能做什么
· 集中管理订阅和自有节点，显示剩余流量和到期时间；刷新时保留你取消勾选的节点
· 支持 Shadowsocks、VMess、VLESS、Trojan、Hysteria 2、TUIC、WireGuard、AnyTLS 等十余种节点协议，按目标客户端的实际能力输出；无法忠实表达的条目明确计入跳过
· 离线识别节点地区，在世界地图上按地区查看节点、测试延迟
· 内置规则方案离线可用，也可以导入自己的 HTTPS 规则方案，自由调整策略组和分流顺序
· 预览生成的配置，一键导入、复制或分享文件
· 可选的 iCloud 同步和局域网共享，在多台设备间使用同一份配置

■ 在本机完成
转换在设备上完成，不经过塔台服务器或第三方在线转换服务。规则快照和离线 IP 国家库随 App 提供。

订阅凭据默认留在本机。iCloud 同步与“代理集合”均默认关闭：前者由你授权后存入自己的 iCloud，后者把原始订阅链接写入导出配置，让兼容客户端自行更新远端节点。分享文件前，请确认接收方可信。

一键导入使用本机限时服务；局域网共享需要主动开启，并使用随机密钥，仅在塔台前台运行时提供服务。凭据类文件使用 iOS 完整文件保护。

塔台没有账号系统、分析统计、广告或崩溃上报。源码公开：https://github.com/pengchujin/tower
使用指南：https://tower.shenqi.uk

■ 说明
塔台只负责格式转换，不包含 VPN 或代理连接功能，不创建网络隧道、不接管系统流量，也不提供服务器或节点。你需要自备订阅内容，并在相应客户端中使用生成的配置。

### 繁体中文

塔台是在 iPhone 和 iPad 本機執行的訂閱與設定轉換工具。它管理你已有的訂閱、自有節點和分流規則，產生其他用戶端能直接匯入的設定檔。

■ 能做什麼
· 集中管理訂閱和自有節點，顯示剩餘流量和到期時間；重新整理時保留你取消勾選的節點
· 支援 Shadowsocks、VMess、VLESS、Trojan、Hysteria 2、TUIC、WireGuard、AnyTLS 等十餘種節點協定，依目標用戶端的實際能力輸出；無法忠實表達的條目明確計入略過
· 離線識別節點地區，在世界地圖上依地區檢視節點、測試延遲
· 內建規則方案離線可用，也可以匯入自己的 HTTPS 規則方案，自由調整策略組和分流順序
· 預覽產生的設定，一鍵匯入、複製或分享檔案
· 可選的 iCloud 同步和區域網路共享，在多台裝置間使用同一份設定

■ 在本機完成
轉換在裝置上完成，不經過塔台伺服器或第三方線上轉換服務。規則快照和離線 IP 國家資料庫隨 App 提供。

訂閱憑證預設留在本機。iCloud 同步與「代理集合」均預設關閉：前者經你授權後存入自己的 iCloud，後者把原始訂閱連結寫入匯出設定，讓相容用戶端自行更新遠端節點。分享檔案前，請確認接收方可信。

一鍵匯入使用本機限時服務；區域網路共享需要主動開啟，並使用隨機金鑰，僅在塔台於前景執行時提供服務。憑證類檔案使用 iOS 完整檔案保護。

塔台沒有帳號系統、分析統計、廣告或當機回報。原始碼公開：https://github.com/pengchujin/tower
使用指南：https://tower.shenqi.uk

■ 說明
塔台只負責格式轉換，不包含 VPN 或代理連線功能，不建立網路通道、不接管系統流量，也不提供伺服器或節點。你需要自備訂閱內容，並在相應用戶端中使用產生的設定。

### 英文

Tower is a subscription and config converter that runs entirely on your iPhone and iPad. It manages the subscriptions, self-hosted nodes and routing rules you already have, and generates config files that other clients can import directly.

■ What it does
· Keep all your subscriptions and your own nodes in one place, with remaining data and expiry dates. Nodes you unchecked stay unchecked after a refresh.
· Parse more than ten node protocols, including Shadowsocks, VMess, VLESS, Trojan, Hysteria 2, TUIC, WireGuard and AnyTLS, and export only what each target client can actually express. Entries that can't be represented faithfully are skipped and counted, never silently broken.
· Identify node regions offline, browse nodes on a world map and test latency by region.
· Use the built-in rule sets offline, or import your own HTTPS rule scheme and adjust policy groups and matching order.
· Preview the generated config, then import it in one tap, copy it or share the file.
· Optional iCloud sync and Local Network Sharing let you use the same setup across devices.

■ Done on your device
Conversion happens on the device. Nothing goes through a Tower server or a third-party online converter. Rule snapshots and an offline IP-to-country database ship with the app.

Subscription credentials stay on your device by default. iCloud sync and Proxy Providers are both off by default: the first stores data in your own iCloud only after you turn it on; the second writes the original subscription URL into the exported config so compatible clients can update nodes themselves. Make sure you trust whoever receives a shared file.

One-tap import uses a short-lived local service. Local Network Sharing has to be turned on, is protected by a random key, and only runs while Tower is in the foreground. Credential files use iOS Complete File Protection.

Tower has no accounts, analytics, ads or crash reporting. Source code: https://github.com/pengchujin/tower
Guide: https://tower.shenqi.uk

■ Please note
Tower only converts formats. It is not a VPN or proxy: it creates no network tunnel, does not route system traffic, and provides no servers or nodes. You need your own subscription, and you use the generated config in the corresponding client.

## 审核备注成稿

本 App 是本机配置文件转换工具，将用户提供的订阅文本转换成 YAML、INI、JSON 或节点订阅文件。它不使用 NetworkExtension，不创建隧道、不转发系统流量、不提供节点。

转换不经过在线转换服务。用户可主动开启自己的 iCloud 同步，或在兼容客户端配置中引用原始订阅 URL；这些功能默认关闭并有说明。开发者不收集订阅、节点或使用数据。

Info.plist 的 NSAllowsArbitraryLoads 用于用户自行提供的 HTTP 订阅地址和本机配置交接服务；HTTP 输入会提示明文风险。正常一键导入只绑定 127.0.0.1、3 分钟失效。用户单独开启局域网共享时才请求本地网络权限，并通过随机访问密钥保护配置。

无登录功能，不需要演示账号。转换测试需要脱敏的订阅样本，不要向审核备注附加个人真实订阅凭据。源码：https://github.com/pengchujin/tower

## 提交字段与核对

| 字段 | 当前内容 |
| --- | --- |
| 类别 | 工具 |
| 支持 URL | https://pengchujin.github.io/tower/support.html |
| 隐私政策 URL | https://pengchujin.github.io/tower/privacy.html |
| 营销 URL | 可留空 |
| 设备 | iPhone、iPad；Mac 版通过 GitHub Releases 和 Homebrew 分发 |
| 截图 | iPhone 6.9″ 与 iPad 13″ 各 5 张，Mac 4 张；拍摄方法见 [DEVELOPMENT](DEVELOPMENT.md#app-store-截图) |
| 隐私问卷 | 按实际无开发者数据收集行为填写，并与隐私政策、PrivacyInfo.xcprivacy 核对 |
| 出口合规 | 当前工程 ITSAppUsesNonExemptEncryption = NO；引入新的加密实现时重新评估 |

提交前实际打开支持/隐私 URL，核对截图与待发布包一致；销售地区和审核决定由发布负责人确认。归档与上传流程见 [RELEASING](RELEASING.md)。
