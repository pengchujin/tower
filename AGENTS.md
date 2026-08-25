# Tower agent instructions

开始工作前先阅读 `CLAUDE.md`，产品约束与完整验收要求以该文件及 `docs/HANDOFF.md` 为准。

## 本机 Xcode 工具链

- 本机开发、测试、真机构建、安装和启动固定使用 `/Applications/Xcode-beta.app/Contents/Developer`。
- 运行任何 `xcodebuild` 或 `xcrun` 命令前，先执行：

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  ```

- 本机 `xcode-select` 可能指向正式版 Xcode；不要依赖它，也不要因为正式版 Xcode 读不到账号或团队就判断用户未登录。先用 `xcodebuild -version` 确认当前命令来自 Xcode Beta。
- 开发账号和团队已登录在 Xcode Beta，真机签名优先使用自动管理。不要擅自退出账号、撤销证书或切换全局 `xcode-select`。
- 远程 TestFlight 归档使用单独的构建机配置，不沿用本机 Beta 规则；按 `docs/RELEASING.md` 执行。
- 仓库公开，文档和日志中不得写入设备 UDID、团队 ID、描述文件 UUID、个人邮箱或签名凭据。
