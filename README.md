<div align="center">

<img src="docs/images/icon.png" width="128" alt="塔台图标">

# 塔台 · Tower

**你的订阅，一处打理。**

在 iPhone、iPad 和 Mac 上管理机场订阅与自有节点，<br>
选好分流规则，一键导入你常用的客户端。

<a href="https://github.com/pengchujin/tower/releases/download/v1.0.26/Tower-1.0.26-65-macOS-universal.dmg"><img src="docs/images/download-mac.svg" width="210" height="48" alt="免费下载 Mac 版"></a>
&nbsp;
<a href="https://apps.apple.com/app/id6797458927"><img src="docs/images/download-ios.svg" width="210" height="48" alt="App Store 支持"></a>

[使用指南](https://tower.shenqi.uk) · [更新日志](https://github.com/pengchujin/tower/releases) · [反馈问题](https://github.com/pengchujin/tower/issues)

<br>

<img src="docs/images/mac-1.jpg" width="880" alt="Mac 版：订阅概览与节点世界地图">

</div>

<br>

## 三步用起来

**添加订阅 → 选择规则 → 导出使用**

<table>
<tr>
<td width="33%"><img src="docs/images/iphone-1.jpg" alt="所有订阅，一张地图看清"></td>
<td width="33%"><img src="docs/images/iphone-2.jpg" alt="规则与策略组，随心定制"></td>
<td width="33%"><img src="docs/images/iphone-3.jpg" alt="一键导入你的客户端"></td>
</tr>
</table>

## 功能一览

<table>
<tr>
<td width="33%" valign="top">
<h3>集中管理</h3>
订阅、自有节点、流量信息和到期提醒放在一起，刷新时保留你取消勾选的节点。
</td>
<td width="33%" valign="top">
<h3>直观看节点</h3>
离线识别节点地区，也能手动标记；在世界地图上按延迟查看和测速。
</td>
<td width="33%" valign="top">
<h3>自由配规则</h3>
内置 ACL4SSR 规则，离线可用；可以导入自己的规则方案，定制策略组。
</td>
</tr>
<tr>
<td valign="top">
<h3>一键导入</h3>
按客户端能力提供一键导入、复制订阅或文件导出。
</td>
<td valign="top">
<h3>跨设备使用</h3>
Mac 专属布局、局域网共享，以及可选的 iCloud 同步。
</td>
<td valign="top">
<h3>连回家里</h3>
把 Tailscale 内网写进 Surge、Stash、Clash / mihomo 和 sing-box 配置，代理时也能访问家里电脑。
</td>
</tr>
</table>

## 支持你常用的客户端

<p>
<img src="Tower/Assets.xcassets/ClientSurge.imageset/ClientSurge.jpg" width="44" alt="Surge">&nbsp;
<img src="Tower/Assets.xcassets/ClientStash.imageset/ClientStash.jpg" width="44" alt="Stash">&nbsp;
<img src="Tower/Assets.xcassets/ClientShadowrocket.imageset/ClientShadowrocket.jpg" width="44" alt="Shadowrocket">&nbsp;
<img src="Tower/Assets.xcassets/ClientLoon.imageset/ClientLoon.jpg" width="44" alt="Loon">&nbsp;
<img src="Tower/Assets.xcassets/ClientQuantumultX.imageset/ClientQuantumultX.jpg" width="44" alt="Quantumult X">&nbsp;
<img src="Tower/Assets.xcassets/ClientEgern.imageset/ClientEgern.jpg" width="44" alt="Egern">&nbsp;
<img src="Tower/Assets.xcassets/ClientSingBox.imageset/ClientSingBox.png" width="44" alt="sing-box">&nbsp;
<img src="Tower/Assets.xcassets/ClientSurgeMac.imageset/ClientSurgeMac.png" width="44" alt="Surge Mac">&nbsp;
<img src="Tower/Assets.xcassets/ClientClashVerge.imageset/ClientClashVerge.png" width="44" alt="Clash Verge">&nbsp;
<img src="Tower/Assets.xcassets/ClientClashMac.imageset/ClientClashMac.png" width="44" alt="ClashMac">&nbsp;
<img src="Tower/Assets.xcassets/ClientFlClash.imageset/flclash.png" width="44" alt="FlClash">&nbsp;
<img src="Tower/Assets.xcassets/ClientMihomoParty.imageset/mihomo-party.png" width="44" alt="Mihomo Party">
</p>

| 平台 | 客户端 |
| :-- | :-- |
| **Mac** | Surge Mac、Clash Verge、ClashMac、FlClash、Mihomo Party 等 |
| **移动端及其他** | Shadowrocket、Surge、Stash、Loon、Quantumult X、Egern、sing-box、Hiddify、V2Box、Clash、Anywhere、Clash Mi、Karing 等 |

Anywhere 支持仅节点订阅与本机一键导入，规则在 Anywhere 内设置。各客户端的导入方式和限制见 [兼容说明](docs/CLIENT-COMPATIBILITY.md)。

<p align="center">
<img src="docs/images/mac-3.jpg" width="880" alt="Mac 版：导出到主流客户端">
</p>

## 本机处理，自己掌控

<table>
<tr>
<td width="50%"><img src="docs/images/iphone-4.jpg" alt="全程在本机完成"></td>
<td width="50%"><img src="docs/images/iphone-5.jpg" alt="连回家里，多设备同步"></td>
</tr>
</table>

- 订阅解析、规则匹配和配置生成都在本机完成，不经过第三方转换服务。
- iCloud 同步默认关闭，由你选择是否开启。
- Tailscale Auth Key 只存在本机钥匙串，不参与同步。
- 塔台不提供节点，也不建立代理连接；导出后请在对应客户端启用配置。

[隐私政策](docs/privacy.md) · [使用与支持](docs/support.md)

## 下载与安装

| 平台 | 获取方式 |
| :-- | :-- |
| **iPhone / iPad** | [App Store](https://apps.apple.com/app/id6797458927) |
| **Mac** | [下载 DMG](https://github.com/pengchujin/tower/releases/download/v1.0.26/Tower-1.0.26-65-macOS-universal.dmg)，或使用 Homebrew |

```sh
brew install --cask pengchujin/tap/tower
```

---

<div align="center">

[开发指南](docs/DEVELOPMENT.md) · [架构](docs/ARCHITECTURE.md) · [发布流程](docs/RELEASING.md) · [贡献前必读](CLAUDE.md)

源码采用 [MIT](LICENSE) 许可。第三方资源按各自许可证分发，详见 [第三方声明](THIRD-PARTY-NOTICES.md)。

</div>
