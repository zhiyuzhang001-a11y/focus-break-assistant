# 开发与修改指南

## 本地工作流

使用 macOS 14+、Swift 6.2。首次运行 `swift test`，再用 `./scripts/build-probe-app.sh` 打包。脚本从空目录构建、生成 `.icns`、签名、运行快照检查、制作并校验 DMG，然后安装到 `/Applications/Focus Break Assistant.app` 并重启。staging App 与临时 iconset 会删除，只保留 DMG 和正式安装；不要手动制作“副本”或改名安装包。

修改前创建分支，例如 `git switch -c codex/improve-reminder`。一个提交聚焦一项行为；提交说明包含改变原因和验证结果。不要提交用户图片、绝对机器路径、下载缓存、进程 ID 或本地设置。

## 按功能找代码

以下名称均相对于 `Sources/`。

- **计时、暂停、稍后、追加提醒**：`FocusBreakProbeCore/ReminderEngine.swift`；系统定时回调与状态文案在 `FocusBreakProbe/ReminderCoordinator.swift`。
- **活动、睡眠、全屏信号**：`FocusBreakProbe/MacSignalCollector.swift`；保持未知状态的保守处理，不推测用户是否在座。
- **菜单与设置**：`FocusBreakProbe/PreviewMenuController.swift`、`SettingsStackView.swift`。
- **提醒画面与按钮**：`FocusBreakProbe/HorizonOverlay.swift`；纯布局策略在 `FocusBreakProbeCore/ResponsiveLayoutPolicy.swift`，文字偏好在 `ReminderPresentation.swift`。
- **照片来源和导入**：`FocusBreakProbe/PhotoLibrary.swift`、`SystemPhotoPicker.swift`、`CategoryLibrary.swift`。
- **在线更新**：`FocusBreakProbe/OnlineReservoir.swift`、`ReservoirProvider.swift`、`ReservoirFileLock.swift`；配额与内容策略在 Core 的 `ImageReservoir.swift`、`ReservoirContentPolicy.swift`。
- **收藏、屏蔽、相似图避让**：`FocusBreakProbe/PhotoCuration.swift`；轮换策略在 `FocusBreakProbeCore/PhotoRotation.swift`。
- **启动和单实例**：`FocusBreakProbe/main.swift`、`ApplicationInstance.swift`；App 元数据在 `Support/FocusBreakProbe-Info.plist`。
- **内置照片与来源**：`FocusBreakProbe/Resources/`，同时维护 `docs/BUILTIN_PHOTOS.md`。

Core 保持不依赖 AppKit。界面和系统服务放在应用 target，便于对纯规则做确定性测试。现阶段保留已有 target 名称，避免仅为重命名影响脚本、资源包和运行路径。

## 验证改动

```sh
swift test
./scripts/build-probe-app.sh
codesign --verify --deep --strict '/Applications/Focus Break Assistant.app'
git diff --check
```

计时变更要覆盖默认路径、追加次数、暂停和自然休息取消；图库变更要覆盖失败保留旧批、容量限制、收藏与导入保留。不要让测试访问或清理真实用户图库。

界面变更应打开 App 检查对应页面和照片比例；单元测试不能证明实机全屏、睡眠、多屏与登录启动正确。实机验收清单见 `docs/REMINDER_MVP.md`。诊断命令如 `swift run focus-break-probe --snapshot` 会运行探针，其他入口以 `main.swift` 为准。

## 文档与素材约束

改变用户行为时同步 README、`docs/REMINDER_MVP.md` 或相应图库说明，并在 CHANGELOG 记录。历史阶段文档是当时的实验记录，不作为当前功能承诺。

遵守根目录 `AGENTS.md`：不生成项目图片、不修改用户原图、保持照片比例、保留第三方作者和许可。仓库目前未指定源代码开源许可证；不要自行追加许可授权。第三方素材许可独立适用。

`artifacts/` 用于本机实验输出；已有历史追踪文件暂保留，新输出默认忽略。需要共享结论时优先整理成脱敏的 `docs/` 报告，并注明实测、模拟与待验收的区别。

## 安装规则

正式本机安装路径固定为 `/Applications/Focus Break Assistant.app`。更新必须通过 `scripts/build-probe-app.sh` 覆盖这个路径；脚本在切换前验证临时 App，若安装失败会恢复旧版本。可分发产物是 `.build/package/` 下的 DMG；该目录不保留另一个 `.app`。不要把同一 App 复制到其他“应用程序”位置或以“副本”命名保存。
