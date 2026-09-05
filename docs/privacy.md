---
title: 塔台隐私政策 · Tower Privacy Policy
---

# 塔台隐私政策

最后更新：2026 年 9 月 5 日

塔台（Tower）是一个在 iPhone 本机运行的**配置文件转换工具**。它把你已有的订阅文本转换成各个客户端能读的配置文件格式。

**塔台不收集任何数据。** 没有账号，没有统计，没有崩溃上报，没有广告，没有任何第三方 SDK。开发者无法看到你使用塔台做了什么。

本文的每一条都可以在源码里核对：<https://github.com/pengchujin/tower>

---

## 一、塔台不收集什么

以下内容默认保存在你的设备上；可选的例外，是你主动开启第 2 节和第 4 节说明的 iCloud 同步，或第 3 节说明的“代理集合”：

- 订阅地址和订阅内容
- 节点信息（服务器地址、端口、密码、UUID、密钥等）
- 生成的配置文件
- 规则选择、分组设置、App 内的任何偏好
- 延迟测试结果

塔台**不使用**任何第三方在线转换服务。同类工具常把订阅内容发到远程服务器去转换——塔台不这么做，转换全部在你的设备上完成。

## 二、塔台什么时候联网

只有四种情况，全部来自你主动执行的操作或主动开启的设置：

1. **获取订阅** —— 你添加或刷新订阅时，塔台向**你自己填写的那个地址**发起请求。设置里有一个**默认关闭**的「打开塔台时更新订阅」开关；只有你主动开启后，塔台才会在每次打开时自动取一次同一批地址。这是你和你的服务提供商之间的连接，塔台不参与，也不会把这个地址告诉任何第三方。
2. **导入或刷新规则链接** —— 你主动导入一个规则地址时才发起。规则地址只接受 HTTPS。App 内置的规则快照任何情况下都不联网。
3. **解析与测速** —— 节点使用域名时，通过系统 DNS 或你指定的 DNS-over-HTTPS 解析；打开地图/节点列表或主动重测时，会向节点地址发起 ICMP 或端口握手以测延迟。
4. **iCloud 同步** —— 默认关闭。只有你在设置中明确开启后，塔台才会把配置存进**你自己的** iCloud 账户，并在 App 启动、回到前台和本机编辑后自动比较或上传配置。数据不经过塔台的服务器，开发者无法访问。关闭后不再同步，但不会自动删除 iCloud 中已有的副本。

除此之外，塔台不会发起网络请求。塔台不在后台运行，因此自动更新和 iCloud 同步只会在你打开 App 时运行，或在 App 前台编辑后上传。

“代理集合”不会让塔台增加网络请求。开启后，原始订阅链接会写入你导出的兼容客户端配置，由你选择的客户端直接向服务提供商更新；该链接可能含账号凭据，只应交给你信任的客户端。

**国家与地区识别不联网。** 塔台先看节点自己的名字判断地区；名字看不出来时，查询随 App 一起打包的**离线** IP 数据库。你的节点服务器地址不会被发送到任何 IP 查询服务。

## 三、本机的临时服务

塔台把配置交给同一台设备上的其他客户端时，会启动一个**只绑定 `127.0.0.1`** 的本地 HTTP 服务。这个地址只有本机能访问，数据不经过任何网络，**45 秒后自动失效**。

设置里的“代理集合”默认关闭。开启后，Stash、Clash、Clash Mi、Karing、Surge、Loon、QuanX 和 Egern 的完整配置可以包含原始订阅链接，以便客户端以后自行更新远程节点。这不会把链接发给塔台服务器，但会把它交给目标客户端；你通过系统分享导出配置时，链接也会随文件一起分享。Shadowrocket、Hiddify、V2Box 和 sing-box MT 不使用此模式。

「局域网订阅」默认关闭；只有你在导出页主动选择它时，塔台才会启动共享。同一 Wi-Fi 下的电脑或路由器随后可以读取塔台生成的配置。它使用随机访问密钥，你可以随时更换密钥使旧链接失效，也可以随时关闭。这个功能只在塔台处于前台时工作。

## 四、设备上的存储

- 订阅、节点和设置保存在 App 自己的沙盒里。**默认不同步、不备份到任何地方。**
- 设置里有一个默认关闭的「iCloud 同步」开关。**只有你主动开启后**，配置才会存入**你自己的** iCloud 账户，用于在同一 Apple 账户的设备之间同步。这份数据存在你的 iCloud 里，不经过塔台的任何服务器，开发者无法访问。开启前会明确告知订阅地址和节点密码会被上传。关闭同步不会删除 iCloud 上已有的副本，你可以在塔台设置中删除云端副本。
- 写到磁盘的凭据类文件——包括导出的配置文件和二维码图片——使用 iOS 的**完整文件保护**（`.completeFileProtection`），设备锁定时无法被读取。
- 临时导出文件会自动清理。
- 删除 App 会删除本机沙盒数据，但不会自动删除已同步的 iCloud 副本或已交给其他客户端的配置。

## 五、系统权限

- **相机** —— 仅在你主动使用扫码添加时启用，用于识别二维码。图像不保存、不上传。
- **本地网络** —— 仅在你主动开启「局域网订阅」时请求，用于让同一 Wi-Fi 下的设备读取配置。
- **剪贴板** —— 打开添加面板时读取一次，用于判断你是否刚复制了订阅或节点链接以便自动填入。只在内容是受支持的链接时使用，不会保存，也不会上传。

## 六、儿童

塔台不面向 13 岁以下儿童，也不会有意收集儿童信息——事实上它不收集任何人的信息。

## 七、政策变更

本政策如有修改，会更新页首的日期并在源码仓库中留下完整的修改记录。

## 八、联系

如对本政策有疑问，请在源码仓库提交 issue：<https://github.com/pengchujin/tower/issues>

---

# Tower Privacy Policy

Last updated: 5 September 2026

Tower is a **configuration file converter** that runs entirely on your iPhone. It turns subscription text you already have into the configuration formats other client apps can read.

**Tower collects no data.** There are no accounts, no analytics, no crash reporting, no advertising, and no third-party SDKs of any kind. The developer cannot see what you do with Tower.

Every claim below can be checked in the source: <https://github.com/pengchujin/tower>

## 1. What never leaves your device

Subscription URLs and their contents, node details (server, port, password, UUID, keys), generated configuration files, your rule and grouping choices, and latency results stay on the device by default. Optional exceptions are iCloud sync, described in Sections 2 and 4, and client-managed subscription updates, described in Section 3. Both are off until you explicitly enable them.

Tower uses **no third-party online conversion service**. Comparable tools often send subscription content to a remote server to be converted; Tower does the conversion on your device instead.

## 2. When Tower uses the network

Only in four cases, each resulting from an action you take or a setting you explicitly enable:

1. **Fetching a subscription** — Tower requests the address *you* entered. That is a connection between you and your provider; the address is not shared with anyone else. Settings carries a switch, **off by default**, that fetches those same addresses once each time you open Tower.
2. **Importing or refreshing a rule URL** — only when you ask for it, and only over HTTPS. The rule snapshots bundled with the app never go online.
3. **Resolution and latency tests** — via the system resolver or your configured DNS-over-HTTPS server. Opening the map/node list or requesting a retest may send ICMP or port-handshake probes to the node address.
4. **iCloud sync** — off by default. After you explicitly enable it in Settings, Tower stores the configuration in **your own** iCloud account and automatically compares or uploads it when the app opens, returns to the foreground, or saves a local edit. It never passes through a Tower server and the developer cannot access it. Turning sync off stops future syncing but does not delete the existing iCloud copy.

Tower makes no other requests. It does not run in the background, so automatic refresh and iCloud sync run only while the app is open, including uploads after an edit made in the foreground.

“Client-managed subscriptions” does not add a Tower network request. When enabled, Tower embeds the original subscription URL in compatible exported profiles so the client you choose can update directly from the provider. The URL may contain account credentials and should be given only to a client you trust.

**Region detection stays offline.** Tower reads a node's country from its own name first; when the name says nothing, it consults an IP database bundled with the app. Your server addresses are never sent to a lookup service.

## 3. On-device temporary service

To hand a configuration to another client on the same device, Tower starts a local HTTP service bound to `127.0.0.1` only. Nothing crosses a network, and the service **expires after 45 seconds**.

“Client-managed subscriptions” is off by default. If enabled, complete profiles for Stash, Clash, Clash Mi, Karing, Surge, Loon, QuanX, and Egern may contain the original subscription URL so those clients can refresh remote nodes later. Tower does not send that URL to a Tower server, but it does hand the URL to the destination client; sharing the exported file also shares the URL. Shadowrocket, Hiddify, V2Box, and sing-box MT do not use this mode.

"LAN subscription" is off by default and must be switched on by you. It is protected by a random access key that you can rotate at any time, and it runs only while Tower is in the foreground.

## 4. Storage

Data lives in the app's own sandbox and, by default, goes nowhere else. Settings carries an iCloud sync switch that is off until you turn it on; only then is the configuration written to **your own** iCloud account so devices on the same Apple Account can share it. It never passes through a Tower server and the developer cannot read it. You are told before enabling it that subscription URLs and node passwords will be uploaded. Turning sync off does not delete the copy already in iCloud — you can remove the cloud copy in Tower Settings. Credential-bearing files written to disk, including exported configurations and QR images, use iOS **complete file protection** and cannot be read while the device is locked. Temporary exports are cleaned up automatically. Deleting the app removes its local sandbox, not existing iCloud copies or configurations already handed to other clients.

## 5. Permissions

**Camera** — only when you scan a QR code; images are neither stored nor uploaded. **Local network** — only when you switch on LAN subscription. **Clipboard** — read once when the add panel opens, to offer to fill in a link you just copied; it is not stored or uploaded.

## 6. Children

Tower is not directed at children under 13 and does not knowingly collect their information — it collects no one's information.

## 7. Changes

Changes update the date at the top of this page and leave a full history in the source repository.

## 8. Contact

Questions: <https://github.com/pengchujin/tower/issues>
