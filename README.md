<div align="center">

<img src="docs/images/icon.png" width="128" alt="塔台图标">

# 塔台 · Tower

**你的订阅，一处打理。**

在 iPhone、iPad 和 Mac 上管理机场订阅与自有节点，选好分流规则，一键导入你常用的客户端。

<a href="https://github.com/pengchujin/tower/releases/download/v1.0.31-72/Tower-1.0.31-72-macOS-universal.dmg"><img src="docs/images/download-mac.svg" width="210" height="48" alt="免费下载 Mac 版"></a>
&nbsp;
<a href="https://apps.apple.com/app/id6797458927"><img src="docs/images/download-ios.svg" width="210" height="48" alt="App Store 支持"></a>

[使用指南](https://tower.shenqi.uk) · [更新日志](https://github.com/pengchujin/tower/releases) · [反馈问题](https://github.com/pengchujin/tower/issues)

</div>

## 三步用起来

**添加订阅 → 选择规则 → 导出使用**

<p align="center">
<img src="docs/images/iphone-1.jpg" width="32%" alt="所有订阅，一张地图看清">
<img src="docs/images/iphone-2.jpg" width="32%" alt="规则与策略组，随心定制">
<img src="docs/images/iphone-3.jpg" width="32%" alt="一键导入你的客户端">
</p>

## 功能一览

- **集中管理**：订阅、自有节点、流量信息和到期提醒放在一起，刷新时保留你取消勾选的节点。
- **直观看节点**：离线识别节点地区，也能手动标记；在世界地图上按延迟查看和测速。
- **自由配规则**：内置 ACL4SSR 规则，离线可用；可以导入自己的规则方案，定制策略组。
- **一键导入**：按客户端能力提供一键导入、复制订阅或文件导出。
- **跨设备使用**：Mac 专属布局、局域网共享，以及可选的 iCloud 同步。
- **连回家里**：把 Tailscale 内网写进 Surge、Stash、Clash / mihomo 和 sing-box 配置，代理时也能访问家里电脑。

## 支持你常用的客户端

**Mac**

<p>
<img src="docs/images/clients/surge-mac.png" width="72" alt="Surge Mac">
<img src="docs/images/clients/clash-verge.png" width="72" alt="Clash Verge">
<img src="docs/images/clients/clashmac.png" width="72" alt="ClashMac">
<img src="docs/images/clients/flclash.png" width="72" alt="FlClash">
<img src="docs/images/clients/mihomo-party.png" width="72" alt="Mihomo Party">
</p>

**iPhone、iPad 及其他**

<p>
<img src="docs/images/clients/shadowrocket.png" width="72" alt="Shadowrocket">
<img src="docs/images/clients/surge.png" width="72" alt="Surge">
<img src="docs/images/clients/stash.png" width="72" alt="Stash">
<img src="docs/images/clients/loon.png" width="72" alt="Loon">
<img src="docs/images/clients/quantumult-x.png" width="72" alt="Quantumult X">
<img src="docs/images/clients/egern.png" width="72" alt="Egern">
<img src="docs/images/clients/sing-box.png" width="72" alt="sing-box">
<img src="docs/images/clients/hiddify.png" width="72" alt="Hiddify">
<img src="docs/images/clients/v2box.png" width="72" alt="V2Box">
<img src="docs/images/clients/clash.png" width="72" alt="Clash">
<img src="docs/images/clients/anywhere.png" width="72" alt="Anywhere">
<img src="docs/images/clients/clash-mi.png" width="72" alt="Clash Mi">
<img src="docs/images/clients/karing.png" width="72" alt="Karing">
</p>

<p align="center">
<img src="docs/images/mac-3.jpg" width="100%" alt="Mac 版：导出到主流客户端">
</p>

## 本机处理，自己掌控

<p align="center">
<img src="docs/images/iphone-4.jpg" width="40%" alt="全程在本机完成">
<img src="docs/images/iphone-5.jpg" width="40%" alt="连回家里，多设备同步">
</p>

- 订阅解析、规则匹配和配置生成都在本机完成，不经过第三方转换服务。
- iCloud 同步默认关闭，由你选择是否开启。
- Tailscale Auth Key 只存在本机钥匙串，不参与同步。
- 塔台不提供节点，也不建立代理连接；导出后请在对应客户端启用配置。

[隐私政策](docs/privacy.md) · [使用与支持](docs/support.md)

## 下载与安装

- **iPhone / iPad**：[App Store](https://apps.apple.com/app/id6797458927)
- **Mac**：[下载 DMG](https://github.com/pengchujin/tower/releases/download/v1.0.31-72/Tower-1.0.31-72-macOS-universal.dmg)，或使用 Homebrew：

```sh
brew install --cask pengchujin/tap/tower
```

---

<div align="center">

[开发指南](docs/DEVELOPMENT.md) · [架构](docs/ARCHITECTURE.md) · [发布流程](docs/RELEASING.md) · [贡献前必读](CLAUDE.md)

源码采用 [MIT](LICENSE) 许可。第三方资源按各自许可证分发，详见 [第三方声明](THIRD-PARTY-NOTICES.md)。

</div>
