# 跨客户端 DNS Policy 转换

## Summary

将当前仅支持 Stash `nameserver-policy` 的实现升级为统一 DNS 模型，并按目标客户端的原生语法做保守、尽力转换。

Mihomo 明确区分普通域名解析、代理节点域名解析及各自 policy；它们不能互相替代。[Mihomo DNS 文档](https://wiki.metacubex.one/en/config/dns/)

Stash、Surge、Egern、Quantumult X、Loon 和 sing-box 均有不同表达方式：[Stash](https://stash.wiki/en/features/dns-server)、[Surge](https://manual.nssurge.com/dns/local-dns-mapping.html)、[Egern](https://egernapp.com/docs/configuration/dns/)、[Quantumult X](https://github.com/crossutility/Quantumult-X/blob/master/sample.conf)、[Loon](https://github.com/Loon0x00/LoonExampleConfig/blob/master/example.conf)、[sing-box](https://sing-box.sagernet.org/configuration/dns/rule/)。

## Key Changes

- 新增可持久化的 `SubscriptionDNSConfiguration`，读取：
  - `enable`
  - `default-nameserver`
  - `nameserver`
  - `fallback`
  - `nameserver-policy`
  - `proxy-server-nameserver`
  - `proxy-server-nameserver-policy`
- 普通订阅响应与 `flag=clash` 探测响应都提取 DNS；探测响应仍不得替换原始节点列表。
- 多订阅按列表顺序合并：
  - 每个全局字段采用首个非空值，不混合不同机场的上游服务器。
  - 相同 matcher 采用先出现的 policy。
  - 禁用订阅立即退出 DNS 合并并使生成缓存失效。
- 仅转换 exact、`+.`、`*.` 等可明确映射的 matcher；`geosite:*` 仅在 Stash 保留，其他目标跳过并警告，不展开大型域名列表、不引入外部规则下载。
- 不降级 DNS 协议、不把多个解析器静默缩减为一个；目标格式无法表达时跳过该条并产生结构化警告。

| 目标 | 普通 DNS policy | 代理节点 DNS |
|---|---|---|
| Stash | 原生 `default-nameserver`、`nameserver`、`nameserver-policy` | Mihomo 专属字段不输出并警告 |
| Surge | `dns-server` / `encrypted-dns-server`；policy 转 `[Host] domain = server:...` | 无等价字段，警告 |
| Shadowrocket | `dns-server`、`fallback-dns-server`；policy 转 `[Host]` | 全局转 `proxy-dns-server`；按域 policy 警告 |
| Loon | `dns-server` / `doh-server`；单解析器 policy 转 `[Host]` | 无等价字段，警告 |
| Quantumult X | 按协议转 `[dns] server`、`doh-server`、`doq-server` 及域名绑定语法 | 无等价字段，警告 |
| Egern | 转 `bootstrap`、`upstreams`、`forward`，保留多解析器组 | 全局转 `proxy_nameservers`；按域 policy 警告 |
| Hiddify | 按现有 sing-box 1.13 兼容格式生成 `dns.servers`、`dns.rules` | 用 outbound `domain_resolver` 对已知节点域名应用 policy |

- `GeneratedConfiguration` 增加结构化 `conversionWarnings`。
- 导出摘要显示每条 DNS 转换警告；警告不阻止预览、复制或导入。
- 当前硬编码 DNS 仅作为字段缺失时的默认值；机场提供了可支持字段时由机场配置替代。
- 内置规则与导入规则方案走同一套 DNS 生成路径。

## Test Plan

- 解析 block、scalar、inline array、引号、带冒号 matcher、URL fragment 及两类 policy。
- 验证旧状态文件可解码，DNS 元数据刷新和禁用订阅行为正确。
- 覆盖多订阅冲突、首订阅优先、缓存失效及警告去重。
- 为七个目标分别验证普通 policy、代理 DNS、通配符展开、协议支持和不可转换警告。
- 同时覆盖内置 preset 与导入 scheme 的生成路径。
- 验证 YAML/INI/JSON 转义，防止订阅内容注入配置段。
- 运行完整 Xcode 测试；sing-box 输出继续通过 JSON 解析，并为每种文本格式增加关键段落快照断言。

## Assumptions

- “Clash YAML”目标继续以 Stash 兼容性为准，不输出未被 Stash 官方确认的 Mihomo 专属字段。
- 本期不转换 `fake-ip`、`fallback-filter`、`respect-rules`、ECS 等扩展配置。
- 不为 `geosite` 做近似映射，也不自动下载额外规则集。
- 无法无损表达的内容采用非阻塞警告，不静默改变语义。
