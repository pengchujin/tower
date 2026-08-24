# 第三方资源说明

塔台的源码以 MIT 许可证发布（见 `LICENSE`）。但 `Tower/Resources/` 下随 App 打包的规则列表和 IP 数据库来自第三方，**它们各自保留原有许可条款，不适用 MIT**。

本文件记录每一项的来源、固定版本和许可状态。哈希与规则条数记录在各自的 `manifest.json` 中，可用对应脚本重新生成核对。

---

## ACL4SSR 规则

- **来源**：https://github.com/ACL4SSR/ACL4SSR
- **固定版本**：`06ff293e02565adceef9aa92321efa2603f68f32`
- **本地路径**：`Tower/Resources/ACL4SSR/`（3 份 `.ini` 配置 + 32 个 `.list` 规则）
- **许可证**：**CC BY-SA 4.0**（https://creativecommons.org/licenses/by-sa/4.0/）
- **更新脚本**：`Scripts/update_acl4ssr_rules.py`
- **清单**：`Tower/Resources/ACL4SSR/ACL4SSR_manifest.json`

按 CC BY-SA 4.0 的要求：署名归 ACL4SSR 项目及其贡献者所有；这些规则文件本身以原样再分发，未作内容修改（仅为避免 bundle 内文件名冲突而统一加了 `ACL4SSR_` 前缀，并把 `master` 链接改写为上述固定版本）；对这些规则数据的任何再分发或改编，仍须以 CC BY-SA 4.0 或兼容许可发布。

## Self-Configuration（用户手动下载）

App 和本仓库不再包含 Self-Configuration 的配置、规则列表或图标。规则页只提供指向项目上游的手动下载入口；下载由用户明确触发，内容保存在用户设备的 Application Support 中并可随时删除。因此它不属于 `Tower/Resources/` 下随 App 再分发的第三方资源。

## IP 国家数据库

- **来源**：https://github.com/sapics/ip-location-db（`geo-whois-asn-country`）
- **固定版本**：`2.3.2026061719`
- **本地路径**：`Tower/Resources/IPCountry/`
- **许可证**：**CC0 1.0**（公共领域贡献）
- **更新脚本**：`Scripts/update_ip_country_db.py`
- **说明文件**：`Tower/Resources/IPCountry/NOTICE.txt`

## 世界地图点阵

- **来源**：[Natural Earth](https://www.naturalearthdata.com)，`ne_110m_land`、`ne_110m_admin_0_countries`
- **本地路径**：`Tower/Resources/WorldMap/`
- **许可证**：**公共领域**（Natural Earth 明确放弃所有权利，无需署名）
- **更新脚本**：`Scripts/update_world_dot_map.py`
- **说明文件**：`Tower/Resources/WorldMap/WorldMap-NOTICE.txt`

首页地图不是 MapKit，而是把陆地和国家边界栅格化成相同尺寸的 Mercator 点阵文本。运行时读取 `WorldDotMap.txt` 的陆地点和 `WorldDotCountries.txt` 的国家归属，不做图像解码；虽然公共领域无需署名，仍记录来源与版本以便追溯和重新生成。

## 国家/地区名称与坐标表

- **来源**：[Natural Earth](https://www.naturalearthdata.com)，`ne_110m_admin_0_countries`
- **本地路径**：`Tower/Services/CountryTable.swift`（生成的 Swift 源码，不是打包资源）
- **许可证**：**公共领域**（同上，无需署名）
- **更新脚本**：`Scripts/update_country_table.py`

节点地区识别用的中英文国名、别名和标注坐标由该数据集生成。生成的是源码而不是资源文件，因为它只有几百行常量、需要在代码评审里看见 diff，也省掉一次启动时的文件读取。Natural Earth 的 110m 精度会略掉香港、新加坡、澳门这类小面积地区，脚本里按名单单独补齐。

## 客户端 App 图标

导出页用各客户端的 App Store 图标标识目标，随 App 打包在 `Tower/Assets.xcassets/Client*.imageset/`：

| 资源 | 客户端 | 权利人 |
| --- | --- | --- |
| `ClientSurge` | Surge | Nanjing Yiwo Information Technology |
| `ClientStash` | Stash | Rocket Team |
| `ClientShadowrocket` | Shadowrocket | Shadow Launch Technology Limited |
| `ClientLoon` | Loon | Lin Zhang |
| `ClientQuantumultX` | Quantumult X | Cross Utility |
| `ClientHiddify` | Hiddify Proxy & VPN | Holistic Resilience |
| `ClientEgern` | Egern | BYTE CROSSING LTD |

这些图标是各自权利人的商标，**不适用本项目的 MIT 许可**。塔台仅将其用于在导出目标列表里指代对应客户端（指称性使用），不表示任何关联、赞助或背书，也不分发这些客户端软件本身。图标取自 Apple 的公开 iTunes Search API 返回的 artwork 地址。权利人如有异议可提 issue，将立即移除并改用 SF Symbol 占位。

## 客户端配置格式

塔台生成 Surge、Clash/Stash、Shadowrocket、Loon、Quantumult X、Hiddify（sing-box）和 Egern 七种配置。这些格式的规范归各自客户端的开发者所有，本项目仅按其公开文档生成配置文件，不包含、不修改、不分发任何客户端软件。
