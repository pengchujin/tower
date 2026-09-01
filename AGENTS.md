# Tower agent instructions

开始工作前先阅读 `CLAUDE.md`，产品约束与完整验收要求以该文件及 `docs/HANDOFF.md` 为准。

## 三台 Mac 的 Xcode 工具链

- **出门使用的 MacBook Air M2**：开发、测试、真机构建、安装和启动固定使用正式版 Xcode：`/Applications/Xcode.app/Contents/Developer`。
- **家中的 Mac mini M4 开发机**：开发、测试和调试固定使用 Xcode Beta：`/Applications/Xcode-beta.app/Contents/Developer`。
- **家中另一台 Mac mini M2 发布机**：归档、打包和 TestFlight 上传固定使用正式版 Xcode：`/Applications/Xcode.app/Contents/Developer`。
- 运行任何 `xcodebuild` 或 `xcrun` 命令前，先按所在机器显式设置 `DEVELOPER_DIR`：

  ```sh
  # MacBook Air M2，或负责发布的 Mac mini M2
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

  # 负责开发调试的 Mac mini M4
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  ```

- 不要依赖或切换全局 `xcode-select`。先运行 `xcodebuild -version`，确认命令来自这台机器规定的 Xcode；某一份 Xcode 读不到账号或团队，不代表另一台机器或另一份 Xcode 未登录。
- 三台机器分别维护自己的 Xcode 账号、证书和描述文件。真机签名优先使用自动管理；不要擅自退出账号、撤销证书或切换全局 `xcode-select`。
- TestFlight 归档按 `docs/RELEASING.md` 在 Mac mini M2 发布机执行。Mac mini M4 只负责使用 Xcode Beta 开发调试，不承担正式打包。
- 仓库公开，文档和日志中不得写入设备 UDID、团队 ID、描述文件 UUID、个人邮箱或签名凭据。
