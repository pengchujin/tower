# 待办与待验证

这里只保留未完成事项。已实施的审查修复及测试结果见[审查报告](../plans/2026-09-05-project-audit.md)。

## Tailscale：一次配置，后续方便导入

- 尚未实现；用户要求先记录，等待测试确认。不要与普通节点协议混用，也不要声称所有 Clash / Surge 版本都支持。
- 先确认使用场景：访问 tailnet 节点、MagicDNS、子网路由或出口节点；不同场景所需配置不同。
- 以稳定连接 UUID 维持身份，分别映射支持版本的固定配置段 / 状态目录；不要每次导出重新生成身份。Surge、Mihomo、sing-box 的配置能力和状态复用需分别验证。
- 首阶段确认 Surge / Stash 的实际能力，再评估 Mihomo 与 sing-box；其他客户端保持“不支持/待确认”，不能自动输出社区 fork 私有字段。
- 优先客户端交互登录。一次性授权密钥只用于首次绑定，敏感值使用 Keychain；不保存 OAuth secret，不写进日志、截图、预览或二维码。重新导入是否沿用身份必须实机测试。
- iOS 前台局域网服务不是持久在线服务器。若需要长期稳定订阅地址，需另行确认由哪个用户自有设备托管，不能擅自上传凭据。

研究入口：[Surge](https://manual.nssurge.com/policies/tailscale.html)、[Stash](https://stash.wiki/en/proxy-protocols/proxy-types#tailscale)、[Mihomo](https://wiki.metacubex.one/en/config/proxies/tailscale/)、[sing-box](https://sing-box.sagernet.org/configuration/endpoint/tailscale/)、[Tailscale 身份](https://tailscale.com/docs/concepts/tailscale-identity)、[Auth Key 安全](https://tailscale.com/docs/features/access-control/auth-keys/how-to/secure-auth-keys)、[与其他 VPN 共存](https://tailscale.com/docs/reference/faq/other-vpns)。实施前重新核对支持版本。

## 等待样本或客户端验证

- VMess 名称回退：等用户提供脱敏样本后再改；核对原始返回体、UA 差异及 ps / remarks，不先覆盖服务商原名。
- Surge TLS 失败：需要脱敏错误和对应节点；检查原始 TLS 字段及客户端支持，不以全局关闭证书校验“修复”。
- 订阅 UA 回退 / 兼容格式：确认返回的节点数量和协议没有丢失；配额补请求只读响应头，不能替换原订阅节点正文。
- 同 URL 重复导入：按客户端分别确认覆盖/新增/内部刷新行为。原始订阅嵌入不代表塔台规则和自有节点也会自动更新。
- 代理集合：官方稳定版客户端逐一实测远端格式、策略组动态成员、UA 和下载失败行为；sing-box 社区 provider 示例只能作为研究线索。
- Shadowrocket 的 Salamander 参数、局域网多网卡/路由器场景保留客户端实测，不据生成成功宣称连通。

## 后续评估

- iOS 16 兼容尚未开始，当前最低仍是 iOS 17；需要单独确认收益和替代交互，不降低现有功能质量。
- 用真机 Instruments 测地图和大量节点切换。先收集长 body、hitch、CPU/内存证据，再决定是否后台化生成或进一步拆分视图。
- [开发清单](DEVELOPMENT.md)中的真机触摸、VoiceOver、权限和分享回归不能由单元测试替代。
