# TestFlight 发布流程

塔台有两条正式版 Xcode 发布路径：出门使用的 MacBook Air M2 可以在当前 Aqua 会话中直接完成自动签名、归档和 App Store Connect / TestFlight 上传；家中 Mac mini M2 是固定发布机，也可从头完成归档和上传。家中 Mac mini M4 的 Xcode Beta 只用于开发调试，不参与正式发布。

2026-09-01 已在 Air 上实测 `1.0.5 (38)`：Release 自动签名、Store 校验、`.xcarchive` 和上传全部成功。第一次上传立即停在 `Failed to Use Accounts`，实际原因是正式版 Xcode 没有登录 Apple Account；本地证书和描述文件仍足以完成归档，所以不能根据“归档成功”推断账号已登录。登录 Xcode 后复用同一份归档即可上传，不需要重新构建。

备用远程流程会从开发机上的 Ghostty 通过 SSH 连接 Mac mini M2，再自动切换到该机的 Aqua 图形会话归档和上传，避免 SSH Background 安全域导致 `codesign` 报 `errSecInternalComponent`。登录钥匙串密码仅在当次终端由 macOS `security` 读取，不写入仓库、脚本、Shell 历史或命令参数。

## 前置条件

- 本地仓库工作区必须干净，并且 `HEAD` 与 `origin/main` 完全一致。
- 随 App 打包的 ACL4SSR 快照必须对应上游最新提交；发布脚本会联网检查并在过期时中止。
- 工程中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 必须已经更新并推送。
- Air 本机归档不需要 `TOWER_RELEASE_HOST`、远端仓库或 Ghostty；它必须处于 Aqua 会话，并使用 `/Applications/Xcode.app/Contents/Developer`。本机已登录开发账号，存在可用证书和匹配 `com.jzb.tower` 的描述文件。
- Air 本机上传前必须在 Xcode **Settings ▸ Accounts** 确认 Apple Account 已登录且能看到对应团队；账号还需具有 App Store Connect 访问权限，或提供单独的 App Store Connect API Key。只有开发证书和描述文件不能证明账号已登录或具备上传能力。
- Mac mini M2 发布机必须安装 `/Applications/Xcode.app`，其登录钥匙串中需要存在可用的 Apple Development 或 Apple Distribution 签名身份，并由具有 App Store Connect 权限的账号完成上传。
- 远程备用流程的开发机和 Mac mini M2 各自需要 `Config/release.local.sh` 中与自身职责对应的私有值（见下一节）；开发机还需安装 Ghostty。SSH 优先使用现有公钥，没有公钥时由 SSH 自己交互询问密码。
- 三台 Mac 都不要依赖或切换全局 `xcode-select`。运行命令前显式设置 `DEVELOPER_DIR` 并用 `xcodebuild -version` 复核。

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

本仓库是公开的，所以构建机地址、它的仓库路径和 Apple 团队 ID 都不写进 Git。远程发布需要的私有值放在 `Config/release.local.sh`；该文件已被 `.gitignore` 忽略，每台机器只填写自己需要的项目：

```sh
# 开发机（运行 Scripts/release_testflight.sh 的那台）
TOWER_RELEASE_HOST="${TOWER_RELEASE_HOST:-用户名@构建机地址}"
TOWER_RELEASE_REPO="${TOWER_RELEASE_REPO:-/构建机上的仓库路径}"

# 做签名和归档的机器
TOWER_DEVELOPMENT_TEAM="${TOWER_DEVELOPMENT_TEAM:-你的团队 ID}"
```

Air 本机归档不需要 `TOWER_RELEASE_HOST`、`TOWER_RELEASE_REPO` 或 Ghostty。工程故意没有把 `DEVELOPMENT_TEAM` 写进项目文件，所以命令行归档仍必须在进程环境或构建参数中提供团队。若 Air 没有本地配置，可从与 `com.jzb.tower` 匹配且未过期的描述文件中确认唯一的 `TeamIdentifier`，只保存在当前 Shell 变量中；找不到或出现多个不同团队时停止，不要猜，也不要把结果打印到日志或写进仓库。看到 `Signing for Tower requires a development team` 只说明命令没有传这个参数，不代表 Xcode 没登录。

用 `${VAR:-…}` 写法是为了让环境变量优先，这样临时换一台机器发布不需要改文件：

```sh
TOWER_RELEASE_HOST=用户名@另一台 Scripts/release_testflight.sh
```

也可以用 `--host`、`--remote-repo` 命令行参数覆盖。任何一个值缺失时脚本会直接停下并说明该往哪里填，不会带着错误的默认值继续。

`Config/ExportOptions-TestFlight.plist` 因此**不含 `teamID`**；`Scripts/release_testflight_remote.sh` 会把它复制到发布目录再补上团队 ID，渲染结果始终落在仓库之外。

## MacBook Air 本机归档与上传的已验证结果

2026-09-01 在当前 Air 的 Aqua 会话中，用正式版 Xcode 26.6 对 `1.0.5 (38)` 完成了以下验证：

1. 自动签名的 Release 真机构建成功。
2. `.xcarchive` 成功生成到 `~/Builds/Tower-TestFlight-1.0.5-38-时间/`。
3. 归档内版本、构建号、Bundle ID 和签名均正确，Store 校验通过。
4. Xcode 未登录 Apple Account 时，上传在 `IDEDistributionUploadAccountStep` 以 `Failed to Use Accounts` 停止。
5. 在 Xcode **Settings ▸ Accounts** 登录原账号后，不重新归档，直接复用同一 `.xcarchive` 上传成功，App Store Connect 开始处理 build 38。

这次故障的根因是“正式版 Xcode 未登录账号”，不是 App Store Connect 角色、证书、描述文件、Bundle ID 或归档错误。以后遇到相同错误按以下顺序处理：

1. 打开当前实际使用的那一份 Xcode，进入 **Settings ▸ Accounts**，确认 Apple Account 和目标团队存在。
2. 若账号不存在或要求重新认证，先完成登录；不要退出另一份 Xcode、撤销证书或切换全局 `xcode-select`。
3. 登录后直接重新分发已有归档。只要构建号尚未成功上传，无需重新归档。
4. 账号已经正常登录仍报相同错误时，才检查 App Store Connect 用户角色、待接受协议或改用 API Key／家中 Mac mini M2。

本机检查基线：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
launchctl managername  # 本机终端应为 Aqua
```

不要因为本机能签名、能装真机或能归档，就推断当前正式版 Xcode 已经登录；签名材料可以在账号退出后继续存在。

## Mac mini M2 备用发布：一条命令

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

## 远程发布脚本会做什么

1. 拒绝带未提交文件的本地工作区。
2. 联网上游检查随包 ACL4SSR 快照；不是最新版本就停止并给出更新命令。
3. 拉取 `origin/main`，确认本地提交已经完整推送。
4. 打开 Ghostty，以交互 SSH 连接 Mac mini。
5. Mac mini 快进到同一个提交，再次核对版本、构建号、工作区和内置规则版本。
6. 需要时交互解锁登录钥匙串，确认签名身份可见。
7. 自动在 Mac mini M2 的 Terminal/Aqua 会话中使用正式版 Xcode 和 Release 配置归档，并将日志实时回传到 Ghostty。
8. 把 `Config/ExportOptions-TestFlight.plist` 复制到发布目录、补上 `TOWER_DEVELOPMENT_TEAM`，再用它上传 App Store Connect。
9. 将归档与日志保存在 Mac mini 的 `~/Builds/Tower-TestFlight-版本-构建号-时间/`。

脚本成功只代表 Xcode 上传命令完成。发布后仍需在 App Store Connect 确认构建已出现、处理完成，以及是否加入了正确的 TestFlight 测试群组。

## 测试发布脚本

```sh
bash Scripts/tests/release_testflight_test.sh
```
