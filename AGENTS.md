# Tower agent instructions

开始工作前先阅读 `CLAUDE.md`，产品约束与完整验收要求以该文件及 `docs/HANDOFF.md` 为准。

## 三台 Mac 的 Xcode 工具链

- **出门使用的 MacBook Air M2**：开发、测试、真机构建、安装、启动、本机归档和需要时的 App Store Connect / TestFlight 上传固定使用正式版 Xcode：`/Applications/Xcode.app/Contents/Developer`。`1.0.5 (38)` 已在本机完成 Release 自动签名、归档和上传。
- **家中的 Mac mini M4 开发机**：开发、测试和调试固定使用 Xcode Beta：`/Applications/Xcode-beta.app/Contents/Developer`。
- **家中另一台 Mac mini M2 发布机**：使用正式版 Xcode：`/Applications/Xcode.app/Contents/Developer`，是家中的固定 App Store Connect / TestFlight 发布机；出门时 Air 可承担同一职责。
- 运行任何 `xcodebuild` 或 `xcrun` 命令前，先按所在机器显式设置 `DEVELOPER_DIR`：

  ```sh
  # MacBook Air M2，或负责发布的 Mac mini M2
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

  # 负责开发调试的 Mac mini M4
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  ```

- 不要依赖或切换全局 `xcode-select`。先运行 `xcodebuild -version`，确认命令来自这台机器规定的 Xcode；某一份 Xcode 读不到账号或团队，不代表另一台机器或另一份 Xcode 未登录。
- 三台机器分别维护自己的 Xcode 账号、证书和描述文件。真机签名优先使用自动管理；不要擅自退出账号、撤销证书或切换全局 `xcode-select`。
- 描述文件和本地签名身份存在，不代表正式版 Xcode 已登录 Apple Account。2026-09-01 Air 首次上传报 `Failed to Use Accounts` 的实际原因是 Xcode 账号未登录；登录后复用同一份 `1.0.5 (38)` 归档即上传成功。遇到相同错误先打开 Xcode **Settings ▸ Accounts** 核对账号与团队，不要重新归档、撤销证书或直接断言账号没有 App Store Connect 权限。Mac mini M4 只负责 Xcode Beta 开发调试，不承担正式打包。
- 仓库公开，文档和日志中不得写入设备 UDID、团队 ID、描述文件 UUID、个人邮箱或签名凭据。
