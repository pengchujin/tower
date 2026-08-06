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

## Self-Configuration 规则

- **来源**：https://github.com/ClashConnectRules/Self-Configuration
- **固定版本**：`fb658cc85802`
- **本地路径**：`Tower/Resources/SelfConfiguration/`
- **许可证**：**上游仓库未声明任何许可证**
- **更新脚本**：`Scripts/update_self_configuration_rules.py`
- **清单**：`Tower/Resources/SelfConfiguration/manifest.json`

⚠️ 上游未声明许可证，按著作权默认规则即为「保留所有权利」，本项目对这部分数据不主张任何权利，仅出于离线可用的目的原样收录并完整署名来源。若上游作者希望移除，请提 issue，我们会立即从仓库中删除这部分资源并改为运行时按需下载。

同一目录下的 `SelfConfiguration-NOTICE.txt` 记录了模板所引用的各规则提供者及其固定版本，这些提供者本身还有各自的上游（如 `dler-io/Rules`、`blackmatrix7/ios_rule_script`），也一并适用其原有条款。

## IP 国家数据库

- **来源**：https://github.com/sapics/ip-location-db（`geo-whois-asn-country`）
- **固定版本**：`2.3.2026061719`
- **本地路径**：`Tower/Resources/IPCountry/`
- **许可证**：**CC0 1.0**（公共领域贡献）
- **更新脚本**：`Scripts/update_ip_country_db.py`
- **说明文件**：`Tower/Resources/IPCountry/NOTICE.txt`

## 世界地图点阵

- **来源**：[Natural Earth](https://www.naturalearthdata.com)，`ne_110m_land`
- **本地路径**：`Tower/Resources/WorldMap/`
- **许可证**：**公共领域**（Natural Earth 明确放弃所有权利，无需署名）
- **更新脚本**：`Scripts/update_world_dot_map.py`
- **说明文件**：`Tower/Resources/WorldMap/WorldMap-NOTICE.txt`

首页地图不是 MapKit，而是把陆地多边形栅格化成等距圆柱投影的点阵文本位图，运行时只读这一个文件、不做图像解码。虽然公共领域无需署名，仍记录来源与版本以便追溯和重新生成。

## 策略组图标

生成的配置中引用了以下图标集的远程地址（图标本身不随 App 打包，由客户端按需加载）：

- Koolson/Qure：https://github.com/Koolson/Qure
- Orz-3/mini：https://github.com/Orz-3/mini

---

## 客户端配置格式

塔台生成 Surge、Clash/Stash、Shadowrocket、Loon、Quantumult X 五种配置。这些格式的规范归各自客户端的开发者所有，本项目仅按其公开文档生成配置文件，不包含、不修改、不分发任何客户端软件。
