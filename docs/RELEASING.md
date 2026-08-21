# TestFlight 发布流程

塔台使用本机 Ghostty 打开一个独立交互终端，再通过 SSH 连接 Mac mini M2。Ghostty 中只负责校验代码和交互解锁钥匙串；真正的归档与上传会自动切换到 Mac mini 的 Aqua 图形会话执行，避免 SSH Background 安全域导致 `codesign` 报 `errSecInternalComponent`。登录钥匙串密码仅在当次终端由 macOS `security` 读取，不写入仓库、脚本、Shell 历史或命令参数。

## 前置条件

- 本地仓库工作区必须干净，并且 `HEAD` 与 `origin/main` 完全一致。
- 随 App 打包的 ACL4SSR 快照必须对应上游最新提交；发布脚本会联网检查并在过期时中止。
- 工程中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 必须已经更新并推送。
- 两台机器都需要各自的 `Config/release.local.sh`（见下一节）。
- Mac mini 的登录钥匙串中需要存在可用的 Apple Development 或 Apple Distribution 签名身份。
- 本机安装 Ghostty；SSH 优先使用现有公钥，没有公钥时由 SSH 自己交互询问密码。

## 打包前更新内置规则

内置 ACL4SSR 规则属于 App 资源，不会在用户设备上自动更新。每次 TestFlight 或 App Store 打包前，发布脚本会执行只读检查：

```sh
python3 Scripts/update_acl4ssr_rules.py --check-latest
```

如果上游已有新提交，脚本会在签名和归档之前停止。回到开发仓库执行：

```sh
python3 Scripts/update_acl4ssr_rules.py --latest
```

更新器会先解析上游最新提交号，再下载三份 ACL4SSR 配置及其引用的全部规则集，把 URL 固定到该提交，并重新生成 `Tower/Resources/ACL4SSR/ACL4SSR_manifest.json` 中的来源、规则数量和 SHA-256。下载全部成功后才会原子替换现有快照。

更新完成后必须：

1. 检查 `git diff -- Tower/Resources/ACL4SSR`，确认只有预期的上游规则变化。
2. 运行 `python3 Scripts/tests/update_acl4ssr_rules_test.py`、`bash Scripts/tests/release_testflight_test.sh` 和完整 iOS 测试。
3. 提交并推送规则资源，再重新运行发布脚本。不要在归档过程中保留未提交的资源变化，否则归档产物无法对应 Git 提交。

需要复现旧快照时可以明确指定完整提交号：

```sh
python3 Scripts/update_acl4ssr_rules.py --revision <完整提交号>
```

## 本地配置

本仓库是公开的，所以构建机地址、它的仓库路径和 Apple 团队 ID 都不写进 Git。它们放在 `Config/release.local.sh`，该文件已被 `.gitignore` 忽略，每台参与发布的机器各有一份，只负责赋值：

```sh
# 开发机（运行 Scripts/release_testflight.sh 的那台）
TOWER_RELEASE_HOST="${TOWER_RELEASE_HOST:-用户名@构建机地址}"
TOWER_RELEASE_REPO="${TOWER_RELEASE_REPO:-/构建机上的仓库路径}"

# 构建机（做签名和归档的那台）
TOWER_DEVELOPMENT_TEAM="${TOWER_DEVELOPMENT_TEAM:-你的团队 ID}"
```

用 `${VAR:-…}` 写法是为了让环境变量优先，这样临时换一台机器发布不需要改文件：

```sh
TOWER_RELEASE_HOST=用户名@另一台 Scripts/release_testflight.sh
```

也可以用 `--host`、`--remote-repo` 命令行参数覆盖。任何一个值缺失时脚本会直接停下并说明该往哪里填，不会带着错误的默认值继续。

`Config/ExportOptions-TestFlight.plist` 因此**不含 `teamID`**；`Scripts/release_testflight_remote.sh` 会把它复制到发布目录再补上团队 ID，渲染结果始终落在仓库之外。

## 一条命令发布

在塔台仓库根目录执行：

```sh
Scripts/release_testflight.sh
```

脚本会自动读取工程版本号和构建号，校验本地与远端 Git 状态，然后打开 Ghostty。按 Ghostty 中的提示输入 Mac mini 登录/钥匙串密码即可。输入不会显示，也不会保存。

需要明确约束目标版本时：

```sh
Scripts/release_testflight.sh --version 1.0.3 --build 30
```

只做校验、不连接 Mac mini：

```sh
Scripts/release_testflight.sh --dry-run
```

如果已经处于 Ghostty 或其他交互终端：

```sh
Scripts/release_testflight.sh --no-ghostty
```

## 脚本会做什么

1. 拒绝带未提交文件的本地工作区。
2. 联网上游检查随包 ACL4SSR 快照；不是最新版本就停止并给出更新命令。
3. 拉取 `origin/main`，确认本地提交已经完整推送。
4. 打开 Ghostty，以交互 SSH 连接 Mac mini。
5. Mac mini 快进到同一个提交，再次核对版本、构建号、工作区和内置规则版本。
6. 需要时交互解锁登录钥匙串，确认签名身份可见。
7. 自动在 Mac mini 的 Terminal/Aqua 会话中使用 Release 配置归档，并将日志实时回传到 Ghostty。
8. 把 `Config/ExportOptions-TestFlight.plist` 复制到发布目录、补上 `TOWER_DEVELOPMENT_TEAM`，再用它上传 App Store Connect。
9. 将归档与日志保存在 Mac mini 的 `~/Builds/Tower-TestFlight-版本-构建号-时间/`。

脚本成功只代表 Xcode 上传命令完成。发布后仍需在 App Store Connect 确认构建已出现、处理完成，以及是否加入了正确的 TestFlight 测试群组。

## 测试发布脚本

```sh
bash Scripts/tests/release_testflight_test.sh
```
