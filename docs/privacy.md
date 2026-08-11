---
title: 塔台隐私政策 · Tower Privacy Policy
---

# 塔台隐私政策

最后更新：2026 年 8 月 11 日

塔台（Tower）是一个在 iPhone 本机运行的**配置文件转换工具**。它把你已有的订阅文本转换成各个客户端能读的配置文件格式。

**塔台不收集任何数据。** 没有账号，没有统计，没有崩溃上报，没有广告，没有任何第三方 SDK。开发者无法看到你使用塔台做了什么。

本文的每一条都可以在源码里核对：<https://github.com/pengchujin/tower>

---

## 一、塔台不收集什么

以下内容**从不离开你的设备**：

- 订阅地址和订阅内容
- 节点信息（服务器地址、端口、密码、UUID、密钥等）
- 生成的配置文件
- 规则选择、分组设置、App 内的任何偏好
- 延迟测试结果

塔台**不使用**任何第三方在线转换服务。同类工具常把订阅内容发到远程服务器去转换——塔台不这么做，转换全部在你的设备上完成。

## 二、塔台什么时候联网

只有三种情况，全部由你主动触发：

1. **获取订阅** —— 你添加或刷新订阅时，塔台向**你自己填写的那个地址**发起请求。这是你和你的服务提供商之间的连接，塔台不参与，也不会把这个地址告诉任何第三方。
2. **导入或刷新规则链接** —— 你主动导入一个规则地址时才发起。规则地址只接受 HTTPS。App 内置的规则快照任何情况下都不联网。
3. **域名解析** —— 节点使用域名时，由系统 DNS 解析。你也可以在设置里自行指定一个 DNS-over-HTTPS 服务器，塔台会改用它。

除此之外，塔台不会在后台、启动时或任何你没有按下按钮的时刻发起网络请求。

**国家与地区识别不联网。** 塔台先看节点自己的名字判断地区；名字看不出来时，查询随 App 一起打包的**离线** IP 数据库。你的节点服务器地址不会被发送到任何 IP 查询服务。

## 三、本机的临时服务

塔台把配置交给同一台设备上的其他客户端时，会启动一个**只绑定 `127.0.0.1`** 的本地 HTTP 服务。这个地址只有本机能访问，数据不经过任何网络，**45 秒后自动失效**。

「局域网订阅」是一个默认关闭、需要你手动开启的功能。开启后，同一 Wi-Fi 下的电脑或路由器可以读取塔台生成的配置。它使用随机访问密钥，你可以随时更换密钥使旧链接失效，也可以随时关闭。这个功能只在塔台处于前台时工作。

## 四、设备上的存储

- 订阅、节点和设置保存在 App 自己的沙盒里。**默认不同步、不备份到任何地方。**
- 设置里有一个默认关闭的「iCloud 同步」开关。**只有你主动开启后**，配置才会存入**你自己的** iCloud 账户，用于在同一 Apple 账户的设备之间同步。这份数据存在你的 iCloud 里，不经过塔台的任何服务器，开发者无法访问。开启前会明确告知订阅地址和节点密码会被上传。关闭同步不会删除 iCloud 上已有的副本，你可以在系统的 iCloud 云盘里自行删除。
- 写到磁盘的凭据类文件——包括导出的配置文件和二维码图片——使用 iOS 的**完整文件保护**（`.completeFileProtection`），设备锁定时无法被读取。
- 临时导出文件会自动清理。
- 删除 App 会一并删除全部数据。

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

Last updated: 11 August 2026

Tower is a **configuration file converter** that runs entirely on your iPhone. It turns subscription text you already have into the configuration formats other client apps can read.

**Tower collects no data.** There are no accounts, no analytics, no crash reporting, no advertising, and no third-party SDKs of any kind. The developer cannot see what you do with Tower.

Every claim below can be checked in the source: <https://github.com/pengchujin/tower>

## 1. What never leaves your device

Subscription URLs and their contents, node details (server, port, password, UUID, keys), generated configuration files, your rule and grouping choices, and latency results. All of it stays on the device.

Tower uses **no third-party online conversion service**. Comparable tools often send subscription content to a remote server to be converted; Tower does the conversion on your device instead.

## 2. When Tower uses the network

Only in three cases, each one started by you:

1. **Fetching a subscription** — Tower requests the address *you* entered. That is a connection between you and your provider; the address is not shared with anyone else.
2. **Importing or refreshing a rule URL** — only when you ask for it, and only over HTTPS. The rule snapshots bundled with the app never go online.
3. **DNS resolution** — through the system resolver, or through a DNS-over-HTTPS server if you configure one in Settings.

Tower makes no requests in the background, at launch, or at any moment you did not initiate.

**Region detection stays offline.** Tower reads a node's country from its own name first; when the name says nothing, it consults an IP database bundled with the app. Your server addresses are never sent to a lookup service.

## 3. On-device temporary service

To hand a configuration to another client on the same device, Tower starts a local HTTP service bound to `127.0.0.1` only. Nothing crosses a network, and the service **expires after 45 seconds**.

"LAN subscription" is off by default and must be switched on by you. It is protected by a random access key that you can rotate at any time, and it runs only while Tower is in the foreground.

## 4. Storage

Data lives in the app's own sandbox and, by default, goes nowhere else. Settings carries an iCloud sync switch that is off until you turn it on; only then is the configuration written to **your own** iCloud account so devices on the same Apple Account can share it. It never passes through a Tower server and the developer cannot read it. You are told before enabling it that subscription URLs and node passwords will be uploaded. Turning sync off does not delete the copy already in iCloud — remove it from iCloud Drive yourself. Credential-bearing files written to disk, including exported configurations and QR images, use iOS **complete file protection** and cannot be read while the device is locked. Temporary exports are cleaned up automatically. Deleting the app deletes everything.

## 5. Permissions

**Camera** — only when you scan a QR code; images are neither stored nor uploaded. **Local network** — only when you switch on LAN subscription. **Clipboard** — read once when the add panel opens, to offer to fill in a link you just copied; it is not stored or uploaded.

## 6. Children

Tower is not directed at children under 13 and does not knowingly collect their information — it collects no one's information.

## 7. Changes

Changes update the date at the top of this page and leave a full history in the source repository.

## 8. Contact

Questions: <https://github.com/pengchujin/tower/issues>
